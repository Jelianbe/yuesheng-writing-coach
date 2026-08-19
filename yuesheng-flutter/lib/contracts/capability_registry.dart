// ─────────────────────────────────────────────────────────────
// 能力契约层 — 能力注册表
//
// 架构评审（2026-08-18）选项 A：能力契约层骨架。
//
// 当前阶段：仅定义接口与注册表骨架，不做实现绑定。
// 后续选项 B（依赖倒置重构）时，各实现类 `implements` 对应能力接口，
// 注册到此处，UI 层改为 `ref.read(diagnosisCapabilityProvider)` 消费。
//
// 纪律（R-010 最小范围）：当前不抽 provider、不改 widget 调用链，
// 只确保接口编译通过 + 契约测试验证可满足性。
//
// ADR: docs/ADR-capability-contracts.md
// ─────────────────────────────────────────────────────────────

import 'diagnosis_capability.dart';
import 'teaching_capability.dart';
import 'material_capability.dart';
import 'genui_capability.dart';
import 'reference_capability.dart';

/// 五大能力接口汇总（供后续注册表 provider 使用）
///
/// 当前阶段不创建实例——仅作为类型注册点。
/// 选项 B 落地时，各实现类 implements 对应接口并注册到此。
final class CapabilityContractRegistry {
  CapabilityContractRegistry._();

  /// 能力接口类型列表（用于契约测试遍历验证）
  static const List<Type> contractTypes = [
    DiagnosisCapability,
    TeachingCapability,
    MaterialCapability,
    GenUiCapability,
    ReferenceCapability,
  ];
}
