import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pk_sim/core/fitting.dart';
import 'package:pk_sim/core/personal_calibration.dart';
import 'package:pk_sim/core/pk.dart';

void main() {
  const population = PkParams(
    model: PkModel.oneCompOral,
    dose: 2,
    vd: 700,
    k: 0.0693,
    ka: 5.0,
    f: 0.15,
  );

  test('少于 4 个点不校准', () {
    final points = [
      for (final t in <double>[1, 2, 3]) ObservedPoint(t, 1e-4),
    ];
    expect(
      calibratePersonal(
        scenario: const PkScenario(params: population),
        points: points,
      ),
      isNull,
    );
  });

  test('实测浓度整体偏高 1.5 倍 → 校准系数约 1.5，V 约缩小到 2/3', () {
    const truth = PkParams(
      model: PkModel.oneCompOral,
      dose: 2,
      vd: 700 / 1.5,
      k: 0.0693,
      ka: 5.0,
      f: 0.15,
    );
    final profile = PkProfile(truth);
    final points = [
      for (final t in <double>[1, 2, 4, 8, 12])
        ObservedPoint(t, profile.concentration(t)),
    ];
    final cal = calibratePersonal(
      scenario: const PkScenario(params: population),
      points: points,
    );
    expect(cal, isNotNull);
    expect(cal!.factor, closeTo(1.5, 0.02));
    expect(cal.r2, greaterThan(0.999));
    expect(cal.applyTo(population).vd, closeTo(700 / 1.5, 1));
  });

  test('个别离群点不会把系数带偏（用中位数）', () {
    final profile = PkProfile(population);
    final points = [
      for (final t in <double>[1, 2, 4, 8])
        ObservedPoint(t, profile.concentration(t)),
      // 一条明显异常的记录
      ObservedPoint(12, profile.concentration(12) * 10),
    ];
    final cal = calibratePersonal(
      scenario: const PkScenario(params: population),
      points: points,
    );
    expect(cal!.factor, closeTo(1.0, 0.05));
  });

  test('校准后曲线能贴合实测点', () {
    const truth = PkParams(
      model: PkModel.oneCompOral,
      dose: 2,
      vd: 450,
      k: 0.0693,
      ka: 5.0,
      f: 0.15,
    );
    final truthProfile = PkProfile(truth);
    final points = [
      for (final t in <double>[0.5, 1, 2, 4, 6, 10])
        ObservedPoint(t, truthProfile.concentration(t)),
    ];
    final cal = calibratePersonal(
      scenario: const PkScenario(params: population),
      points: points,
    );
    final fitted = PkSimulator(PkScenario(params: cal!.applyTo(population)));
    for (final p in points) {
      expect(fitted.concentrationAt(p.t), closeTo(p.c, p.c * 0.05));
    }
  });

  test('系数说明文字区分高低', () {
    expect(factorDescription(1.4), contains('高'));
    expect(factorDescription(0.6), contains('低'));
    expect(factorDescription(1.0), contains('基本一致'));
    expect(safeFactor(0), greaterThan(0));
    expect(math.max(1, 2), 2);
  });
}
