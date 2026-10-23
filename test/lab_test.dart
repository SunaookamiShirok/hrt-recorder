import 'package:flutter_test/flutter_test.dart';
import 'package:pk_sim/data/lab_record.dart';
import 'package:pk_sim/utils/units.dart';

void main() {
  final sample = [
    LabRecord(
      id: 'a1',
      takenAt: DateTime(2026, 1, 2, 8, 30),
      analyte: 'E2',
      value: 120,
      unit: ConcentrationUnit.pgPerMl,
      hoursSinceDose: 6,
      note: '贴片第 2 天',
    ),
    LabRecord(
      id: 'a2',
      takenAt: DateTime(2026, 2, 2, 9),
      analyte: 'CPA',
      value: 0.05,
      unit: ConcentrationUnit.mgPerL,
      note: '',
    ),
  ];

  group('化验记录模型', () {
    test('数值换算到 mg/L', () {
      expect(sample[0].valueMgPerL, closeTo(0.00012, 1e-12));
      expect(sample[1].valueMgPerL, closeTo(0.05, 1e-12));
    });

    test('JSON 编解码往返', () {
      final raw = LabRecordsCodec.encode(sample);
      final back = LabRecordsCodec.decode(raw);
      expect(back.length, 2);
      expect(back[0].analyte, 'E2');
      expect(back[0].value, 120);
      expect(back[0].unit, ConcentrationUnit.pgPerMl);
      expect(back[0].hoursSinceDose, 6);
      expect(back[0].note, '贴片第 2 天');
      expect(back[1].hoursSinceDose, isNull);
    });

    test('损坏的数据不会抛异常', () {
      expect(LabRecordsCodec.decode('not json').length, 0);
      expect(LabRecordsCodec.decode('{"records":[{"x":1}]}').length, 0);
    });

    test('CSV 导出后可再导入', () {
      final csv = LabRecordsCodec.toCsv(sample);
      final parsed = LabRecordsCodec.fromCsv(csv);
      expect(parsed.records.length, 2);
      expect(parsed.records.first.analyte, 'E2');
      expect(parsed.records.first.value, 120);
      expect(parsed.records.first.unit, ConcentrationUnit.pgPerMl);
      expect(parsed.records.first.hoursSinceDose, 6);
    });

    test('导出时逗号与换行被清理', () {
      final messy = [
        LabRecord(
          id: 'x',
          takenAt: DateTime(2026, 3, 1),
          analyte: 'E2',
          value: 90,
          unit: ConcentrationUnit.pgPerMl,
          note: '第一行, 含逗号\n第二行',
        ),
      ];
      final csv = LabRecordsCodec.toCsv(messy);
      final back = LabRecordsCodec.fromCsv(csv);
      expect(back.records.length, 1);
      expect(back.records.first.note, contains('含逗号'));
    });
  });
}
