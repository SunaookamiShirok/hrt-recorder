// 多次给药 / 稳态模拟页。
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

class MultiDosePage extends StatefulWidget {
  const MultiDosePage({super.key});

  @override
  State<MultiDosePage> createState() => _MultiDosePageState();
}

class _MultiDosePageState extends State<MultiDosePage> {
  PkParams _params = regimens.first.toParams();
  Regimen _regimen = regimens.first;
  double _interval = regimens.first.interval;
  int _doseCount = 8;
  bool _steadyView = false;
  bool? _usePersonal;
  double _spread = 0.5;

  void _selectRegimen(Regimen r) {
    setState(() {
      _regimen = r;
      _params = r.toParams(weight: _params.weight);
      _interval = r.interval;
      _doseCount = r.model.isZeroOrder ? 2 : 8;
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
    final scheme = Theme.of(context).colorScheme;
    final unit = UnitScope.of(context);
    final settings = CalibrationSettings.instance;
    final population = _populationParams();

    // 个体模型：只用与当前方案同指标的化验记录校准
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

    final scenario = PkScenario(
      params: effectiveParams,
      interval: _interval,
      doseCount: _doseCount,
      steadyState: _steadyView,
    );
    final sim = PkSimulator(scenario);
    final metrics = sim.multipleDoseMetrics();

    final span = _steadyView ? _interval * 2 : _interval * _doseCount;
    final samples = sim.sample(duration: span, points: 900);
    final doses = [
      for (var i = 0; i <= (_steadyView ? 2 : _doseCount); i++) i * _interval,
    ];

    final halfWidth = calibration != null
        ? (calibration.relativeSd * 1.96).clamp(0.05, 1.5)
        : _spread;
    final bandLow = [
      for (final p in samples) SamplePoint(p.t, math.max(0, p.c * (1 - halfWidth))),
    ];
    final bandHigh = [for (final p in samples) SamplePoint(p.t, p.c * (1 + halfWidth))];
    final unifiedSamples = (calibration != null)
        ? PkSimulator(
            PkScenario(
              params: population,
              interval: _interval,
              doseCount: _doseCount,
              steadyState: _steadyView,
            ),
          ).sample(duration: span, points: 900)
        : null;

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('多次给药与稳态',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(
          '按固定间隔 τ 重复给药，叠加计算稳态峰谷浓度、波动度与达稳时间',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: '浓度-时间曲线',
          subtitle: _steadyView
              ? '稳态下的两个给药间隔（曲线呈周期性）'
              : '共 $_doseCount 次给药，虚线为给药时刻',
          icon: Icons.stacked_line_chart,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (calibration == null) ...[
                _spreadSelector(context),
                const SizedBox(width: 8),
              ],
              Chip(
                visualDensity: VisualDensity.compact,
                label: Text(_steadyView ? '稳态视图' : '$_doseCount 次给药'),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
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
                label: calibration != null ? '个体模型' : '总血药浓度',
              ),
            ],
            bands: halfWidth > 0
                ? [
                    ChartBand(
                      low: convertSamples(bandLow, unit),
                      high: convertSamples(bandHigh, unit),
                      color: scheme.primary,
                      label: '个体差异 ±${(_spread * 100).round()}%',
                    ),
                  ]
                : const [],
            doses: doses,
            yUnit: unit.label,
            height: 360,
          ),
        ),
        const SizedBox(height: 14),
        _metricsGrid(context, metrics),
        const SizedBox(height: 14),
        _steadyTable(context),
        const SizedBox(height: 14),
        InfoBanner(
          text: _steadyView
              ? '稳态浓度按无限次给药的历史剂量叠加计算；实际临床达到 95% 稳态约需 '
                  '${fmtNum(metrics.timeToSteadyState, maxSignificant: 3)} h。'
              : '当前显示 $_doseCount 次给药的叠加结果，指标区仍按稳态计算，便于对比。',
        ),
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
            scenarioHint: '按稳态方案（τ = ${fmtNum(_interval, maxSignificant: 3)} h）校准',
            method: settings.method,
            onMethodChanged: (m) => setState(() => settings.setMethod(m)),
            dose: _params.dose,
            onDoseChanged: (v) => setState(() => _params = _params.copyWith(dose: v)),
          )
        else
          ParamsPanel(
            params: _params,
            onChanged: (p) => setState(() => _params = p),
          ),
        const SizedBox(height: 12),
        SectionCard(
          title: '给药方案',
          icon: Icons.event_repeat,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: ParamField(
                      label: '给药间隔 τ',
                      unit: 'h',
                      value: _interval,
                      onChanged: (v) => setState(() => _interval = v.clamp(0.5, 96).toDouble()),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ParamField(
                      label: '给药次数',
                      unit: '次',
                      value: _doseCount.toDouble(),
                      onChanged: (v) => setState(
                        () => _doseCount = v.round().clamp(1, 40),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('稳态视图', style: Theme.of(context).textTheme.bodyMedium),
                        Text(
                          '只显示稳态下的周期性曲线',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _steadyView,
                    onChanged: (v) => setState(() => _steadyView = v),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        InfoBanner(
          text: '稳态峰浓度 Css,max = C0 / (1 − e^(−k·τ))（一室静注式；其他模型按剂量叠加数值计算），'
              '蓄积比 R = 1 / (1 − e^(−k·τ))，波动度 FI = (Cmax − Cmin) / Cavg。',
        ),
      ],
    );

    return ResponsivePage(controls: controls, body: body);
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

  Widget _metricsGrid(BuildContext context, MultipleDoseMetrics m) {
    final unit = UnitScope.of(context);
    final tiles = <Widget>[
      MetricTile(
        label: 'Css,max',
        value: unit.format(m.steady.cMax),
        unit: unit.label,
        hint: '稳态峰浓度',
        color: Theme.of(context).colorScheme.primary,
      ),
      MetricTile(
        label: 'Css,min',
        value: unit.format(m.steady.cMin),
        unit: unit.label,
        hint: '稳态谷浓度',
      ),
      MetricTile(
        label: 'Css,avg',
        value: unit.format(m.steady.cAvg),
        unit: unit.label,
        hint: '平均稳态浓度',
      ),
      MetricTile(
        label: '波动度 FI',
        value: fmtNum(m.fluctuation * 100, maxSignificant: 3),
        unit: '%',
        hint: '（Cmax−Cmin）/Cavg',
      ),
      MetricTile(label: '蓄积比 R', value: fmtNum(m.accumulation), unit: '×', hint: 'Css,max / C1,max'),
      MetricTile(
        label: '达稳时间',
        value: fmtNum(m.timeToSteadyState, maxSignificant: 3),
        unit: 'h',
        hint: '达到 95% 稳态',
      ),
      MetricTile(
        label: 'AUCτ',
        value: unit.format(m.steady.auc),
        unit: unit.aucLabel,
        hint: '一个间隔的 AUC',
      ),
      MetricTile(
        label: '首剂 Cmax',
        value: unit.format(m.firstDose.cMax),
        unit: unit.label,
        hint: '第一次给药',
      ),
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

  Widget _steadyTable(BuildContext context) {
    final unit = UnitScope.of(context);
    final ss = PkSimulator(
      PkScenario(params: _params, interval: _interval, steadyState: true),
    ).sample(duration: _interval, points: 13);

    final csv = StringBuffer('t_h,C_ss_${unit.label.replaceAll('/', '_')}\n');
    for (final p in ss) {
      csv.writeln('${p.t.toStringAsFixed(2)},${unit.convert(p.c).toStringAsFixed(4)}');
    }

    return SectionCard(
      title: '稳态一个给药间隔内的浓度',
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
            DataColumn(label: Text('Css (${unit.label})')),
          ],
          rows: [
            for (final p in ss)
              DataRow(cells: [
                DataCell(Text(fmtNum(p.t, maxSignificant: 4))),
                DataCell(Text(unit.format(p.c))),
              ]),
          ],
        ),
      ),
    );
  }
}
