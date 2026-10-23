import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pk_sim/core/dataset.dart';
import 'package:pk_sim/core/fitting.dart';
import 'package:pk_sim/core/pk.dart';

void main() {
  group('单室口服拟合', () {
    const truth = PkParams(
      model: PkModel.oneCompOral,
      dose: 400,
      vd: 50,
      k: 0.14,
      ka: 1.1,
      f: 1.0,
    );

    final profile = PkProfile(truth);
    final points = [
      for (final t in <double>[0.5, 1, 1.5, 2, 3, 4, 6, 8, 10, 12, 18, 24])
        ObservedPoint(t, profile.concentration(t)),
    ];

    test('能还原 k 与 ka（无噪声）', () {
      final result = PkFitter(points: points, dose: 400).fitOral();
      expect(result.params.k, closeTo(0.14, 0.01));
      expect(result.params.ka, closeTo(1.1, 0.1));
      expect(result.params.vd, closeTo(50, 4));
      expect(result.r2, greaterThan(0.99));
    });

    test('有噪声时仍能拟合出合理参数', () {
      final noisy = demoOralData();
      final result = PkFitter(points: noisy, dose: 400).fitOral();
      expect(result.params.k, closeTo(0.14, 0.03));
      expect(result.params.ka, closeTo(1.1, 0.35));
      expect(result.r2, greaterThan(0.95));
    });

    test('拟合曲线与数据点数量一致', () {
      final result = PkFitter(points: points, dose: 400).fitOral();
      expect(result.predicted.length, points.length);
      expect(result.curve(duration: 24, points: 50).length, 50);
    });
  });

  group('单室静注拟合', () {
    const truth = PkParams(model: PkModel.oneCompIv, dose: 500, vd: 35, k: 0.12);
    final profile = PkProfile(truth);
    final points = [
      for (final t in <double>[0.25, 0.5, 1, 2, 4, 6, 8, 12, 24])
        ObservedPoint(t, profile.concentration(t)),
    ];

    test('能还原 k 与表观分布容积', () {
      final result = PkFitter(points: points, dose: 500).fitIv();
      expect(result.params.k, closeTo(0.12, 0.005));
      expect(result.params.vd, closeTo(35, 1.5));
      expect(result.r2, greaterThan(0.999));
    });
  });

  group('Nelder–Mead', () {
    test('能最小化二次函数', () {
      final nm = NelderMead((x) => math.pow(x[0] - 3, 2) + math.pow(x[1] + 1, 2).toDouble());
      final best = nm.minimize([0.0, 0.0]);
      expect(best[0], closeTo(3, 1e-3));
      expect(best[1], closeTo(-1, 1e-3));
    });
  });
}
