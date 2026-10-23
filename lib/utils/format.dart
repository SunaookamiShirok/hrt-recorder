// 数值格式化与刻度计算的小工具。
import 'dart:math' as math;

/// 自适应有效数字格式化。
///
/// 科学计数法只在数量级过大（> 10⁷）或过小（< 10⁻⁶，否则会被四舍五入成 0）
/// 时使用，其余情况一律用普通小数——读起来更直观。
String fmtNum(double v, {int maxSignificant = 4}) {
  if (v.isNaN) return '—';
  if (v.isInfinite) return v > 0 ? '∞' : '-∞';
  if (v == 0) return '0';
  final abs = v.abs();
  if (abs >= 1e7 || abs < 1e-6) {
    return v.toStringAsExponential(2);
  }
  final digits = (maxSignificant - (math.log(abs) / math.ln10).floor()).clamp(0, 8);
  var s = v.toStringAsFixed(digits);
  if (s.contains('.')) {
    s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }
  return s;
}

/// 固定小数位。
String fmtFixed(double v, int digits) {
  if (v.isNaN) return '—';
  if (v.isInfinite) return v > 0 ? '∞' : '-∞';
  return v.toStringAsFixed(digits);
}

/// 把 [range] 向上取整到“好看”的刻度步长。
double niceStep(double range, {int targetTicks = 5}) {
  if (range <= 0 || !range.isFinite) return 1;
  final rough = range / math.max(1, targetTicks);
  final exp = (math.log(rough) / math.ln10).floor();
  final base = math.pow(10, exp).toDouble();
  final frac = rough / base;
  double nice;
  if (frac <= 1) {
    nice = 1;
  } else if (frac <= 2) {
    nice = 2;
  } else if (frac <= 2.5) {
    nice = 2.5;
  } else if (frac <= 5) {
    nice = 5;
  } else {
    nice = 10;
  }
  return nice * base;
}

/// 生成 [0, max] 上的坐标轴刻度。
List<double> axisTicks(double max, {int targetTicks = 5}) {
  if (max <= 0 || !max.isFinite) return const [0, 1];
  final step = niceStep(max, targetTicks: targetTicks);
  final ticks = <double>[];
  var v = 0.0;
  while (v <= max + step * 0.5) {
    ticks.add(v);
    v += step;
    if (ticks.length > 40) break;
  }
  if (ticks.isEmpty) ticks.add(0);
  return ticks;
}

/// 把数值向上取到刻度边界。
double axisCeil(double max, {int targetTicks = 5}) {
  if (max <= 0 || !max.isFinite) return 1;
  final step = niceStep(max, targetTicks: targetTicks);
  return (max / step).ceil() * step;
}

/// 半衰期换算。
double halfLifeFromK(double k) => k <= 0 ? double.infinity : math.ln2 / k;

/// 速率常数换算。
double kFromHalfLife(double tHalf) => tHalf <= 0 ? 0 : math.ln2 / tHalf;
