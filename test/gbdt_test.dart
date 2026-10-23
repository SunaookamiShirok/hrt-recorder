import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pk_sim/core/dataset.dart';
import 'package:pk_sim/core/gbdt.dart';

void main() {
  group('GBDT 基础拟合', () {
    final rng = math.Random(1);
    final x = <List<double>>[];
    final y = <double>[];
    for (var i = 0; i < 400; i++) {
      final a = rng.nextDouble() * 10;
      final b = rng.nextDouble() * 10;
      x.add([a, b]);
      y.add(2 * a + math.sin(b) * 5);
    }

    final model = GbdtRegressor(nEstimators: 80, maxDepth: 4, learningRate: 0.2)
      ..fit(x, y);

    test('训练后残差明显下降', () {
      var sse = 0.0;
      var sst = 0.0;
      final mean = y.reduce((a, b) => a + b) / y.length;
      for (var i = 0; i < x.length; i++) {
        final p = model.predict(x[i]);
        sse += (p - y[i]) * (p - y[i]);
        sst += (y[i] - mean) * (y[i] - mean);
      }
      expect(1 - sse / sst, greaterThan(0.95));
    });

    test('树的数量与深度受参数约束', () {
      expect(model.treeCount, 80);
      for (final tree in model.trees) {
        expect(tree.depth, lessThanOrEqualTo(4));
      }
    });

    test('特征重要度归一化', () {
      final importance = model.featureImportance;
      expect(importance.length, 2);
      expect(importance.reduce((a, b) => a + b), closeTo(1.0, 1e-9));
    });
  });

  group('血药浓度代理模型', () {
    test('在合成数据上验证集 R² 达到可用水平', () {
      final rows = generateSyntheticDataset(rows: 900, seed: 5);
      final split = splitDataset(rows);
      final model = GbdtRegressor(nEstimators: 60, maxDepth: 5, learningRate: 0.15)
        ..fit(
          [for (final r in split.train) r.x],
          [for (final r in split.train) r.y],
        );

      var sse = 0.0;
      var sst = 0.0;
      final mean = split.valid.map((r) => r.y).reduce((a, b) => a + b) / split.valid.length;
      for (final r in split.valid) {
        final p = model.predict(r.x);
        sse += (p - r.y) * (p - r.y);
        sst += (r.y - mean) * (r.y - mean);
      }
      expect(1 - sse / sst, greaterThan(0.9));
    });

    test('浓度经过对数变换可逆', () {
      for (final c in [0.0, 0.5, 12.3, 100.0]) {
        expect(targetToConcentration(concentrationToTarget(c)), closeTo(c, 1e-9));
      }
    });
  });
}
