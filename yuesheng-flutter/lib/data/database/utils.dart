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
