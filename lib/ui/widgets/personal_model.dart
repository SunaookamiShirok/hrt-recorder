// 数据模型来源切换：统一模型（文献/示例参数）⇄ 个体模型（用化验值校准）。
import 'package:flutter/material.dart';

import '../../core/calibration.dart';
import '../../core/pk.dart';
import '../../utils/format.dart';
import 'common.dart';

/// 统一 / 个体 模型切换。
class ModelSourceSwitch extends StatelessWidget {
  const ModelSourceSwitch({
    super.key,
    required this.usePersonal,
    required this.canUsePersonal,
    required this.recordCount,
    required this.onChanged,
  });

  final bool usePersonal;
  final bool canUsePersonal;

  /// 带「距给药」时间的记录数（用于提示还差几条）。
  final int recordCount;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SectionCard(
      title: '数据模型',
      icon: Icons.alt_route,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<bool>(
            segments: [
              const ButtonSegment(
                value: false,
                label: Text('统一模型'),
                icon: Icon(Icons.public, size: 16),
              ),
              ButtonSegment(
                value: true,
                label: Text(canUsePersonal ? '个体模型（$recordCount）' : '个体模型'),
                icon: const Icon(Icons.person_outline, size: 16),
                enabled: canUsePersonal,
              ),
            ],
            selected: {usePersonal && canUsePersonal},
            onSelectionChanged: (s) => onChanged(s.first),
          ),
          const SizedBox(height: 8),
          Text(
            canUsePersonal
                ? '统一模型：文献/示例参数；个体模型：用你的 $recordCount 条化验值校准暴露水平'
                : '统一模型：先用文献/示例参数。在「化验记录」页添加至少 4 条'
                    '带「距上次给药 (h)」的记录后，可切换为个体模型',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.4,
                ),
          ),
        ],
      ),
    );
  }
}

/// 个体模型说明卡：选择校准方法，显示个体化 V、拟合优度与 V 的时间轨迹。
class PersonalModelCard extends StatelessWidget {
  const PersonalModelCard({
    super.key,
    required this.analyte,
    required this.calibration,
    required this.baseParams,
    required this.scenarioHint,
    required this.dose,
    required this.onDoseChanged,
    required this.method,
    required this.onMethodChanged,
  });

  final String analyte;
  final CalibrationResult? calibration;
  final PkParams baseParams;
  final String scenarioHint;
  final double dose;
  final ValueChanged<double> onDoseChanged;
  final CalibrationMethod method;
  final ValueChanged<CalibrationMethod> onMethodChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cal = calibration;

    return SectionCard(
      title: '个体模型',
      icon: Icons.person_outline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ParamField(
            label: '剂量 D',
            unit: 'mg',
            value: dose,
            onChanged: onDoseChanged,
          ),
          const SizedBox(height: 10),
          if (analyte == 'E2')
            DropdownButtonFormField<CalibrationMethod>(
              initialValue: method,
              decoration: const InputDecoration(
                labelText: '校准方法',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: [
                for (final m in CalibrationMethod.values)
                  DropdownMenuItem(
                    value: m,
                    child: Text(
                      m.experimental ? '${m.label} · 实验' : m.label,
                      style: TextStyle(
                        color: m.experimental ? scheme.tertiary : null,
                      ),
                    ),
                  ),
              ],
              onChanged: (m) {
                if (m != null) onMethodChanged(m);
              },
            )
          else
            Text(
              '校准方法：经验缩放（CPA 暂不支持动态方法）',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          const SizedBox(height: 10),
          Text(
            '用于校准的指标：$analyte（只用同指标的化验记录）',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 8),
          if (cal == null)
            const InfoBanner(
              icon: Icons.info_outline,
              text: '这些化验点不足 4 个（或预测值异常），暂时无法校准。',
            )
          else ...[
            _row(context, '个体化 V', '${fmtNum(cal.vd, maxSignificant: 3)} L'),
            _row(context, '不确定度',
                '±${fmtNum(cal.vdSd, maxSignificant: 2)} L（${fmtNum(cal.relativeSd * 100, maxSignificant: 2)}%）'),
            _row(context, '样本数', '${cal.n} 条'),
            _row(context, 'R²', fmtNum(cal.r2, maxSignificant: 3)),
            if (cal.history.length >= 2) _row(context, 'V 轨迹', _trendText(cal)),
            const SizedBox(height: 8),
            Text(
              '校准只调整暴露水平（等效 V），消除与吸收形状仍来自统一模型；'
              '$scenarioHint。',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.4,
                  ),
            ),
            if (cal.warning != null) ...[
              const SizedBox(height: 10),
              InfoBanner(icon: Icons.warning_amber_outlined, text: cal.warning!),
            ],
          ],
        ],
      ),
    );
  }

  String _trendText(CalibrationResult cal) {
    final first = cal.history.first;
    final last = cal.history.last;
    final delta = (last.vd - first.vd) / first.vd * 100;
    final dir = delta >= 0 ? '↑' : '↓';
    return '${fmtNum(first.vd, maxSignificant: 3)} → ${fmtNum(last.vd, maxSignificant: 3)} L'
        '（$dir${fmtNum(delta.abs(), maxSignificant: 2)}%）';
  }

  Widget _row(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          Text(value,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  )),
        ],
      ),
    );
  }
}