// 真实化验记录：数据模型、JSON 与 CSV 序列化。
import 'dart:convert' as convert;

import '../utils/units.dart';

/// 一条化验记录。
///
/// 数值按用户看到的单位保存（pg/mL、ng/mL、mg/L），换算成内核单位 mg/L
/// 由 [valueMgPerL] 完成。
class LabRecord {
  const LabRecord({
    required this.id,
    required this.takenAt,
    required this.analyte,
    required this.value,
    required this.unit,
    this.hoursSinceDose,
    this.note = '',
  });

  final String id;
  final DateTime takenAt;

  /// 指标名，例如 E2、CPA，或用户自定义。
  final String analyte;

  final double value;
  final ConcentrationUnit unit;

  /// 可选的「距上次给药小时数」，用于把化验点画到模拟曲线上。
  final double? hoursSinceDose;

  final String note;

  /// 换算成内核单位 mg/L。
  double get valueMgPerL => unit.toBase(value);

  LabRecord copyWith({
    DateTime? takenAt,
    String? analyte,
    double? value,
    ConcentrationUnit? unit,
    double? hoursSinceDose,
    String? note,
  }) {
    return LabRecord(
      id: id,
      takenAt: takenAt ?? this.takenAt,
      analyte: analyte ?? this.analyte,
      value: value ?? this.value,
      unit: unit ?? this.unit,
      hoursSinceDose: hoursSinceDose ?? this.hoursSinceDose,
      note: note ?? this.note,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'takenAt': takenAt.toIso8601String(),
        'analyte': analyte,
        'value': value,
        'unit': unit.name,
        'hoursSinceDose': hoursSinceDose,
        'note': note,
      };

  static LabRecord? fromJson(Map<String, dynamic> json) {
    try {
      final unitName = json['unit'] as String? ?? ConcentrationUnit.pgPerMl.name;
      final unit = ConcentrationUnit.values.firstWhere(
        (u) => u.name == unitName,
        orElse: () => ConcentrationUnit.pgPerMl,
      );
      return LabRecord(
        id: json['id'] as String? ?? '',
        takenAt: DateTime.parse(json['takenAt'] as String),
        analyte: json['analyte'] as String? ?? 'E2',
        value: (json['value'] as num).toDouble(),
        unit: unit,
        hoursSinceDose: (json['hoursSinceDose'] as num?)?.toDouble(),
        note: json['note'] as String? ?? '',
      );
    } catch (_) {
      return null;
    }
  }
}

/// 化验记录集合的序列化工具（纯函数，便于测试）。
class LabRecordsCodec {
  const LabRecordsCodec._();

  static String encode(List<LabRecord> records) {
    final list = [for (final r in records) r.toJson()];
    return convert.jsonEncode({'version': 1, 'records': list});
  }

  static List<LabRecord> decode(String raw) {
    try {
      final decoded = convert.jsonDecode(raw);
      if (decoded is! Map) return const [];
      final list = decoded['records'];
      if (list is! List) return const [];
      final out = <LabRecord>[];
      for (final item in list) {
        if (item is Map) {
          final r = LabRecord.fromJson(Map<String, dynamic>.from(item));
          if (r != null) out.add(r);
        }
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  static String toCsv(List<LabRecord> records) {
    final b = StringBuffer('takenAt,analyte,value,unit,hoursSinceDose,note\n');
    for (final r in records) {
      final note = r.note.replaceAll('\n', ' ').replaceAll(',', '，');
      b.writeln('${r.takenAt.toIso8601String()},${r.analyte},${r.value},'
          '${r.unit.label},${r.hoursSinceDose ?? ''},$note');
    }
    return b.toString().trimRight();
  }

  /// 解析 CSV（第一行可为表头）。返回记录与跳过的行数。
  static ({List<LabRecord> records, int skipped}) fromCsv(String text) {
    final lines = text.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).toList();
    final out = <LabRecord>[];
    var skipped = 0;
    for (var i = 0; i < lines.length; i++) {
      final cells = lines[i].split(',').map((c) => c.trim()).toList();
      if (cells.length < 4) {
        skipped++;
        continue;
      }
      final when = DateTime.tryParse(cells[0]);
      final value = double.tryParse(cells[2].replaceAll(',', '.'));
      final unit = ConcentrationUnit.values.firstWhere(
        (u) => u.label == cells[3],
        orElse: () => ConcentrationUnit.pgPerMl,
      );
      if (when == null || value == null) {
        // 表头行也会落到这里，属于正常情况
        skipped++;
        continue;
      }
      out.add(LabRecord(
        id: '${when.microsecondsSinceEpoch}_$i',
        takenAt: when,
        analyte: cells[1].isEmpty ? 'E2' : cells[1],
        value: value,
        unit: unit,
        hoursSinceDose: cells.length > 4 ? double.tryParse(cells[4]) : null,
        note: cells.length > 5 ? cells.sublist(5).join(',') : '',
      ));
    }
    out.sort((a, b) => a.takenAt.compareTo(b.takenAt));
    return (records: out, skipped: skipped);
  }
}
