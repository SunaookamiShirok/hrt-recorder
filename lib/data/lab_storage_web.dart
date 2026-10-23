// 本地存储（Web）：写入浏览器 localStorage。
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// 极简键值存储。
class LabStorage {
  static String _key(String name) => 'pk_sim_$name';

  static String locationOf(String name) => '浏览器 localStorage（键 ${_key(name)}）';

  static JSObject? get _ls {
    final v = globalContext['localStorage'];
    if (v == null || !v.isA<JSObject>()) return null;
    return v as JSObject;
  }

  static Future<String?> load(String name) async {
    try {
      final ls = _ls;
      if (ls == null) return null;
      final value = ls.callMethod<JSAny?>('getItem'.toJS, _key(name).toJS);
      return value?.dartify() as String?;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> save(String name, String data) async {
    try {
      final ls = _ls;
      if (ls == null) return false;
      ls.callMethod<JSAny?>('setItem'.toJS, _key(name).toJS, data.toJS);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> clear(String name) async {
    try {
      final ls = _ls;
      if (ls == null) return false;
      ls.callMethod<JSAny?>('removeItem'.toJS, _key(name).toJS);
      return true;
    } catch (_) {
      return false;
    }
  }
}
