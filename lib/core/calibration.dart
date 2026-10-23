// E2 个体校准引擎：经验缩放 / OU-Kalman / EKF / 贝叶斯 MAP。
//
// 所有方法都建立在同一个观测结构上：C(t) ∝ 1/V，即
//   ln C = ln g(t; k) − ln V
// 其中 g 是「V=1 时的浓度」。因此 V 的观测是线性的，OU-Kalman 可以用
// 标准线性 Kalman；只有把 k 也当状态时（EKF）才需要线性化。
import 'dart:math' as math;

import 'pk.dart';

/// 校准方法。
enum CalibrationMethod {
  empirical('经验缩放（近期加权）', false),
  ouKalman('OU-Kalman 动态校准', false),
  ekf('EKF 参数学习', false),
  bayes('贝叶斯 MAP（实验）', true);

  const CalibrationMethod(this.label, this.experimental);

  final String label;
  final bool experimental;
}

/// 一条参与校准的化验点。
class CalibrationPoint {
  const CalibrationPoint({
    required this.at,
    required this.tHours,
    required this.concentration,
  });

  final DateTime at;

  /// 距上次给药小时数。
  final double tHours;

  /// 浓度 (mg/L)。
  final double concentration;
}

/// 历史某个时刻的个体 V 估计。
class VHistoryPoint {
  const VHistoryPoint(this.at, this.vd, this.sd);

  final DateTime at;
  final double vd;
  final double sd;
}

/// 校准结果。
class CalibrationResult {
  const CalibrationResult({
    required this.method,
    required this.vd,
    required this.vdSd,
    required this.r2,
    required this.n,
    required this.history,
    this.warning,
  });

  final CalibrationMethod method;

  /// 当前（最近一次化验时）的个体表观分布容积。
  final double vd;
  final double vdSd;

  final double r2;
  final int n;

  /// 每个化验时刻的 V 估计，用于「模型随时间回溯」。
  final List<VHistoryPoint> history;

  final String? warning;

  /// 相对不确定度（用于画预测带）。
  ///
  /// 下限 6%：即使化验点「完美」，单室近似、E1S 储库等模型误差依然存在，
  /// 区间不该画得比这更窄。
  double get relativeSd => vd <= 0 ? 0.5 : (vdSd / vd).clamp(0.06, 1.0);

  PkParams applyTo(PkParams population) => population.copyWith(vd: vd);
}

// ---------------------------------------------------------------------------
// 公共小工具
// ---------------------------------------------------------------------------

double _conc(PkParams base, double vd, double k, double t) {
  if (vd <= 0 || k <= 0) return 0;
  return PkProfile(base.copyWith(vd: vd, k: k)).concentration(t);
}

double _lnConc(PkParams base, double vd, double k, double t) {
  final c = _conc(base, vd, k, t);
  return c <= 0 ? -20 : math.log(c);
}

double _r2(List<double> obs, List<double> pred) {
  if (obs.length < 2) return 0;
  final mean = obs.reduce((a, b) => a + b) / obs.length;
  var sse = 0.0;
  var sst = 0.0;
  for (var i = 0; i < obs.length; i++) {
    sse += (pred[i] - obs[i]) * (pred[i] - obs[i]);
    sst += (obs[i] - mean) * (obs[i] - mean);
  }
  return sst <= 1e-18 ? 1 : 1 - sse / sst;
}

// ---------------------------------------------------------------------------
// 入口
// ---------------------------------------------------------------------------

/// 用化验点校准 [population]。
///
/// [now] 用于计算记录的新旧程度（经验法的近期加权）。
CalibrationResult? calibrateIndividual({
  required CalibrationMethod method,
  required PkParams population,
  required List<CalibrationPoint> points,
  DateTime? now,
}) {
  if (points.length < 4) return null;
  final sorted = List<CalibrationPoint>.from(points)
    ..sort((a, b) => a.at.compareTo(b.at));
  final ref = now ?? DateTime.now();
  switch (method) {
    case CalibrationMethod.empirical:
      return _empirical(population, sorted, ref);
    case CalibrationMethod.ouKalman:
      return _ouKalman(population, sorted, ref);
    case CalibrationMethod.ekf:
      return _ekf(population, sorted, ref);
    case CalibrationMethod.bayes:
      return _bayes(population, sorted, ref);
  }
}

// ---------------------------------------------------------------------------
// 1. 经验缩放：按记录新旧加权的中位比例
// ---------------------------------------------------------------------------

CalibrationResult? _empirical(
  PkParams pop,
  List<CalibrationPoint> pts,
  DateTime now,
) {
  const halfLifeDays = 90.0;
  var sw = 0.0;
  var swl = 0.0;
  var swl2 = 0.0;
  final obs = <double>[];
  final predScale = <double>[];
  for (final p in pts) {
    final g = _conc(pop, pop.vd, pop.k, p.tHours);
    if (g <= 0 || p.concentration <= 0) continue;
    final ageDays = now.difference(p.at).inMinutes / (60 * 24);
    final w = math.pow(0.5, (ageDays < 0 ? 0 : ageDays) / halfLifeDays).toDouble();
    final lr = math.log(p.concentration / g);
    sw += w;
    swl += w * lr;
    swl2 += w * lr * lr;
    obs.add(p.concentration);
    predScale.add(g);
  }
  if (sw <= 0 || swl2 <= 0) return null;

  final meanLr = swl / sw;
  final variance = math.max(0.0, swl2 / sw - meanLr * meanLr);
  final factor = math.exp(meanLr);
  final vd = pop.vd / factor;

  final preds = [for (final g in predScale) g * factor];
  final history = <VHistoryPoint>[];
  for (final p in pts) {
    final g = _conc(pop, pop.vd, pop.k, p.tHours);
    if (g <= 0 || p.concentration <= 0) continue;
    history.add(VHistoryPoint(p.at, pop.vd / (p.concentration / g), pop.vd * 0.4));
  }

  return CalibrationResult(
    method: CalibrationMethod.empirical,
    vd: vd,
    vdSd: vd * math.sqrt(variance),
    r2: _r2(obs, preds),
    n: pts.length,
    history: history,
    warning: pts.length < 6 ? '样本少于 6 条，经验校准的不确定度较大' : null,
  );
}

// ---------------------------------------------------------------------------
// 2. OU-Kalman：ln V 的均值回复随机过程，观测线性
// ---------------------------------------------------------------------------

CalibrationResult? _ouKalman(
  PkParams pop,
  List<CalibrationPoint> pts,
  DateTime now,
) {
  const tauDays = 180.0; // 向人群均值回归的时间常数
  const sigmaMonth = 0.06; // 每月 lnV 漂移的标准差
  const measCv = 0.12; // 化验误差 12%
  final mu = math.log(pop.vd);
  var x = mu;
  var p = 0.16; // 初始先验 CV 40%

  final history = <VHistoryPoint>[];
  final obs = <double>[];
  final preds = <double>[];
  DateTime? prev;

  for (final pt in pts) {
    final dt = prev == null
        ? 30.0
        : math.max(0.5, pt.at.difference(prev).inMinutes / (60 * 24));
    final phi = math.exp(-dt / tauDays);
    final sigma = sigmaMonth / math.sqrt(30) * math.sqrt(dt);
    final q = sigma * sigma;
    // 预测
    x = mu + phi * (x - mu);
    p = phi * phi * p + q;
    // 更新（h = ln g − x，故 H = −1）
    final g = _conc(pop, math.exp(x), pop.k, pt.tHours);
    if (g > 0 && pt.concentration > 0) {
      final innovation = math.log(pt.concentration) - math.log(g);
      final s = p + measCv * measCv;
      final k = -p / s;
      x += k * innovation;
      p = p * (measCv * measCv) / s;
      obs.add(pt.concentration);
      preds.add(_conc(pop, math.exp(x), pop.k, pt.tHours));
    }
    history.add(VHistoryPoint(pt.at, math.exp(x), math.exp(x) * math.sqrt(p)));
    prev = pt.at;
  }

  final vd = math.exp(x);
  return CalibrationResult(
    method: CalibrationMethod.ouKalman,
    vd: vd,
    vdSd: vd * math.sqrt(p),
    r2: _r2(obs, preds),
    n: pts.length,
    history: history,
    warning: pts.length < 5 ? '动态跟踪需要更多时间点，结果几乎等同先验' : null,
  );
}

// ---------------------------------------------------------------------------
// 3. EKF：状态 [lnV, lnk]，观测非线性
// ---------------------------------------------------------------------------

CalibrationResult? _ekf(
  PkParams pop,
  List<CalibrationPoint> pts,
  DateTime now,
) {
  const tauDays = 240.0;
  const sigmaMonthV = 0.05;
  const sigmaMonthK = 0.03;
  const measCv = 0.12;

  final muV = math.log(pop.vd);
  final muK = math.log(pop.k);
  var x = muV;
  var y = muK;
  // 协方差 (2x2)：P = [[p00, p01], [p10, p11]]
  var p00 = 0.16, p01 = 0.0, p10 = 0.0, p11 = 0.09;

  final history = <VHistoryPoint>[];
  final obs = <double>[];
  final preds = <double>[];
  DateTime? prev;

  for (final pt in pts) {
    final dt = prev == null
        ? 30.0
        : math.max(0.5, pt.at.difference(prev).inMinutes / (60 * 24));
    final phi = math.exp(-dt / tauDays);
    // 预测
    x = muV + phi * (x - muV);
    y = muK + phi * (y - muK);
    final qV = math.pow(sigmaMonthV / math.sqrt(30), 2) * dt;
    final qK = math.pow(sigmaMonthK / math.sqrt(30), 2) * dt;
    p00 = phi * phi * p00 + qV;
    p01 = phi * phi * p01;
    p10 = p01;
    p11 = phi * phi * p11 + qK;

    // 观测
    final vd = math.exp(x);
    final k = math.exp(y);
    final h = _lnConc(pop, vd, k, pt.tHours);
    if (vd > 0 && k > 0 && pt.concentration > 0) {
      // 数值雅可比
      const eps = 1e-4;
      final hV = _lnConc(pop, vd * (1 + eps), k, pt.tHours);
      final hK = _lnConc(pop, vd, k * (1 + eps), pt.tHours);
      final hx = (hV - h) / eps;
      final hy = (hK - h) / eps;
      final s = hx * hx * p00 + hx * hy * (p01 + p10) + hy * hy * p11 + measCv * measCv;
      final innovation = math.log(pt.concentration) - h;
      final kx = (p00 * hx + p01 * hy) / s;
      final ky = (p10 * hx + p11 * hy) / s;
      x += kx * innovation;
      y += ky * innovation;
      // P = P − K H P
      final newP00 = p00 - kx * (hx * p00 + hy * p10);
      final newP01 = p01 - kx * (hx * p01 + hy * p11);
      final newP10 = p10 - ky * (hx * p00 + hy * p10);
      final newP11 = p11 - ky * (hx * p01 + hy * p11);
      p00 = newP00;
      p01 = newP01;
      p10 = newP10;
      p11 = newP11;
      obs.add(pt.concentration);
      preds.add(_conc(pop, math.exp(x), math.exp(y), pt.tHours));
    }
    history.add(VHistoryPoint(pt.at, math.exp(x), math.exp(x) * math.sqrt(p00)));
    prev = pt.at;
  }

  final vd = math.exp(x);
  return CalibrationResult(
    method: CalibrationMethod.ekf,
    vd: vd,
    vdSd: vd * math.sqrt(p00),
    r2: _r2(obs, preds),
    n: pts.length,
    history: history,
    warning: 'k 在稀疏采样下几乎不可辨识，EKF 的 k 估计主要由先验决定',
  );
}

// ---------------------------------------------------------------------------
// 4. 贝叶斯 MAP（实验）：先验 + 似然，Laplace 近似
// ---------------------------------------------------------------------------

CalibrationResult? _bayes(
  PkParams pop,
  List<CalibrationPoint> pts,
  DateTime now,
) {
  const priorSdV = 0.40;
  const priorSdK = 0.30;
  const measCv = 0.12;

  final muV = math.log(pop.vd);
  final muK = math.log(pop.k);

  double objective(double lv, double lk) {
    final vd = math.exp(lv);
    final k = math.exp(lk);
    var s = 0.0;
    for (final p in pts) {
      final pred = _conc(pop, vd, k, p.tHours);
      if (pred <= 0 || p.concentration <= 0) continue;
      final r = math.log(p.concentration) - math.log(pred);
      s += r * r / (measCv * measCv);
    }
    s += math.pow((lv - muV) / priorSdV, 2).toDouble();
    s += math.pow((lk - muK) / priorSdK, 2).toDouble();
    return 0.5 * s;
  }

  // 粗网格 + 局部精修（Nelder-Mead 在 2 维上足够）
  var bestV = muV;
  var bestK = muK;
  var best = objective(bestV, bestK);
  for (var i = 0; i <= 24; i++) {
    final lv = muV - 2.0 + 4.0 * i / 24;
    for (var j = 0; j <= 24; j++) {
      final lk = muK - 1.5 + 3.0 * j / 24;
      final v = objective(lv, lk);
      if (v < best) {
        best = v;
        bestV = lv;
        bestK = lk;
      }
    }
  }

  // 简单坐标下降精修
  var step = 0.2;
  for (var iter = 0; iter < 120; iter++) {
    var improved = false;
    for (final dir in const [[1.0, 0.0], [-1.0, 0.0], [0.0, 1.0], [0.0, -1.0]]) {
      final v = objective(bestV + dir[0] * step, bestK + dir[1] * step);
      if (v < best) {
        best = v;
        bestV += dir[0] * step;
        bestK += dir[1] * step;
        improved = true;
      }
    }
    if (!improved) step *= 0.5;
    if (step < 1e-5) break;
  }

  // 数值 Hessian（2x2）
  const eps = 1e-4;
  final f00 = objective(bestV + eps, bestK);
  final f11 = objective(bestV, bestK + eps);
  final f0m = objective(bestV - eps, bestK);
  final f1m = objective(bestV, bestK - eps);
  final fpp = objective(bestV + eps, bestK + eps);
  final h00 = (f00 - 2 * best + f0m) / (eps * eps);
  final h11 = (f11 - 2 * best + f1m) / (eps * eps);
  final h01 = (fpp - f00 - f11 + best) / (eps * eps);
  final det = h00 * h11 - h01 * h01;
  final sdV = det > 1e-12 ? math.sqrt(math.max(0.0, h11 / det)) : priorSdV;

  final vd = math.exp(bestV);
  final k = math.exp(bestK);
  final obs = <double>[];
  final preds = <double>[];
  final history = <VHistoryPoint>[];
  for (final p in pts) {
    obs.add(p.concentration);
    preds.add(_conc(pop, vd, k, p.tHours));
    history.add(VHistoryPoint(p.at, vd, vd * sdV));
  }

  return CalibrationResult(
    method: CalibrationMethod.bayes,
    vd: vd,
    vdSd: vd * sdV,
    r2: _r2(obs, preds),
    n: pts.length,
    history: history,
    warning: '实验特性：后验几乎等于「先验 + 少量数据」，样本少时请只作参考',
  );
}
