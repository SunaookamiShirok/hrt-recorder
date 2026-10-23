// 校准设置：方法选择 + 实验性药物相互作用开关（全局，各页面共享）。
import 'package:flutter/foundation.dart';

import 'calibration.dart';

class CalibrationSettings extends ChangeNotifier {
  CalibrationSettings._();

  static final CalibrationSettings instance = CalibrationSettings._();

  CalibrationMethod _method = CalibrationMethod.empirical;
  bool _cpaInteraction = false;
  double _cpaInhibition = 0.25;

  CalibrationMethod get method => _method;

  /// 实验性：同时使用 CPA 时抑制 E2 清除。
  bool get cpaInteraction => _cpaInteraction;

  /// 假定的清除率下降比例（0.25 = CL 降低 25%）。
  double get cpaInhibition => _cpaInhibition;

  void setMethod(CalibrationMethod value) {
    if (_method == value) return;
    _method = value;
    notifyListeners();
  }

  void setCpaInteraction(bool value) {
    if (_cpaInteraction == value) return;
    _cpaInteraction = value;
    notifyListeners();
  }

  void setCpaInhibition(double value) {
    final v = value.clamp(0.0, 0.6);
    if ((_cpaInhibition - v).abs() < 1e-9) return;
    _cpaInhibition = v;
    notifyListeners();
  }

  /// 对 E2 方案应用相互作用后的参数。
  static const String cpaNote =
      '实验性假设：CPA 可能竞争 E2 的代谢通路。幅度没有可靠临床数据，'
      '这里仅作为敏感性分析使用，不代表真实相互作用。';
}
