// anon_id_store.dart — 匿名设备标识（`DECISIONS §4-516` 甲' 裁定落地）
//
// 【裁定来源】`§4-516`：`anon_id` 走 `payload` 键（非新列、不改 `session_tag`），
//   UUID v4 · 36 字符 · 设备内持久 · 可重置 · 非硬件/非账号 · 服务端不建映射表。
//
// 【注入形态】首帧后由 `main.dart` 注入 `InteractionEventService.anonId`
//   （不阻塞冷启动）。为 null / 空串时不发键 ⇒ 该行不可归因
//   （报批稿 2026-11-15 §七 F2，设计如此）。
//
// 【生成式】`package:uuid` 的 v4 —— 与全仓 `generateUuid()`
//   （`lib/data/database/utils.dart`，20+ 处调用）同源，不造第二套。
//   与 web 侧 `crypto.getRandomValues` 构造的 v4 同构：均 36 字符小写 v4，
//   ⇒ 报批稿判据①「形如 UUID v4」两端同一判据。
//
// 【失败语义】读不到 / 写不进（隐私模式、存储异常）⇒ 返回 null 并留痕。绝不抛。
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// SharedPreferences 键（web 侧为 `yuesheng_anon_id_v1`，语义同族、命名空间不同）。
const String kAnonIdPrefsKey = 'anon_id_v1';

/// 匿名设备标识读写（设备内唯一真源）。
class AnonIdStore {
  AnonIdStore._();

  /// 内存缓存：注入后 `record()` 只读此值，不再做 IO。
  static String? _cached;

  /// 测试用：清缓存（配合 `SharedPreferences.setMockInitialValues`）。
  @visibleForTesting
  static void debugReset() => _cached = null;

  /// 读现有值；缺或形状不合法 ⇒ 生成 UUID v4 并写回。多次调用返回同值。
  ///
  /// 「可重置」= 清站点数据 / 卸载重装（本期零 UI，见报批稿 §三 裁点 2 乙）。
  static Future<String?> loadOrCreate() async {
    final cached = _cached;
    if (cached != null) return cached;
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getString(kAnonIdPrefsKey);
      final id = (existing != null && existing.length == 36)
          ? existing
          : const Uuid().v4();
      if (id != existing) {
        await prefs.setString(kAnonIdPrefsKey, id);
      }
      _cached = id;
      return id;
    } catch (e) {
      debugPrint('[anon_id] 读写失败（该行将不可归因）: $e');
      return null;
    }
  }
}
