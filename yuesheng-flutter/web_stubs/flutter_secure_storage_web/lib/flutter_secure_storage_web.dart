// ─────────────────────────────────────────────────────────────
// flutter_secure_storage · **web 侧替身**（DECISIONS §4-461 裁 1=α / 裁 2=读写分档）
//
// 本包是原 `flutter_secure_storage_web` 1.2.1 的本地同包名替身，经根 pubspec
// `dependency_overrides` 覆盖。原包是 dart2html 时代插件（dart:html / dart:js_util
// + package:js 0.6.7），dart2wasm 下三库全不存在 ⇒ 序 3 残余 48 error 全数源自本包。
//
// ★ 替身契约（与原包逐字对齐，使 web_plugin_registrant 无感改指向）：
//   - 同包名 `flutter_secure_storage_web` / 同 pluginClass `FlutterSecureStorageWeb`
//     / 同 fileName `flutter_secure_storage_web.dart`；
//   - `extends FlutterSecureStoragePlatform`（platform_interface 1.1.2，序 3 已实证
//     其在 dart2wasm 下编译零 error）+ `registerWith` 置 instance；
//   - **不依赖 js** ⇒ js 0.6.7 退出 web 编译图（pubspec.lock 仍因 dev 依赖 build_runner
//     保留 js，但 build_runner 不进 web 产物）；本文件不 import dart:html / dart:js_util。
//
// ★ 裁 2 语义（读写分档）：
//   - 读侧（read / containsKey / readAll）返 null / false / 空 —— 对齐 §4-459 裁 2
//     「web stub 一律返回 null」先例 + U8「web 不配 key」语义；
//   - 写侧（write / delete / deleteAll）抛 UnsupportedError —— 不静默成功，避免
//     「上层以为写成功」的静默数据丢失（key 保管静默丢失代价 > 快照仪器）。
//   U8 掩码（裁 3 并入）使 web UI 不暴露配 key 入口 ⇒ 写侧从 UI 不可达，抛错仅兜底。
//
// ★ 硬边界：移动端 android/ios/windows 实现 + 主包 4 个导入点逐字不动；
//   本替身只 endorsed web，不进移动端解析路径。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

/// web 侧 key 保管替身：浏览器首发**不提供 key 持久化**。
class FlutterSecureStorageWeb extends FlutterSecureStoragePlatform {
  /// 由构建生成的 `web_plugin_registrant.dart` 调用（与原包同签名）。
  static void registerWith(Registrar registrar) {
    FlutterSecureStoragePlatform.instance = FlutterSecureStorageWeb();
  }

  /// 写侧：web 不支持 key 保管 ⇒ 抛错（不静默成功，避免静默丢 key）。
  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    throw UnsupportedError(
      'web 首发不支持 key 保管（DECISIONS §4-461 裁 2）：write 不可用',
    );
  }

  /// 读侧：web 无 key 可读 ⇒ 恒 null（与「不配 key」同语义）。
  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async =>
      null;

  /// 读侧：web 无 key ⇒ 恒 false。
  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async =>
      false;

  /// 写侧：web 不支持 key 保管 ⇒ 抛错。
  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    throw UnsupportedError(
      'web 首发不支持 key 保管（DECISIONS §4-461 裁 2）：delete 不可用',
    );
  }

  /// 读侧：web 无 key 可列 ⇒ 恒空 Map。
  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async =>
      const <String, String>{};

  /// 写侧：web 不支持 key 保管 ⇒ 抛错。
  @override
  Future<void> deleteAll({
    required Map<String, String> options,
  }) async {
    throw UnsupportedError(
      'web 首发不支持 key 保管（DECISIONS §4-461 裁 2）：deleteAll 不可用',
    );
  }
}
