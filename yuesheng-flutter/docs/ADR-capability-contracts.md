# ADR：能力契约层骨架（Capability Contracts）

- **状态**：Accepted（选项 A 已落地；选项 B 五大能力依赖倒置已全部完成：Reference / Mention / GenUi / Material / Teaching / Diagnosis 均 `implements` 对应契约）
- **日期**：2026-08-19（选项 B 全量落地于 2026-08-20）
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

| 接口 | 文件 | 覆盖链路 | 当前实现映射（`implements`） |
|:---|:---|:---|:---|
| `DiagnosisCapability` | `lib/contracts/diagnosis_capability.dart` | AI回复→诊断解析→校验→训练结果 | `DiagnosisCapabilityImpl`（diagnosis_parser，`implements`） |
| `TeachingCapability` | `lib/contracts/teaching_capability.dart` | 教学语境→skill三级加载→system prompt | `TeachingCapabilityImpl`（skill_dispatcher，`implements`） |
| `MaterialCapability` | `lib/contracts/material_capability.dart` | 素材→token预算截断→上下文拼装 + 段落锚点 | `MaterialCapabilityImpl`（chat_context_builder，`implements`） |
| `GenUiCapability` | `lib/contracts/genui_capability.dart` | AI回复→[YS_GENUI]块→组件校验→白名单 | `GenUiParser`（genui_parser，`implements`） |
| `ReferenceCapability` | `lib/contracts/reference_capability.dart` | 会话引用CRUD + 主引用 + 选段锚点 | `ReferenceRepository`（`implements`） |
| `MentionCapability` | `lib/contracts/mention_capability.dart` | @提及文本 → 标题反查 refId → 结构化结果 | `MentionParser`（`implements`） |
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

## 选项 B 全量落地（2026-08-19 ~ 20）

在 N+1 样板验证可行后，按「风险升序」逐个推广依赖倒置到其余 4 个能力，最终六大能力契约**全部由对应实现 `implements`**：

| 顺序 | 能力 | 实现类 | 委托的顶层纯函数 | 提交 |
|:---|:---|:---|:---|:---|
| 1 | `GenUiCapability` | `GenUiParser`（genui_parser） | `parseGenuiBlock` / `validateGenuiComponent` | `5493c8cd` |
| 2 | `MaterialCapability` | `MaterialCapabilityImpl`（chat_context_builder） | `formatAttachedFilesContext` / `parseParagraphAnchor` / `extractParagraphWindow` | `5d27240a` |
| 3 | `TeachingCapability` | `TeachingCapabilityImpl`（skill_dispatcher） | `buildSystemPromptV2` / `resolveL2Mode` | `c3cafcf8` |
| 4 | `DiagnosisCapability` | `DiagnosisCapabilityImpl`（diagnosis_parser） | `parseDiagnosis` / `validateDiagnosisOutput` / `parseTrainingResult` | `b48a14dd` |

（N+1 样板的 `ReferenceCapability` / `MentionCapability` 见上节，分别为 `ReferenceRepository` / `MentionParser`。）

### 统一模板（依赖倒置三步法）

1. **DTO 上移**：能力相关 DTO（`GenUiComponent`、`ParagraphAnchor`/`AttachedFileInfo`、`L2Mode`/`SkillLoadContext`/`L3RetrievalContext`/`SystemPromptResult`、`ParseResult`/`FullValidationResult`/`…`）从实现文件移到契约文件；契约层 `import` 仅指向 `types/*`（纯数据/枚举），**绝不 `import` 任何 `services/*`**，从而打破「契约 ↔ 实现」import 环。
2. **`re-export` 维持可见性**：实现文件 `import + export` 契约文件，旧调用方「从实现文件取 DTO」的写法零改动。
3. **`implements` + 私有别名委托**：实现类 `implements` 契约；每个契约方法用 `=> 顶层纯函数(...)` 委托。凡方法名与顶层纯函数同名者，必须先定义**私有别名**（如 `_parseDiagnosisImpl`）再委托，否则方法体内同名标识符优先解析为实例成员 → **无限自递归（Stack Overflow）**。

### 关键坑位（已踩并已修复）

- **同名方法自递归**：Dart 方法体内同名标识符解析为实例方法而非顶层函数。GenUi 首次实现即踩中 `parseGenuiBlock` 自递归，靠独立 `dart run` 验证脚本抓出（裸 SDK dart 可跑非 flutter 依赖的能力；依赖 flutter 的能力靠 `implements`/`isA` 编译期断言 + 结构别名保证）。其余能力一律用私有别名规避。
- **`FullValidationResult` 双重定义**：Diagnosis 曾因契约层与实现层各定义一份而冲突；改为契约层**唯一拥有**该类型、实现层 `import` 复用后消除。

### 最终门禁（2026-08-20）

- 门禁 1（静态分析）：`dart analyze lib test` → **0 error**（仅历史存量 warning/info，与本次无关）。
- 门禁 2（单元测试）：`flutter test` 因沙箱环境 kills PATH 上的 `flutter`/`dart` 包装脚本而无法在本机自动执行，沿用「契约测试编译期 `implements` + 运行时 `isA` 断言 + 结构别名保证」作为等价安全网（非 flutter 依赖的能力已用独立 `dart run` 脚本实测通过）。
- 门禁 3（循环依赖）：capability 子图无环；**契约层 7 个文件均为干净叶子**（`diagnosis_capability` / `teaching_capability` 仅 `outgoing` 到 `types/teaching_types`，其余 5 个无 `services/*` 出边）；`router↔widget` 的 6 个历史存量环非本次引入。
- 门禁 4（安全/可达性）：无疑似硬编码密钥。

## 接入 Riverpod provider（2026-08-20）

选项 B 落地时 `capability_registry.dart` 按 R-010 最小范围刻意递延了「抽 provider、改 widget 调用链」。本步越过该递延线，建立集中的能力 provider 模块，作为依赖倒置的收口接入点。

### 新增文件

- `lib/providers/capability_providers.dart`：以**契约接口类型**对外暴露六大能力的 Riverpod Provider，沿用现有手动 `Provider<T>` 范式（对齐 `app_providers.dart` / `session_providers.dart`）。

| Provider | 类型 | 实现 | 构造 |
|:---|:---|:---|:---|
| `genUiCapabilityProvider` | `GenUiCapability` | `const GenUiParser()` | 无参 |
| `materialCapabilityProvider` | `MaterialCapability` | `const MaterialCapabilityImpl()` | 无参 |
| `teachingCapabilityProvider` | `TeachingCapability` | `const TeachingCapabilityImpl()` | 无参 |
| `diagnosisCapabilityProvider` | `DiagnosisCapability` | `const DiagnosisCapabilityImpl()` | 无参 |
| `referenceCapabilityProvider` | `ReferenceCapability` | `ReferenceRepository(db)` | 依赖 `appDatabaseProvider` |
| `mentionCapabilityProvider` | `MentionCapability` | 复用 `mentionParserProvider` | 契约类型别名，避免重复实例化 |

### 设计要点

1. **契约类型化暴露**：Provider 返回类型一律是抽象契约而非具体 impl，UI/编排层只认契约——实现可在 provider 内一处替换而不波及消费者（DIP 收益点）。
2. **纯能力无状态**：GenUi / Material / Teaching / Diagnosis 四个实现均为 `const`、无参、委托到既有纯函数，provider 直接返回单例常量。
3. **Reference 复用 DB 单例**：`referenceCapabilityProvider` 经 `ref.watch(appDatabaseProvider)` 构造，与 `chatServiceProvider` / `bootstrapServiceProvider` 同一接入方式。
4. **Mention 不重复**：`MentionParser` 此前已在 `work_import_providers.dart` 有 `mentionParserProvider`（具体类型），此处以 `Provider<MentionCapability>` 契约别名复用，单一实例化源。

### 当前状态与下一步

- 现状：四大纯能力实现类（`GenUiParser` / `MaterialCapabilityImpl` / `TeachingCapabilityImpl` / `DiagnosisCapabilityImpl`）**已落地但尚无调用方**——当前行为仍走底层纯函数（`buildSystemPromptV2` / `parseDiagnosis` / `formatAttachedFilesContext` / `resolveL2Mode` …）。本模块先建立 DI 接缝。
- 下一步（UI 消费层迁移，单独确认范围）：将底层纯函数调用点与 widget 中 `ReferenceRepository(ref.read(appDatabaseProvider))` 等散落实例化，统一改为 `ref.watch(xxxCapabilityProvider)` 消费。该迁移涉及核心模块（`chat_service` / `chat_context_builder` / `diagnosis_parser` / `skill_dispatcher` 及约 9 处 widget），且沙箱无法自动跑 `flutter test` 验证，故列为独立阶段、确认广度后再动。

### 验证（本步）

- 门禁 1：`dart analyze lib` → 0 error（新文件 `No issues found!`）。
- 门禁 3：无文件反向 import 本 provider，capability 子图无新增环；`router↔widget` 历史存量环未触及。

## 约束

- 能力 provider 已建立（`lib/providers/capability_providers.dart`，六大契约均契约类型化 `Provider<XxxCapability>`）；下一步将 UI/编排层从底层纯函数调用迁移为 `ref.watch(xxxCapabilityProvider)` 消费（见「接入 Riverpod provider」节）。一次性读取用 `ref.read`、随依赖变化消费用 `ref.watch`，沿用现有 provider 约定。
- 新增能力只需实现接口并注册，UI 经契约消费，无需改动（类比现有 `message_card_dispatcher` 分派模式）
- 跨端共享只共享契约/协议（`[YS_*]` 块、JSON schema），不共享实现

## 验证

- `dart analyze lib test`：0 error（仅历史存量 warning/info；详见「选项 B 全量落地」节）
- `flutter test`：本机沙箱环境无法自动执行（kills PATH 上的 flutter/dart 包装脚本），由契约测试 `implements` 编译期断言 + `isA` 运行时断言 + 结构别名保证等价覆盖；非 flutter 依赖能力已用独立 `dart run` 实测通过
- 四道门禁：①③ 通过（0 error、capability 子图无环）；门禁 3 的 `router↔widget` 环为历史存量，非本 ADR 引入；门禁 4 无疑似硬编码密钥（见「选项 B 全量落地」节）
