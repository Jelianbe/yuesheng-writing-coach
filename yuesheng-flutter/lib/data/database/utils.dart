// ─────────────────────────────────────────────────────────────
// DB 工具函数 — 复刻 yuesheng-android/src/db/index.ts 的工具函数
// uuid / nowSec / parseJson / stringifyJson
// ─────────────────────────────────────────────────────────────

import 'dart:convert';
import 'package:uuid/uuid.dart';

/// UUID v4 生成（替代原项目的 crypto.randomUUID + 兜底实现）
String generateUuid() {
  return const Uuid().v4();
}

/// 当前 unix 秒（与原项目 nowSec 一致）
int nowSec() {
  return DateTime.now().millisecondsSinceEpoch ~/ 1000;
}

/// JSON 解析：失败返回 fallback，绝不 throw
/// 复刻原项目 parseJson 的语义（DB 里 JSON 字段可能脏）
T parseJson<T>(
  String? raw,
  T fallback,
  T Function(Map<String, dynamic>) fromJson,
) {
  if (raw == null || raw.isEmpty) return fallback;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      return fromJson(decoded);
    }
    return fallback;
  } catch (_) {
    return fallback;
  }
}

/// JSON 列表解析：失败返回空列表
List<T> parseJsonList<T>(
  String? raw,
  List<T> fallback,
  T Function(Map<String, dynamic>) fromJson,
) {
  if (raw == null || raw.isEmpty) return fallback;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is List) {
      return decoded.whereType<Map<String, dynamic>>().map(fromJson).toList();
    }
    return fallback;
  } catch (_) {
    return fallback;
  }
}

/// JSON 字符串列表解析：失败返回空列表
List<String> parseJsonStringList(String? raw) {
  if (raw == null || raw.isEmpty) return [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is List) {
      return decoded
          .map((e) => e?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
    }
    return [];
  } catch (_) {
    return [];
  }
}

/// JSON 序列化（null 安全）
String stringifyJson(dynamic value) {
  return jsonEncode(value);
}

/// 章节内容指纹（C78 D-6）：FNV-1a 32-bit，返回 8 位小写十六进制串
///
/// 用途：事实抽取落地时记录当时该章正文指纹，后续比对指纹变化 → 相关
/// 断言/事件标记 stale，由用户在角色标签页确认或修正。
/// 自实现而非用 String.hashCode：Dart 字符串 hash 不保证跨版本/跨 isolate
/// 稳定，用它会导致存量事实在升级后集体误判为 stale。
String chapterFingerprint(String content) {
  const int offsetBasis = 0x811c9dc5;
  const int prime = 0x01000193;
  var hash = offsetBasis;
  for (var i = 0; i < content.length; i++) {
    hash = (hash ^ content.codeUnitAt(i)) & 0xFFFFFFFF;
    hash = (hash * prime) & 0xFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}
