// 参数编辑面板：模型选择 + 各参数输入 + 实时派生值提示。
import 'package:flutter/material.dart';

import '../../core/calibration_settings.dart';
import '../../core/pk.dart';
import '../../core/regimens.dart';
import '../../utils/format.dart';
import 'common.dart';



/// 方案选择：5 个具体用药方案（药 + 给药方式）。
class RegimenPicker extends StatelessWidget {
  const RegimenPicker({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final Regimen selected;
  final ValueChanged<Regimen> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SectionCard(
      title: '方案',
      icon: Icons.medication_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final r in regimens)
                ChoiceChip(
                  label: Text(r.name),
                  selected: selected.id == r.id,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => onSelected(r),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            selected.detail,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          if (selected.analyte == 'E2')
            AnimatedBuilder(
              animation: CalibrationSettings.instance,
              builder: (context, _) {
                final s = CalibrationSettings.instance;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Divider(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '同时使用 CPA（实验性）',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        Switch(
                          value: s.cpaInteraction,
                          onChanged: s.setCpaInteraction,
                        ),
                      ],
                    ),
                    if (s.cpaInteraction) ...[
                      Text(
                        '假定 E2 清除率降低 ${(s.cpaInhibition * 100).round()}%',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                      Slider(
                        value: s.cpaInhibition,
                        min: 0.05,
                        max: 0.6,
                        divisions: 11,
                        label: '${(s.cpaInhibition * 100).round()}%',
                        onChanged: s.setCpaInhibition,
                      ),
                      Text(
                        CalibrationSettings.cpaNote,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              height: 1.35,
                            ),
                      ),
                    ],
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class ParamsPanel extends StatelessWidget {
  const ParamsPanel({
    super.key,
    required this.params,
    required this.onChanged,
    this.extra,
    this.title = '给药参数',
  });

  final PkParams params;
  final ValueChanged<PkParams> onChanged;
  final Widget? extra;
  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isTwo = params.model.isTwoCompartment;
    final isOral = params.model.isOral;
    final isZero = params.model.isZeroOrder;
    final isDual = params.model.isDualAbsorption;

    return SectionCard(
      title: title,
      icon: Icons.tune,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: ParamField(
                  label: '体重',
                  unit: 'kg',
                  value: params.weight,
                  onChanged: (w) {
                    if (w <= 0) return;
                    onChanged(params.copyWith(
                      weight: w,
                      vd: params.vd * (w / params.weight),
                    ));
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ParamField(
                  label: '剂量 D',
                  unit: 'mg',
                  value: params.dose,
                  onChanged: (v) => onChanged(params.copyWith(dose: v)),
                ),
              ),
            ],
          ),
          ExpansionTile(
            title: Text(
              '高级参数（V、k、ka、F 等）',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            subtitle: Text(
              '默认由统一模型提供，化验后可切换个体模型自动修正',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(top: 10, bottom: 4),
            shape: const Border(),
            collapsedShape: const Border(),
            children: [
              Row(
                children: [
                  Expanded(
                    child: ParamField(
                      label: isTwo ? '中央室容积 V1' : '分布容积 V',
                      unit: 'L',
                      value: params.vd,
                      onChanged: (v) => onChanged(params.copyWith(vd: v)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ParamField(
                  label: isTwo ? 'k10' : '消除速率 k',
                  unit: 'h⁻¹',
                  value: params.k,
                  onChanged: (v) => onChanged(params.copyWith(k: v)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ParamField(
                  label: '半衰期 t½',
                  unit: 'h',
                  value: halfLifeFromK(params.k),
                  onChanged: (v) => onChanged(params.copyWith(k: kFromHalfLife(v))),
                ),
              ),
            ],
          ),
          if (isZero) ...[
            const SizedBox(height: 10),
            ParamField(
              label: '输入时长 T（输注 / 贴片佩戴）',
              unit: 'h',
              value: params.infusionDuration,
              onChanged: (v) => onChanged(params.copyWith(infusionDuration: v)),
            ),
          ],
          if (isOral) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ParamField(
                    label: '吸收速率 ka',
                    unit: 'h⁻¹',
                    value: params.ka,
                    onChanged: (v) => onChanged(params.copyWith(ka: v)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ParamField(
                    label: '生物利用度 F',
                    unit: '0–1',
                    value: params.f,
                    onChanged: (v) => onChanged(params.copyWith(f: v)),
                  ),
                ),
              ],
            ),
          ],
          if (isDual) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ParamField(
                    label: '快相 ka1（粘膜）',
                    unit: 'h⁻¹',
                    value: params.ka,
                    onChanged: (v) => onChanged(params.copyWith(ka: v)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ParamField(
                    label: '慢相 ka2（吞咽）',
                    unit: 'h⁻¹',
                    value: params.ka2,
                    onChanged: (v) => onChanged(params.copyWith(ka2: v)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ParamField(
                    label: '总生物利用度 F',
                    unit: '0–1',
                    value: params.f,
                    onChanged: (v) => onChanged(params.copyWith(f: v)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ParamField(
                    label: '快相占比 F1',
                    unit: '0–1',
                    value: params.fFast,
                    onChanged: (v) => onChanged(params.copyWith(fFast: v)),
                  ),
                ),
              ],
            ),
          ],
          if (isTwo) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ParamField(
                    label: 'k12（中央→外周）',
                    unit: 'h⁻¹',
                    value: params.k12,
                    onChanged: (v) => onChanged(params.copyWith(k12: v)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ParamField(
                    label: 'k21（外周→中央）',
                    unit: 'h⁻¹',
                    value: params.k21,
                    onChanged: (v) => onChanged(params.copyWith(k21: v)),
                  ),
                ),
              ],
            ),
          ],
            ],
          ),
          if (extra != null) ...[
            const SizedBox(height: 12),
            extra!,
          ],
          const SizedBox(height: 12),
          _derived(context),
        ],
      ),
    );
  }

  Widget _derived(BuildContext context) {
    final profile = PkProfile(params);
    final scheme = Theme.of(context).colorScheme;
    final rows = <(String, String)>[
      ('半衰期 t½', '${fmtNum(profile.tHalf, maxSignificant: 3)} h'),
      ('清除率 CL', '${fmtNum(profile.clearance, maxSignificant: 3)} L/h'),
      ('表观分布容积 Vss', '${fmtNum(profile.vss, maxSignificant: 3)} L'),
      ('平均滞留时间 MRT', '${fmtNum(profile.mrt, maxSignificant: 3)} h'),
      if (params.model.isTwoCompartment) ...[
        ('分布相 α', '${fmtNum(profile.alpha, maxSignificant: 3)} h⁻¹'),
        ('消除相 β', '${fmtNum(profile.beta, maxSignificant: 3)} h⁻¹'),
      ],
      if (params.model.isZeroOrder) ...[
        ('输入速率 R0', '${fmtNum(profile.inputRate, maxSignificant: 3)} mg/h'),
        ('折合', '${fmtNum(profile.inputRate * 24000, maxSignificant: 3)} µg/天'),
      ],
      if (params.model.isDualAbsorption) ...[
        ('快相 F1', fmtNum(params.f * params.fFast, maxSignificant: 3)),
        ('慢相 F2', fmtNum(params.f * (1 - params.fFast), maxSignificant: 3)),
        ('慢相吸收 t½', '${fmtNum(halfLifeFromK(params.ka2), maxSignificant: 3)} h'),
      ],
    ];
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(row.$1,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                  Text(row.$2,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          )),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
