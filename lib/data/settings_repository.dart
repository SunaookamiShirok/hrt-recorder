// 设置持久化：把主题色、体重、目标区间、校准方法等统一存到一个 JSON。
import 'dart:convert' as convert;

import 'package:flutter/material.dart';

import '../core/app_settings.dart';
import '../core/calibration.dart';
import '../core/calibration_settings.dart';
import '../core/theme_controller.dart';
import 'lab_storage.dart';

class SettingsRepository {
  SettingsRepository._();

  static final SettingsRepository instance = SettingsRepository._();

  static const _key = 'app_settings';

  bool _ready = false;

  Future<void> load() async {
    final raw = await LabStorage.load(_key);
    if (raw != null && raw.isNotEmpty) {
      try {
        final map = convert.jsonDecode(raw);
        if (map is Map) {
          _apply(Map<String, dynamic>.from(map));
        }
      } catch (_) {
        // 忽略损坏的设置
      }
    }
    _ready = true;
    ThemeController.instance.addListener(persist);
    AppSettings.instance.addListener(persist);
    CalibrationSettings.instance.addListener(persist);
  }

  void _apply(Map<String, dynamic> map) {
    final accent = map['accent'] as String?;
    if (accent != null) {
      final v = int.tryParse(accent.replaceFirst('#', ''), radix: 16);
      if (v != null) ThemeController.instance.setAccentQuiet(Color(0xFF000000 | v));
    }

    final app = AppSettings.instance;
    if (map['weight'] is num) app.setWeight((map['weight'] as num).toDouble());
    if (map['e2Low'] is num && map['e2High'] is num) {
      app.setE2Range((map['e2Low'] as num).toDouble(), (map['e2High'] as num).toDouble());
    }
    if (map['cpaHigh'] is num) app.setCpaHigh((map['cpaHigh'] as num).toDouble());

    final cal = CalibrationSettings.instance;
    final method = map['method'] as String?;
    if (method != null) {
      final m = CalibrationMethod.values.where((e) => e.name == method);
      if (m.isNotEmpty) cal.setMethod(m.first);
    }
    if (map['cpaInteraction'] is bool) {
      cal.setCpaInteraction(map['cpaInteraction'] as bool);
    }
    if (map['cpaInhibition'] is num) {
      cal.setCpaInhibition((map['cpaInhibition'] as num).toDouble());
    }
  }

  Future<void> persist() async {
    if (!_ready) return;
    final map = <String, dynamic>{
      'accent':
          '#${ThemeController.instance.accent.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
      'weight': AppSettings.instance.weight,
      'e2Low': AppSettings.instance.e2Low,
      'e2High': AppSettings.instance.e2High,
      'cpaHigh': AppSettings.instance.cpaHigh,
      'method': CalibrationSettings.instance.method.name,
      'cpaInteraction': CalibrationSettings.instance.cpaInteraction,
      'cpaInhibition': CalibrationSettings.instance.cpaInhibition,
    };
    await LabStorage.save(_key, convert.jsonEncode(map));
  }
}
