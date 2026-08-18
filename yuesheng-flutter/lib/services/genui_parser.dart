// ─────────────────────────────────────────────────────────────
// genui_parser — GenUI 协议块解析（B-1 GenUI v1）
//
// 从 AI 回复中提取 [YS_GENUI]...[/YS_GENUI] 块内的组件 spec，
// 复用 [YS_FACT] 的「标记提取→剥离→容错解析→失败降级 null」模式。
//
// 组件类型白名单见 genui_validator.dart（diff/quiz/stat/progress/timeline）。
// 单个块内可放一个组件对象，或 {"components":[...]} 数组。
// 解析失败/无块 → 返回 null；坏组件 → 跳过（不阻断主流程）。
// 纯函数，无副作用，不 throw。
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'genui_validator.dart';

/// GenUI 协议块分隔符
const String kGenuiStart = '[YS_GENUI]';
const String kGenuiEnd = '[/YS_GENUI]';

/// 一个 GenUI 组件（已通过白名单校验）
class GenUiComponent {
  final String type;
  final Map<String, dynamic> data;

  const GenUiComponent({required this.type, required this.data});

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{'type': type};
    map.addAll(data);
    return map;
  }
}

/// 从完整回复文本中提取所有 GenUI 组件
///
/// - 无标记 → null（降级跳过）
/// - 有起始标记无结束标记 → 容错：取到文本末尾
/// - JSON 截断/坏格式 → 容错：修复中文引号后重试；仍失败则该块跳过
/// - 白名单外类型 / 缺必需字段 → 跳过（spec guard）
/// 返回非空列表，若无任何合法组件 → null。
List<GenUiComponent>? parseGenuiBlock(String rawText) {
  final components = <GenUiComponent>[];
  var searchFrom = 0;
  while (true) {
    final start = rawText.indexOf(kGenuiStart, searchFrom);
    if (start == -1) break;
    final end = rawText.indexOf(kGenuiEnd, start + kGenuiStart.length);
    final String jsonStr;
    if (end == -1) {
      jsonStr = rawText.substring(start + kGenuiStart.length).trim();
      _tryAddComponents(components, jsonStr);
      break; // 无结束标记，保守终止
    } else {
      jsonStr = rawText
          .substring(start + kGenuiStart.length, end)
          .trim();
      _tryAddComponents(components, jsonStr);
      searchFrom = end + kGenuiEnd.length;
    }
  }
  return components.isEmpty ? null : components;
}

void _tryAddComponents(List<GenUiComponent> out, String jsonStr) {
  if (jsonStr.isEmpty) return;
  final parsed = _lenientJson(jsonStr);
  if (parsed == null) return;
  if (parsed is List) {
    for (final e in parsed) {
      if (e is Map) _addIfValid(out, Map<String, dynamic>.from(e));
    }
  } else if (parsed is Map) {
    final map = Map<String, dynamic>.from(parsed);
    if (map['components'] is List) {
      for (final e in map['components']) {
        if (e is Map) _addIfValid(out, Map<String, dynamic>.from(e));
      }
    } else {
      _addIfValid(out, map);
    }
  }
}

void _addIfValid(List<GenUiComponent> out, Map<String, dynamic> raw) {
  final c = validateGenuiComponent(raw);
  if (c != null) out.add(c);
}

/// 容错 JSON 解析：原生失败 + 含中文引号 → 替换后重试；仍失败 → null
Object? _lenientJson(String s) {
  try {
    return jsonDecode(s);
  } catch (_) {
    final fixed = s.replaceAll('\u201C', '"').replaceAll('\u201D', '"');
    if (fixed == s) return null;
    try {
      return jsonDecode(fixed);
    } catch (_) {
      return null;
    }
  }
}

/// 从文本中剥离所有 [YS_GENUI]...[/YS_GENUI] 块
///
/// 供展示层剥离原始 spec（AI 输出协议块后不得泄漏给用户）。
/// 无标记 → 原样返回；完整块 → 整块移除，前后文本拼接；
/// 无结束标记的残块 → 自该标记起截断（保守防泄漏）。纯函数，不 throw。
String stripGenuiBlock(String rawText) {
  final buf = StringBuffer();
  var cursor = 0;
  while (true) {
    final start = rawText.indexOf(kGenuiStart, cursor);
    if (start == -1) {
      buf.write(rawText.substring(cursor));
      break;
    }
    buf.write(rawText.substring(cursor, start).trimRight());
    final end = rawText.indexOf(kGenuiEnd, start + kGenuiStart.length);
    if (end == -1) break; // 残块：保守截断
    cursor = end + kGenuiEnd.length;
  }
  return buf.toString().trim();
}
