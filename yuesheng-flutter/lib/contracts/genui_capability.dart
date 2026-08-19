// ─────────────────────────────────────────────────────────────
// 能力契约层 — GenUI 组件能力接口
//
// 架构评审（2026-08-18）选项 A：能力契约层骨架。
// 纯接口定义，不改任何现有实现。
//
// 当前实现映射：
//   parseBlock      → lib/services/genui_parser.dart parseGenuiBlock
//   validateComponent → lib/services/genui_validator.dart validateGenuiComponent
//   whitelist       → lib/services/genui_validator.dart kGenuiWhitelist
//
// ADR: docs/ADR-capability-contracts.md
// ─────────────────────────────────────────────────────────────

import '../services/genui_parser.dart';

/// GenUI 组件能力契约
///
/// 覆盖「AI 回复 → [YS_GENUI] 块解析 → 组件校验 → 白名单过滤」链路。
/// UI 层经此契约获取合法组件列表，不直接依赖 parser/validator 内部。
abstract class GenUiCapability {
  /// 组件类型白名单（diff/quiz/stat/progress/timeline）。
  Set<String> get componentWhitelist;

  /// 从 AI 完整回复中提取所有 [YS_GENUI] 块并解析为组件列表。
  /// 无块时返回 null（区分「无组件」与「有块但全部非法」）。
  List<GenUiComponent>? parseGenuiBlock(String rawText);

  /// 校验单个组件 spec，合法则返回组件，否则返回 null（坏节点丢弃）。
  GenUiComponent? validateGenuiComponent(Map<String, dynamic> raw);
}
