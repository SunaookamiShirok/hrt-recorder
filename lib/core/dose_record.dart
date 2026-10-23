// 用药记录：每一次给药的时间、药物、途径、剂量。
import 'dart:convert' as convert;

/// 一次给药记录。
class DoseRecord {
  const DoseRecord({
    required this.id,
    required this.takenAt,
    required this.drug,
    required this.route,
    required this.dose,
    this.holdMinutes,
    this.note = '',
  });

  final String id;
  final DateTime takenAt;

  /// 'E2' 或 'CPA'。
  final String drug;

  /// 途径：'口服' / '舌下' / '贴片' / '肌注'。
  final String route;

  final double dose;

  /// 含服时长（分钟），仅舌下记录有意义。
  final double? holdMinutes;

  final String note;

  Map<String, dynamic> toJson() => {
        'id': id,
        'takenAt': takenAt.toIso8601String(),
        'drug': drug,
        'route': route,
        'dose': dose,
        'holdMinutes': holdMinutes,
        'note': note,
      };

  static DoseRecord? fromJson(Map<String, dynamic> json) {
    try {
      return DoseRecord(
        id: json['id'] as String? ?? '',
        takenAt: DateTime.parse(json['takenAt'] as String),
        drug: json['drug'] as String? ?? 'E2',
        route: json['route'] as String? ?? '口服',
        dose: (json['dose'] as num).toDouble(),
        holdMinutes: (json['holdMinutes'] as num?)?.toDouble(),
        note: json['note'] as String? ?? '',
      );
    } catch (_) {
      return null;
    }
  }
}

class DoseRecordsCodec {
  const DoseRecordsCodec._();

  static String encode(List<DoseRecord> records) => convert.jsonEncode({
        'version': 1,
        'records': [for (final r in records) r.toJson()],
      });

  static List<DoseRecord> decode(String raw) {
    try {
      final decoded = convert.jsonDecode(raw);
      if (decoded is! Map) return const [];
      final list = decoded['records'];
      if (list is! List) return const [];
      return [
        for (final item in list)
          if (item is Map) ?DoseRecord.fromJson(Map<String, dynamic>.from(item)),
      ];
    } catch (_) {
      return const [];
    }
  }
}
