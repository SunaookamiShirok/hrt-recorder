// 药代动力学（PK）核心模型：单室/双室、单次/多次给药、曲线与参数计算。
//
// 全部为纯 Dart 实现，不依赖任何第三方包，因此可同时运行在
// Windows / Web / Android 上。
import 'dart:math' as math;

/// 房室模型与给药途径。
enum PkModel {
  oneCompIv('一室模型 · 静注', '静注'),
  oneCompOral('一室模型 · 口服', '口服'),
  twoCompIv('二室模型 · 静注', '二室静注'),
  zeroOrder('恒速输入 · 输注/贴片', '输注/贴片'),
  dualAbsorption('双吸收相 · 含服/复方', '含服/复方');

  const PkModel(this.label, this.shortLabel);

  final String label;

  /// 简短名称，用于模型选择按钮。
  final String shortLabel;

  bool get isOral => this == PkModel.oneCompOral;

  bool get isTwoCompartment => this == PkModel.twoCompIv;

  /// 零级（恒速）输入：输注泵、透皮贴片。
  bool get isZeroOrder => this == PkModel.zeroOrder;

  /// 双吸收相：舌下/颊粘膜含服（粘膜快吸收 + 吞咽部分慢吸收），或速释+缓释复方。
  bool get isDualAbsorption => this == PkModel.dualAbsorption;
}

/// 给药方案的参数集合。
///
/// 剂量单位为 mg，体积单位为 L，速率常数单位为 h⁻¹，时间单位为 h。
class PkParams {
  const PkParams({
    this.model = PkModel.oneCompIv,
    this.dose = 500,
    this.vd = 35,
    this.k = 0.12,
    this.ka = 1.2,
    this.f = 0.8,
    this.k12 = 0.5,
    this.k21 = 0.8,
    this.infusionDuration = 24,
    this.ka2 = 0.9,
    this.fFast = 0.55,
    this.weight = 70,
  });

  final PkModel model;

  /// 每次给药剂量 (mg)。
  final double dose;

  /// 表观分布容积 (L)；二室模型时为中央室容积 V1。
  final double vd;

  /// 消除速率常数 k（一室），或中央室消除常数 k10（二室），单位 h⁻¹。
  final double k;

  /// 一级吸收速率常数 ka (h⁻¹)，仅口服模型使用。
  final double ka;

  /// 生物利用度 F（0–1），仅口服模型使用。
  final double f;

  /// 中央室向外周室转运常数 k12 (h⁻¹)，仅二室模型使用。
  final double k12;

  /// 外周室向中央室转运常数 k21 (h⁻¹)，仅二室模型使用。
  final double k21;

  /// 恒速输入的持续时间 (h)，仅零级输入模型（输注 / 贴片）使用。
  /// 总剂量 [dose] 在该时段内匀速进入体循环，输入速率 R0 = dose / infusionDuration。
  final double infusionDuration;

  /// 慢相吸收速率常数 ka2 (h⁻¹)，仅双吸收相模型使用（[ka] 为快相 ka1）。
  final double ka2;

  /// 快相吸收占总生物利用度的比例 F1（0–1），仅双吸收相模型使用。
  final double fFast;

  /// 体重 (kg)。分布容积已按其换算，这里保留用于显示与再缩放。
  final double weight;

  PkParams copyWith({
    PkModel? model,
    double? dose,
    double? vd,
    double? k,
    double? ka,
    double? f,
    double? k12,
    double? k21,
    double? infusionDuration,
    double? ka2,
    double? fFast,
    double? weight,
  }) {
    return PkParams(
      model: model ?? this.model,
      dose: dose ?? this.dose,
      vd: vd ?? this.vd,
      k: k ?? this.k,
      ka: ka ?? this.ka,
      f: f ?? this.f,
      k12: k12 ?? this.k12,
      k21: k21 ?? this.k21,
      infusionDuration: infusionDuration ?? this.infusionDuration,
      ka2: ka2 ?? this.ka2,
      fFast: fFast ?? this.fFast,
      weight: weight ?? this.weight,
    );
  }

  /// 参数是否落在有物理意义的范围内。
  List<String> validate() {
    final errors = <String>[];
    if (dose <= 0) errors.add('剂量必须大于 0');
    if (weight <= 0) errors.add('体重必须大于 0');
    if (vd <= 0) errors.add('分布容积必须大于 0');
    if (k <= 0) errors.add('消除速率常数 k 必须大于 0');
    if (model.isOral || model.isDualAbsorption) {
      if (ka <= 0) errors.add('吸收速率常数 ka 必须大于 0');
      if (f <= 0 || f > 1) errors.add('生物利用度 F 应在 (0, 1] 之间');
    }
    if (model.isDualAbsorption) {
      if (ka2 <= 0) errors.add('慢相吸收速率 ka2 必须大于 0');
      if (fFast <= 0 || fFast >= 1) errors.add('快相占比 F1 应在 (0, 1) 之间');
    }
    if (model.isTwoCompartment) {
      if (k12 < 0) errors.add('k12 不能为负');
      if (k21 <= 0) errors.add('k21 必须大于 0');
    }
    if (model.isZeroOrder && infusionDuration <= 0) {
      errors.add('恒速输入的持续时间必须大于 0');
    }
    return errors;
  }

  @override
  String toString() =>
      'PkParams(model: ${model.name}, dose: $dose, vd: $vd, k: $k, '
      'ka: $ka, f: $f, k12: $k12, k21: $k21, T: $infusionDuration, '
      'ka2: $ka2, fFast: $fFast)';
}

/// 时间-浓度采样点。
class SamplePoint {
  const SamplePoint(this.t, this.c);

  final double t;
  final double c;

  @override
  String toString() => '(${t.toStringAsFixed(2)}, ${c.toStringAsFixed(4)})';
}

/// 单个给药方案对应的解析血药浓度曲线。
class PkProfile {
  PkProfile(this.params) {
    if (params.model.isTwoCompartment) {
      final s = params.k + params.k12 + params.k21;
      final disc = math.max(0.0, s * s - 4 * params.k * params.k21);
      final root = math.sqrt(disc);
      _alpha = (s + root) / 2;
      _beta = (s - root) / 2;
      _coefA = params.dose * (_alpha - params.k21) / (params.vd * (_alpha - _beta));
      _coefB = params.dose * (params.k21 - _beta) / (params.vd * (_alpha - _beta));
    } else {
      _alpha = params.k;
      _beta = params.k;
      _coefA = params.dose / params.vd;
      _coefB = 0;
    }
  }

  final PkParams params;

  late final double _alpha;
  late final double _beta;
  late final double _coefA;
  late final double _coefB;

  /// 分布相速率常数 α (h⁻¹)。
  double get alpha => _alpha;

  /// 消除相（终末）速率常数 β (h⁻¹)。
  double get beta => _beta;

  /// 双指数项系数 A (mg/L)。
  double get coefA => _coefA;

  /// 双指数项系数 B (mg/L)。
  double get coefB => _coefB;

  /// 终末消除半衰期 t½ (h)。
  double get tHalf => math.ln2 / terminalRate;

  /// 终末相速率常数：二室用 β，一室用 k。
  double get terminalRate => params.model.isTwoCompartment ? _beta : params.k;

  /// 清除率 CL (L/h)。
  double get clearance => params.k * params.vd;

  /// 稳态表观分布容积 Vss (L)。
  double get vss =>
      params.model.isTwoCompartment ? params.vd * (1 + params.k12 / params.k21) : params.vd;

  /// 平均滞留时间 MRT (h)。
  double get mrt {
    final cl = clearance;
    if (cl <= 0) return 0;
    final base = vss / cl;
    // 恒速输入的平均输入时间 = T/2。
    return params.model.isZeroOrder ? base + params.infusionDuration / 2 : base;
  }

  /// 恒速输入的速率 R0 (mg/h)，仅零级模型有意义。
  double get inputRate =>
      params.model.isZeroOrder && params.infusionDuration > 0
          ? params.dose / params.infusionDuration
          : 0;

  /// 初始浓度 C0 (mg/L)，即 t=0⁺ 时的浓度。
  double get initialConcentration {
    if (params.model.isTwoCompartment) return _coefA + _coefB;
    if (params.model.isOral) return 0;
    if (params.model.isZeroOrder) return 0;
    if (params.model.isDualAbsorption) return 0;
    return params.dose / params.vd;
  }

  /// 单个一级吸收项的贡献，[scale] 已包含 F·D/V。
  double _absorptionTerm(double t, double ka, double scale) {
    final k = params.k;
    if ((ka - k).abs() < 1e-9) {
      // ka == k 时的极限形式，避免除零。
      return scale * k * t * math.exp(-k * t);
    }
    return scale * ka / (ka - k) * (math.exp(-k * t) - math.exp(-ka * t));
  }

  /// 单次给药后 t 时刻的血药浓度 (mg/L)。
  double concentration(double t) {
    if (t < 0) return 0;
    switch (params.model) {
      case PkModel.oneCompIv:
        return params.dose / params.vd * math.exp(-params.k * t);
      case PkModel.oneCompOral:
        return _absorptionTerm(t, params.ka, params.f * params.dose / params.vd);
      case PkModel.twoCompIv:
        return _coefA * math.exp(-_alpha * t) + _coefB * math.exp(-_beta * t);
      case PkModel.zeroOrder:
        final cl = params.k * params.vd;
        if (cl <= 0) return 0;
        final tEnd = params.infusionDuration;
        if (t <= tEnd) {
          // 输入期间：R0/CL · (1 − e^(−kt))
          return inputRate / cl * (1 - math.exp(-params.k * t));
        }
        // 输入结束后按一室消除衰减
        final cAtEnd = inputRate / cl * (1 - math.exp(-params.k * tEnd));
        return cAtEnd * math.exp(-params.k * (t - tEnd));
      case PkModel.dualAbsorption:
        // 快相（粘膜吸收）+ 慢相（吞咽部分）并联
        final fTotal = params.f * params.dose / params.vd;
        final fast = fTotal * params.fFast;
        final slow = fTotal * (1 - params.fFast);
        return _absorptionTerm(t, params.ka, fast) +
            _absorptionTerm(t, params.ka2, slow);
    }
  }
}

/// 给药场景：单次，或按固定间隔重复给药。
class PkScenario {
  const PkScenario({
    required this.params,
    this.interval = 12,
    this.doseCount = 1,
    this.steadyState = false,
  });

  final PkParams params;

  /// 给药间隔 τ (h)。
  final double interval;

  /// 给药次数（稳态模式下可忽略）。
  final int doseCount;

  /// 是否直接按稳态叠加计算。
  final bool steadyState;

  bool get isRepeated => interval > 0 && (steadyState || doseCount > 1);

  PkScenario copyWith({
    PkParams? params,
    double? interval,
    int? doseCount,
    bool? steadyState,
  }) {
    return PkScenario(
      params: params ?? this.params,
      interval: interval ?? this.interval,
      doseCount: doseCount ?? this.doseCount,
      steadyState: steadyState ?? this.steadyState,
    );
  }
}

/// 单个给药间隔内的药动学指标。
class IntervalMetrics {
  const IntervalMetrics({
    required this.cMax,
    required this.tMax,
    required this.cMin,
    required this.auc,
    required this.cAvg,
    required this.start,
    required this.end,
  });

  final double cMax;

  /// 峰值出现的时间（绝对时间，h）。
  final double tMax;

  /// 区间末端浓度 (mg/L)。
  final double cMin;

  /// 区间内 AUC（梯形法，mg·h/L）。
  final double auc;

  /// 平均浓度 Cavg = AUC / 区间长度 (mg/L)。
  final double cAvg;

  final double start;
  final double end;
}

/// 单次给药后的完整药动学指标。
class SingleDoseMetrics {
  const SingleDoseMetrics({
    required this.cMax,
    required this.tMax,
    required this.auc,
    required this.aucInf,
    required this.tHalf,
    required this.clearance,
    required this.vss,
    required this.mrt,
    required this.duration,
  });

  final double cMax;
  final double tMax;
  final double auc;
  final double aucInf;
  final double tHalf;
  final double clearance;
  final double vss;
  final double mrt;
  final double duration;
}

/// 多次给药（稳态）指标。
class MultipleDoseMetrics {
  const MultipleDoseMetrics({
    required this.steady,
    required this.firstDose,
    required this.fluctuation,
    required this.accumulation,
    required this.timeToSteadyState,
  });

  /// 稳态一个给药间隔内的指标。
  final IntervalMetrics steady;

  /// 首剂一个给药间隔内的指标（用于计算蓄积比）。
  final IntervalMetrics firstDose;

  /// 波动度 FI = (Css,max − Css,min) / Css,avg。
  final double fluctuation;

  /// 蓄积比 R = Css,max / C1,max。
  final double accumulation;

  /// 达到稳态的时间 (h)。
  final double timeToSteadyState;
}

/// 模拟器：把 [PkScenario] 转成曲线与指标。
class PkSimulator {
  PkSimulator(this.scenario) : _profile = PkProfile(scenario.params);

  final PkScenario scenario;
  final PkProfile _profile;

  PkProfile get profile => _profile;

  /// t 时刻的总血药浓度（含既往剂量的叠加）。
  double concentrationAt(double t) {
    if (t < 0) return 0;
    if (!scenario.isRepeated) return profile.concentration(t);

    if (scenario.steadyState) {
      final tau = scenario.interval;
      var phase = t % tau;
      // t 正好落在给药间隔末尾时，应取左极限（谷浓度），而不是下一个周期的峰。
      if (phase == 0 && t > 0) phase = tau;
      return _steadyStateConcentration(phase);
    }

    final tau = scenario.interval;
    final lastIndex = math.min(scenario.doseCount - 1, (t / tau).floor());
    var sum = 0.0;
    for (var i = 0; i <= lastIndex; i++) {
      sum += profile.concentration(t - i * tau);
    }
    return sum;
  }

  /// 稳态下一个给药间隔内 phase∈[0, τ) 的浓度：把历史剂量向前叠加。
  double _steadyStateConcentration(double phase) {
    final tau = scenario.interval;
    var sum = 0.0;
    for (var i = 0; i < 400; i++) {
      final term = profile.concentration(phase + i * tau);
      sum += term;
      if (i >= 3 && term <= 1e-12 * math.max(sum, 1e-12)) break;
    }
    return sum;
  }

  /// 在 [0, duration] 上均匀采样。
  List<SamplePoint> sample({required double duration, int points = 900}) {
    final n = math.max(2, points);
    final out = <SamplePoint>[];
    for (var i = 0; i < n; i++) {
      final t = duration * i / (n - 1);
      out.add(SamplePoint(t, concentrationAt(t)));
    }
    return out;
  }

  /// 在一个区间内计算 Cmax/Tmax/AUC 等。
  IntervalMetrics intervalMetrics(double start, double end, {int samples = 4000}) {
    var n = math.max(8, samples);
    if (n.isEven) n += 1; // 复合 Simpson 需要偶数个小区间
    final step = (end - start) / (n - 1);
    var bestIdx = 0;
    var best = double.negativeInfinity;
    final values = List<double>.filled(n, 0);
    for (var i = 0; i < n; i++) {
      final c = concentrationAt(start + i * step);
      values[i] = c;
      if (c > best) {
        best = c;
        bestIdx = i;
      }
    }
    var auc = 0.0;
    for (var i = 0; i < n - 1; i += 2) {
      auc += step / 3 * (values[i] + 4 * values[i + 1] + values[i + 2]);
    }
    final cEnd = concentrationAt(end);
    final lo = start + math.max(0, bestIdx - 1) * step;
    final hi = start + math.min(n - 1, bestIdx + 1) * step;
    // 静注模型的峰值就在 t=0，避免黄金分割收敛到 1e-15 这样的噪声值。
    final refined = bestIdx == 0 ? start : _goldenMax(lo, hi);
    return IntervalMetrics(
      cMax: best,
      tMax: refined,
      cMin: cEnd,
      auc: auc,
      cAvg: auc / math.max(end - start, 1e-9),
      start: start,
      end: end,
    );
  }

  /// 单次给药的整体指标（[duration] 为观察时长）。
  SingleDoseMetrics singleDoseMetrics(double duration) {
    final m = intervalMetrics(0, duration, samples: 3000);
    final cl = profile.clearance;
    final terminalC = profile.concentration(duration);
    final aucInf = m.auc + terminalC / profile.terminalRate;
    return SingleDoseMetrics(
      cMax: m.cMax,
      tMax: m.tMax,
      auc: m.auc,
      aucInf: aucInf,
      tHalf: profile.tHalf,
      clearance: cl,
      vss: profile.vss,
      mrt: profile.mrt,
      duration: duration,
    );
  }

  /// 多次给药指标：稳态区间 + 首剂区间。
  MultipleDoseMetrics multipleDoseMetrics() {
    final tau = scenario.interval;
    final ssSim = PkSimulator(
      PkScenario(params: scenario.params, interval: tau, steadyState: true),
    );
    final steady = ssSim.intervalMetrics(0, tau, samples: 1200);
    final first = PkSimulator(PkScenario(params: scenario.params, interval: tau, doseCount: 1))
        .intervalMetrics(0, tau, samples: 1200);
    final fi = steady.cAvg <= 0 ? 0.0 : (steady.cMax - steady.cMin) / steady.cAvg;
    final rac = first.cMax <= 0 ? 1.0 : steady.cMax / first.cMax;
    return MultipleDoseMetrics(
      steady: steady,
      firstDose: first,
      fluctuation: fi,
      accumulation: rac,
      timeToSteadyState: ssSim.timeToSteadyState(),
    );
  }

  /// 达到 95% 稳态峰值所需时间 (h)。
  double timeToSteadyState() {
    final tau = scenario.interval;
    var ssPeak = 0.0;
    const n = 400;
    for (var i = 0; i < n; i++) {
      final c = _steadyStateConcentration(tau * i / (n - 1));
      if (c > ssPeak) ssPeak = c;
    }
    if (ssPeak <= 0) return 0;
    for (var dose = 1; dose <= 60; dose++) {
      var peak = 0.0;
      for (var i = 0; i < 200; i++) {
        final t = (dose - 1) * tau + tau * i / 199;
        var sum = 0.0;
        final lastIndex = math.min(dose - 1, (t / tau).floor());
        for (var j = 0; j <= lastIndex; j++) {
          sum += profile.concentration(t - j * tau);
        }
        if (sum > peak) peak = sum;
      }
      if (peak >= 0.95 * ssPeak) return dose * tau;
    }
    return 60 * tau;
  }

  double _goldenMax(double lo, double hi) {
    const invPhi = 0.6180339887498949;
    var a = lo;
    var b = hi;
    var c = b - invPhi * (b - a);
    var d = a + invPhi * (b - a);
    var fc = concentrationAt(c);
    var fd = concentrationAt(d);
    for (var i = 0; i < 60; i++) {
      if (fc > fd) {
        b = d;
        d = c;
        fd = fc;
        c = b - invPhi * (b - a);
        fc = concentrationAt(c);
      } else {
        a = c;
        c = d;
        fc = fd;
        d = a + invPhi * (b - a);
        fd = concentrationAt(d);
      }
    }
    return (a + b) / 2;
  }
}

