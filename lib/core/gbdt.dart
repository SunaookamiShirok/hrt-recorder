// XGBoost 风格的梯度提升回归树（GBDT）纯 Dart 实现。
//
// 与官方 XGBoost 的关键点一致：
//   · 二阶泰勒展开，损失函数用梯度 g 与海森 h；
//   · 叶节点权重 w* = −G/(H+λ)；
//   · 分裂增益 = ½[GL²/(HL+λ) + GR²/(HR+λ) − G²/(H+λ)] − γ；
//   · 学习率（shrinkage）、行采样、列采样、最小叶权重约束。
// 没有第三方依赖，因此可以跑在 Windows / Web / Android 上。
import 'dart:math' as math;

/// 回归树节点。
class TreeNode {
  const TreeNode.leaf(this.value)
      : featureIndex = -1,
        threshold = 0,
        left = null,
        right = null;

  const TreeNode.split({
    required this.featureIndex,
    required this.threshold,
    required this.left,
    required this.right,
  }) : value = 0;

  final int featureIndex;
  final double threshold;

  /// 叶节点输出值；内部节点为 0。
  final double value;
  final TreeNode? left;
  final TreeNode? right;

  bool get isLeaf => featureIndex < 0;

  /// 树的深度（根节点为 0）。
  int get depth {
    if (isLeaf) return 0;
    return 1 + math.max(left!.depth, right!.depth);
  }

  int get leafCount => isLeaf ? 1 : left!.leafCount + right!.leafCount;
}

/// 梯度提升回归器。
class GbdtRegressor {
  GbdtRegressor({
    this.nEstimators = 120,
    this.maxDepth = 4,
    this.learningRate = 0.1,
    this.lambda = 1.0,
    this.gamma = 0.0,
    this.minChildWeight = 1.0,
    this.subsample = 0.9,
    this.colsampleByTree = 0.9,
    this.seed = 42,
  });

  final int nEstimators;
  final int maxDepth;
  final double learningRate;
  final double lambda;
  final double gamma;
  final double minChildWeight;
  final double subsample;
  final double colsampleByTree;
  final int seed;

  final List<TreeNode> _trees = [];
  List<double> _importance = const [];
  double _baseScore = 0;
  int _nFeatures = 0;

  List<TreeNode> get trees => List.unmodifiable(_trees);
  int get treeCount => _trees.length;
  double get baseScore => _baseScore;

  /// 训练时使用的特征维度。
  int get nFeatures => _nFeatures;

  /// 归一化后的特征重要度（按分裂增益累计）。
  List<double> get featureImportance {
    final total = _importance.fold(0.0, (a, b) => a + b);
    if (total <= 0) return List.filled(_importance.length, 0);
    return [for (final v in _importance) v / total];
  }

  /// 训练。[onProgress] 会以 (已完成树数, 总树数) 回调。
  void fit(
    List<List<double>> x,
    List<double> y, {
    void Function(int done, int total)? onProgress,
  }) {
    if (x.isEmpty || x.length != y.length) {
      throw ArgumentError('特征与标签数量不一致');
    }
    final n = x.length;
    final m = x.first.length;
    _nFeatures = m;
    final rng = math.Random(seed);

    _baseScore = y.reduce((a, b) => a + b) / n;
    final pred = List<double>.filled(n, _baseScore);
    final rows = List<int>.generate(n, (i) => i);

    // 每个特征只排序一次，节点内按掩码过滤，避免反复排序。
    final sortedByFeature = <List<int>>[];
    for (var f = 0; f < m; f++) {
      final idx = List<int>.from(rows)..sort((a, b) => x[a][f].compareTo(x[b][f]));
      sortedByFeature.add(idx);
    }

    _trees.clear();
    _importance = List<double>.filled(m, 0);

    for (var t = 0; t < nEstimators; t++) {
      final gradients = List<double>.filled(n, 0);
      final hessians = List<double>.filled(n, 1);
      for (var i = 0; i < n; i++) {
        gradients[i] = pred[i] - y[i];
      }

      final sampled = subsample >= 1.0
          ? rows
          : [for (final i in rows) if (rng.nextDouble() < subsample) i];
      final features = <int>[];
      for (var f = 0; f < m; f++) {
        if (colsampleByTree >= 1.0 || rng.nextDouble() < colsampleByTree) features.add(f);
      }
      if (features.isEmpty) features.add(rng.nextInt(m));

      final tree = _build(
        indices: sampled.isEmpty ? rows : sampled,
        x: x,
        g: gradients,
        h: hessians,
        sortedByFeature: sortedByFeature,
        features: features,
        depth: 0,
      );
      _trees.add(tree);
      for (var i = 0; i < n; i++) {
        pred[i] += learningRate * _predictTree(tree, x[i]);
      }
      onProgress?.call(t + 1, nEstimators);
    }
  }

  double predict(List<double> x) {
    var out = _baseScore;
    for (final tree in _trees) {
      out += learningRate * _predictTree(tree, x);
    }
    return out;
  }

  double _predictTree(TreeNode node, List<double> x) {
    var current = node;
    while (!current.isLeaf) {
      current = x[current.featureIndex] <= current.threshold ? current.left! : current.right!;
    }
    return current.value;
  }

  TreeNode _build({
    required List<int> indices,
    required List<List<double>> x,
    required List<double> g,
    required List<double> h,
    required List<List<int>> sortedByFeature,
    required List<int> features,
    required int depth,
  }) {
    var totalG = 0.0;
    var totalH = 0.0;
    for (final i in indices) {
      totalG += g[i];
      totalH += h[i];
    }
    final leafValue = -totalG / (totalH + lambda);

    if (depth >= maxDepth || indices.length < 4 || totalH + lambda <= 0) {
      return TreeNode.leaf(leafValue);
    }

    final mask = List<bool>.filled(x.length, false);
    for (final i in indices) {
      mask[i] = true;
    }

    var bestGain = 0.0;
    var bestFeature = -1;
    var bestThreshold = 0.0;
    final dimension = x.first.length;

    for (final f in features) {
      if (f >= dimension) continue;
      final order = sortedByFeature[f];
      final local = <int>[];
      for (final i in order) {
        if (mask[i]) local.add(i);
      }
      if (local.length < 2) continue;

      var gl = 0.0;
      var hl = 0.0;
      for (var j = 0; j < local.length - 1; j++) {
        final i = local[j];
        gl += g[i];
        hl += h[i];
        final gr = totalG - gl;
        final hr = totalH - hl;
        if (hl < minChildWeight || hr < minChildWeight) continue;
        final v1 = x[local[j]][f];
        final v2 = x[local[j + 1]][f];
        if (v1 == v2) continue;
        final gain = 0.5 *
                (gl * gl / (hl + lambda) + gr * gr / (hr + lambda) - totalG * totalG / (totalH + lambda)) -
            gamma;
        if (gain > bestGain + 1e-12) {
          bestGain = gain;
          bestFeature = f;
          bestThreshold = (v1 + v2) / 2;
        }
      }
    }

    if (bestFeature < 0) {
      return TreeNode.leaf(leafValue);
    }

    _importance[bestFeature] += bestGain;

    final leftIdx = <int>[];
    final rightIdx = <int>[];
    for (final i in indices) {
      if (x[i][bestFeature] <= bestThreshold) {
        leftIdx.add(i);
      } else {
        rightIdx.add(i);
      }
    }
    if (leftIdx.isEmpty || rightIdx.isEmpty) return TreeNode.leaf(leafValue);

    return TreeNode.split(
      featureIndex: bestFeature,
      threshold: bestThreshold,
      left: _build(
        indices: leftIdx,
        x: x,
        g: g,
        h: h,
        sortedByFeature: sortedByFeature,
        features: features,
        depth: depth + 1,
      ),
      right: _build(
        indices: rightIdx,
        x: x,
        g: g,
        h: h,
        sortedByFeature: sortedByFeature,
        features: features,
        depth: depth + 1,
      ),
    );
  }
}
