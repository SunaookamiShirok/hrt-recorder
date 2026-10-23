// 全局浓度单位上下文 + 顶部切换控件。
import 'package:flutter/material.dart';

import '../core/pk.dart';
import '../utils/units.dart';

/// 全局浓度单位（各页面可监听，方案切换时可自动切换单位）。
class UnitController extends ValueNotifier<ConcentrationUnit> {
  UnitController._() : super(ConcentrationUnit.pgPerMl);

  static final UnitController instance = UnitController._();

  void set(ConcentrationUnit unit) {
    if (value != unit) value = unit;
  }
}

/// 把内核采样点（mg/L）换算成显示单位。
List<SamplePoint> convertSamples(List<SamplePoint> points, ConcentrationUnit unit) {
  if (unit == ConcentrationUnit.mgPerL) return points;
  return [for (final p in points) SamplePoint(p.t, unit.convert(p.c))];
}

/// 提供全局浓度单位。
class UnitScope extends InheritedWidget {
  const UnitScope({super.key, required this.unit, required super.child});

  final ConcentrationUnit unit;

  static ConcentrationUnit of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<UnitScope>();
    return scope?.unit ?? ConcentrationUnit.mgPerL;
  }

  @override
  bool updateShouldNotify(UnitScope oldWidget) => oldWidget.unit != unit;
}

/// AppBar 里的单位切换按钮。
class UnitSelector extends StatelessWidget {
  const UnitSelector({super.key, required this.unit, required this.onChanged});

  final ConcentrationUnit unit;
  final ValueChanged<ConcentrationUnit> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopupMenuButton<ConcentrationUnit>(
      tooltip: '浓度单位',
      initialValue: unit,
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final u in ConcentrationUnit.values)
          PopupMenuItem(
            value: u,
            child: Row(
              children: [
                Icon(
                  u == unit ? Icons.check : Icons.circle_outlined,
                  size: 16,
                  color: u == unit ? scheme.primary : Colors.transparent,
                ),
                const SizedBox(width: 8),
                Text(u.label),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.straighten, size: 15),
            const SizedBox(width: 5),
            Text(unit.label, style: const TextStyle(fontSize: 12.5)),
          ],
        ),
      ),
    );
  }
}
