// 开发用：验证原生本地存储能正常写入/读取/清除。
// 运行：dart run tool/check_storage.dart
// ignore_for_file: avoid_print
import 'package:pk_sim/data/lab_storage_io.dart';

Future<void> main() async {
  const key = 'lab_records';
  print('存储位置: ${LabStorage.locationOf(key)}');
  final ok = await LabStorage.save(key, '{"version":1,"records":[]}');
  print('save -> $ok');
  final raw = await LabStorage.load(key);
  print('load -> $raw');
  final cleared = await LabStorage.clear(key);
  print('clear -> $cleared');
  final after = await LabStorage.load(key);
  print('after clear -> $after');
}
