// ─────────────────────────────────────────────────────────────
// 能力契约层 — GenUI 组件能力接口
//
// 架构评审（2026-08-18）选项 A：能力契约层骨架。
// 选项 B（依赖倒置）：GenUiCapability 自持 DTO（GenUiComponent），
// 不 import 任何实现文件，避免契约↔实现的循环依赖（门禁 3）。
//
// 实现映射（Dependency Inversion）：
//   class GenUiParser (lib/services/genui_parser.dart) implements GenUiCapability
//   委托到现有纯函数 parseGenuiBlock / validateGenuiComponent / kGenuiWhitelist。
//
// ADR: docs/ADR-capability-contracts.md
// ─────────────────────────────────────────────────────────────

/// 一个 GenUI 组件（已通过白名单校验）
///
/// DTO 上移至契约层（选项 B）：原定义于 lib/services/genui_parser.dart，
/// 由 genui_parser.dart re-export 以维持既有调用方可见性。
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
