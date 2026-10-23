// 本地存储：原生写文件，Web 写 localStorage。按名字区分不同的数据集。
import 'dart:io';

/// 极简键值存储。
class LabStorage {
  static const _folder = 'pk_sim';

  static String get _sep => Platform.pathSeparator;

  static String _fileName(String name) => '$name.json';

  /// 数据位置说明（用于界面上告诉用户数据存在哪）。
  static String locationOf(String name) => _candidates(name).first.path;

  static List<File> _candidates(String name) {
    final files = <File>[
      File('${_baseDir().path}$_sep$_folder$_sep${_fileName(name)}'),
    ];
    if (Platform.isAndroid) {
      files.add(File('${Directory.systemTemp.path}$_sep$_folder$_sep${_fileName(name)}'));
    }
    return files;
  }

  static Directory _baseDir() {
    final env = Platform.environment;
    if (Platform.isWindows) {
      final appData = env['APPDATA'];
      if (appData != null && appData.isNotEmpty) return Directory(appData);
      return Directory('${env['USERPROFILE'] ?? '.'}\\AppData\\Roaming');
    }
    if (Platform.isMacOS) {
      return Directory('${env['HOME'] ?? '.'}/Library/Application Support');
    }
    if (Platform.isAndroid) {
      return Directory.systemTemp.parent;
    }
    final xdg = env['XDG_DATA_HOME'];
    if (xdg != null && xdg.isNotEmpty) return Directory(xdg);
    return Directory('${env['HOME'] ?? '.'}/.local/share');
  }

  static Future<String?> load(String name) async {
    for (final file in _candidates(name)) {
      try {
        if (file.existsSync()) return file.readAsStringSync();
      } catch (_) {
        // 换下一个候选路径
      }
    }
    return null;
  }

  static Future<bool> save(String name, String data) async {
    for (final file in _candidates(name)) {
      try {
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(data, flush: true);
        return true;
      } catch (_) {
        // 换下一个候选路径
      }
    }
    return false;
  }

  static Future<bool> clear(String name) async {
    var cleared = false;
    for (final file in _candidates(name)) {
      try {
        if (file.existsSync()) {
          file.deleteSync();
          cleared = true;
        }
      } catch (_) {
        // 忽略
      }
    }
    return cleared;
  }
}
