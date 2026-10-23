// 概览：当前估算浓度、用药概况、双轴曲线。
import 'package:flutter/material.dart';

import '../../core/app_settings.dart';
import '../../core/calibration.dart';
import '../../core/calibration_settings.dart';
import '../../core/dose_engine.dart';
import '../../core/dose_record.dart';
import '../../core/pk.dart';
import '../../core/regimens.dart';
import '../../data/dose_store.dart';
import '../../data/lab_store.dart';
import '../../utils/format.dart';
import '../../utils/units.dart';
import '../theme.dart';
import '../widgets/chart.dart';
import '../widgets/dose_form.dart';

class OverviewPage extends StatefulWidget {
  const OverviewPage({super.key});

  @override
  State<OverviewPage> createState() => _OverviewPageState();
}

class _OverviewPageState extends State<OverviewPage> {
  String _range = '1W';

  @override
  void initState() {
    super.initState();
    DoseStore.instance.ensureLoaded();
    LabStore.instance.ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        DoseStore.instance,
        LabStore.instance,
        CalibrationSettings.instance,
        AppSettings.instance,
      ]),
      builder: (context, _) {
        final now = DateTime.now();
        final weight = AppSettings.instance.weight;
        final doses = DoseStore.instance.records;

        final e2Doses = doses.where((d) => d.drug == 'E2').toList();
        final latestE2 = e2Doses.isNotEmpty ? e2Doses.first : null;
        final regimen = latestE2 == null
            ? regimens.first
            : regimenById(_regimenIdFor('E2', latestE2.route));
        final population = regimen.toParams(weight: weight);

        final cal = LabStore.instance.taggedCount('E2') >= 4
            ? calibrateIndividual(
                method: CalibrationSettings.instance.method,
                population: population,
                points: LabStore.instance.calibrationPoints('E2'),
              )
            : null;
        final ratio = cal == null ? 1.0 : cal.vd / population.vd;
        final relSdE2 = cal?.relativeSd ?? 0.40;

        final s = CalibrationSettings.instance;
        final inhibitedK = (s.cpaInteraction && latestE2 != null)
            ? population.k * (1 - s.cpaInhibition)
            : null;

        final engine = DoseEngine(
          doses: doses,
          weight: weight,
          individualVdRatio: ratio,
          inhibitedK: inhibitedK,
        );
        final e2 = engine.estimate('E2', now, relativeSd: relSdE2);
        final cpa = engine.estimate('CPA', now, relativeSd: 0.40);

        final windowDays = _range == '1W' ? 7 : 30;
        final from = now.subtract(Duration(days: windowDays));
        final e2Series = engine.series('E2', from: from, to: now, points: 140);
        final cpaSeries = engine.series('CPA', from: from, to: now, points: 140);

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
          children: [
            _header(context, cal != null),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, c) {
                final wide = c.maxWidth > 620;
                final e2Card = _EstimateCard(
                  title: 'E2',
                  unit: 'pg/mL',
                  value: _toUnit(e2.central, ConcentrationUnit.pgPerMl),
                  digits: 1,
                  color: PkTheme.accent,
                  rows: [
                    ('95% CI', '${_fmt(_toUnit(e2.low95, ConcentrationUnit.pgPerMl))} – '
                        '${_fmt(_toUnit(e2.high95, ConcentrationUnit.pgPerMl))} pg/mL'),
                    ('68% 区间', '${_fmt(_toUnit(e2.low68, ConcentrationUnit.pgPerMl))} – '
                        '${_fmt(_toUnit(e2.high68, ConcentrationUnit.pgPerMl))} pg/mL'),
                    ('个体化模型', cal == null ? '未校准' : '${fmtNum(cal.vd)} L'),
                    ('最近化验', _lastLab('E2')),
                  ],
                  warning: _warningE2(e2, cal),
                );
                final cpaCard = _EstimateCard(
                  title: 'CPA',
                  unit: 'ng/mL',
                  value: _toUnit(cpa.central, ConcentrationUnit.ngPerMl),
                  digits: 2,
                  color: PkTheme.accentAlt,
                  rows: [
                    ('群体 PK 范围', '${_fmt(_toUnit(cpa.populationLow, ConcentrationUnit.ngPerMl))} – '
                        '${_fmt(_toUnit(cpa.populationHigh, ConcentrationUnit.ngPerMl))} ng/mL'),
                    ('95% 区间', '${_fmt(_toUnit(cpa.low95, ConcentrationUnit.ngPerMl))} – '
                        '${_fmt(_toUnit(cpa.high95, ConcentrationUnit.ngPerMl))} ng/mL'),
                    ('最近化验', _lastLab('CPA')),
                    ('说明', '估算（未经个体校准）'),
                  ],
                  warning: _warningCpa(cpa),
                );
                if (wide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: e2Card),
                      const SizedBox(width: 12),
                      Expanded(child: cpaCard),
                    ],
                  );
                }
                return Column(
                  children: [e2Card, const SizedBox(height: 12), cpaCard],
                );
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _MiniCard(
                    icon: Icons.timeline,
                    label: '总用药次数',
                    value: '${doses.length}',
                    color: PkTheme.accent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _MiniCard(
                    icon: Icons.medication_outlined,
                    label: '上次抗雄药物',
                    value: _lastDoseText('CPA'),
                    sub: _lastDoseDate('CPA'),
                    color: PkTheme.accentAlt,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _lastDoseCard(context, latestE2),
            const SizedBox(height: 12),
            _chartCard(context, e2Series, cpaSeries),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------

  Widget _header(BuildContext context, bool calibrated) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: PkTheme.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.monitor_heart_outlined, size: 16, color: PkTheme.muted),
              const SizedBox(width: 6),
              Text('当前估算血药浓度',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(color: PkTheme.muted)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  calibrated ? '个体化模型' : '群体模型',
                  style: const TextStyle(fontSize: 11, color: PkTheme.text),
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        GestureDetector(
          onTap: () async {
            final record = await showDoseDialog(context);
            if (record != null) await DoseStore.instance.add(record);
          },
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [PkTheme.accentLight, PkTheme.accent],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: PkTheme.accent.withValues(alpha: 0.45),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(Icons.add, color: Colors.white, size: 26),
          ),
        ),
      ],
    );
  }

  String _fmt(double v) => v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  double _toUnit(double mgL, ConcentrationUnit unit) => unit.convert(mgL);

  String _lastLab(String drug) {
    final list = LabStore.instance.byAnalyte(drug);
    if (list.isEmpty) return '—';
    final r = list.first;
    return '${fmtNum(r.value, maxSignificant: 3)} ${r.unit.label}';
  }

  String _warningE2(DrugEstimate e, CalibrationResult? cal) {
    final v = _toUnit(e.central, ConcentrationUnit.pgPerMl);
    final low = AppSettings.instance.e2Low;
    final high = AppSettings.instance.e2High;
    if (v < low) return '低于参考范围';
    if (v > high) return '高于参考范围';
    return '';
  }

  String _warningCpa(DrugEstimate e) {
    final v = _toUnit(e.central, ConcentrationUnit.ngPerMl);
    if (v > AppSettings.instance.cpaHigh) return '高于自设上限';
    return '';
  }

  String _lastDoseText(String drug) {
    final d = DoseStore.instance.latestOf(drug);
    if (d == null) return '—';
    return '${fmtNum(d.dose, maxSignificant: 3)} mg';
  }

  String _lastDoseDate(String drug) {
    final d = DoseStore.instance.latestOf(drug);
    if (d == null) return '暂无记录';
    return '${d.takenAt.month}月${d.takenAt.day}日';
  }

  Widget _lastDoseCard(BuildContext context, DoseRecord? dose) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PkTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: dose == null
          ? const Text('还没有用药记录，点右上角 + 添加',
              style: TextStyle(color: PkTheme.muted))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('上次雌二醇',
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: PkTheme.accent.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(dose.route,
                          style: TextStyle(fontSize: 11, color: PkTheme.accent)),
                    ),
                    const Spacer(),
                    Text('${dose.takenAt.month}月${dose.takenAt.day}日',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  '${dose.dose.toStringAsFixed(2)} mg',
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    color: PkTheme.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${dose.takenAt.hour.toString().padLeft(2, '0')}:'
                  '${dose.takenAt.minute.toString().padLeft(2, '0')}'
                  '${dose.holdMinutes != null ? ' · 含服 ${dose.holdMinutes!.toStringAsFixed(0)} 分钟' : ''}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
    );
  }

  Widget _chartCard(
    BuildContext context,
    List<SamplePoint> e2,
    List<SamplePoint> cpa,
  ) {
    final e2Points = [
      for (final p in e2)
        SamplePoint(p.t / 24, ConcentrationUnit.pgPerMl.convert(p.c)),
    ];
    final cpaPoints = [
      for (final p in cpa)
        SamplePoint(p.t / 24, ConcentrationUnit.ngPerMl.convert(p.c)),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 10, 8),
      decoration: BoxDecoration(
        color: PkTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.show_chart, size: 18, color: PkTheme.accent),
              const SizedBox(width: 8),
              Text('血药浓度', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text('估算', style: TextStyle(fontSize: 11)),
              ),
              const Spacer(),
              SegmentedButton<String>(
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                segments: const [
                  ButtonSegment(value: '1M', label: Text('1M')),
                  ButtonSegment(value: '1W', label: Text('1W')),
                ],
                selected: {_range},
                onSelectionChanged: (s) => setState(() => _range = s.first),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ConcentrationChart(
            series: [
              ChartSeries(
                points: e2Points,
                color: PkTheme.accent,
                label: 'E2 (pg/mL)',
                width: 2,
              ),
              ChartSeries(
                points: cpaPoints,
                color: PkTheme.accentAlt,
                label: 'CPA (ng/mL)',
                width: 2,
                rightAxis: true,
              ),
            ],
            height: 280,
            xUnit: '天',
            yUnit: 'pg/mL',
            rightUnit: 'ng/mL',
            rightColor: PkTheme.accentAlt,
            animate: false,
          ),
        ],
      ),
    );
  }
}

String _regimenIdFor(String drug, String route) {
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

class _EstimateCard extends StatelessWidget {
  const _EstimateCard({
    required this.title,
    required this.unit,
    required this.value,
    required this.digits,
    required this.color,
    required this.rows,
    this.warning = '',
  });

  final String title;
  final String unit;
  final double value;
  final int digits;
  final Color color;
  final List<(String, String)> rows;
  final String warning;

  @override
  Widget build(BuildContext context) {
    final color = this.color;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PkTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withValues(alpha: 0.16), PkTheme.surface],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value.toStringAsFixed(digits),
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                  color: color,
                  height: 1,
                ),
              ),
              const SizedBox(width: 6),
              Text(unit, style: const TextStyle(color: PkTheme.muted)),
            ],
          ),
          const SizedBox(height: 10),
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 78,
                    child: Text(r.$1, style: const TextStyle(fontSize: 11, color: PkTheme.muted)),
                  ),
                  Expanded(
                    child: Text(r.$2,
                        style: const TextStyle(fontSize: 11, color: PkTheme.text)),
                  ),
                ],
              ),
            ),
          if (warning.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: PkTheme.warn.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: PkTheme.warn.withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.info_outline, size: 12, color: PkTheme.warn),
                  const SizedBox(width: 4),
                  Text(warning,
                      style: const TextStyle(fontSize: 11, color: PkTheme.warn)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniCard extends StatelessWidget {
  const _MiniCard({
    required this.icon,
    required this.label,
    required this.value,
    this.sub,
    this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? sub;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: PkTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: (color ?? PkTheme.accent).withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: color ?? PkTheme.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 11, color: PkTheme.muted)),
                const SizedBox(height: 2),
                Text(value,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                if (sub != null)
                  Text(sub!, style: const TextStyle(fontSize: 11, color: PkTheme.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
