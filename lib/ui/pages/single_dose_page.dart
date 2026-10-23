// 单次给药模拟页。
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/calibration.dart';
import '../../core/calibration_settings.dart';
import '../../core/pk.dart';
import '../../core/regimens.dart';
import '../../data/lab_store.dart';
import '../../utils/format.dart';
import '../unit_scope.dart';
import '../widgets/chart.dart';
import '../widgets/common.dart';
import '../widgets/page_layout.dart';
import '../widgets/params_panel.dart';
import '../widgets/personal_model.dart';

class SingleDosePage extends StatefulWidget {
  const SingleDosePage({super.key});

  @override
  State<SingleDosePage> createState() => _SingleDosePageState();
}

class _SingleDosePageState extends State<SingleDosePage> {
  PkParams _params = regimens.first.toParams();
  Regimen _regimen = regimens.first;
  double? _durationOverride;
  bool? _usePersonal;
  double _spread = 0.5;

  void _selectRegimen(Regimen r) {
    setState(() {
      _regimen = r;
      _params = r.toParams(weight: _params.weight);
      _durationOverride = null;
    });
    UnitController.instance.set(r.defaultUnit);
  }

  @override
  void initState() {
    super.initState();
    LabStore.instance.addListener(_onLabChanged);
    CalibrationSettings.instance.addListener(_onLabChanged);
    LabStore.instance.ensureLoaded();
  }

  @override
  void dispose() {
    LabStore.instance.removeListener(_onLabChanged);
    CalibrationSettings.instance.removeListener(_onLabChanged);
    super.dispose();
  }

  void _onLabChanged() {
    if (mounted) setState(() {});
  }

  double get _autoDuration {
    final tHalf = PkProfile(_params).tHalf;
    var d = tHalf.isFinite ? 6 * tHalf : 48.0;
    // 恒速输入（贴片/输注）必须覆盖整个输入期，否则曲线会被截断。
    if (_params.model.isZeroOrder) {
      d = math.max(d, _params.infusionDuration * 1.6);
    }
    return d.clamp(4.0, 240.0).toDouble();
  }

  double get _duration => _durationOverride ?? _autoDuration;

  void _update(PkParams p) => setState(() => _params = p);

  /// 人群基准参数：E2 方案在开启实验性 CPA 相互作用时降低清除率。
  PkParams _populationParams() {
    final s = CalibrationSettings.instance;
    if (s.cpaInteraction && _regimen.analyte == 'E2') {
      return _params.copyWith(k: _params.k * (1 - s.cpaInhibition));
    }
    return _params;
  }

  @override
  Widget build(BuildContext context) {
    final settings = CalibrationSettings.instance;
    // 人群基准参数（含实验性的 CPA 相互作用）
    final population = _populationParams();
    // 个体模型：只用与当前方案同指标的化验记录校准（至少 4 条带「距给药」）
    final personalAnalyte = _regimen.analyte;
    final canPersonal = LabStore.instance.taggedCount(personalAnalyte) >= 4;
    final usePersonal = (_usePersonal ?? canPersonal) && canPersonal;
    final calibration = usePersonal
        ? calibrateIndividual(
            method: settings.method,
            population: population,
            points: LabStore.instance.calibrationPoints(personalAnalyte),
          )
        : null;
    final effectiveParams = calibration?.applyTo(population) ?? population;

    final sim = PkSimulator(PkScenario(params: effectiveParams));
    final metrics = sim.singleDoseMetrics(_duration);
    final samples = sim.sample(duration: _duration, points: 520);
    final scheme = Theme.of(context).colorScheme;
    final unit = UnitScope.of(context);

    // 预测区间：校准后改用后验不确定度（95%），未校准时用手动百分比
    final halfWidth = calibration != null
        ? (calibration.relativeSd * 1.96).clamp(0.05, 1.5)
        : _spread;
    final bandLow = [
      for (final p in samples) SamplePoint(p.t, math.max(0, p.c * (1 - halfWidth))),
    ];
    final bandHigh = [for (final p in samples) SamplePoint(p.t, p.c * (1 + halfWidth))];
    // 个体模型下同时画出统一模型，便于对比
    final unifiedSamples = (calibration != null)
        ? PkSimulator(PkScenario(params: population)).sample(duration: _duration, points: 520)
        : null;

    final chart = Container(
      padding: const EdgeInsets.only(top: 6),
      child: ConcentrationChart(
        series: [
          if (unifiedSamples != null)
            ChartSeries(
              points: convertSamples(unifiedSamples, unit),
              color: scheme.outline,
              dashed: true,
              width: 1.8,
              label: '统一模型',
            ),
          ChartSeries(
            points: convertSamples(samples, unit),
            color: scheme.primary,
            fill: true,
            label: calibration != null ? '个体模型' : '预测血药浓度',
          ),
        ],
        bands: halfWidth > 0
            ? [
                ChartBand(
                  low: convertSamples(bandLow, unit),
                  high: convertSamples(bandHigh, unit),
                  color: scheme.primary,
                  label: calibration != null
                      ? '95% 区间'
                      : '个体差异 ±${(_spread * 100).round()}%',
                ),
              ]
            : const [],
        markers: [
          if (metrics.tMax > 0 && metrics.tMax <= _duration)
            ChartMarker(metrics.tMax, unit.convert(metrics.cMax), label: 'Cmax'),
        ],
        yUnit: unit.label,
        height: 360,
      ),
    );

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(context),
        const SizedBox(height: 14),
        SectionCard(
          title: '浓度-时间曲线',
          subtitle: '悬停 / 拖动查看任意时刻的浓度',
          icon: Icons.show_chart,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (calibration == null) ...[
                _spreadSelector(context),
                const SizedBox(width: 8),
              ],
              _durationChip(context),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
          child: chart,
        ),
        const SizedBox(height: 14),
        _metricsGrid(context, metrics),
        const SizedBox(height: 14),
        _sampleTable(context, samples),
      ],
    );

    final controls = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RegimenPicker(selected: _regimen, onSelected: _selectRegimen),
        const SizedBox(height: 12),
        ModelSourceSwitch(
          usePersonal: usePersonal,
          canUsePersonal: canPersonal,
          recordCount: LabStore.instance.taggedCount(personalAnalyte),
          onChanged: (v) => setState(() => _usePersonal = v),
        ),
        const SizedBox(height: 12),
        if (usePersonal)
          PersonalModelCard(
            analyte: personalAnalyte,
            calibration: calibration,
            baseParams: population,
            scenarioHint: '按单次给药校准',
            method: settings.method,
            onMethodChanged: (m) => setState(() => settings.setMethod(m)),
            dose: _params.dose,
            onDoseChanged: (v) => setState(() => _params = _params.copyWith(dose: v)),
          )
        else
          ParamsPanel(
            params: _params,
            onChanged: _update,
            extra: _durationControl(context),
          ),
        const SizedBox(height: 12),
        InfoBanner(text: _formulaText()),
        const SizedBox(height: 12),
        const InfoBanner(
          icon: Icons.health_and_safety_outlined,
          text: '本工具用于药理学教学与科研计算，所有参数需由使用者自行确认，不能作为临床给药依据。',
        ),
      ],
    );

    return ResponsivePage(controls: controls, body: body);
  }

  Widget _header(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('单次给药模拟',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(
                '选择模型与参数，实时得到浓度-时间曲线及 Cmax / Tmax / AUC 等指标',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }


  Widget _durationControl(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('观察时长', style: Theme.of(context).textTheme.bodySmall),
            Text('${fmtNum(_duration, maxSignificant: 3)} h',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    )),
          ],
        ),
        Slider(
          value: _duration.clamp(1.0, 240.0).toDouble(),
          min: 1,
          max: 240,
          divisions: 239,
          label: '${fmtNum(_duration, maxSignificant: 3)} h',
          onChanged: (v) => setState(() => _durationOverride = v),
        ),
      ],
    );
  }

  Widget _spreadSelector(BuildContext context) {
    return DropdownButton<double>(
      value: _spread,
      underline: const SizedBox.shrink(),
      style: Theme.of(context).textTheme.labelMedium,
      items: const [
        DropdownMenuItem(value: 0.0, child: Text('无区间')),
        DropdownMenuItem(value: 0.25, child: Text('±25%')),
        DropdownMenuItem(value: 0.5, child: Text('±50%')),
        DropdownMenuItem(value: 0.75, child: Text('±75%')),
      ],
      onChanged: (v) {
        if (v != null) setState(() => _spread = v);
      },
    );
  }

  Widget _durationChip(BuildContext context) {
    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: const Icon(Icons.schedule, size: 16),
      label: Text('${fmtNum(_duration, maxSignificant: 3)} h'),
    );
  }

  Widget _metricsGrid(BuildContext context, SingleDoseMetrics m) {
    final unit = UnitScope.of(context);
    final tiles = <Widget>[
      MetricTile(
        label: 'Cmax',
        value: unit.format(m.cMax),
        unit: unit.label,
        hint: '峰浓度',
        color: Theme.of(context).colorScheme.primary,
      ),
      MetricTile(label: 'Tmax', value: fmtNum(m.tMax), unit: 'h', hint: '达峰时间'),
      MetricTile(
        label: 'AUC₀₋∞',
        value: unit.format(m.aucInf),
        unit: unit.aucLabel,
        hint: '曲线下总面积',
      ),
      MetricTile(label: 't½', value: fmtNum(m.tHalf), unit: 'h', hint: '消除半衰期'),
      MetricTile(label: 'CL', value: fmtNum(m.clearance), unit: 'L/h', hint: '清除率'),
      MetricTile(label: 'Vss', value: fmtNum(m.vss), unit: 'L', hint: '稳态分布容积'),
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

  Widget _sampleTable(BuildContext context, List<SamplePoint> samples) {
    final unit = UnitScope.of(context);
    final step = (samples.length / 12).ceil().clamp(1, samples.length);
    final rows = <SamplePoint>[
      for (var i = 0; i < samples.length; i += step) samples[i],
      if ((samples.length - 1) % step != 0) samples.last,
    ];
    final csv = StringBuffer('t_h,C_${unit.label.replaceAll('/', '_')}\n');
    for (final p in rows) {
      csv.writeln('${p.t.toStringAsFixed(2)},${unit.convert(p.c).toStringAsFixed(4)}');
    }

    return SectionCard(
      title: '数据表（每 ${fmtNum(_duration / (rows.length - 1), maxSignificant: 2)} h 取点）',
      icon: Icons.table_rows_outlined,
      trailing: TextButton.icon(
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: csv.toString()));
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('已复制 CSV 到剪贴板')),
          );
        },
        icon: const Icon(Icons.copy_all, size: 16),
        label: const Text('复制 CSV'),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 36,
          dataRowMinHeight: 30,
          dataRowMaxHeight: 36,
          columnSpacing: 28,
          columns: [
            const DataColumn(label: Text('t (h)')),
            DataColumn(label: Text('C (${unit.label})')),
          ],
          rows: [
            for (final p in rows)
              DataRow(cells: [
                DataCell(Text(fmtNum(p.t, maxSignificant: 4))),
                DataCell(Text(unit.format(p.c))),
              ]),
          ],
        ),
      ),
    );
  }

  String _formulaText() {
    switch (_params.model) {
      case PkModel.oneCompIv:
        return '一室静注：C(t) = (D / V) · e^(−k·t)，其中 t½ = ln2 / k，AUC₀₋∞ = D / CL。';
      case PkModel.oneCompOral:
        return '一室口服：C(t) = F·D·ka / [V·(ka − k)] · (e^(−k·t) − e^(−ka·t))，要求 ka ≠ k。';
      case PkModel.twoCompIv:
        return '二室静注：C(t) = A·e^(−α·t) + B·e^(−β·t)，A + B = D / V1，α、β 由 k10、k12、k21 决定。';
      case PkModel.zeroOrder:
        return '恒速输入（输注/贴片）：输入期间 C(t) = R0/CL · (1 − e^(−k·t))，'
            '结束后按 C(T)·e^(−k·(t−T)) 衰减，R0 = D / T，稳态 Css = R0 / CL。';
      case PkModel.dualAbsorption:
        return '双吸收相（含服/复方）：两个一级吸收项并联，F1、F2 是快相/慢相'
            '占总剂量的比例（F1 + F2 = F）：快相决定早期尖峰，慢相决定后段拖尾。';
    }
  }
}
