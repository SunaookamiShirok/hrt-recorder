// 暗紫主题（强调色可由用户选择）。
import 'package:flutter/material.dart';

class PkTheme {
  const PkTheme._();

  static const bg = Color(0xFF14101C);
  static const surface = Color(0xFF1F1830);
  static const surfaceHigh = Color(0xFF2A2140);
  static const text = Color(0xFFF3EEFF);
  static const muted = Color(0xFFA79BC4);
  static const warn = Color(0xFFFFB020);
  static const ok = Color(0xFF34D399);

  /// 目前使用的强调色（由 ThemeController 设置）。
  static Color accent = const Color(0xFFD946EF);

  /// 由强调色派生的第二颜色（用于 CPA 等第二个数据系列）。
  static Color get accentAlt {
    final hsl = HSLColor.fromColor(accent);
    return hsl.withHue((hsl.hue + 45) % 360).withSaturation(0.62).withLightness(0.63).toColor();
  }

  /// 比强调色更亮的版本，用于渐变。
  static Color get accentLight {
    final hsl = HSLColor.fromColor(accent);
    return hsl.withLightness((hsl.lightness + 0.18).clamp(0.0, 1.0)).toColor();
  }

  static ThemeData dark({Color? accent}) {
    final a = accent ?? PkTheme.accent;
    final scheme = ColorScheme.fromSeed(
      seedColor: a,
      brightness: Brightness.dark,
    ).copyWith(
      primary: a,
      secondary: const Color(0xFF22D3EE),
      surface: surface,
      onSurface: text,
      error: const Color(0xFFFF6B6B),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      dividerColor: Colors.white12,
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: const CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      textTheme: const TextTheme(
        headlineSmall: TextStyle(color: text, fontWeight: FontWeight.w700),
        titleLarge: TextStyle(color: text, fontWeight: FontWeight.w700),
        bodyMedium: TextStyle(color: text),
        bodySmall: TextStyle(color: muted),
        labelSmall: TextStyle(color: muted),
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      sliderTheme: const SliderThemeData(
        trackHeight: 3,
        overlayShape: RoundSliderOverlayShape(overlayRadius: 14),
      ),
    );
  }
}
