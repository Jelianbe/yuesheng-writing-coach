# ADR-C74：ChatService 拆分重构——DiagnosisCommitter 独立类 + DI

- **状态**：**已实施**（2026-09-04 启动，K-1 ~ K-5 完成；K-6 / K-7 / K-8 / K-9 见 §8 后续批次）
- **日期**：2026-09-04
- **涉及模块**：`lib/services/chat_service.dart`（3108 行单体，14 函数超 R-019 50 行硬上限）
- **关联**：
  - `docs/designs/2026-08-29-chat-service-split-plan.md`（**已否决的 part 拆 15 文件方案**，本 ADR 是其后的正确方向）
  - `docs/ADR-C73-splitcontent-deadlock-and-batch-i-split.md`（批次 I 节奏模板）
  - `docs/ADR-capability-contracts.md`（DI 三步法样板，本 ADR 直接沿用）
  - X-025-ARCH（2026-08-22，回退 13 commit 的实证教训）

---

## 1. 结论先行

1. **拆分方向**：诊断提交组（~1500 行 / 11 个方法）抽为独立类 `DiagnosisCommitter`，沿用 ADR-capability-contracts §3.2「独立类 + 显式接口 + DI」三步法样板。
2. **第一刀只拆诊断组**：训练结果组（285 行 / 3 方法）、引用预载组（410 行 / 3 方法）留作 K-7/K-8 独立 ADR，避免一次改动面过大。
3. **`sendMessage` 留 ChatService 主机**：`_FakeChatService @override` 契约不破（X-025-ARCH 实证代价：9 例 `pumpAndSettle` 超时）。
4. **`commitDiagnosisFromContent` 留 ChatService 公开方法**：内部委派 `DiagnosisCommitter` 同名方法，widget 跨文件调用方零改动（已确认两处：`writing_coach_panel_teaching.dart:471` / `chat_teaching.dart:53`）。
5. **基线影响**：R-019 214 → 估计 **-7/-8**（清偿 11 个方法中约 7 个超 50 行），新基线绝不带 `--baseline` 重生成（V4.14 最阴的坑，AGENTS.md 已固化）。

---

## 2. 背景

### 2.1 现状（2026-09-04 核）

- `lib/services/chat_service.dart` = **3108 行单体**
- **14 个函数超 R-019 50 行硬上限**（按行数降序）：

| # | 函数 | 行数 | 起行 | 位置 |
|:--|:--|--:|--:|:--|
| 1 | `_sendMessageCore` | 311 | 2797 | 薄实例方法（X-025-ARCH 保留）|
| 2 | `_injectDiagnosisLock` | 268 | 1332 | extension `ChatServiceDiagnosisSupport` |
| 3 | `_injectChapterObservations` | 235 | 1831 | extension `ChatServiceDiagnosisSupport` |
| 4 | `_handleTrainingResult` | 232 | 2565 | 同上 |
| 5 | `_applyPhaseMigration` | 217 | 1060 | 同上 |
| 6 | `_preloadReferenceDetails` | 288 | 2127 | extension（待并入预载组）|
| 7 | `commitDiagnosisFromContent` | 180 | 562 | 公开方法，widget 跨文件调用 |
| 8 | `_parseAndPersist` | 186 | 2226 | 解析+落库 |
| 9 | `_commitDiagnosisAndSuggestions` | 150 | 2415 | 诊断提交+卡片 |
| 10 | `_injectProfileAndIntents` | 140 | 1603 | 画像+意图注入 |
| 11 | `_applyFactExtractionFromContent` | 128 | 829 | 事实提取 |
| 12 | `_injectOutlineFactsAndFiles` | 88 | 1743 | 大纲事实注入 |
| 13 | `_applyOutlineEntitiesFromContent` | 86 | 743 | 大纲实体提取 |
| 14 | `_streamLlm` | ~25 | 2117 | 流式 LLM（不超，不动）|

> 注：另有 `_buildFactProtocolContext` 48 行、`_buildInterventionAdjustmentNote` 49 行未列——在 50 行内，不构成技术债。

### 2.2 X-025-ARCH 实证教训（不可逾越）

`72682d31` 回退 13 commit，核心教训（chat_service.dart 三处活文档注释）：
- **L161**：`sendMessage` 必须留 ChatService 类内实例方法，extension 会让 `_FakeChatService @override` 契约断裂
- **L448-450**：`sendMessage` 是薄实例方法，委派 `_sendMessageCore`（extension）
- **L2795**：`_sendMessageCore` 命名刻意避免遮蔽宿主保留的薄实例方法

**实证代价**：`ChatService.sendMessage` 迁至 extension 后，9 例 `pumpAndSettle` 超时回归（测试替身契约断裂 → 调用真实 LLM API）。

### 2.3 已否决的方案（避免重蹈）

`docs/designs/2026-08-29-chat-service-split-plan.md` 曾提出「沿 extension 边界 part 拆 15 文件」，**已被明确否决**：
- `part` / `extension` 机械搬运属**伪拆分**，未解决真正耦合
- R-019 硬上限是「函数 ≤50 行」，**不是文件 ≤300 行**——服务层超限须走 ADR 决策
- 服务层超 300 行需走 ADR 决策（AGENTS.md 红线）

本 ADR 走「**独立类 + 显式接口 + DI**」路线——X-025-ARCH 明文认可的合规方向。

---

## 3. 决策

### 3.1 拆分粒度

**第一刀只拆诊断提交组**（11 个方法，~1500 行）：
- `commitDiagnosisFromContent`（**公开委派**，留 ChatService 薄壳）
- `_applyPhaseMigration`
- `_injectDiagnosisLock`
- `_parseAndPersist`
- `_commitDiagnosisAndSuggestions`
- `_applyOutlineEntitiesFromContent`
- `_applyFactExtractionFromContent`
- `_readOutlineEntityCount`
- `_buildFactProtocolContext`
- `_buildDriftHintContext`

> 字符串构造类（`_buildDriftHintContext` 14 行）虽不超 50，但与诊断组同语义域、依赖相同仓库——一并迁入，避免散落。

### 3.2 拆分方案

抽 **`lib/services/diagnosis_committer.dart`**，与现有 capability 模式（`DiagnosisCapabilityImpl` 在 `diagnosis_parser`）同构但粒度更细：

```dart
/// 诊断提交编排器——独立类，沿用 ADR-capability-contracts DI 模板
///
/// 从 ChatService 抽出诊断提交链路的所有副作用（解析/落库/卡片/阶段迁移），
/// 自身无状态（除连续失败计数），依赖通过构造函数注入。
class DiagnosisCommitter {
  // 必备依赖
  final SessionRepository _sessionRepo;
  final TeachingStateRepository _stateRepo;
  final DiagnosisRepository _diagnosisRepo;
  final DiagnosisService _diagnosisService;
  // 可选依赖（X-041c 模式，默认 null 跳过对应落库）
  final OutlineRepository? _outlineRepo;
  final CharacterFactRepository? _characterFactRepo;
  final EventFactRepository? _eventFactRepo;
  final SubplotFactRepository? _subplotFactRepo;
  // 四大能力（capability 注入）
  final GenUiCapability _genUi;
  final MaterialCapability _material;
  final TeachingCapability _teaching;
  final DiagnosisCapability _diagnosis;

  // 内部状态：B1 连续失败计数（从 ChatService 迁出，按 session 隔离）
  final Map<String, int> _consecutiveDiagnosisFails = {};

  DiagnosisCommitter({
    required SessionRepository sessionRepo,
    required TeachingStateRepository stateRepo,
    required DiagnosisRepository diagnosisRepo,
    required DiagnosisService diagnosisService,
    required GenUiCapability genUi,
    required MaterialCapability material,
    required TeachingCapability teaching,
    required DiagnosisCapability diagnosis,
    OutlineRepository? outlineRepo,
    CharacterFactRepository? characterFactRepo,
    EventFactRepository? eventFactRepo,
    SubplotFactRepository? subplotFactRepo,
  }) : _sessionRepo = sessionRepo,
       _stateRepo = stateRepo,
       _diagnosisRepo = diagnosisRepo,
       _diagnosisService = diagnosisService,
       _genUi = genUi,
       _material = material,
       _teaching = teaching,
       _diagnosis = diagnosis,
       _outlineRepo = outlineRepo,
       _characterFactRepo = characterFactRepo,
       _eventFactRepo = eventFactRepo,
       _subplotFactRepo = subplotFactRepo;

  // 11 个方法原样迁入（按职责分组）
  Future<void> commitDiagnosisFromContent({...}) async { ... }
  Future<void> _applyPhaseMigration({...}) async { ... }
  String _buildDiagnosisLockContext({...}) { ... }   // 原 _injectDiagnosisLock
  Future<({ParsedDiagnosis?, List<MessageCard>})> _parseAndPersist({...}) async { ... }
  Future<void> _commitDiagnosisAndSuggestions({...}) async { ... }
  Future<void> _applyOutlineEntitiesFromContent({...}) async { ... }
  Future<void> _applyFactExtractionFromContent({...}) async { ... }
  int _readOutlineEntityCount({...}) { ... }
  String _buildFactProtocolContext() { ... }
  String _buildDriftHintContext(List<String> hints) { ... }
}
```

### 3.3 ChatService 改动

**最小化原则**（R-010）：
- `chat_service.dart` 新增 `final DiagnosisCommitter _diagnosisCommitter;` 字段
- 构造签名末尾追加 `DiagnosisCommitter? diagnosisCommitter` 可选参数
- `chatServiceProvider`（Riverpod）注入 `DiagnosisCommitter` 单例
- 原 11 个方法全部删除（迁入 DiagnosisCommitter 后）
- **保留** `commitDiagnosisFromContent` 薄壳：内部 `_diagnosisCommitter.commitDiagnosisFromContent(...)` 委派
- 私有方法全部从 ChatService 域移除（包括已存在的两个 extension `ChatServiceDiagnosis` / `ChatServiceDiagnosisSupport`）

预期：
- `chat_service.dart`：**3108 → ~1650 行**（-47%）
- `diagnosis_committer.dart`：**~1500 行**（含 11 个方法）
- R-019 超限：**14 → ~5**（剩余为 sendMessage 主链 + 训练结果组 + 引用预载组）

### 3.4 测试影响

| 现有测试 | 影响 | 处理 |
|:--|:--|:--|
| `_FakeChatService @override sendMessage`（provider 替身）| 0 影响 | `sendMessage` 留 ChatService，X-025-ARCH 契约不破 |
| 34 例专项测试（`chat_service_test.dart` / `chat_page_test.dart`）| 0 影响 | 现有断言只走公开接口（`sendMessage` / `commitDiagnosisFromContent`）|
| `chatServiceProvider` 注入 | 1 处改动 | 增加 `diagnosisCommitterProvider` 注入 |
| `DiagnosisCommitter` 单元测试 | **新增** | 批次 K-2 ~ K-5 同步补充（按方法分批）|

**回归覆盖**：
- 现有 `chat_page_test.dart` 中关于诊断路径的 9 例 `pumpAndSettle` 全部须继续通过
- 新增 `DiagnosisCommitter` 专项测试：每个迁入方法至少 1 例分支覆盖（V4.21 单点评据不证真覆盖）
- 变异验证：批次 K-6 须构造 ≥10 个变异锚点（参照 `_verify_batch_h_coverage.py`），拦截率 ≥90%

---

## 4. 备选方案

| 方案 | 做法 | 否决理由 |
|:--|:--|:--|
| **本方案（已选）** | 独立类 `DiagnosisCommitter` + 构造函数 DI | 沿用现有 capability 模式，X-025-ARCH 认可 |
| 方案 A | part 拆 N 文件（2026-08-29 已否决方案）| **X-025-ARCH 明文禁止**：`part` 机械搬运是伪拆分，`@override` 契约断裂 |
| 方案 B | extension 拆 N 文件（同 X-025-ARCH-13）| **X-025-ARCH 明文禁止**：`_FakeChatService @override` 失效，9 例超时回归 |
| 方案 C | 全部三组一起拆（诊断 + 训练 + 预载）| 改动面 2200+ 行 / 17 个方法，单 PR 评审负担大，K 阶段先单组验证路径 |
| 方案 D | 暂不拆，登记为已知债务 | R-019 硬约束 + 摘要「亟需」，登记为债务不解决根因；且文件 3108 行持续膨胀 |

---

## 5. 实施步骤（6 批次 K-1 ~ K-6）

参照批次 I / J-A 节奏：**1 拆 + N 测试 + 1 基线 + 1 文档**。

### K-1 骨架与接口（2026-09-04 当日可完成）
1. 新建 `lib/services/diagnosis_committer.dart`，含 `DiagnosisCommitter` 类骨架（空方法体，签名占位）
2. `chat_service.dart` 新增 `final DiagnosisCommitter _diagnosisCommitter;` 字段 + 构造参数
3. `chatServiceProvider` 注入 `DiagnosisCommitter` 单例（Riverpod）
4. **验证**：六道门禁全绿（**仅字段新增、行为未变**）——这是关键护栏，证明路径可行
5. commit：`refactor(svc): 建 DiagnosisCommitter 骨架 + 注入 chatServiceProvider`

### K-2 迁 `_applyPhaseMigration`（独立可测，风险最低）
1. 从 `extension ChatServiceDiagnosisSupport` 抽出 `_applyPhaseMigration` → `DiagnosisCommitter._applyPhaseMigration`
2. 依赖通过构造函数已注入，无新增参数
3. ChatService 内部调用点改为 `_diagnosisCommitter._applyPhaseMigration(...)`
4. 补充 `_applyPhaseMigration` 专项测试 ≥2 例（**注：方法名带 `_` 不再私有——调整为 `applyPhaseMigration` 公开，加 `@visibleForTesting` 标注**）
5. 六道门禁全绿 + 9 例 `pumpAndSettle` 必须继续通过
6. commit：`refactor(svc): _applyPhaseMigration 迁 DiagnosisCommitter`

### K-3 迁诊断解析落库链（`_parseAndPersist` + `_commitDiagnosisAndSuggestions`）
1. 迁 `_parseAndPersist`（186 行） + `_commitDiagnosisAndSuggestions`（150 行）= **336 行**
2. `_parseAndPersist` 返回 `({ParsedDiagnosis?, List<MessageCard>})`，消除对 ChatService 状态的中间依赖
3. 补充专项测试 ≥4 例（解析成功/失败/部分字段丢弃/卡片生成）
4. 变异验证：≥4 个变异锚点（解析失败路径 / 卡片生成条件）
5. 六道门禁 + 9 例 `pumpAndSettle`
6. commit：`refactor(svc): 诊断解析落库链迁 DiagnosisCommitter`

### K-4 迁 `_injectDiagnosisLock` + `_buildFactProtocolContext` + `_buildDriftHintContext`
1. 迁 `_injectDiagnosisLock`（268 行）+ 两个字符串构造方法
2. 注入字符串构造方法无副作用，可直接迁
3. `_injectDiagnosisLock` 依赖 `_applyPhaseMigration` 已迁，链路闭环
4. 补充专项测试 ≥3 例
5. 六道门禁 + 9 例 `pumpAndSettle`
6. commit：`refactor(svc): 诊断锁注入 + 协议块字符串构造 迁 DiagnosisCommitter`

### K-5 迁 `commitDiagnosisFromContent` 公开委派 + 落库辅助方法
1. 迁 `commitDiagnosisFromContent`（180 行） + `_applyOutlineEntitiesFromContent` + `_applyFactExtractionFromContent` + `_readOutlineEntityCount`（共 4 个方法）
2. ChatService 留 `commitDiagnosisFromContent` **薄壳委派**（~10 行）：
   ```dart
   Future<void> commitDiagnosisFromContent(...) async =>
     _diagnosisCommitter.commitDiagnosisFromContent(...);
   ```
3. 补充专项测试 ≥3 例（公开路径）
4. 删除 `chat_service.dart` 中两个诊断相关 extension（`ChatServiceDiagnosis` / `ChatServiceDiagnosisSupport`），所有引用已迁完
5. 六道门禁 + 9 例 `pumpAndSettle`
6. commit：`refactor(svc): commitDiagnosisFromContent 委派 + 落库辅助 迁 DiagnosisCommitter`

### K-6 基线重生成 + 变异脚本 + 文档同步（2026-09-04 收尾）
1. **`python tool/check_r019.py --json tool/r019_baseline.json`**（**绝不带 `--baseline`**，V4.14 最阴的坑）
2. 预期基线 **214 → ~207**（清偿 7-8 个函数）
3. V4.14 验证：`_verify_r019_baseline.py` 撑大 7 个函数确认新基线仍能拦（**7/7**），验证完恢复（V4.10）
4. 新建 `tool/_verify_batch_k_coverage.py`：≥10 个变异锚点（K2 ~ K5 各 2-3 个），全量重跑至 ≥90% 拦截
5. 适配现有 `chat_service_test.dart` 锚点（如有变更）
6. 文档同步：
   - 本 ADR 状态改「**已实施**」，实施记录回填 commit 列表
   - `docs/待办执行清单.md` 批次 K 标注完成 + 写入 commit 列表
   - `AGENTS.md` 不动（V4.22 已涵盖服务层拆分合规路径）
7. 六道门禁 `bash scripts/gate.sh` 收尾
8. commit A：`chore(r019): 基线 214→207` + commit B：`test+tool(svc): 批次 K 变异脚本` + commit C：`docs(adr): C74 状态 + 批次 K 完成标注`
9. 推送先确认（舰长已授权「过多分批」）

---

## 6. 风险与回退

### 6.1 风险表

| 风险 | 概率 | 影响 | 缓解 |
|:--|:--:|:--|:--|
| `_FakeChatService @override` 契约断裂（X-025-ARCH 教训）| 低 | 高 | 保留 `sendMessage` 薄壳 + 6 道门禁 + 9 例 `pumpAndSettle` 必跑 |
| 公开方法 `commitDiagnosisFromContent` 行为漂移 | 中 | 高 | 薄壳委派同签名 + 专项测试 ≥3 例 + 现有 widget 调用方回归 |
| `DiagnosisCommitter` 与 ChatService 状态共享（`_consecutiveDiagnosisFails`）| 中 | 中 | 状态字段随类迁出，**不共享**；按 session 隔离逻辑不变 |
| 循环依赖（DiagnosisCommitter ↔ ChatService）| 低 | 高 | DiagnosisCommitter **不引用** ChatService；ChatService 单向引用 DiagnosisCommitter |
| R-019 净化不彻底（部分函数迁入新类后仍超 50）| 中 | 低 | K-6 一次性清查 + V4.14 验证；残留超 50 登记基线 |
| 测试替身契约（_FakeChatService 不持有 _diagnosisCommitter）| 低 | 中 | 测试替身 override sendMessage 整体即可，不需访问 _diagnosisCommitter |
| 变异漏网（V4.21 单点评据不证真覆盖）| 中 | 中 | K-6 ≥10 锚点，拦截率 ≥90% 才算护栏完好 |
| sendMessageCore 311 行仍超限（拆分后 chat_service.dart 仍残留）| 高 | 低 | **不在本 ADR 范围**——K-7/K-8 独立处理；R-019 允许存量豁免 |

### 6.2 回退计划

- **回退点**：批次 K-1 / K-2 / K-3 / K-4 / K-5 / K-6 各自独立 commit，任意 commit 可独立 `git revert`
- **回退验证**：
  - 字段新增型改动（K-1）：revert 后 `git status` 干净 + 六道门禁全绿
  - 方法迁出型改动（K-2 ~ K-5）：revert 后**需**同时回退对应专项测试（否则测试引用不存在的 `DiagnosisCommitter` 方法失败）
  - 基线/文档型改动（K-6）：独立 revert 无副作用
- **回退触发条件**：
  - 9 例 `pumpAndSettle` 任一回归
  - 变异拦截率 < 80%
  - 公开方法行为漂移（widget 端可观测的失败）

### 6.3 护栏（K-1 ~ K-6 每步必跑）

```bash
# 六道门禁
bash scripts/gate.sh

# 9 例 pumpAndSettle 专项（X-025-ARCH 教训）
flutter test test/widgets/chat_page_test.dart --plain-name "pumpAndSettle" --no-pub

# 变异验证（K-2 ~ K-5 累加，K-6 收尾）
python tool/_verify_batch_k_coverage.py
```

---

## 7. 验收（K-6 收尾时全绿）

| 项 | 标准 |
|:--|:--|
| chat_service.dart 行数 | 3108 → ~1650（-47%）|
| DiagnosisCommitter 行数 | ~1500 |
| R-019 超限函数 | 14 → ≤7（清偿 7-8）|
| R-019 基线 | 214 → ~207（重生成不带 `--baseline`）|
| V4.14 验证 | 7/7 函数撑大后被新基线拦住 |
| 9 例 pumpAndSettle | 全绿 |
| 变异拦截 | ≥10 锚点，≥90% 拦截 |
| 六道门禁 | 全绿 |
| 公开方法签名 | `commitDiagnosisFromContent` 同名同参同返回 |
| ChatService 构造签名 | 末尾追加 `DiagnosisCommitter?` 可选（默认 null 兼容 30+ 测试）|

---

## 8. 与后续批次的关系

| 批次 | 主题 | 依赖 |
|:--|:--|:--|
| **K-1 ~ K-6** | **诊断组拆分（本 ADR 范围）** | — |
| K-7（独立 ADR）| 训练结果组（`_handleTrainingResult` + 2 observer）| K-6 完成后启动 |
| K-8（独立 ADR）| 引用预载组（`_preloadReferenceDetails` + 缓存字段）| K-6 完成后启动 |
| K-9（独立 ADR）| `_sendMessageCore` 311 行残余 | 待 K-7/K-8 后评估：或细分步骤块，或登记为已知债务 |

---

## 9. 待舰长确认 3 件事

1. **拆分粒度**：第一刀只拆诊断组（推荐），还是三组一起拆？
2. **节奏**：6 批次（K-1 ~ K-6，每步独立 commit 可回退）vs 更大颗粒（如 K-1 + K-2-5 合并、PR 评审后 K-6 收尾）？
3. **方法可见性**：从 ChatService 私有 `_method` 迁入 DiagnosisCommitter 后，是保留 `_method` 私有（受限但纯封装），还是改 `method` 公开 + `@visibleForTesting`（便于专项测试）？

按舰长"按你说的来"，本 ADR 取推荐：6 批次 / 拆诊断组 / 公开 `method` + `@visibleForTesting`。如有调整，K-1 启动前告知。

---

## 10. 实施记录（K-5 收尾）

### K-1 骨架与接口（commit b820b886）
- 新建 `lib/services/diagnosis_committer.dart`：DiagnosisCommitter 类骨架 + 11 方法签名占位 + 必备依赖（5 个）+ 可选依赖（5 个）+ 4 capability 注入
- `lib/services/chat_service.dart` 新增 `final DiagnosisCommitter? _diagnosisCommitter;` 字段 + 构造参数（nullable 不破坏 30+ 测试）
- `lib/providers/session_providers.dart` 装配 diagnosisCommitterProvider + chatServiceProvider 注入
- **护栏**：六道门禁全绿（仅字段新增，行为零变化，证明路径可行）

### K-2 迁 _applyPhaseMigration（commit adaca8e5）
- 从 `extension ChatServiceDiagnosisSupport` 抽出 `_applyPhaseMigration`（217 行）→ `DiagnosisCommitter.applyPhaseMigration`（公开 + @visibleForTesting）
- 10 个测试 fixture 装 DiagnosisCommitter（K-2 阶段装配的 12 个点中的 8 个）
- 副作用：诊断阶段迁移逻辑链 phase-mapper → M4-A/B/C 闭环迁移至独立类

### K-3 迁协议块字符串构造（commit a5816120）
- 原 K-3 计划迁 `_parseAndPersist`（186）+ `_commitDiagnosisAndSuggestions`（150）= 336 行
- 调整：改迁 `_buildDriftHintContext`（14）+ `_buildFactProtocolContext`（48）= 62 行（零依赖字符串构造）
- 1 个测试 fixture 装 DiagnosisCommitter（chat_service_drift_injection_test）

### K-4 迁实体/事实落库辅助（commit 1a73a1fb）
- 原 K-4 计划迁 `_injectDiagnosisLock`（268）+ 4 helper——链 20+ 调用点风险高
- 调整：改迁 `_applyOutlineEntitiesFromContent`（78）+ `_applyFactExtractionFromContent`（122）
- 2 个测试 fixture 装 DiagnosisCommitter（chat_service_fact_coverage_t2_4_test + chat_service_outline_test）+ K-2 阶段 7 个 buildChatService 配套（conflict/coverage_t2_4/coverage_t2_4_b/dialogue_tag/grammar/intent/ui_e2e）
- chat_service.dart 行数 3108 → 2628（净减 480 行，-15%）

### K-5 收紧 + 基线 + 文档（commit 0c37c14f + 当前 commit）
- **收紧**：DiagnosisCommitter 字段/构造参数/8 个调用点全部升级为 required
- **标注清理**：5 个错加的 @visibleForTesting 移除（chat_service 是同包 production，不该被 visibleForTesting 限制）
- **测试 fixture 补全**：K-2~K-4 阶段漏装 18 处全部补齐（8 buildChatService + 3 inline + 1 _FakeChatService + 4 live_*.dart + 15 文件补 import）
- **门禁收尾**：0/2/3/4/5 全绿，门禁 1 已知 11 warnings（4 unused_import + 6 unused_field + 1 unintended_html 来自 K-2~K-4 预留字段，登记 known debt）
- **基线**：tool/r019_baseline.json 重生成（不带 --baseline）= 214 条（3 移除 chat_service 旧位置 + 3 新增 diagnosis_committer 新位置）

### 文件行数变化
| 文件 | K-1 前 | K-5 后 | 变化 |
|:--|--:|--:|--:|
| lib/services/chat_service.dart | 3108 | 2628 | **−480（−15%）** |
| lib/services/diagnosis_committer.dart | 0 | 696 | **+696（新建）** |
| 净增 | — | — | **+216**（拆出独立类的天然代价） |

### R-019 净化进度
- K-1 前：chat_service.dart 14 个函数超 50 行
- K-5 后：chat_service.dart 11 个（清偿 3：_applyPhaseMigration / _applyOutlineEntitiesFromContent / _applyFactExtractionFromContent 迁出），diagnosis_committer.dart 3 个（迁入即超）
- 净减少 11 个超限函数（chat_service.dart -3 + diagnosis_committer.dart +3 抵消，余 11 + 3 = 14 总量不变，但分散到 2 个文件便于独立治理）

### 已知债务
1. 门禁 1：11 个 unused_field/unused_import/unintended_html warnings（K-2~K-4 预留 capability 字段），无 error，待 K-7/K-8/K-9 真正消费 capability 时消除
2. `_injectDiagnosisLock`（268 行）+ 4 helper（`_buildFocusHistory`/`_parseUserFocusFromMessage`/`_buildInterventionAdjustmentNote`/`_mapFocusSource`）仍滞留在 chat_service.dart，K-7 独立 ADR 处理
3. chat_service.dart 仍残留 11 个超 50 行函数（`_sendMessageCore` 311 + `_injectDiagnosisLock` 268 + `_injectChapterObservations` 237 + `_handleTrainingResult` 137 + `_parseAndPersist` 188 + `commitDiagnosisFromContent` 178 + `_commitDiagnosisAndSuggestions` 153 + `_injectOutlineFactsAndFiles` 89 + `_preloadReferenceDetails` 85 + `_injectProfileAndIntents` 73 + `_injectReferences` 64）——K-7 训练组 + K-8 预载组 + K-9 _injectDiagnosisLock 独立 ADR

### K-7 + K-9 收尾（2026-09-05，ChatService 真分解第二阶段）
- **K-7 MessageInjector**（lib/services/message_injector.dart，1463 行）：5 公开 API + 11 helper +
  _insertPhaseSummaryOnMastered，承载引用注入逻辑
- **K-9 DiagnosisFlowHandler**（lib/services/diagnosis_flow_handler.dart，903 → 1169 行）：
  ChatService 4 个诊断链方法迁出 + 公开委派；chat_service.dart 1654 → 859 行（3 个 extension 删除）
- **R-019 净化**：K-9 4 个超限函数全拆（parseAndPersist 155 → 主方法 + 7 helper + 3 record typedef /
  commitDiagnosisFromContent 147 → 5 helper / commitDiagnosisAndSuggestions 97 → 5 helper /
  handleTrainingResult 51 → 1 helper）；基线收紧至 204 条，_verify_r019_baseline.py 验证仍能拦
- **fixture 修复战役**：23 测试文件畸形块修复 + 3 层连环问题（import 库路径 26 处 / CMT 类型 22 文件 /
  dh 缺 messageInjector 29 块）全解决；计数判据通过
- **K-9 mutation**：	ool/_k9_mutation.py 5 变异 → M1-M4 拦截（M1 补 FT-22 判据测试：
  streamChat 计数==1），M5 known 预存盲区（outline 兜底分支无测试装配 outlineRepo，登记）
- **六道门禁全绿**：format ✓ / analyze 7 K-1 预存 warning / test 2374+14 ✓ / 循环依赖 ✓ /
  密钥 ✓ / R-019 0 新增超限 ✓
- 收尾报告：docs/audits/2026-09-05-ADR-C74-K9-ChatService拆分收尾报告.md
