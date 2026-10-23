// 根据平台选择本地存储实现：原生走文件，Web 走 localStorage。
export 'lab_storage_io.dart' if (dart.library.js_interop) 'lab_storage_web.dart';
