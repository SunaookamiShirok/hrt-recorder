// 用药记录的内存缓存 + 本地持久化。
import 'package:flutter/foundation.dart';

import '../core/dose_record.dart';
import 'lab_storage.dart';

class DoseStore extends ChangeNotifier {
  DoseStore._();

  static final DoseStore instance = DoseStore._();

  static const _key = 'dose_records';

  List<DoseRecord> _records = [];
  bool _loaded = false;
  String? _error;
  String _location = '';

  List<DoseRecord> get records => List.unmodifiable(_records);
  bool get isLoaded => _loaded;
  String? get error => _error;
  String get location => _location;

  List<DoseRecord> byDrug(String drug) =>
      [for (final r in _records) if (r.drug == drug) r];

  DoseRecord? latestOf(String drug) {
    final list = byDrug(drug);
    if (list.isEmpty) return null;
    return list.first;
  }

  int countOf(String drug) => _records.where((r) => r.drug == drug).length;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    final raw = await LabStorage.load(_key);
    _records = raw == null ? [] : DoseRecordsCodec.decode(raw);
    _records.sort((a, b) => b.takenAt.compareTo(a.takenAt));
    _location = LabStorage.locationOf(_key);
    _loaded = true;
    notifyListeners();
  }

  Future<void> add(DoseRecord record) async {
    _records = [record, ..._records]
      ..sort((a, b) => b.takenAt.compareTo(a.takenAt));
    await _persist();
    notifyListeners();
  }

  Future<void> remove(String id) async {
    _records = [for (final r in _records) if (r.id != id) r];
    await _persist();
    notifyListeners();
  }

  Future<void> clearAll() async {
    _records = [];
    await LabStorage.clear(_key);
    _error = null;
    notifyListeners();
  }

  Future<void> _persist() async {
    final ok = await LabStorage.save(_key, DoseRecordsCodec.encode(_records));
    _error = ok ? null : '保存失败：无法写入本地存储，请检查磁盘权限。';
  }
}
