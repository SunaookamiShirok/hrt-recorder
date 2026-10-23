// 新增 / 编辑用药记录的对话框。
import 'package:flutter/material.dart';

import '../../core/dose_record.dart';
import '../theme.dart';

Future<DoseRecord?> showDoseDialog(BuildContext context, {DoseRecord? initial}) {
  return showDialog<DoseRecord>(
    context: context,
    builder: (context) => _DoseDialog(initial: initial),
  );
}

class _DoseDialog extends StatefulWidget {
  const _DoseDialog({this.initial});

  final DoseRecord? initial;

  @override
  State<_DoseDialog> createState() => _DoseDialogState();
}

class _DoseDialogState extends State<_DoseDialog> {
  late DateTime _when = widget.initial?.takenAt ?? DateTime.now();
  late String _drug = widget.initial?.drug ?? 'E2';
  late String _route = widget.initial?.route ?? '口服';
  late final TextEditingController _dose =
      TextEditingController(text: (widget.initial?.dose ?? 2).toString());
  late final TextEditingController _hold = TextEditingController(
      text: widget.initial?.holdMinutes?.toStringAsFixed(0) ?? '15');
  late final TextEditingController _note =
      TextEditingController(text: widget.initial?.note ?? '');

  static const _e2Routes = ['口服', '舌下', '贴片', '肌注'];
  static const _cpaRoutes = ['口服'];

  @override
  void dispose() {
    _dose.dispose();
    _hold.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _when,
      firstDate: DateTime(2015),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_when),
    );
    if (!mounted) return;
    setState(() {
      _when = DateTime(date.year, date.month, date.day, time?.hour ?? _when.hour,
          time?.minute ?? _when.minute);
    });
  }

  @override
  Widget build(BuildContext context) {
    final routes = _drug == 'CPA' ? _cpaRoutes : _e2Routes;
    if (!routes.contains(_route)) _route = routes.first;

    return AlertDialog(
      backgroundColor: PkTheme.surface,
      title: Text(widget.initial == null ? '记录一次用药' : '编辑用药记录'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                onPressed: _pickDateTime,
                icon: const Icon(Icons.schedule, size: 18),
                label: Text(_fmt(_when)),
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'E2', label: Text('雌二醇')),
                  ButtonSegment(value: 'CPA', label: Text('CPA')),
                ],
                selected: {_drug},
                onSelectionChanged: (s) => setState(() {
                  _drug = s.first;
                  _route = _drug == 'CPA' ? '口服' : '口服';
                  if (_drug == 'CPA') _dose.text = '12.5';
                }),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _route,
                decoration: const InputDecoration(
                  labelText: '途径',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final r in routes) DropdownMenuItem(value: r, child: Text(r)),
                ],
                onChanged: (r) {
                  if (r != null) setState(() => _route = r);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _dose,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: '剂量 (mg)',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              if (_route == '舌下') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _hold,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: '含服时长 (分钟)',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _note,
                decoration: const InputDecoration(
                  labelText: '备注',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final dose = double.tryParse(_dose.text.trim());
            if (dose == null || dose <= 0) return;
            Navigator.pop(
              context,
              DoseRecord(
                id: widget.initial?.id ??
                    DateTime.now().microsecondsSinceEpoch.toString(),
                takenAt: _when,
                drug: _drug,
                route: _route,
                dose: dose,
                holdMinutes:
                    _route == '舌下' ? double.tryParse(_hold.text.trim()) : null,
                note: _note.text.trim(),
              ),
            );
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}

String _fmt(DateTime d) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}
