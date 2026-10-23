// XGBoost 风格梯度提升代理模型页。
//
// 用内置合成数据集训练一个「给药参数 → 血药浓度」的回归模型，
// 再与解析解对比，直观看到机器学习模型在 PK 问题上的精度。
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/dataset.dart';
import '../../core/gbdt.dart';
import '../../core/pk.dart';
import '../../utils/format.dart';
import '../unit_scope.dart';
import '../widgets/chart.dart';
import '../widgets/common.dart';
import '../widgets/page_layout.dart';

/// 训练请求（可跨 isolate 传输）。
class TrainRequest {
  const TrainRequest({
    required this.rows,
    required this.nEstimators,
    required this.maxDepth,
    required this.learningRate,
    required this.lambda,
  });

  final List<TrainingRow> rows;
  final int nEstimators;
  final int maxDepth;
  final double learningRate;
  final double lambda;
}

/// 训练结果。
class TrainResult {
  const TrainResult({
    required this.model,
    required this.trainR2,
    required this.validR2,
    required this.validRmse,
    required this.trainRows,
    required this.validRows,
  });

  final GbdtRegressor model;
  final double trainR2;
  final double validR2;
  final double validRmse;
  final int trainRows;
  final int validRows;
}

/// 顶层训练函数，供 compute 调用。
TrainResult trainPkSurrogate(TrainRequest req) {
  final split = splitDataset(req.rows, validRatio: 0.2, seed: 11);
  final model = GbdtRegressor(
    nEstimators: req.nEstimators,
    maxDepth: req.maxDepth,
    learningRate: req.learningRate,
    lambda: req.lambda,
    subsample: 0.9,
    colsampleByTree: 0.9,
    seed: 42,
  )..fit(
      [for (final r in split.train) r.x],
      [for (final r in split.train) r.y],
    );

  double r2(List<TrainingRow> rows) {
    if (rows.isEmpty) return 0;
    final mean = rows.map((r) => r.y).reduce((a, b) => a + b) / rows.length;
    var sse = 0.0;
    var sst = 0.0;
    for (final r in rows) {
      final p = model.predict(r.x);
      sse += (p - r.y) * (p - r.y);
      sst += (r.y - mean) * (r.y - mean);
    }
    return sst <= 1e-12 ? 1 : 1 - sse / sst;
  }

  var rmse = 0.0;
  for (final r in split.valid) {
    final pred = targetToConcentration(model.predict(r.x));
    final actual = targetToConcentration(r.y);
    rmse += (pred - actual) * (pred - actual);
  }
  rmse = split.valid.isEmpty ? 0 : math.sqrt(rmse / split.valid.length);

  return TrainResult(
    model: model,
    trainR2: r2(split.train),
    validR2: r2(split.valid),
    validRmse: rmse,
    trainRows: split.train.length,
    validRows: split.valid.length,
  );
}

class MlPage extends StatefulWidget {
  const MlPage({super.key});

  @override
  State<MlPage> createState() => _MlPageState();
}

class _MlPageState extends State<MlPage> {
  TrainResult? _result;
  bool _training = false;
  String? _error;

  int _trees = 120;
  int _depth = 5;
  double _eta = 0.15;
  double _lambda = 1.0;

  PkParams _params = const PkParams(
    model: PkModel.oneCompOral,
    dose: 2,
    vd: 860,
    k: 0.045,
    ka: 1.2,
    f: 0.05,
  );
  double _horizon = 36;

  Future<void> _train() async {
    setState(() {
      _training = true;
      _error = null;
    });
    final rows = generateSyntheticDataset(rows: 1600, seed: 7);
    final request = TrainRequest(
      rows: rows,
      nEstimators: _trees,
      maxDepth: _depth,
      learningRate: _eta,
      lambda: _lambda,
    );
    try {
      final result = await compute(trainPkSurrogate, request, debugLabel: 'gbdt-train');
      if (!mounted) return;
      setState(() {
        _result = result;
        _training = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '训练失败：$e';
        _training = false;
      });
    }
  }

  List<double> _featuresFor(PkParams p, double t) => [
        p.dose,
        p.vd,
        p.k,
        p.model.isOral ? p.ka : 0.0,
        p.f,
        p.model.isOral ? 1.0 : 0.0,
        timeFeature(t),
      ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final unit = UnitScope.of(context);
    final result = _result;
    final analytic = PkSimulator(PkScenario(params: _params));
    final analyticCurve = analytic.sample(duration: _horizon, points: 120);

    final List<SamplePoint>? mlCurve = result == null
        ? null
        : [
            for (var i = 0; i <= 120; i++)
              SamplePoint(
                _horizon * i / 120,
                targetToConcentration(
                  result.model.predict(_featuresFor(_params, _horizon * i / 120)),
                ),
              ),
          ];

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('XGBoost 风格代理模型',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(
          '纯 Dart 实现的梯度提升树（二阶泰勒 + 正则化分裂增益），训练后可直接预测浓度并与解析解对比',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: '预测对比',
          subtitle: result == null ? '先在右侧训练模型' : '蓝线为模型预测，虚橙线为一室解析解',
          icon: Icons.insights,
          trailing: _training
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
          child: Column(
            children: [
              ConcentrationChart(
                series: [
                  if (mlCurve != null)
                    ChartSeries(
                      points: convertSamples(mlCurve, unit),
                      color: scheme.primary,
                      fill: true,
                      label: 'GBDT 预测',
                    ),
                  ChartSeries(
                    points: convertSamples(analyticCurve, unit),
                    color: const Color(0xFFE8590C),
                    label: '解析解',
                    dashed: true,
                    width: 1.8,
                  ),
                ],
                yUnit: unit.label,
                height: 340,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (_error != null) ...[
          InfoBanner(icon: Icons.error_outline, text: _error!),
          const SizedBox(height: 12),
        ],
        if (result != null) ...[
          _metricsGrid(context, result, analyticCurve, mlCurve!),
          const SizedBox(height: 14),
          _importanceCard(context, result),
          const SizedBox(height: 12),
        ] else
          InfoBanner(
            text: '训练数据由内置 PK 模型随机生成（${1600} 行，覆盖静注/口服、不同剂量与速率常数），'
                '标签为 ln(C + 0.001)，因此模型在低浓度段也有分辨率。',
          ),
      ],
    );

    final controls = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          title: '模型超参数',
          icon: Icons.account_tree_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sliderRow(
                context,
                '树数量',
                _trees.toDouble(),
                40,
                300,
                (v) => setState(() => _trees = v.round()),
                suffix: '棵',
              ),
              _sliderRow(
                context,
                '最大深度',
                _depth.toDouble(),
                2,
                8,
                (v) => setState(() => _depth = v.round()),
                suffix: '层',
              ),
              _sliderRow(
                context,
                '学习率 η',
                _eta,
                0.02,
                0.5,
                (v) => setState(() => _eta = v),
                digits: 2,
              ),
              _sliderRow(
                context,
                'L2 正则 λ',
                _lambda,
                0.1,
                10,
                (v) => setState(() => _lambda = v),
                digits: 1,
              ),
              const SizedBox(height: 4),
              FilledButton.icon(
                onPressed: _training ? null : _train,
                icon: const Icon(Icons.model_training, size: 18),
                label: Text(_training ? '训练中…' : (_result == null ? '训练模型' : '重新训练')),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: '预测参数',
          icon: Icons.tune,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<PkModel>(
                segments: const [
                  ButtonSegment(value: PkModel.oneCompIv, label: Text('静注'), icon: Icon(Icons.bolt_outlined, size: 16)),
                  ButtonSegment(value: PkModel.oneCompOral, label: Text('口服'), icon: Icon(Icons.water_drop_outlined, size: 16)),
                ],
                selected: {_params.model},
                onSelectionChanged: (s) => setState(() => _params = _params.copyWith(model: s.first)),
              ),
              const SizedBox(height: 10),
              ParamField(
                label: '剂量 D',
                unit: 'mg',
                value: _params.dose,
                onChanged: (v) => setState(() => _params = _params.copyWith(dose: v)),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ParamField(
                      label: '分布容积 V',
                      unit: 'L',
                      value: _params.vd,
                      onChanged: (v) => setState(() => _params = _params.copyWith(vd: v)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ParamField(
                      label: '消除常数 k',
                      unit: 'h⁻¹',
                      value: _params.k,
                      onChanged: (v) => setState(() => _params = _params.copyWith(k: v)),
                    ),
                  ),
                ],
              ),
              if (_params.model.isOral) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ParamField(
                        label: '吸收常数 ka',
                        unit: 'h⁻¹',
                        value: _params.ka,
                        onChanged: (v) => setState(() => _params = _params.copyWith(ka: v)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ParamField(
                        label: '生物利用度 F',
                        unit: '0–1',
                        value: _params.f,
                        onChanged: (v) => setState(() => _params = _params.copyWith(f: v)),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              _sliderRow(
                context,
                '预测时长',
                _horizon,
                6,
                96,
                (v) => setState(() => _horizon = v),
                suffix: 'h',
                digits: 0,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const InfoBanner(
          icon: Icons.memory,
          text: '这是 XGBoost 算法的独立 Dart 实现，不依赖 Python 或 libxgboost，'
              '因此同一套代码可以跑在 Android 与 Web 上。',
        ),
      ],
    );

    return ResponsivePage(controls: controls, body: body);
  }

  Widget _sliderRow(
    BuildContext context,
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged, {
    String? suffix,
    int digits = 0,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            Text(
              '${value.toStringAsFixed(digits)}${suffix ?? ''}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
            ),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: max - min <= 1 ? 1 : (max - min).round().clamp(2, 60),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _metricsGrid(
    BuildContext context,
    TrainResult r,
    List<SamplePoint> analytic,
    List<SamplePoint> ml,
  ) {
    final unit = UnitScope.of(context);
    var maxRel = 0.0;
    var sumRel = 0.0;
    var n = 0;
    // 只在「有效浓度区间」（峰值的 5% 以上）统计相对误差，避免近零浓度把比例放大。
    final peak = analytic.fold(0.0, (a, p) => p.c > a ? p.c : a);
    final cutoff = peak * 0.05;
    for (var i = 0; i < analytic.length && i < ml.length; i++) {
      final truth = analytic[i].c;
      if (truth < cutoff) continue;
      final rel = (ml[i].c - truth).abs() / truth;
      maxRel = rel > maxRel ? rel : maxRel;
      sumRel += rel;
      n++;
    }
    final meanRel = n == 0 ? 0.0 : sumRel / n;

    final tiles = <Widget>[
      MetricTile(
        label: '验证集 R²',
        value: fmtNum(r.validR2, maxSignificant: 4),
        hint: '对数浓度空间',
        color: Theme.of(context).colorScheme.primary,
      ),
      MetricTile(label: '训练集 R²', value: fmtNum(r.trainR2, maxSignificant: 4), hint: '拟合优度'),
      MetricTile(
        label: '验证 RMSE',
        value: unit.format(r.validRmse),
        unit: unit.label,
        hint: '浓度均方根误差',
      ),
      MetricTile(
        label: '平均相对误差',
        value: fmtNum(meanRel * 100, maxSignificant: 3),
        unit: '%',
        hint: '峰值 5% 以上区间',
      ),
      MetricTile(
        label: '最大相对误差',
        value: fmtNum(maxRel * 100, maxSignificant: 3),
        unit: '%',
        hint: '峰值 5% 以上区间',
      ),
      MetricTile(label: '训练 / 验证样本', value: '${r.trainRows} / ${r.validRows}'),
      MetricTile(label: '树数量', value: '${r.model.treeCount}', unit: '棵'),
      MetricTile(label: '叶子总数', value: '${r.model.trees.fold(0, (a, t) => a + t.leafCount)}'),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final columns = (c.maxWidth / 190).floor().clamp(1, 6);
        final width = (c.maxWidth - 10 * (columns - 1)) / columns;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final t in tiles) SizedBox(width: width, child: t),
          ],
        );
      },
    );
  }

  Widget _importanceCard(BuildContext context, TrainResult r) {
    final importance = r.model.featureImportance;
    final maxValue = importance.fold(0.0, (a, b) => a > b ? a : b);
    return SectionCard(
      title: '特征重要度',
      subtitle: '按分裂增益累计并归一化',
      icon: Icons.bar_chart,
      child: Column(
        children: [
          for (var i = 0; i < surrogateFeatures.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 120,
                    child: Text(
                      '${surrogateFeatures[i].name} (${surrogateFeatures[i].unit})',
                      style: Theme.of(context).textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: maxValue <= 0 ? 0 : importance[i] / maxValue,
                        minHeight: 10,
                        backgroundColor:
                            Theme.of(context).colorScheme.surfaceContainerHighest,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 52,
                    child: Text(
                      '${(importance[i] * 100).toStringAsFixed(1)}%',
                      textAlign: TextAlign.right,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
