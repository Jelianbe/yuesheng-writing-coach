// ─────────────────────────────────────────────────────────────
// genui_validator — GenUI 组件白名单 + spec guard（B-1 GenUI v1）
//
// 仿 dsh-genui 的「坏节点丢弃/节点上限/无 eval」原则：
// 对模型输出的 UI spec 永远白名单 + 必需字段校验，坏节点静默丢弃，
// 模型输出错格式不崩 UI，只降级。
// ─────────────────────────────────────────────────────────────

import '../contracts/genui_capability.dart';

// 注：原第 10 行曾有 `import 'genui_parser.dart';`，是冗余依赖——
// GenUiComponent 定义于上面的 contracts，本文件未使用 parser 的任何符号。
// ADR-C70：删除该 import 即解开 `genui_parser ↔ genui_validator` 循环。

/// GenUI 组件白名单（首版 5 种教学刚需组件）
const Set<String> kGenuiWhitelist = {
  'diff',
  'quiz',
  'stat',
  'progress',
  'timeline',
};

/// 校验单个组件 spec，返回合法组件或 null（坏节点丢弃）
///
/// 规则：
/// - type 必须为字符串且在白名单内
/// - diff：必须含 before / after（字符串）
/// - quiz：必须含 items 数组，每项含 q + options(≥2) + answer(int)
/// - stat：必须含 items 数组，每项含 label（字符串）+ value（num）+ max（num）
/// - progress：必须含 steps 数组，每项含 label（字符串）+ status（字符串）
/// - timeline：必须含 events 数组，每项含 date（字符串）+ title（字符串）
GenUiComponent? validateGenuiComponent(Map<String, dynamic> raw) {
  final type = raw['type'];
  if (type is! String) return null;
  if (!kGenuiWhitelist.contains(type)) return null;

  // 白名单与校验器一一对应：新增组件类型必须同时补校验器，
  // 否则按「未知类型」拒收（防御式——不放行未经校验的 spec）
  final ok = switch (type) {
    'diff' => _validateDiff(raw),
    'quiz' => _validateQuiz(raw),
    'stat' => _validateStat(raw),
    'progress' => _validateProgress(raw),
    'timeline' => _validateTimeline(raw),
    _ => false,
  };
  if (!ok) return null;

  return GenUiComponent(type: type, data: Map<String, dynamic>.from(raw));
}

/// diff：必须含 before / after（字符串）
bool _validateDiff(Map<String, dynamic> raw) =>
    raw['before'] is String && raw['after'] is String;

/// quiz：必须含 items 数组，每项含 q + options(≥2) + answer(int)
bool _validateQuiz(Map<String, dynamic> raw) {
  final items = raw['items'];
  if (items is! List || items.isEmpty) return false;
  for (final it in items) {
    if (it is! Map) return false;
    final m = Map<String, dynamic>.from(it);
    if (m['q'] is! String) return false;
    if (m['options'] is! List || (m['options'] as List).length < 2) {
      return false;
    }
    if (m['answer'] is! int) return false;
  }
  return true;
}

/// stat：必须含 items 数组，每项含 label（字符串）+ value（num）+ max（num）
bool _validateStat(Map<String, dynamic> raw) {
  final items = raw['items'];
  if (items is! List || items.isEmpty) return false;
  for (final it in items) {
    if (it is! Map) return false;
    final m = Map<String, dynamic>.from(it);
    if (m['label'] is! String) return false;
    if (m['value'] is! num) return false;
    if (m['max'] is! num) return false;
  }
  return true;
}

/// progress：必须含 steps 数组，每项含 label（字符串）+ status（字符串）
bool _validateProgress(Map<String, dynamic> raw) {
  final steps = raw['steps'];
  if (steps is! List || steps.isEmpty) return false;
  for (final it in steps) {
    if (it is! Map) return false;
    final m = Map<String, dynamic>.from(it);
    if (m['label'] is! String) return false;
    if (m['status'] is! String) return false;
  }
  return true;
}

/// timeline：必须含 events 数组，每项含 date（字符串）+ title（字符串）
bool _validateTimeline(Map<String, dynamic> raw) {
  final events = raw['events'];
  if (events is! List || events.isEmpty) return false;
  for (final it in events) {
    if (it is! Map) return false;
    final m = Map<String, dynamic>.from(it);
    if (m['date'] is! String) return false;
    if (m['title'] is! String) return false;
  }
  return true;
}
