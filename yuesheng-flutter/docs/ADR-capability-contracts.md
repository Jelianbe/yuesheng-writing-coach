# ADR：能力契约层骨架（Capability Contracts）

- **状态**：Accepted
- **日期**：2026-08-19
- **关联**：`docs/architecture-review-2026-08-18.md` §5 选项 A

## 背景

架构评审（2026-08-18）识别出 C5 耦合点：诊断/教学/素材/GenUI/引用五大能力仍是「隐式能力」，无显式接口契约。UI 层直接依赖具体实现类，替换数据源或扩展新能力时连带改动面大。

评审给出三个选项：
- A（推荐）：产出能力契约层骨架（interface + 契约测试），纯只读/新建
- B：样板依赖倒置重构
- C：文档↔代码映射表

本批执行选项 A。

## 决策

### 新增 5 个能力接口 + 1 个注册表

| 接口 | 文件 | 覆盖链路 | 当前实现映射 |
|:---|:---|:---|:---|
| `DiagnosisCapability` | `lib/contracts/diagnosis_capability.dart` | AI回复→诊断解析→校验→训练结果 | diagnosis_parser / diagnosis_validator / chat_training_parser |
| `TeachingCapability` | `lib/contracts/teaching_capability.dart` | 教学语境→skill三级加载→system prompt | skill_dispatcher / skill_layers |
| `MaterialCapability` | `lib/contracts/material_capability.dart` | 素材→token预算截断→上下文拼装 + 段落锚点 | chat_context_builder |
| `GenUiCapability` | `lib/contracts/genui_capability.dart` | AI回复→[YS_GENUI]块→组件校验→白名单 | genui_parser / genui_validator |
| `ReferenceCapability` | `lib/contracts/reference_capability.dart` | 会话引用CRUD + 主引用 + 选段 + @提及 | reference_repository / mention_parser |
| `CapabilityContractRegistry` | `lib/contracts/capability_registry.dart` | 接口类型注册点 | — |

### 设计原则

1. **纯新建**：不修改任何现有实现代码，零行为变更
2. **复用现有类型**：接口方法签名使用现有的 `ParseResult`、`FullValidationResult`、`SystemPromptResult`、`ParagraphAnchor`、`GenUiComponent`、`ReferencedItem`、`ParseResult`(MentionParser) 等类型，不造新语义（R-021）
3. **契约测试验证可满足性**：每个接口有一个 `_ContractAdapter implements XxxCapability` 适配器类，其存在即证明接口签名与现有实现兼容（编译期保证）
4. **不过度抽象**（R-010）：当前不抽 provider、不改 widget 调用链，只确保接口编译通过 + 契约测试验证

### 契约测试模式

每个接口的测试包含：
- 接口在注册表中注册（`contractTypes` 包含该类型）
- 现有实现的返回类型与接口签名一致（运行时 `isA<T>()` 断言）
- `implements` 编译验证（适配器类定义即证明签名匹配，编译失败 = 接口与实现不兼容）

## 约束

- 后续选项 B（依赖倒置重构）时，各实现类 `implements` 对应接口，注册到 provider，UI 层改为 `ref.read(xxxCapabilityProvider)` 消费
- 新增能力只需实现接口并注册，UI 经契约消费，无需改动（类比现有 `message_card_dispatcher` 分派模式）
- 跨端共享只共享契约/协议（`[YS_*]` 块、JSON schema），不共享实现

## 验证

- `dart analyze lib test`：0 issue
- `flutter test`：1877 passed / 14 skipped / 0 failed（基线 1852 + 契约测试 25）
- 四道门禁全绿（gate.sh）
