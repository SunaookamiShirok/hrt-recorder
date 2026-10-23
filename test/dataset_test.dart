import 'package:flutter_test/flutter_test.dart';
import 'package:pk_sim/core/dataset.dart';

void main() {
  group('CSV 解析', () {
    test('带表头的逗号分隔', () {
      final r = parseConcentrationCsv('time,conc\n0.5,2.1\n1,4.2\n2,5.0\n');
      expect(r.points.length, 3);
      expect(r.points.first.t, 0.5);
      expect(r.points.first.c, 2.1);
      expect(r.delimiter, ',');
    });

    test('分号与小数逗号', () {
      final r = parseConcentrationCsv('0,5;2,1\n1,0;4,2');
      expect(r.points.length, 2);
      expect(r.points[1].t, 1.0);
      expect(r.points[1].c, 4.2);
    });

    test('制表符分隔与空行', () {
      final r = parseConcentrationCsv('0\t0\n\n1\t3.5\n2\t4.0\n');
      expect(r.points.length, 3);
      expect(r.points.last.c, 4.0);
    });

    test('按时间排序并跳过坏行', () {
      final r = parseConcentrationCsv('2,4\nfoo,bar\n1,2\n0,0\n');
      expect(r.points.map((p) => p.t).toList(), [0.0, 1.0, 2.0]);
      expect(r.skipped, 1);
    });

    test('空输入安全', () {
      expect(parseConcentrationCsv('').isEmpty, isTrue);
    });
  });

  test('演示数据按时间递增且为正', () {
    final data = demoOralData();
    expect(data.length, greaterThan(5));
    for (var i = 0; i < data.length; i++) {
      expect(data[i].c, greaterThan(0));
      if (i > 0) expect(data[i].t, greaterThan(data[i - 1].t));
    }
  });
}
