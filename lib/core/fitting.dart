// 参数反推：由实测「时间-浓度」数据点拟合房室模型参数。
//
// 策略：先在对数网格上做全局粗搜（浓度对 scale 是线性的，可解析求解），
// 再用 Nelder–Mead 单纯形法局部精修，避免初值敏感导致的局部极小。
import 'dart:math' as math;

import 'pk.dart';

/// 一个实测浓度点。
class ObservedPoint {
  const ObservedPoint(this.t, this.c);

  final double t;
  final double c;

  @override
  String toString() => '(${t.toStringAsFixed(2)}, ${c.toStringAsFixed(3)})';
}

/// 拟合结果。
class FitResult {
  const FitResult({
    required this.params,
    required this.r2,
    required this.rmse,
    required this.iterations,
    required this.converged,
    required this.predicted,
  });

  /// 拟合得到的参数。口服模型的 vd 为表观分布容积 V/F。
  final PkParams params;

  /// 决定系数 R²。
  final double r2;

  /// 相对残差均方根。
  final double rmse;

  final int iterations;
  final bool converged;

  /// 与实测点一一对应的拟合浓度。
  final List<double> predicted;

  /// 拟合曲线（用于绘图）。
  List<SamplePoint> curve({required double duration, int points = 400}) {
    final profile = PkProfile(params);
    return List.generate(points, (i) {
      final t = duration * i / (points - 1);
      return SamplePoint(t, profile.concentration(t));
    });
  }
}

/// 通用 Nelder–Mead 单纯形最小化器。
class NelderMead {
  NelderMead(this.objective, {this.maxIterations = 500, this.tolerance = 1e-10});

  final double Function(List<double> x) objective;
  final int maxIterations;
  final double tolerance;

  List<double> minimize(List<double> start) {
    final n = start.length;
    if (n == 0) return start;
    final simplex = <List<double>>[List<double>.from(start)];
    for (var i = 0; i < n; i++) {
      final p = List<double>.from(start);
      p[i] += p[i].abs() * 0.08 + 0.02;
      simplex.add(p);
    }
    final values = simplex.map(objective).toList();

    for (var iter = 0; iter < maxIterations; iter++) {
      final order = List<int>.generate(n + 1, (i) => i)
        ..sort((a, b) => values[a].compareTo(values[b]));
      final sortedPoints = [for (final i in order) simplex[i]];
      final sortedValues = [for (final i in order) values[i]];
      for (var i = 0; i <= n; i++) {
        simplex[i] = sortedPoints[i];
        values[i] = sortedValues[i];
      }

      final spread = (values[n] - values[0]).abs();
      final scale = math.max(values[0].abs(), 1e-12);
      if (spread <= tolerance * scale) break;

      final centroid = List<double>.filled(n, 0);
      for (var i = 0; i < n; i++) {
        for (var j = 0; j < n; j++) {
          centroid[j] += simplex[i][j] / n;
        }
      }

      final worst = simplex[n];
      final reflected = _combine(centroid, worst, 1.0);
      final fr = objective(reflected);
      if (fr < values[0]) {
        final expanded = _combine(centroid, worst, 2.0);
        final fe = objective(expanded);
        if (fe < fr) {
          simplex[n] = expanded;
          values[n] = fe;
        } else {
          simplex[n] = reflected;
          values[n] = fr;
        }
      } else if (fr < values[n - 1]) {
        simplex[n] = reflected;
        values[n] = fr;
      } else {
        final contracted = fr < values[n]
            ? _combine(centroid, reflected, 0.5)
            : _combine(centroid, worst, 0.5);
        final fc = objective(contracted);
        if (fc < math.min(fr, values[n])) {
          simplex[n] = contracted;
          values[n] = fc;
        } else {
          for (var i = 1; i <= n; i++) {
            simplex[i] = [
              for (var j = 0; j < n; j++) simplex[0][j] + 0.5 * (simplex[i][j] - simplex[0][j]),
            ];
            values[i] = objective(simplex[i]);
          }
        }
      }
    }

    var best = 0;
    for (var i = 1; i <= n; i++) {
      if (values[i] < values[best]) best = i;
    }
    return simplex[best];
  }

  List<double> _combine(List<double> centroid, List<double> worst, double factor) {
    return [
      for (var j = 0; j < centroid.length; j++) centroid[j] + factor * (centroid[j] - worst[j]),
    ];
  }
}

/// 拟合器。
class PkFitter {
  PkFitter({required this.points, required this.dose});

  final List<ObservedPoint> points;

  /// 已知给药剂量 (mg)。
  final double dose;

  /// 相对误差的浓度下限，避免低浓度点权重爆炸。
  double get _floor {
    final maxC = points.map((p) => p.c).fold(0.0, math.max);
    return math.max(maxC * 0.02, 1e-4);
  }

  /// 单室静注：C(t) = C0·e^(−kt)，返回 C0 与 k。
  FitResult fitIv({PkModel model = PkModel.oneCompIv}) {
    final ts = points.map((p) => p.t).toList();
    final cs = points.map((p) => p.c).toList();
    final floor = _floor;

    double evaluate(double k) {
      // 对 C0 线性：C0 = Σw·c·e^(−kt) / Σw·(e^(−kt))²
      var num = 0.0;
      var den = 0.0;
      for (var i = 0; i < ts.length; i++) {
        final w = 1 / math.pow(math.max(cs[i], floor), 2);
        final e = math.exp(-k * ts[i]);
        num += w * cs[i] * e;
        den += w * e * e;
      }
      if (den <= 0) return double.infinity;
      final c0 = num / den;
      var sse = 0.0;
      for (var i = 0; i < ts.length; i++) {
        final pred = c0 * math.exp(-k * ts[i]);
        final w = 1 / math.pow(math.max(cs[i], floor), 2);
        sse += w * (pred - cs[i]) * (pred - cs[i]);
      }
      return sse;
    }

    // 对数网格粗搜 k
    var bestK = 0.1;
    var best = double.infinity;
    const steps = 120;
    for (var i = 0; i < steps; i++) {
      final k = math.exp(math.log(0.001) + (math.log(2.0) - math.log(0.001)) * i / (steps - 1));
      final v = evaluate(k);
      if (v < best) {
        best = v;
        bestK = k;
      }
    }

    final nm = NelderMead((x) => evaluate(math.exp(x[0])), maxIterations: 300);
    final bestLog = nm.minimize([math.log(bestK)]);
    final k = math.exp(bestLog[0]);

    var num = 0.0;
    var den = 0.0;
    for (var i = 0; i < ts.length; i++) {
      final w = 1 / math.pow(math.max(cs[i], floor), 2);
      final e = math.exp(-k * ts[i]);
      num += w * cs[i] * e;
      den += w * e * e;
    }
    final c0 = den > 0 ? num / den : 0.0;
    final params = PkParams(model: model, dose: dose, vd: c0 > 0 ? dose / c0 : 1, k: k);
    return _summarize(params, (t) => c0 * math.exp(-k * t));
  }

  /// 单室口服（一级吸收）：C(t) = scale·ka/(ka−k)·(e^(−kt) − e^(−ka·t))。
  /// 拟合得到 scale = F·D/V，返回 vd = D/scale（即表观 V/F）。
  ///
  /// [allowFlipFlop] 为 true 时允许 ka < k，用于缓释/储库制剂。
  /// [fixedK] 给定时固定消除常数，只拟合释放/吸收速率 ka——这是储库型数据
  /// 唯一可辨识的拟合方式：单条曲线对 ka、k 是对称的，无法自行区分两者。
  FitResult fitOral({bool allowFlipFlop = false, double? fixedK}) {
    final ts = points.map((p) => p.t).toList();
    final cs = points.map((p) => p.c).toList();
    final floor = _floor;

    double shape(double t, double ka, double k) {
      if ((ka - k).abs() < 1e-7) return k * t * math.exp(-k * t);
      return ka / (ka - k) * (math.exp(-k * t) - math.exp(-ka * t));
    }

    /// 给定 ka、k，解析求最优 scale（浓度对 scale 是线性的）。
    double solveScale(double ka, double k) {
      var num = 0.0;
      var den = 0.0;
      for (var i = 0; i < ts.length; i++) {
        final w = 1 / math.pow(math.max(cs[i], floor), 2);
        final g = shape(ts[i], ka, k);
        num += w * cs[i] * g;
        den += w * g * g;
      }
      return den > 0 ? num / den : 0.0;
    }

    /// 加权残差平方和。
    double sseOf(double ka, double k) {
      if (ka <= 0 || k <= 0 || (ka - k).abs() < 1e-7) return double.infinity;
      final scale = solveScale(ka, k);
      var s = 0.0;
      for (var i = 0; i < ts.length; i++) {
        final w = 1 / math.pow(math.max(cs[i], floor), 2);
        final pred = scale * shape(ts[i], ka, k);
        s += w * (pred - cs[i]) * (pred - cs[i]);
      }
      return s;
    }

    double ka;
    double k;

    if (fixedK != null && fixedK > 0) {
      // 已知消除常数：只需拟合释放/吸收速率 ka。
      // 这样才可辨识——同一条曲线单靠形状无法区分 ka 与 k 谁更大。
      k = fixedK;
      var bestKa = fixedK;
      var best = double.infinity;
      const steps = 160;
      for (var i = 0; i < steps; i++) {
        final cand =
            math.exp(math.log(1e-4) + (math.log(20.0) - math.log(1e-4)) * i / (steps - 1));
        final v = sseOf(cand, k);
        if (v < best) {
          best = v;
          bestKa = cand;
        }
      }
      final nm = NelderMead((x) => sseOf(math.exp(x[0]), k), maxIterations: 300);
      ka = math.exp(nm.minimize([math.log(bestKa)])[0]);
    } else {
      var bestKa = 1.0;
      var bestK = 0.1;
      var bestSse = double.infinity;
      const kaSteps = 36;
      const kSteps = 44;
      for (var i = 0; i < kaSteps; i++) {
        final candKa =
            math.exp(math.log(0.05) + (math.log(15.0) - math.log(0.05)) * i / (kaSteps - 1));
        for (var j = 0; j < kSteps; j++) {
          final candK =
              math.exp(math.log(0.003) + (math.log(1.2) - math.log(0.003)) * j / (kSteps - 1));
          if ((candKa - candK).abs() < 1e-6) continue;
          if (!allowFlipFlop && candKa <= candK) continue;
          final v = sseOf(candKa, candK);
          if (v < bestSse) {
            bestSse = v;
            bestKa = candKa;
            bestK = candK;
          }
        }
      }

      final nm = NelderMead(
        (x) => sseOf(math.exp(x[0]), math.exp(x[1])),
        maxIterations: 400,
      );
      final refined = nm.minimize([math.log(bestKa), math.log(bestK)]);
      ka = math.exp(refined[0]);
      k = math.exp(refined[1]);
      if (!allowFlipFlop && ka < k) {
        final tmp = ka;
        ka = k;
        k = tmp;
      }
    }

    final scale = solveScale(ka, k);
    final params = PkParams(
      model: PkModel.oneCompOral,
      dose: dose,
      vd: scale > 0 ? dose / scale : 1,
      k: k,
      ka: ka,
      f: 1.0,
    );
    return _summarize(params, (t) => scale * shape(t, ka, k));
  }

  /// 双吸收相（含服 / 速释+缓释复方）拟合。
  ///
  /// 两个吸收相的 ka 与占比在单条曲线上高度相关，无法全部自由拟合，
  /// 因此固定消除常数 [fixedK] 与快相 [fastKa]（含服片通常 3–8 h⁻¹），
  /// 只拟合慢相 ka2 与快相占比 F1。
  FitResult fitDual({required double fixedK, double fastKa = 5.0}) {
    final ts = points.map((p) => p.t).toList();
    final cs = points.map((p) => p.c).toList();
    final floor = _floor;
    final k = fixedK;

    double term(double t, double ka) {
      if ((ka - k).abs() < 1e-7) return k * t * math.exp(-k * t);
      return ka / (ka - k) * (math.exp(-k * t) - math.exp(-ka * t));
    }

    double shapeAt(double t, double ka2, double f1) =>
        f1 * term(t, fastKa) + (1 - f1) * term(t, ka2);

    double solveScale(double ka2, double f1) {
      var num = 0.0;
      var den = 0.0;
      for (var i = 0; i < ts.length; i++) {
        final w = 1 / math.pow(math.max(cs[i], floor), 2);
        final g = shapeAt(ts[i], ka2, f1);
        num += w * cs[i] * g;
        den += w * g * g;
      }
      return den > 0 ? num / den : 0.0;
    }

    double sseOf(double ka2, double f1) {
      if (ka2 <= 0 || f1 <= 0 || f1 >= 1) return double.infinity;
      final scale = solveScale(ka2, f1);
      var s = 0.0;
      for (var i = 0; i < ts.length; i++) {
        final w = 1 / math.pow(math.max(cs[i], floor), 2);
        final pred = scale * shapeAt(ts[i], ka2, f1);
        s += w * (pred - cs[i]) * (pred - cs[i]);
      }
      return s;
    }

    var bestKa2 = 1.0;
    var bestF1 = 0.5;
    var best = double.infinity;
    const ka2Steps = 24;
    const f1Steps = 9;
    for (var i = 0; i < ka2Steps; i++) {
      final ka2 = math.exp(math.log(0.1) + (math.log(3.0) - math.log(0.1)) * i / (ka2Steps - 1));
      for (var j = 0; j < f1Steps; j++) {
        final f1 = 0.15 + (0.85 - 0.15) * j / (f1Steps - 1);
        final v = sseOf(ka2, f1);
        if (v < best) {
          best = v;
          bestKa2 = ka2;
          bestF1 = f1;
        }
      }
    }

    // 用 logit 变换保证 F1 落在 (0,1)
    double logit(double p) => math.log(p / (1 - p));
    double expit(double z) => 1 / (1 + math.exp(-z));

    final nm = NelderMead(
      (x) => sseOf(math.exp(x[0]), expit(x[1])),
      maxIterations: 400,
    );
    final refined = nm.minimize([math.log(bestKa2), logit(bestF1)]);
    final ka2 = math.exp(refined[0]);
    final f1 = expit(refined[1]);
    final scale = solveScale(ka2, f1);

    final params = PkParams(
      model: PkModel.dualAbsorption,
      dose: dose,
      vd: scale > 0 ? dose / scale : 1,
      k: k,
      ka: fastKa,
      ka2: ka2,
      f: 1.0,
      fFast: f1,
    );
    return _summarize(params, (t) => scale * shapeAt(t, ka2, f1));
  }

  FitResult _summarize(PkParams params, double Function(double t) predict) {
    final cs = points.map((p) => p.c).toList();
    final predicted = [for (final p in points) predict(p.t)];
    final floor = _floor;

    final mean = cs.reduce((a, b) => a + b) / cs.length;
    var sst = 0.0;
    var sse = 0.0;
    var weighted = 0.0;
    for (var i = 0; i < cs.length; i++) {
      sst += (cs[i] - mean) * (cs[i] - mean);
      final d = predicted[i] - cs[i];
      sse += d * d;
      final w = 1 / math.pow(math.max(cs[i], floor), 2);
      weighted += w * d * d;
    }
    final r2 = sst <= 1e-12 ? 1.0 : 1 - sse / sst;
    return FitResult(
      params: params,
      r2: r2,
      rmse: math.sqrt(weighted / cs.length),
      iterations: 1,
      converged: true,
      predicted: predicted,
    );
  }
}
