// 个体化：用用户的真实化验值校准统一模型。
//
// 思路：化验点很少（通常 4–10 个），不足以同时反推 ka、k、V。
// 因此只校准「暴露水平」——求一个比例系数，把统一模型的整条曲线缩放到
// 用户的实际浓度；等价于调整表观分布容积 V（C ∝ 1/V）。
// 吸收与消除的形状仍来自统一模型，这样结果稳定、不会过拟合。
import 'dart:math' as math;

import 'fitting.dart' show ObservedPoint;
import 'pk.dart';

/// 个体校准结果。
class PersonalCalibration {
  const PersonalCalibration({
    required this.factor,
    required this.n,
    required this.r2,
    required this.meanRelError,
  });

  /// 用户实测 / 统一模型预测 的中位比例。
  final double factor;

  /// 参与校准的化验点数量。
  final int n;

  /// 校准后曲线对实测点的决定系数。
  final double r2;

  /// 校准后的平均相对误差（0.15 = 15%）。
  final double meanRelError;

  /// 校准后的个体化参数：只改动表观分布容积。
  PkParams applyTo(PkParams params) {
    final safe = factor <= 0 ? 1.0 : factor;
    return params.copyWith(vd: params.vd / safe);
  }
}

/// 用 [points]（时间 = 距给药小时数，浓度 = mg/L）校准 [scenario]。
///
/// 少于 4 个点、或预测值非正时返回 null。
PersonalCalibration? calibratePersonal({
  required PkScenario scenario,
  required List<ObservedPoint> points,
}) {
  if (points.length < 4) return null;
  final sim = PkSimulator(scenario);

  final ratios = <double>[];
  for (final p in points) {
    final predicted = sim.concentrationAt(p.t);
    if (predicted > 1e-12 && p.c > 0) {
      ratios.add(p.c / predicted);
    }
  }
  if (ratios.length < 4) return null;

  ratios.sort();
  // 用中位数而不是均值，避免个别异常化验值把模型带偏。
  final rawFactor = ratios[ratios.length ~/ 2];
  final factor = rawFactor.clamp(0.05, 20.0).toDouble();

  final observed = [for (final p in points) p.c];
  final mean = observed.reduce((a, b) => a + b) / observed.length;
  var sse = 0.0;
  var sst = 0.0;
  var rel = 0.0;
  for (final p in points) {
    final predicted = sim.concentrationAt(p.t) * factor;
    sse += (predicted - p.c) * (predicted - p.c);
    sst += (p.c - mean) * (p.c - mean);
    if (p.c > 0) rel += (predicted - p.c).abs() / p.c;
  }

  return PersonalCalibration(
    factor: factor,
    n: points.length,
    r2: sst <= 1e-12 ? 1.0 : 1 - sse / sst,
    meanRelError: rel / points.length,
  );
}

/// 校准系数换算成「等效 V 变化」的说明文字。
String factorDescription(double factor) {
  if (factor > 1.02) {
    return '你的实测浓度比统一模型高 ${((factor - 1) * 100).toStringAsFixed(0)}%，'
        '等效分布容积约缩小到 ${(1 / factor * 100).toStringAsFixed(0)}%';
  }
  if (factor < 0.98) {
    return '你的实测浓度比统一模型低 ${((1 - factor) * 100).toStringAsFixed(0)}%，'
        '等效分布容积约放大到 ${(1 / factor * 100).toStringAsFixed(0)}%';
  }
  return '你的实测水平与统一模型基本一致';
}

/// 用于在提示里显示的比例。
double safeFactor(double factor) => math.max(factor, 0.01);
