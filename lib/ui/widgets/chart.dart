// 自绘浓度-时间曲线：坐标轴、网格、曲线、给药标记、实测点、悬停十字线。
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/pk.dart';
import '../../utils/format.dart';

/// 一条曲线。
class ChartSeries {
  const ChartSeries({
    required this.points,
    required this.color,
    this.label = '',
    this.fill = false,
    this.dashed = false,
    this.width = 2.2,
    this.rightAxis = false,
  });

  final List<SamplePoint> points;
  final Color color;
  final String label;
  final bool fill;
  final bool dashed;
  final double width;

  /// 是否使用右侧纵轴（双轴图）。
  final bool rightAxis;
}

/// 散点（实测值）。
class ChartMarker {
  const ChartMarker(this.t, this.c, {this.label = ''});

  final double t;
  final double c;
  final String label;
}

/// 预测区间带：上界与下界两条曲线之间的半透明填充。
class ChartBand {
  const ChartBand({
    required this.low,
    required this.high,
    required this.color,
    this.label = '',
  });

  final List<SamplePoint> low;
  final List<SamplePoint> high;
  final Color color;
  final String label;
}

/// 浓度-时间图。
class ConcentrationChart extends StatefulWidget {
  const ConcentrationChart({
    super.key,
    required this.series,
    this.bands = const <ChartBand>[],
    this.doses = const <double>[],
    this.markers = const <ChartMarker>[],
    this.height = 340,
    this.yUnit = 'mg/L',
    this.xUnit = 'h',
    this.yMax,
    this.animate = true,
    this.rightUnit,
    this.rightColor,
  });

  final List<ChartSeries> series;

  /// 右侧纵轴单位（双轴图）；为空表示不显示右轴。
  final String? rightUnit;
  final Color? rightColor;

  /// 预测区间带（画在曲线下方）。
  final List<ChartBand> bands;

  /// 给药时间点，绘制竖向虚线。
  final List<double> doses;

  final List<ChartMarker> markers;
  final double height;
  final String yUnit;
  final String xUnit;
  final double? yMax;
  final bool animate;

  @override
  State<ConcentrationChart> createState() => _ConcentrationChartState();
}

class _ConcentrationChartState extends State<ConcentrationChart> {
  double? _hoverX;
  double? _hoverY;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    double maxT = 1;
    var maxC = 0.0;
    var maxCRight = 0.0;
    for (final s in widget.series) {
      for (final p in s.points) {
        if (p.t > maxT) maxT = p.t;
        if (s.rightAxis) {
          if (p.c > maxCRight) maxCRight = p.c;
        } else if (p.c > maxC) {
          maxC = p.c;
        }
      }
    }
    for (final m in widget.markers) {
      if (m.t > maxT) maxT = m.t;
      if (m.c > maxC) maxC = m.c;
    }
    for (final band in widget.bands) {
      for (final p in band.high) {
        if (p.t > maxT) maxT = p.t;
        if (p.c > maxC) maxC = p.c;
      }
    }
    if (widget.doses.isNotEmpty) {
      maxT = math.max(maxT, widget.doses.last);
    }
    final yTop = widget.yMax ?? axisCeil(maxC * 1.12);
    final rightTop = axisCeil(maxCRight * 1.12);

    if (widget.series.every((s) => s.points.isEmpty) && widget.markers.isEmpty) {
      return SizedBox(
        height: widget.height,
        child: Center(
          child: Text('暂无数据', style: textTheme.bodyMedium?.copyWith(color: scheme.outline)),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.series.any((s) => s.label.isNotEmpty) ||
            widget.bands.any((b) => b.label.isNotEmpty))
          _legend(context),
        MouseRegion(
          onHover: (event) => setState(() {
            _hoverX = event.localPosition.dx;
            _hoverY = event.localPosition.dy;
          }),
          onExit: (_) => setState(() {
            _hoverX = null;
            _hoverY = null;
          }),
          child: GestureDetector(
            onHorizontalDragUpdate: (d) => setState(() {
              _hoverX = d.localPosition.dx;
              _hoverY = d.localPosition.dy;
            }),
            onHorizontalDragEnd: (_) => setState(() {
              _hoverX = null;
              _hoverY = null;
            }),
            onTapDown: (d) => setState(() {
              _hoverX = d.localPosition.dx;
              _hoverY = d.localPosition.dy;
            }),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: widget.animate ? const Duration(milliseconds: 450) : Duration.zero,
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => CustomPaint(
                size: Size(double.infinity, widget.height),
                painter: _ChartPainter(
                  series: widget.series,
                  bands: widget.bands,
                  doses: widget.doses,
                  markers: widget.markers,
                  maxT: maxT,
                  yTop: yTop,
                  rightTop: rightTop,
                  rightUnit: widget.rightUnit,
                  rightColor: widget.rightColor ?? scheme.secondary,
                  hoverX: _hoverX,
                  hoverY: _hoverY,
                  progress: widget.animate ? value.clamp(0.05, 1.0) : 1.0,
                  gridColor: scheme.outlineVariant.withValues(alpha: 0.5),
                  axisColor: scheme.outline,
                  labelColor: scheme.onSurfaceVariant,
                  tooltipBg: scheme.inverseSurface,
                  tooltipFg: scheme.onInverseSurface,
                  xUnit: widget.xUnit,
                  yUnit: widget.yUnit,
                  textStyle: textTheme.labelSmall ?? const TextStyle(fontSize: 11),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _legend(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 6),
      child: Wrap(
        spacing: 16,
        runSpacing: 4,
        children: [
          for (final s in widget.series)
            if (s.label.isNotEmpty)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 14,
                    height: 3,
                    decoration: BoxDecoration(
                      color: s.color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(s.label, style: Theme.of(context).textTheme.labelMedium),
                ],
              ),
          for (final b in widget.bands)
            if (b.label.isNotEmpty)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 14,
                    height: 10,
                    decoration: BoxDecoration(
                      color: b.color.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(color: b.color.withValues(alpha: 0.5)),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(b.label, style: Theme.of(context).textTheme.labelMedium),
                ],
              ),
        ],
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.series,
    required this.bands,
    required this.doses,
    required this.markers,
    required this.maxT,
    required this.yTop,
    required this.rightTop,
    this.rightUnit,
    required this.rightColor,
    required this.hoverX,
    required this.hoverY,
    required this.progress,
    required this.gridColor,
    required this.axisColor,
    required this.labelColor,
    required this.tooltipBg,
    required this.tooltipFg,
    required this.xUnit,
    required this.yUnit,
    required this.textStyle,
  });

  final List<ChartSeries> series;
  final List<ChartBand> bands;
  final List<double> doses;
  final List<ChartMarker> markers;
  final double maxT;
  final double yTop;
  final double rightTop;
  final String? rightUnit;
  final Color rightColor;
  final double? hoverX;
  final double? hoverY;
  final double progress;
  final Color gridColor;
  final Color axisColor;
  final Color labelColor;
  final Color tooltipBg;
  final Color tooltipFg;
  final String xUnit;
  final String yUnit;
  final TextStyle textStyle;

  static const _padLeft = 58.0;
  static const _padRight = 18.0;
  static const _padTop = 16.0;
  static const _padBottom = 34.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rightPad = rightUnit == null ? _padRight : 46.0;
    final plot = Rect.fromLTRB(
      _padLeft,
      _padTop,
      size.width - rightPad,
      size.height - _padBottom,
    );
    if (plot.width <= 0 || plot.height <= 0) return;

    final yTicks = axisTicks(yTop, targetTicks: 5);
    final xTicks = axisTicks(maxT, targetTicks: 6);

    double dx(double t) => plot.left + (t / maxT) * plot.width;
    double dy(double c) => plot.bottom - (c / yTop) * plot.height;
    double dyR(double c) => plot.bottom - (c / rightTop) * plot.height;

    // 网格
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (final t in yTicks) {
      final y = dy(t);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
    }
    for (final t in xTicks) {
      final x = dx(t);
      canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), gridPaint);
    }

    // 坐标轴
    final axisPaint = Paint()
      ..color = axisColor.withValues(alpha: 0.8)
      ..strokeWidth = 1;
    canvas.drawLine(plot.bottomLeft, plot.bottomRight, axisPaint);
    canvas.drawLine(plot.bottomLeft, plot.topLeft, axisPaint);

    // 刻度文字
    for (final t in yTicks) {
      _text(
        canvas,
        fmtNum(t, maxSignificant: 3),
        Offset(plot.left - 8, dy(t)),
        align: _Align.rightCenter,
      );
    }
    for (final t in xTicks) {
      _text(canvas, fmtNum(t, maxSignificant: 3), Offset(dx(t), plot.bottom + 6),
          align: _Align.topCenter);
    }
    _text(canvas, 't ($xUnit)', Offset(plot.right, plot.bottom + 18), align: _Align.topRight);
    _text(canvas, 'C ($yUnit)', Offset(plot.left - 8, plot.top - 4), align: _Align.bottomRight);

    // 右轴（双轴图）
    if (rightUnit != null) {
      final rTicks = axisTicks(rightTop, targetTicks: 5);
      for (final t in rTicks) {
        _text(
          canvas,
          fmtNum(t, maxSignificant: 3),
          Offset(plot.right + 8, dyR(t)),
          align: _Align.topLeft,
          color: rightColor,
        );
      }
      _text(
        canvas,
        'C ($rightUnit)',
        Offset(plot.right + 8, plot.top - 4),
        align: _Align.bottomRight,
        color: rightColor,
      );
    }

    // 给药标记
    if (doses.isNotEmpty) {
      final dosePaint = Paint()
        ..color = markerColor.withValues(alpha: 0.45)
        ..strokeWidth = 1.2;
      for (final t in doses) {
        if (t < 0 || t > maxT) continue;
        _dashedLine(canvas, Offset(dx(t), plot.top), Offset(dx(t), plot.bottom), dosePaint);
      }
    }

    // 曲线
    canvas.save();
    canvas.clipRect(plot);

    // 预测区间带（先画，压在曲线下面）
    for (final band in bands) {
      if (band.low.length < 2 || band.high.length < 2) continue;
      final path = Path();
      for (var i = 0; i < band.high.length; i++) {
        final p = band.high[i];
        final x = dx(p.t);
        final y = dy(p.c);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      for (var i = band.low.length - 1; i >= 0; i--) {
        final p = band.low[i];
        path.lineTo(dx(p.t), dy(p.c));
      }
      path.close();
      canvas.drawPath(path, Paint()..color = band.color.withValues(alpha: 0.16));
    }

    for (final s in series) {
      if (s.points.length < 2) continue;
      final path = Path();
      final pointList = s.points;
      final count = math.max(2, (pointList.length * progress).round());
      for (var i = 0; i < count && i < pointList.length; i++) {
        final p = pointList[i];
        final x = dx(p.t);
        final y = s.rightAxis ? dyR(p.c) : dy(p.c);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      if (s.fill && !s.rightAxis) {
        final fillPath = Path.from(path)
          ..lineTo(dx(pointList[count - 1].t), plot.bottom)
          ..lineTo(dx(pointList.first.t), plot.bottom)
          ..close();
        final gradient = ui.Gradient.linear(
          Offset(0, plot.top),
          Offset(0, plot.bottom),
          [s.color.withValues(alpha: 0.28), s.color.withValues(alpha: 0.02)],
        );
        canvas.drawPath(fillPath, Paint()..shader = gradient);
      }
      final paint = Paint()
        ..color = s.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = s.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      if (s.dashed) {
        _dashedPath(canvas, path, paint);
      } else {
        canvas.drawPath(path, paint);
      }
    }

    // 实测点
    for (final m in markers) {
      final center = Offset(dx(m.t), dy(m.c));
      canvas.drawCircle(center, 4.5, Paint()..color = Colors.white);
      canvas.drawCircle(
        center,
        4.5,
        Paint()
          ..color = markerColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    canvas.restore();

    // 悬停十字线
    final hx = hoverX;
    if (hx != null && hx >= plot.left && hx <= plot.right) {
      final t = ((hx - plot.left) / plot.width) * maxT;
      final crossPaint = Paint()
        ..color = labelColor.withValues(alpha: 0.55)
        ..strokeWidth = 1;
      canvas.drawLine(Offset(hx, plot.top), Offset(hx, plot.bottom), crossPaint);
      _drawTooltip(canvas, size, plot, t, hx);
    }
  }

  void _drawTooltip(Canvas canvas, Size size, Rect plot, double t, double hx) {
    final rows = <String>['t = ${fmtNum(t, maxSignificant: 4)} $xUnit'];
    for (final s in series) {
      if (s.points.isEmpty) continue;
      final c = _interpolate(s.points, t);
      if (c == null) continue;
      final value = fmtNum(c, maxSignificant: 4);
      rows.add(s.label.isEmpty ? 'C = $value $yUnit' : '${s.label}: $value');
    }

    const lineHeight = 17.0;
    const pad = 8.0;
    var w = 0.0;
    for (final r in rows) {
      w = math.max(w, _measure(r).width);
    }
    final boxW = w + pad * 2;
    final boxH = rows.length * lineHeight + pad * 2 - 4;
    var left = hx + 14;
    if (left + boxW > size.width - 4) left = hx - boxW - 14;
    final top = math.max(4.0, math.min(plot.top + 8, size.height - boxH - 4));
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, boxW, boxH),
      const Radius.circular(8),
    );
    canvas.drawRRect(rect, Paint()..color = tooltipBg.withValues(alpha: 0.94));
    for (var i = 0; i < rows.length; i++) {
      _text(
        canvas,
        rows[i],
        Offset(left + pad, top + pad + i * lineHeight),
        color: tooltipFg,
        align: _Align.topLeft,
      );
    }
  }

  double? _interpolate(List<SamplePoint> points, double t) {
    if (points.isEmpty) return null;
    if (t <= points.first.t) return points.first.c;
    if (t >= points.last.t) return points.last.c;
    var lo = 0;
    var hi = points.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) ~/ 2;
      if (points[mid].t <= t) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final a = points[lo];
    final b = points[hi];
    final span = b.t - a.t;
    if (span.abs() < 1e-12) return a.c;
    final f = (t - a.t) / span;
    return a.c + (b.c - a.c) * f;
  }

  Color get markerColor => const Color(0xFFE8590C);

  Size _measure(String text) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: textStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    return tp.size;
  }

  void _text(
    Canvas canvas,
    String text,
    Offset at, {
    _Align align = _Align.topLeft,
    Color? color,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: textStyle.copyWith(color: color ?? labelColor),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    var offset = at;
    switch (align) {
      case _Align.topLeft:
        offset = at;
        break;
      case _Align.topCenter:
        offset = Offset(at.dx - tp.width / 2, at.dy);
        break;
      case _Align.topRight:
        offset = Offset(at.dx - tp.width, at.dy);
        break;
      case _Align.rightCenter:
        offset = Offset(at.dx - tp.width, at.dy - tp.height / 2);
        break;
      case _Align.bottomRight:
        offset = Offset(at.dx - tp.width, at.dy - tp.height);
        break;
    }
    tp.paint(canvas, offset);
  }

  void _dashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 4.0;
    const gap = 4.0;
    final total = (b - a).distance;
    if (total <= 0) return;
    final dir = (b - a) / total;
    var d = 0.0;
    while (d < total) {
      final end = math.min(d + dash, total);
      canvas.drawLine(a + dir * d, a + dir * end, paint);
      d = end + gap;
    }
  }

  void _dashedPath(Canvas canvas, Path path, Paint paint) {
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        final end = math.min(d + 7, metric.length);
        canvas.drawPath(metric.extractPath(d, end), paint);
        d = end + 5;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) {
    return old.series != series ||
        old.bands != bands ||
        old.hoverX != hoverX ||
        old.hoverY != hoverY ||
        old.maxT != maxT ||
        old.yTop != yTop ||
        old.progress != progress ||
        old.doses != doses ||
        old.markers != markers;
  }
}

enum _Align { topLeft, topCenter, topRight, rightCenter, bottomRight }
