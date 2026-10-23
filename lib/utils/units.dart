// 浓度单位换算：内核统一用 mg/L，界面可切换显示单位。
import 'format.dart';

/// 浓度显示单位。
enum ConcentrationUnit {
  mgPerL('mg/L', 1.0, 'mg·h/L'),
  ngPerMl('ng/mL', 1000.0, 'ng·h/mL'),
  pgPerMl('pg/mL', 1000000.0, 'pg·h/mL');

  const ConcentrationUnit(this.label, this.factor, this.aucLabel);

  /// 显示名称。
  final String label;

  /// 1 mg/L 等于多少个该单位。
  final double factor;

  /// AUC 的单位。
  final String aucLabel;

  /// 把内核浓度（mg/L）换算成显示值。
  double convert(double mgPerL) => mgPerL * factor;

  /// 把显示值换算回 mg/L。
  double toBase(double value) => value / factor;

  /// 直接格式化为显示数值。
  String format(double mgPerL, {int maxSignificant = 4}) =>
      fmtNum(mgPerL * factor, maxSignificant: maxSignificant);
}
