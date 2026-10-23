// 主题色：可选的强调色（持久化由 SettingsRepository 统一处理）。
import 'package:flutter/material.dart';

import '../ui/theme.dart';

class ThemeController extends ChangeNotifier {
  ThemeController._();

  static final ThemeController instance = ThemeController._();

  /// 预设强调色。
  static const presets = <({String name, Color color})>[
    (name: '品红', color: Color(0xFFD946EF)),
    (name: '紫罗兰', color: Color(0xFF8B5CF6)),
    (name: '玫红', color: Color(0xFFF43F5E)),
    (name: '天蓝', color: Color(0xFF3B82F6)),
    (name: '青色', color: Color(0xFF22D3EE)),
    (name: '翠绿', color: Color(0xFF34D399)),
    (name: '琥珀', color: Color(0xFFFB923C)),
    (name: '金黄', color: Color(0xFFFACC15)),
  ];

  Color _accent = presets.first.color;

  Color get accent => _accent;

  ThemeData theme() => PkTheme.dark(accent: _accent);

  void setAccent(Color color) {
    if (_accent.toARGB32() == color.toARGB32()) return;
    _accent = color;
    notifyListeners();
  }

  /// 启动时恢复设置，不触发保存。
  void setAccentQuiet(Color color) => _accent = color;
}
