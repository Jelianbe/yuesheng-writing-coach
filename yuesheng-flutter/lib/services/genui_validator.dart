// ─────────────────────────────────────────────────────────────
// genui_validator — GenUI 组件白名单 + spec guard（B-1 GenUI v1）
//
// 仿 dsh-genui 的「坏节点丢弃/节点上限/无 eval」原则：
// 对模型输出的 UI spec 永远白名单 + 必需字段校验，坏节点静默丢弃，
// 模型输出错格式不崩 UI，只降级。
// ─────────────────────────────────────────────────────────────

import 'genui_parser.dart';

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
/// - stat/progress/timeline：宽松接受（占位卡片处理缺失字段）
GenUiComponent? validateGenuiComponent(Map<String, dynamic> raw) {
  final type = raw['type'];
  if (type is! String) return null;
  if (!kGenuiWhitelist.contains(type)) return null;

  switch (type) {
    case 'diff':
      if (raw['before'] is! String || raw['after'] is! String) return null;
    case 'quiz':
      final items = raw['items'];
      if (items is! List || items.isEmpty) return null;
      for (final it in items) {
        if (it is! Map) return null;
        final m = Map<String, dynamic>.from(it);
        if (m['q'] is! String) return null;
        if (m['options'] is! List || (m['options'] as List).length < 2) {
          return null;
        }
        if (m['answer'] is! int) return null;
      }
    case 'stat':
    case 'progress':
    case 'timeline':
      // 占位卡片处理，宽松接受（title/items 缺失时占位渲染）
      break;
  }
  return GenUiComponent(type: type, data: Map<String, dynamic>.from(raw));
}
