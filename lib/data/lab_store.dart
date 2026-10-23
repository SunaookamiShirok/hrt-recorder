// 化验记录的内存缓存 + 本地持久化（ChangeNotifier，供各页面监听）。
import 'package:flutter/foundation.dart';

import '../core/calibration.dart';
import '../core/fitting.dart' show ObservedPoint;
import 'lab_record.dart';
import 'lab_storage.dart';

class LabStore extends ChangeNotifier {
  LabStore._();

  static final LabStore instance = LabStore._();

  List<LabRecord> _records = [];
  bool _loaded = false;
  String? _error;
  String _location = '';

  List<LabRecord> get records => List.unmodifiable(_records);
  bool get isLoaded => _loaded;
  String? get error => _error;
  String get location => _location;

  /// 出现过哪些指标名（按出现顺序）。
  List<String> get analytes {
    final set = <String>{};
    for (final r in _records) {
      set.add(r.analyte);
    }
    return set.toList();
  }

  List<LabRecord> byAnalyte(String analyte) =>
      [for (final r in _records) if (r.analyte == analyte) r];

  /// 带「距给药」时间的记录数（按指标统计）。
  int taggedCount(String analyte) => _records
      .where((r) => r.analyte == analyte && r.hoursSinceDose != null)
      .length;

  /// 有多少条记录带「距给药」时间。
  int get taggedTotal => _records.where((r) => r.hoursSinceDose != null).length;

  /// 满足最少条数的指标列表（用于个体模型）。
  List<String> analytesWithHours({int minCount = 4}) {
    final counts = <String, int>{};
    for (final r in _records) {
      if (r.hoursSinceDose != null) {
        counts[r.analyte] = (counts[r.analyte] ?? 0) + 1;
      }
    }
    final out = [
      for (final e in counts.entries)
        if (e.value >= minCount) e.key,
    ]..sort();
    return out;
  }

  /// 某个指标的化验点（t = 距给药小时数，C = mg/L），按时间排序。
  List<ObservedPoint> taggedPoints(String analyte) {
    final out = [
      for (final r in _records)
        if (r.analyte == analyte && r.hoursSinceDose != null)
          ObservedPoint(r.hoursSinceDose!, r.valueMgPerL),
    ]..sort((a, b) => a.t.compareTo(b.t));
    return out;
  }

  /// 带日期的化验点（供 Kalman / 贝叶斯校准使用），按采血日期排序。
  List<CalibrationPoint> calibrationPoints(String analyte) {
    final out = [
      for (final r in _records)
        if (r.analyte == analyte && r.hoursSinceDose != null)
          CalibrationPoint(
            at: r.takenAt,
            tHours: r.hoursSinceDose!,
            concentration: r.valueMgPerL,
          ),
    ]..sort((a, b) => a.at.compareTo(b.at));
    return out;
  }

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    final raw = await LabStorage.load('lab_records');
    _records = raw == null ? [] : LabRecordsCodec.decode(raw);
    _records.sort((a, b) => b.takenAt.compareTo(a.takenAt));
    _location = LabStorage.locationOf('lab_records');
    _loaded = true;
    notifyListeners();
  }

  Future<void> add(LabRecord record) async {
    _records = [record, ..._records];
    _records.sort((a, b) => b.takenAt.compareTo(a.takenAt));
    await _persist();
    notifyListeners();
  }

  Future<void> remove(String id) async {
    _records = [for (final r in _records) if (r.id != id) r];
    await _persist();
    notifyListeners();
  }

  /// 合并导入的记录（按 id 去重）。
  Future<int> mergeAll(List<LabRecord> incoming) async {
    final existing = {for (final r in _records) r.id};
    final added = [for (final r in incoming) if (!existing.contains(r.id)) r];
    if (added.isEmpty) return 0;
    _records = [..._records, ...added]..sort((a, b) => b.takenAt.compareTo(a.takenAt));
    await _persist();
    notifyListeners();
    return added.length;
  }

  Future<void> clearAll() async {
    _records = [];
    await LabStorage.clear('lab_records');
    _error = null;
    notifyListeners();
  }

  Future<void> _persist() async {
    final ok = await LabStorage.save('lab_records', LabRecordsCodec.encode(_records));
    _error = ok ? null : '保存失败：无法写入本地存储，请检查磁盘权限。';
  }
}
