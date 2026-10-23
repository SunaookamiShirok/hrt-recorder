// 具体用药方案：把「药 + 给药方式」包装成带默认参数的预设。
//
// 参数取自文献量级，按 70 kg 成人体重换算；实际使用时按体重线性缩放 V。
// 这些数值只用于模拟，不是用药建议。
import '../utils/units.dart';
import 'pk.dart';

class Regimen {
  const Regimen({
    required this.id,
    required this.name,
    required this.analyte,
    required this.detail,
    required this.model,
    required this.defaultDose,
    required this.volumePerKg,
    required this.k,
    required this.defaultUnit,
    required this.interval,
    this.ka = 1.0,
    this.f = 1.0,
    this.ka2 = 0.5,
    this.fFast = 0.7,
    this.infusionDuration = 24,
  });

  final String id;
  final String name;

  /// 对应的化验指标名（E2 / CPA），个体校准只会用同指标的记录。
  final String analyte;

  /// 副标题，例如「2 mg 片剂」。
  final String detail;

  final PkModel model;

  /// 默认单次剂量 (mg)。
  final double defaultDose;

  /// 表观分布容积（L/kg，按体重缩放）。
  final double volumePerKg;

  /// 消除速率常数 (h⁻¹)。
  final double k;

  /// 该方案的默认浓度单位。
  final ConcentrationUnit defaultUnit;

  /// 默认给药间隔 (h)。
  final double interval;

  final double ka;
  final double f;
  final double ka2;
  final double fFast;
  final double infusionDuration;

  /// 生成对应体重的参数。
  PkParams toParams({double weight = 70, double? dose}) {
    return PkParams(
      model: model,
      dose: dose ?? defaultDose,
      vd: volumePerKg * weight,
      k: k,
      ka: ka,
      f: f,
      ka2: ka2,
      fFast: fFast,
      infusionDuration: infusionDuration,
      weight: weight,
    );
  }

  /// 在现有参数上应用本方案（保留剂量与体重）。
  PkParams applyTo(PkParams current) => toParams(
        weight: current.weight,
        dose: current.dose,
      );
}

/// 5 个方案：E2 口服 / CPA 口服 / E2 贴片 / E2 含服 / E2 肌注。
const List<Regimen> regimens = [
  Regimen(
    id: 'e2_oral',
    name: 'E2 口服',
    analyte: 'E2',
    detail: '雌二醇片 2 mg',
    model: PkModel.oneCompOral,
    defaultDose: 2,
    volumePerKg: 860 / 70,
    k: 0.045,
    ka: 1.2,
    f: 0.05,
    defaultUnit: ConcentrationUnit.pgPerMl,
    interval: 24,
  ),
  Regimen(
    id: 'cpa_oral',
    name: 'CPA 口服',
    analyte: 'CPA',
    detail: '醋酸环丙孕酮 12.5 mg',
    model: PkModel.oneCompOral,
    defaultDose: 12.5,
    volumePerKg: 1000 / 70,
    k: 0.01733,
    ka: 1.0,
    f: 1.0,
    defaultUnit: ConcentrationUnit.ngPerMl,
    interval: 24,
  ),
  Regimen(
    id: 'e2_patch',
    name: 'E2 贴片',
    analyte: 'E2',
    detail: '透皮 100 µg/天，贴 84 h',
    model: PkModel.zeroOrder,
    defaultDose: 0.35,
    volumePerKg: 600 / 70,
    k: 0.0866,
    infusionDuration: 84,
    defaultUnit: ConcentrationUnit.pgPerMl,
    interval: 84,
  ),
  Regimen(
    id: 'e2_sublingual',
    name: 'E2 含服',
    analyte: 'E2',
    detail: '舌下 2 mg',
    model: PkModel.dualAbsorption,
    defaultDose: 2,
    volumePerKg: 700 / 70,
    k: 0.0693,
    ka: 5.0,
    ka2: 0.5,
    f: 0.15,
    fFast: 0.7,
    defaultUnit: ConcentrationUnit.pgPerMl,
    interval: 12,
  ),
  Regimen(
    id: 'e2_im',
    name: 'E2 肌注',
    analyte: 'E2',
    detail: '戊酸雌二醇 5 mg，储库型',
    model: PkModel.oneCompOral,
    defaultDose: 5,
    volumePerKg: 600 / 70,
    k: 0.09,
    ka: 0.004,
    f: 1.0,
    defaultUnit: ConcentrationUnit.pgPerMl,
    interval: 168,
  ),
];

Regimen regimenById(String id) =>
    regimens.firstWhere((r) => r.id == id, orElse: () => regimens.first);
