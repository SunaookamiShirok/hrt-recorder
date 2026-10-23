// 设置：单位、体重、目标区间、实验开关、数据管理。
import 'package:flutter/material.dart';

import '../../core/app_settings.dart';
import '../../core/calibration_settings.dart';
import '../../core/theme_controller.dart';
import '../../data/dose_store.dart';
import '../../data/lab_store.dart';
import '../../utils/format.dart';
import '../../utils/units.dart';
import '../theme.dart';
import '../unit_scope.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  void initState() {
    super.initState();
    LabStore.instance.ensureLoaded();
    DoseStore.instance.ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([AppSettings.instance, CalibrationSettings.instance]),
      builder: (context, _) {
        final unit = UnitScope.of(context);
        final app = AppSettings.instance;
        final cal = CalibrationSettings.instance;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
          children: [
            Text('设置', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 16),
            _card(
              context,
              title: '主题色',
              child: AnimatedBuilder(
                animation: ThemeController.instance,
                builder: (context, _) {
                  final current = ThemeController.instance.accent;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          for (final p in ThemeController.presets)
                            Tooltip(
                              message: p.name,
                              child: GestureDetector(
                                onTap: () => ThemeController.instance.setAccent(p.color),
                                child: Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: p.color,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: p.color.toARGB32() == current.toARGB32()
                                          ? Colors.white
                                          : Colors.white24,
                                      width: p.color.toARGB32() == current.toARGB32() ? 3 : 1,
                                    ),
                                  ),
                                  child: p.color.toARGB32() == current.toARGB32()
                                      ? const Icon(Icons.check, size: 18, color: Colors.white)
                                      : null,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      StatefulBuilder(
                        builder: (context, setLocal) {
                          var hue = HSVColor.fromColor(current).hue;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('自定义色相',
                                  style: TextStyle(fontSize: 11, color: PkTheme.muted)),
                              Slider(
                                value: hue,
                                max: 360,
                                onChanged: (v) {
                                  setLocal(() => hue = v);
                                  ThemeController.instance.setAccent(
                                    HSVColor.fromAHSV(1, v, 0.78, 0.92).toColor(),
                                  );
                                },
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  );
                },
              ),
            ),
            _card(
              context,
              title: '显示单位',
              child: SegmentedButton<ConcentrationUnit>(
                segments: [
                  for (final u in ConcentrationUnit.values)
                    ButtonSegment(value: u, label: Text(u.label)),
                ],
                selected: {unit},
                onSelectionChanged: (s) => UnitController.instance.set(s.first),
              ),
            ),
            _card(
              context,
              title: '体重',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('${fmtNum(app.weight, maxSignificant: 3)} kg',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                      const Spacer(),
                      const Text('用于按体重缩放分布容积',
                          style: TextStyle(fontSize: 11, color: PkTheme.muted)),
                    ],
                  ),
                  Slider(
                    value: app.weight,
                    min: 40,
                    max: 120,
                    divisions: 80,
                    onChanged: app.setWeight,
                  ),
                ],
              ),
            ),
            _card(
              context,
              title: '目标区间（仅作界面提示）',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'E2 ${app.e2Low.toStringAsFixed(0)} – ${app.e2High.toStringAsFixed(0)} pg/mL',
                    style: const TextStyle(fontSize: 13),
                  ),
                  RangeSlider(
                    values: RangeValues(app.e2Low, app.e2High),
                    max: 400,
                    divisions: 80,
                    onChanged: (v) => app.setE2Range(v.start, v.end),
                  ),
                  Text('CPA 上限 ${app.cpaHigh.toStringAsFixed(0)} ng/mL',
                      style: const TextStyle(fontSize: 13)),
                  Slider(
                    value: app.cpaHigh,
                    max: 200,
                    divisions: 40,
                    onChanged: app.setCpaHigh,
                  ),
                  const Text(
                    '这些区间由你自己设定，用于概览页的提示，不是医学建议。',
                    style: TextStyle(fontSize: 11, color: PkTheme.muted),
                  ),
                ],
              ),
            ),
            _card(
              context,
              title: '实验特性',
              child: Column(
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('CPA 抑制 E2 清除'),
                            SizedBox(height: 2),
                            Text('敏感性分析假设，幅度无可靠临床数据',
                                style: TextStyle(fontSize: 11, color: PkTheme.muted)),
                          ],
                        ),
                      ),
                      Switch(
                        value: cal.cpaInteraction,
                        onChanged: cal.setCpaInteraction,
                      ),
                    ],
                  ),
                  if (cal.cpaInteraction)
                    Slider(
                      value: cal.cpaInhibition,
                      min: 0.05,
                      max: 0.6,
                      divisions: 11,
                      label: '−${(cal.cpaInhibition * 100).round()}%',
                      onChanged: cal.setCpaInhibition,
                    ),
                ],
              ),
            ),
            _card(
              context,
              title: '数据管理',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('化验：${LabStore.instance.location}',
                      style: const TextStyle(fontSize: 11, color: PkTheme.muted)),
                  const SizedBox(height: 4),
                  Text('用药：${DoseStore.instance.location}',
                      style: const TextStyle(fontSize: 11, color: PkTheme.muted)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('清空全部数据？'),
                                content: const Text('将删除本机保存的化验与用药记录，无法恢复。'),
                                actions: [
                                  TextButton(
                                      onPressed: () => Navigator.pop(context, false),
                                      child: const Text('取消')),
                                  FilledButton(
                                      onPressed: () => Navigator.pop(context, true),
                                      child: const Text('清空')),
                                ],
                              ),
                            );
                            if (ok == true) {
                              await LabStore.instance.clearAll();
                              await DoseStore.instance.clearAll();
                            }
                          },
                          icon: const Icon(Icons.delete_outline, size: 16),
                          label: const Text('清空数据'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _card(BuildContext context, {required String title, required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PkTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
