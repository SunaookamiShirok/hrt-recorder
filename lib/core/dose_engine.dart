// 由用药记录推算任意时刻的血药浓度（叠加法）。
import 'dart:math' as math;

import 'dose_record.dart';
import 'pk.dart';
import 'regimens.dart';

/// 某个时刻的浓度估计。
class DrugEstimate {
  const DrugEstimate({
    required this.drug,
    required this.central,
    required this.low68,
    required this.high68,
    required this.low95,
    required this.high95,
    required this.populationLow,
    required this.populationHigh,
  });

  final String drug;
  final double central;
  final double low68;
  final double high68;
  final double low95;
  final double high95;

  /// 完全不使用个体校准时的范围（V ±40%）。
  final double populationLow;
  final double populationHigh;
}

/// 简单的浓度计算器：把每条用药记录按对应方案叠加。
class DoseEngine {
  DoseEngine({
    required this.doses,
    required this.weight,
    this.individualVdRatio,
    this.inhibitedK,
  });

  final List<DoseRecord> doses;
  final double weight;

  /// 个体 V 相对人群 V 的比例（1.0 表示未校准）。
  final double? individualVdRatio;

  /// 实验性 CPA 抑制后的 k 值（仅对 E2 生效）。
  final double? inhibitedK;

  static String _regimenIdFor(String drug, String route) {
    if (drug == 'CPA') return 'cpa_oral';
    switch (route) {
      case '舌下':
        return 'e2_sublingual';
      case '贴片':
        return 'e2_patch';
      case '肌注':
        return 'e2_im';
      default:
        return 'e2_oral';
    }
  }

  PkParams _paramsFor(DoseRecord dose, {double? vdRatio}) {
    final regimen = regimenById(_regimenIdFor(dose.drug, dose.route));
    final p = regimen.toParams(weight: weight, dose: dose.dose);
    final ratio = vdRatio ?? 1.0;
    final k = (dose.drug == 'E2' && inhibitedK != null) ? inhibitedK! : p.k;
    return p.copyWith(vd: p.vd * ratio, k: k);
  }

  /// [at] 时刻某药物的总浓度 (mg/L)。
  double concentrationAt(String drug, DateTime at, {double? vdRatio}) {
    final ratio = vdRatio ?? individualVdRatio ?? 1.0;
    var sum = 0.0;
    for (final dose in doses) {
      if (dose.drug != drug) continue;
      final ageH = at.difference(dose.takenAt).inMinutes / 60.0;
      if (ageH < 0 || ageH > 24 * 60) continue;
      final params = _paramsFor(dose, vdRatio: ratio);
      sum += PkProfile(params).concentration(ageH);
    }
    return sum;
  }

  /// 采样一段时间的曲线。
  List<SamplePoint> series(
    String drug, {
    required DateTime from,
    required DateTime to,
    int points = 160,
    double? vdRatio,
  }) {
    final span = to.difference(from);
    final out = <SamplePoint>[];
    for (var i = 0; i < points; i++) {
      final at = from.add(span * (i / (points - 1)));
      out.add(SamplePoint(
        i * span.inMinutes / 60.0 / (points - 1),
        concentrationAt(drug, at, vdRatio: vdRatio),
      ));
    }
    return out;
  }

  /// 当前估计 + 区间。
  DrugEstimate estimate(String drug, DateTime now, {double relativeSd = 0.0}) {
    final central = concentrationAt(drug, now);
    final sd = math.max(relativeSd, 0.0);
    return DrugEstimate(
      drug: drug,
      central: central,
      low68: central * (1 - 1.0 * sd),
      high68: central * (1 + 1.0 * sd),
      low95: central * (1 - 1.96 * sd),
      high95: central * (1 + 1.96 * sd),
      // V 越大浓度越低：下限来自 V 上限（+40%），上限来自 V 下限（−40%）
      populationLow: concentrationAt(drug, now, vdRatio: 1 / 0.6),
      populationHigh: concentrationAt(drug, now, vdRatio: 1 / 1.4),
    );
  }
}
