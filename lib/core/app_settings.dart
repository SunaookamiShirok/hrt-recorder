// 应用级设置：体重、目标区间、实验开关（内存态）。
import 'package:flutter/foundation.dart';

class AppSettings extends ChangeNotifier {
  AppSettings._();

  static final AppSettings instance = AppSettings._();

  double _weight = 70;
  double _e2Low = 100;
  double _e2High = 200;
  double _cpaHigh = 50;

  double get weight => _weight;

  /// E2 目标区间下限 (pg/mL)。
  double get e2Low => _e2Low;

  /// E2 目标区间上限 (pg/mL)。
  double get e2High => _e2High;

  /// CPA 上限 (ng/mL)。
  double get cpaHigh => _cpaHigh;

  void setWeight(double v) {
    final n = v.clamp(30.0, 200.0);
    if ((_weight - n).abs() < 1e-9) return;
    _weight = n;
    notifyListeners();
  }

  void setE2Range(double low, double high) {
    _e2Low = low.clamp(0.0, 1000.0);
    _e2High = high.clamp(0.0, 1000.0);
    notifyListeners();
  }

  void setCpaHigh(double v) {
    _cpaHigh = v.clamp(0.0, 500.0);
    notifyListeners();
  }
}
