// 化验记录页：录入真实化验值、本地保存、趋势图、CSV 导入导出。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/pk.dart';
import '../../data/lab_record.dart';
import '../../data/lab_store.dart';
import '../../utils/format.dart';
import '../../utils/units.dart';
import '../widgets/chart.dart';
import '../widgets/common.dart';
import '../widgets/page_layout.dart';

class LabPage extends StatefulWidget {
  const LabPage({super.key});

  @override
  State<LabPage> createState() => _LabPageState();
}

class _LabPageState extends State<LabPage> {
  final LabStore _store = LabStore.instance;

  DateTime _when = DateTime.now();
  String _analyte = 'E2';
  final TextEditingController _customAnalyte = TextEditingController();
  final TextEditingController _value = TextEditingController();
  final TextEditingController _hours = TextEditingController();
  final TextEditingController _note = TextEditingController();
  ConcentrationUnit _unit = ConcentrationUnit.pgPerMl;
  ConcentrationUnit _displayUnit = ConcentrationUnit.pgPerMl;
  String? _chartAnalyte;

  @override
  void initState() {
    super.initState();
    _store.ensureLoaded();
  }

  @override
  void dispose() {
    _customAnalyte.dispose();
    _value.dispose();
    _hours.dispose();
    _note.dispose();
    super.dispose();
  }

  String get _analyteName {
    if (_analyte == '其他') {
      final v = _customAnalyte.text.trim();
      return v.isEmpty ? '其他' : v;
    }
    return _analyte;
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _when,
      firstDate: DateTime(2015),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      helpText: '选择化验日期',
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_when),
      helpText: '选择采血时间',
    );
    if (!mounted) return;
    setState(() {
      _when = DateTime(date.year, date.month, date.day, time?.hour ?? _when.hour,
          time?.minute ?? _when.minute);
    });
  }

  Future<void> _add() async {
    final value = double.tryParse(_value.text.trim().replaceAll(',', '.'));
    if (value == null || value <= 0) {
      _snack('请填写有效的化验数值');
      return;
    }
    final hours = double.tryParse(_hours.text.trim().replaceAll(',', '.'));
    final record = LabRecord(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      takenAt: _when,
      analyte: _analyteName,
      value: value,
      unit: _unit,
      hoursSinceDose: hours,
      note: _note.text.trim(),
    );
    await _store.add(record);
    if (!mounted) return;
    setState(() {
      _value.clear();
      _hours.clear();
      _note.clear();
      _chartAnalyte = record.analyte;
    });
    _snack('已保存到本机');
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _store,
      builder: (context, _) {
        final records = _store.records;
        final analytes = _store.analytes;

        return ResponsivePage(
          controls: _controls(context),
          body: _body(context, records, analytes),
        );
      },
    );
  }

  Widget _controls(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          title: '新增化验记录',
          icon: Icons.add_chart,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                onPressed: _pickDateTime,
                icon: const Icon(Icons.event, size: 18),
                label: Text('采血时间：${_fmtDateTime(_when)}'),
              ),
              const SizedBox(height: 10),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'E2', label: Text('E2')),
                  ButtonSegment(value: 'CPA', label: Text('CPA')),
                  ButtonSegment(value: '其他', label: Text('其他')),
                ],
                selected: {_analyte},
                onSelectionChanged: (s) => setState(() => _analyte = s.first),
              ),
              if (_analyte == '其他') ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _customAnalyte,
                  decoration: const InputDecoration(
                    labelText: '指标名称',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _value,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: '化验值',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 130,
                    child: DropdownButtonFormField<ConcentrationUnit>(
                      initialValue: _unit,
                      decoration: const InputDecoration(
                        labelText: '单位',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final u in ConcentrationUnit.values)
                          DropdownMenuItem(value: u, child: Text(u.label)),
                      ],
                      onChanged: (u) {
                        if (u != null) setState(() => _unit = u);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _hours,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: '距上次给药 (h) — 可选',
                  helperText: '填了就能把这条化验点画到模拟曲线上',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _note,
                decoration: const InputDecoration(
                  labelText: '备注（剂型、时段等）',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _add,
                icon: const Icon(Icons.save_outlined, size: 18),
                label: const Text('保存记录'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: '数据管理',
          icon: Icons.storage_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _store.location.isEmpty
                    ? '本地存储初始化中…'
                    : '保存位置：${_store.location}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final csv = LabRecordsCodec.toCsv(_store.records);
                        await Clipboard.setData(ClipboardData(text: csv));
                        _snack('已复制 CSV 到剪贴板');
                      },
                      icon: const Icon(Icons.copy_all, size: 16),
                      label: const Text('导出'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _importDialog,
                      icon: const Icon(Icons.file_download_outlined, size: 16),
                      label: const Text('导入'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _store.records.isEmpty
                    ? null
                    : () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('清空全部记录？'),
                            content: const Text('将删除本机保存的所有化验记录，且无法恢复。'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('取消'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('清空'),
                              ),
                            ],
                          ),
                        );
                        if (ok == true) {
                          await _store.clearAll();
                          _snack('已清空');
                        }
                      },
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('清空全部'),
              ),
              if (_store.error != null)
                Text(
                  _store.error!,
                  style: TextStyle(color: scheme.error, fontSize: 12),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _importDialog() async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导入 CSV 记录'),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '每行：takenAt,analyte,value,unit,hoursSinceDose,note',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                maxLines: 8,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                decoration: const InputDecoration(
                  hintText: '2026-01-02T08:00:00,E2,120,pg/mL,6,',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('导入')),
        ],
      ),
    );
    final text = controller.text;
    controller.dispose();
    if (ok != true) return;
    final parsed = LabRecordsCodec.fromCsv(text);
    if (parsed.records.isEmpty) {
      _snack('没有解析到有效记录');
      return;
    }
    final added = await _store.mergeAll(parsed.records);
    _snack('导入 $added 条（跳过 ${parsed.skipped} 行）');
  }

  Widget _body(
    BuildContext context,
    List<LabRecord> records,
    List<String> analytes,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final selected = _chartAnalyte ?? (analytes.isNotEmpty ? analytes.first : 'E2');
    final shown = [for (final r in records) if (r.analyte == selected) r]
      ..sort((a, b) => a.takenAt.compareTo(b.takenAt));

    final points = <SamplePoint>[];
    if (shown.isNotEmpty) {
      final first = shown.first.takenAt;
      for (final r in shown) {
        final hours = r.takenAt.difference(first).inMinutes / 60.0;
        points.add(SamplePoint(hours, _displayUnit.convert(r.valueMgPerL)));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('化验记录',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(
          '记录真实化验值并与模拟曲线对照，数据只保存在本机',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 14),
        const InfoBanner(
          icon: Icons.lock_outline,
          text: '记录保存在本机（不上传任何服务器）。本工具不提供用药建议，'
              '化验结果请结合医生解读；如出现不适请及时就医。',
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: '趋势（$selected）',
          subtitle: shown.isEmpty ? '还没有记录' : '共 ${shown.length} 条，横轴为距首条记录的小时数',
          icon: Icons.show_chart,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButton<ConcentrationUnit>(
                value: _displayUnit,
                underline: const SizedBox.shrink(),
                items: [
                  for (final u in ConcentrationUnit.values)
                    DropdownMenuItem(value: u, child: Text(u.label)),
                ],
                onChanged: (u) {
                  if (u != null) setState(() => _displayUnit = u);
                },
              ),
              if (analytes.isNotEmpty) ...[
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: analytes.contains(selected) ? selected : analytes.first,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final a in analytes) DropdownMenuItem(value: a, child: Text(a)),
                  ],
                  onChanged: (a) => setState(() => _chartAnalyte = a),
                ),
              ],
            ],
          ),
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
          child: ConcentrationChart(
            series: [
              ChartSeries(points: points, color: scheme.primary, label: selected),
            ],
            markers: [for (final p in points) ChartMarker(p.t, p.c)],
            yUnit: _displayUnit.label,
            height: 300,
          ),
        ),
        const SizedBox(height: 14),
        _stats(context, _displayUnit, shown),
        const SizedBox(height: 14),
        _list(context, records),
      ],
    );
  }

  Widget _stats(BuildContext context, ConcentrationUnit unit, List<LabRecord> shown) {
    String latest = '—';
    String low = '—';
    String high = '—';
    if (shown.isNotEmpty) {
      final values = [for (final r in shown) unit.convert(r.valueMgPerL)];
      latest = unit.format(shown.last.valueMgPerL);
      low = fmtNum(values.reduce((a, b) => a < b ? a : b), maxSignificant: 4);
      high = fmtNum(values.reduce((a, b) => a > b ? a : b), maxSignificant: 4);
    }
    final tiles = <Widget>[
      MetricTile(label: '记录数', value: '${shown.length}'),
      MetricTile(label: '最近一次', value: latest, unit: unit.label),
      MetricTile(label: '最低', value: low, unit: unit.label),
      MetricTile(label: '最高', value: high, unit: unit.label),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final columns = (c.maxWidth / 190).floor().clamp(1, 4);
        final width = (c.maxWidth - 10 * (columns - 1)) / columns;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [for (final t in tiles) SizedBox(width: width, child: t)],
        );
      },
    );
  }

  Widget _list(BuildContext context, List<LabRecord> records) {
    final scheme = Theme.of(context).colorScheme;
    return SectionCard(
      title: '全部记录（${records.length}）',
      icon: Icons.list_alt,
      child: records.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text('还没有记录，先在右侧添加一条',
                    style: TextStyle(color: scheme.onSurfaceVariant)),
              ),
            )
          : Column(
              children: [
                for (final r in records)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(r.analyte, style: const TextStyle(fontSize: 12)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${_fmtDateTime(r.takenAt)}   ${fmtNum(r.value, maxSignificant: 4)} ${r.unit.label}',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              if (r.hoursSinceDose != null || r.note.isNotEmpty)
                                Text(
                                  [
                                    if (r.hoursSinceDose != null)
                                      '距给药 ${fmtNum(r.hoursSinceDose!, maxSignificant: 3)} h',
                                    if (r.note.isNotEmpty) r.note,
                                  ].join(' · '),
                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: '删除',
                          iconSize: 18,
                          onPressed: () => _store.remove(r.id),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

String _fmtDateTime(DateTime d) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}
