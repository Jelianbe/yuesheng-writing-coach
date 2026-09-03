# ADR-C70：解三个循环依赖（R-020 零容忍）

- 日期：2026-09-03
- 状态：已裁决，待实施
- 触发：修复「门禁 3 长期假绿」后，扫描器首次真正工作，暴露 3 个存量环
- 涉及规则：R-020（循环依赖零容忍）、R-010（最小化范围）、R-019（行数硬上限）
- 是否核心模块：**C1 / C3 是**（Skill 注入链路 / provider 装配），故需本 ADR

---

## 1 背景

`scripts/check_circular.py` 此前有三层缺陷（路径不可解析 + 失败开放 +
裸相对导入不进图），导致门禁 3 **从未真正扫描过任何文件**。修复后首次运行
即报出 3 个循环依赖。

Dart 语言**允许**循环 import，所以这 3 个环从未引发编译或运行错误——
这是它们能长期存在的原因，也是必须靠静态门禁才能发现的原因。

三个环此前已登记进 `tool/circular_baseline.json` 走止血模式（只卡新增）。
本 ADR 裁决如何把它们清零。

---

## 2 事实（耦合内容，精确到行）

### C1 `syndrome_registry` ↔ `syndrome_skill_levels`

| 方向 | 位置 | 依赖的符号 |
|---|---|---|
| registry → skill_levels | `syndrome_registry.dart:11` | **仅 `SkillLevel`**（enum） |
| skill_levels → registry | `syndrome_skill_levels.dart:12` | `kSyndromeSkillLevelsDerived`（派生映射数据） |

- `SkillLevel` 定义于 `syndrome_skill_levels.dart:16-27`。
- registry 中 `SkillLevel` 的全部出现位置：`:83`（`SyndromeEntry.level` 字段类型）、
  `:185`（`kSyndromeSkillLevelsDerived` 返回类型）、`:217` 起（枚举值 `SkillLevel.l1` 等）。
  **没有使用 skill_levels 的任何函数或数据。**
- skill_levels 中来自 registry 的是 `:42` `kSyndromeSkillLevels => kSyndromeSkillLevelsDerived`。
- 调用方（4 处 lib + 3 处 test）：`chat_service.dart:82`（用 `InterventionLevel`）、
  `focus_resolver.dart:13`（用 `SkillLevel`）、`syndrome_registry.dart:11`、
  `test/services/{focus_resolver_coverage,syndrome_registry,syndrome_skill_levels}_test.dart`。

### C2 `genui_parser` ↔ `genui_validator`

| 方向 | 位置 | 依赖的符号 |
|---|---|---|
| parser → validator | `genui_parser.dart:16` | `validateGenuiComponent`（真实依赖） |
| validator → parser | `genui_validator.dart:10` | **无**（冗余 import） |

- `GenUiComponent` 定义于 `lib/contracts/genui_capability.dart:19`，
  而 `genui_validator.dart:9` **已经 import 了该 contracts**。
- validator 全文（80 行）使用的外部符号只有 `GenUiComponent`（contracts），
  未使用 parser 的任何符号。**该 import 是冗余的。**

### C3 `work_import_providers` ↔ `capability_providers`

| 方向 | 位置 | 依赖的符号 |
|---|---|---|
| work_import → capability | `work_import_providers.dart:21,31` | `referenceCapabilityProvider` |
| capability → work_import | `capability_providers.dart:75` | `mentionParserProvider` |

- `mentionParserProvider` 定义于 `work_import_providers.dart:26`，
  其构造需要 `referenceCapabilityProvider`（capability 层产物）。
- `mentionCapabilityProvider`（`capability_providers.dart:74`）是纯转发：
  `(ref) => ref.watch(mentionParserProvider)`，**无外部调用方**。
- `mentionParserProvider` 的消费方：`chat_teaching.dart:207`。
  该**文件是 `chat_page.dart` 的 part**（`part of 'chat_page.dart';`），
  而 `chat_page.dart` 同时 import 了 `work_import_providers` 与 `capability_providers`。
- `test/widgets/bookshelf_page_test.dart:73` 只 override `workImportServiceProvider`。

---

## 3 方案与裁决

### C2：删除冗余 import（非重构，零风险）

删掉 `genui_validator.dart:10` 的 `import 'genui_parser.dart';`。

**这不是重构**——依赖本就不存在，只是声明没删干净。与 X-023 批次清理
`unnecessary_import` 属同类操作，不涉及任何调用关系变化。

### C1：抽 `SkillLevel` 到独立类型文件 + `export` 透传（**裁决采纳**）

1. 新建 `lib/services/syndrome_skill_types.dart`，仅放 `SkillLevel` enum；
2. `syndrome_skill_levels.dart` 改为 `export 'syndrome_skill_types.dart';`
   ——**保留全部对外 API 不变**，4 处 lib + 3 处 test 的 import 一行不用改；
3. `syndrome_registry.dart:11` 的 import 改指向 `syndrome_skill_types.dart`。

依赖方向变为：`registry → types`、`skill_levels → registry`，单向无环。

**被否决的方案：**

- **B：把 `kSyndromeSkillLevelsDerived` 抽到第三个文件。**
  该映射是「症候条目 → 技能层级」，与 `kSyndromeRegistry` 的条目**同生共死**——
  b9 真源化的设计意图正是「由注册表派生、不再手写」。拆开等于把派生关系
  切断，退回双写维护，与 ADR 记录的设计方向相反。
- **C：合并两个文件。**
  registry 831 + skill_levels 150 ≈ 981 行，直接违反 R-019；且 X-025-ARCH
  已明确反对用合并/搬运处理结构问题（该批次回退了 13 个伪拆分 commit）。
- **D：把 `InterventionLevel` 也一起抽走。**
  语义上两个 enum 同属教学层级，一起抽确实更整齐；但 registry 只需要
  `SkillLevel`，按 R-010 最小化范围，本次只动必须的这一个。
  `InterventionLevel` 暂留原处，在新文件注释中说明。

### C3：把 `mentionParserProvider` 搬进 `capability_providers.dart`（**裁决采纳**）

1. `mentionParserProvider` 定义整体迁入 `capability_providers.dart`
   （放在 `referenceCapabilityProvider` 之后、`mentionCapabilityProvider` 之前）；
2. `capability_providers.dart` 删除 `import 'work_import_providers.dart';`，
   补入 `mention_parser.dart` / `manuscript_repository.dart` / `chapter_repository.dart`；
3. `work_import_providers.dart` 删除 `mentionParserProvider` 及其独占的
   `mention_parser.dart` import。

依赖方向变为：`work_import → capability`，单向无环。

**为什么方向是这样（而不是把 capability 侧的引用搬走）：**
`mentionParserProvider` 的构造需要 `referenceCapabilityProvider`，
说明它在依赖层次上**位于 capability 装配之下**；而 `capability_providers.dart`
的文件职责就是「六大能力契约的 Riverpod 接入点」，mention 正是其中之一。
把 provider 搬到它依赖方所在的文件，是顺着依赖箭头走，不是逆着走。

**被否决的方案：**

- **B：在 capability_providers 里重新构造一个 `MentionParser`。**
  会产生第二个实例。`capability_providers.dart:15-18` 的注释明确写着
  「复用既有 mentionParserProvider，避免重复实例化」，本方案与之冲突。
- **C：删掉 `mentionCapabilityProvider`。**
  grep 显示它当前无外部调用方，删掉确实能解开环。但它是契约层的对外
  能力集成员，删除会改变契约层的语义边界；按 R-010 保守原则
  「不确定价值的内容保留不删」，不采用。

---

## 4 零行为变更的判据

三个改动都必须是**纯粹的依赖图调整**，不得改变任何一行可执行语义：

| # | 判据 | 怎么验 |
|---|---|---|
| 1 | 无 import 增减引起的符号解析变化 | `flutter analyze lib` → No issues found |
| 2 | C1 的 `SkillLevel` 语义完全一致 | 枚举成员、value、label 逐一比对；`export` 保证外部可达性不变 |
| 3 | C3 的 provider 构造参数不变 | 搬迁前后 `MentionParser(ManuscriptRepository(db), ChapterRepository(db), ref.read(referenceCapabilityProvider))` 完全一致 |
| 4 | **症候 prompt 零漂移** | `syndrome_registry` 内容会进 L3（见 ADR-C69），改其 import 后跑锚点测试必须**零漂移**（V4.9） |
| 5 | 受影响测试全绿 | genui / syndrome_registry / syndrome_skill_levels / bookshelf_page / chat_page 家族 |
| 6 | 环数归零 | `check_circular.py`（不带基线）→ 0 环 |

### 关于判据 4 的特别说明

`kSyndromeRegistry` 经 `progressive_diagnosis.dart` 派生出分块 prompt 的
症候清单（ADR-C69 刚把该清单改为由注册表派生）。本 ADR 只改 import、
不改任何常量内容，**预期锚点零漂移**。若出现漂移，说明改动超出了预期
范围，必须停下来查，不能顺手重生成基线了事。

---

## 5 验证计划（实施时逐条执行）

1. 每个环改完立刻 `dart format` + `flutter analyze lib`；
2. 三环全部改完：
   - 抽测受影响测试文件（先 `ls` 确认真实文件名，V4.6）；
   - `flutter test` 全量；
   - 锚点测试（**不**带 `UPDATE_SNAPSHOTS`，应为绿）；
   - `check_circular.py .`（不带基线）→ 期望 0 环；
3. 基线转全量：环清零后 `tool/circular_baseline.json` 重生成应为空数组，
   并把 `gate.sh` 门禁 3 的 `--baseline` 去掉，转**全量卡口**
   （这是 V4.14 设定的终点：存量清偿完毕就不再需要豁免）；
4. 变异验证：临时造一个新环（按项目真实写法，裸相对导入）→ 全量卡口
   必须报出且退出码非 0，验证完删除（V4.10 / V4.15）；
5. 跑完整六道门禁。

---

## 6 风险与回退

| 风险 | 评估 | 处置 |
|---|---|---|
| `export` 让 `SkillLevel` 有两条可达路径 | 低：对使用者无差别，analyzer 不会因此报 `unnecessary_import` | 若 analyze 报冗余 import，改用显式 import 各自引用 types |
| provider 搬家改变实例生命周期 | 低：Riverpod 懒加载，provider 定义在哪个文件不影响实例标识 | 若 chat 相关测试出现实例不一致，回退 C3 并改走「新建 `mention_providers.dart` + 同时搬走 `mentionCapabilityProvider`」 |
| C1 触碰核心真源 `syndrome_registry` | 中：831 行、进 L3 prompt | 只改 import 一行，不动任何常量；靠判据 4（锚点零漂移）兜底 |
| 环清零后门禁转全量可能暴露新问题 | 低：全量模式即「任何环都拦」 | 若出现新环，按本 ADR 同样的流程处理 |

**回退方式**：三个改动各自独立，任一出问题 `git revert` 对应 commit 即可；
`tool/circular_baseline.json` 保留在库中，需要时可按格式重新登记豁免。
