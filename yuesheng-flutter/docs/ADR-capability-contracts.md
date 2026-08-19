# ADR：能力契约层骨架（Capability Contracts）

- **状态**：Accepted（选项 A 已落地；选项 B 已首落 N+1 样板：ReferenceCapability + MentionCapability 依赖倒置）
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
| `ReferenceCapability` | `lib/contracts/reference_capability.dart` | 会话引用CRUD + 主引用 + 选段锚点 | reference_repository（`ReferenceRepository implements`） |
| `MentionCapability` | `lib/contracts/mention_capability.dart` | @提及文本 → 标题反查 refId → 结构化结果 | mention_parser（`MentionParser implements`） |
| `CapabilityContractRegistry` | `lib/contracts/capability_registry.dart` | 接口类型注册点（现 6 个能力） | — |

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

## 选项 B 首落：N+1 样板（2026-08-19）

按路线图「按顺序、先打样板」推进选项 B。挑选 N+1（引用域，历史上 `A-3 遗留 N+1 消除` 对应的主引用反查批量查询）作为第一个 `implements` 样板，验证依赖倒置在门禁 3（循环依赖）下的可行性，并确立后续 4 个能力可照抄的模板。

### 做法

1. **真正的依赖倒置（契约层自持 DTO）**：把 `ReferencedItem`、`ParseResult`、`ParsedMention` 从实现文件上移至各自契约文件，契约层不再 `import` 任何实现，从而打破「契约 ↔ 实现」的 import 环。实现文件通过 `re-export` 维持旧有「从实现文件导入 DTO」的调用方可见性，零行为变更、零调用方改动。
2. **`ReferenceRepository implements ReferenceCapability`**：新增 `listReferences`（别名 → `listReferencesOfSession`）覆盖契约方法；5 个引用方法加 `@override`。构造签名不变（`ReferenceRepository(db)`），所有构造点无需改。
3. **`parseMentions` 拆为独立 `MentionCapability`**：原 `ReferenceCapability.parseMentions` 的实现 `MentionParser` 反向依赖 `ReferenceRepository`（取附属文件），若并入 `ReferenceCapability` 会让契约层与实现成环（违反门禁 3）。故独立为 `MentionCapability`，`MentionParser implements MentionCapability`。构造签名不变（`MentionParser(ms, ch, ref)`）。
4. **`CapabilityContractRegistry`** 新增 `MentionCapability`（现 6 个能力类型），注释更新为「选项 B 已首落」。
5. **契约测试升级**：删除合成 `_ContractAdapter` shim，改为编译期子类型断言（`ReferenceRepository` / `MentionParser` 必须 `implements` 对应契约，否则测试文件无法 `dart analyze`），保留注册表断言。

### 为什么这是正确样板

- 实现依赖契约、契约不依赖实现（DIP 成立），通过门禁 3 的 import 图 DFS 检测。
- capability 子图是干净 DAG。门禁 3 当前仍报 `router/app_router ↔ widgets/*` 的 6 个环，但那是历史存量（相对 import 双向引用），与本次改动无关；本批不修（超出最小范围），列为后续独立项。
- 其余 4 个能力（diagnosis / teaching / material / genui）沿用同一模板：DTO 上移 + `implements` + `re-export`，即可逐个落地。

### 验证（本批）

- `dart analyze lib`：0 error（仅 1 条历史存量 `reference_bar` 的 unnecessary_this info）
- `flutter test`：1879 passed / 14 skipped / 0 failed（基线 1877，净增 2：新增 mention 契约测试 3、reference 契约精简 1）
- 门禁 3：capability 子图无环；`router↔widget` 为历史存量环，非本次引入
- 门禁 4：无疑似硬编码密钥

## 约束

- 后续选项 B（依赖倒置重构）时，各实现类 `implements` 对应接口，注册到 provider，UI 层改为 `ref.read(xxxCapabilityProvider)` 消费
- 新增能力只需实现接口并注册，UI 经契约消费，无需改动（类比现有 `message_card_dispatcher` 分派模式）
- 跨端共享只共享契约/协议（`[YS_*]` 块、JSON schema），不共享实现

## 验证

- `dart analyze lib`：0 error（仅历史存量 info；详见「选项 B 首落」节）
- `flutter test`：1879 passed / 14 skipped / 0 failed
- 四道门禁：①②④ 通过；门禁 3 的 `router↔widget` 环为历史存量，非本 ADR 引入（见「选项 B 首落」节）
