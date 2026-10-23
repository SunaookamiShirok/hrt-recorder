// 主题色：可选的强调色，保存在本机。
import 'package:flutter/material.dart';

import '../data/lab_storage.dart';
import '../ui/theme.dart';

class ThemeController extends ChangeNotifier {
  ThemeController._();

  static final ThemeController instance = ThemeController._();

  static const _key = 'ui_settings';

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

  /// 由强调色派生的配色方案。
  ThemeData theme() => PkTheme.dark(accent: _accent);

  Future<void> load() async {
    final raw = await LabStorage.load(_key);
    if (raw == null || raw.isEmpty) return;
    final hex = raw.trim();
    final value = int.tryParse(hex.replaceFirst('#', ''), radix: 16);
    if (value == null) return;
    _accent = Color(0xFF000000 | value);
    notifyListeners();
  }

  Future<void> setAccent(Color color) async {
    if (_accent.toARGB32() == color.toARGB32()) return;
    _accent = color;
    notifyListeners();
    final hex = '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
    await LabStorage.save(_key, hex);
  }
}
