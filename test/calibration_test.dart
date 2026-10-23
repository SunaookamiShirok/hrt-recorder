import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pk_sim/core/calibration.dart';
import 'package:pk_sim/core/pk.dart';

void main() {
  const population = PkParams(
    model: PkModel.oneCompOral,
    dose: 2,
    vd: 860,
    k: 0.045,
    ka: 1.2,
    f: 0.05,
  );

  // 模拟一个真实 V 不同的个体，在 6 个时间点采血
  List<CalibrationPoint> buildPoints({
    required double trueVd,
    int n = 6,
    double noise = 0.0,
    Duration spacing = const Duration(days: 14),
  }) {
    final profile = PkProfile(population.copyWith(vd: trueVd));
    final rng = math.Random(7);
    final times = <double>[1, 2, 4, 8, 12, 24];
    return [
      for (var i = 0; i < n; i++)
        CalibrationPoint(
          at: DateTime(2026, 1, 1).add(spacing * i),
          tHours: times[i % times.length],
          concentration: profile.concentration(times[i % times.length]) *
              (1 + (rng.nextDouble() * 2 - 1) * noise),
        ),
    ];
  }

  group('四种校准引擎', () {
    test('经验法能还原 1.5 倍的 V', () {
      final pts = buildPoints(trueVd: 860 * 1.5);
      final r = calibrateIndividual(
        method: CalibrationMethod.empirical,
        population: population,
        points: pts,
        now: DateTime(2026, 2, 1),
      );
      expect(r, isNotNull);
      expect(r!.vd, closeTo(860 * 1.5, 40));
      expect(r.r2, greaterThan(0.99));
    });

    test('OU-Kalman 能收敛到真实 V', () {
      final pts = buildPoints(trueVd: 500);
      final r = calibrateIndividual(
        method: CalibrationMethod.ouKalman,
        population: population,
        points: pts,
        now: DateTime(2026, 4, 1),
      );
      expect(r, isNotNull);
      expect(r!.vd, closeTo(500, 80));
      expect(r.history.length, pts.length);
      expect(r.vdSd, greaterThan(0));
    });

    test('EKF 能给出有限的 V 与 k 估计', () {
      final pts = buildPoints(trueVd: 1200);
      final r = calibrateIndividual(
        method: CalibrationMethod.ekf,
        population: population,
        points: pts,
        now: DateTime(2026, 4, 1),
      );
      expect(r, isNotNull);
      expect(r!.vd.isFinite, isTrue);
      expect(r.vd, greaterThan(0));
      expect(r.vdSd.isFinite, isTrue);
    });

    test('贝叶斯 MAP 在无噪声数据上贴近真值', () {
      final pts = buildPoints(trueVd: 600);
      final r = calibrateIndividual(
        method: CalibrationMethod.bayes,
        population: population,
        points: pts,
        now: DateTime(2026, 4, 1),
      );
      expect(r, isNotNull);
      expect(r!.vd, closeTo(600, 120));
      expect(r.r2, greaterThan(0.9));
    });

    test('少于 4 个点全部返回 null', () {
      final pts = buildPoints(trueVd: 600, n: 3);
      for (final m in CalibrationMethod.values) {
        expect(
          calibrateIndividual(method: m, population: population, points: pts),
          isNull,
          reason: m.label,
        );
      }
    });

    test('实验标记：只有贝叶斯是实验性', () {
      expect(CalibrationMethod.bayes.experimental, isTrue);
      expect(CalibrationMethod.empirical.experimental, isFalse);
      expect(CalibrationMethod.ouKalman.experimental, isFalse);
      expect(CalibrationMethod.ekf.experimental, isFalse);
    });
  });

  group('CPA 相互作用对 E2 清除的影响', () {
    test('降低 k 会抬高稳态浓度', () {
      const base = PkParams(
        model: PkModel.oneCompOral,
        dose: 2,
        vd: 860,
        k: 0.045,
        ka: 1.2,
        f: 0.05,
      );
      final inhibited = base.copyWith(k: base.k * 0.75);
      final normal = PkSimulator(const PkScenario(params: base, interval: 24, steadyState: true))
          .concentrationAt(12);
      final withCpa =
          PkSimulator(PkScenario(params: inhibited, interval: 24, steadyState: true))
              .concentrationAt(12);
      expect(withCpa, greaterThan(normal));
      expect(withCpa, closeTo(normal * 0.045 / (0.045 * 0.75), normal * 0.2));
    });
  });
}
