# ADR-C54：阶段迁移信号撞车（首诊同时触发 P0→P1 与 P1→P2）

- 状态：**提案**（待舰长确认后生效）
- 日期：2026-09-01
- 关联：AGENTS.md L110（核心模块改动先写 ADR）、ADR-skill-orthogonal-model.md、ADR-knowledge-injection-driver-model.md
- 影响模块：`lib/services/phase_transition.dart`、`lib/services/phase_mapper_resolver.dart`、`lib/services/chat_service.dart`（教学状态机）
- 真源参考：`src/assets/skills/phase-mapper.ts` L40-62（4 条决策规则）、`utils/phase-transition.ts`
- 本文所有结论均标注 `file:line`；凡未读到代码的一律标「未验证」，不推断为事实。

---

## 1. 背景与问题陈述

### 1.1 现象

学员**首次展示文本**并且**首次被诊断出症候**时，两个迁移信号必然同时成立：

| 信号 | 定义处 | 迁移动作 |
|:--|:--|:--|
| P0→P1 | `lib/services/skills_l1_core_p1.dart:73-74` | 填 `"suggested_phase": "P1_WORLD"` |
| P1→P2 | `lib/services/skills_l1_core_p1.dart:80-81` | 填 `"suggested_phase": "P2_PRACTICE_LOOP"` |

但诊断块 schema 里 `suggested_phase` 是**单值字符串**（`lib/services/skills_l1_core_p2.dart:111`），一轮只能填一个。

### 1.2 这不是理论问题——4 个模型实例实测复现

用 `docs/audits/_prompt_dump/` 下真实 system prompt 导出件做 LLM 角色扮演，四个独立模型实例全部撞上，且各自表述：

| 实例 | 填的值 | 自述 |
|:--|:--|:--|
| A（改动前版本） | `P1_WORLD` | 「这是我自己选的，**非明文规定**」 |
| B（改动后版本） | `P2_PRACTICE_LOOP` | 「我预期它会被单向递进校验拒绝」 |
| C | 记录了冲突本身 | 「coaching-rhythm §2.1 把 <200 字文本列为 P0_ENGAGE 自动触发，红线『不要在确认前给任何写作建议』；teaching-strategy §3.2 却说『用户主动请求评价时可跳过前两阶段』。两条直接冲突，我选了后者。**如果换一次采样，这里可能走成先确认再诊断。**」 |
| D | 同上 | 记录「<200 字触发 P0」与「主动求教可跳 P2」的冲突 |

**实例 C 引用的两处原文均在源码中核实到**：
- coaching-rhythm §2.1 触发条件：`lib/services/skills_beginner_p3.dart:48`（「直接展示文本但字数很少（< 200字）」列为 P0 自动触发）；同节步骤1 红线：`lib/services/skills_beginner_p3.dart:69`（「❌ 不要在确认前给任何写作建议」）
- 导出件中的对应位置（实测所用那份）：`docs/audits/_prompt_dump/beginner_doubao.txt:1252-1261`（§2.1）、`:1278-1279`（红线）
- teaching-strategy §3.2：`lib/services/skills_l1_core_p1.dart:185`「用户主动请求评价时可跳过前两阶段。」

**关键判据**：模型每次都在自行裁决，且实例 C 明确表示裁决结果在两次采样间可能不同。这意味着**教学路径依赖采样**，是确定性问题，不是措辞问题。

### 1.3 冲突在 prompt 里是明文存在的，且全项目没有裁决规则

- 两份阶段指引**同时注入**：P 系指引整段在 L1（`skills_l1_core_p1.dart:65-106`），不随阶段裁剪（对比 coaching-rhythm 会按阶段切片，`lib/services/skills_beginner_p9.dart:49-66`）。
- schema 只警告「不合法的迁移建议会被拒绝」（`skills_l1_core_p2.dart:111`），**没有**说明两个信号同时成立时填哪个。
- **系统提示词不注入「当前阶段」明文**：`lib/services/chat_context_builder.dart` 与 `lib/services/skill_dispatcher.dart` 中 grep「当前阶段 / currentPhase / 当前教学阶段」**零命中**；仅 UI 学习报告里有（`lib/services/progress_service.dart:227`，非 system prompt）。AI 只能从注入了哪一段 coaching-rhythm 切片反推自己在 P0 还是 P1。

---

## 2. 代码侧核实结果（全部已读到代码）

### 2.1 `validatePhaseTransition`：只放行「同阶段 + 相邻递进 + P4→P2」

`lib/services/phase_transition.dart:33-46`，判定逻辑原文：

```dart
bool validatePhaseTransition(TeachingPhase current, TeachingPhase suggested) {
  if (current == suggested) return true;                       // :34  同阶段
  final currentIdx = _kPhaseOrder.indexOf(current);
  final suggestedIdx = _kPhaseOrder.indexOf(suggested);
  if (currentIdx == -1 || suggestedIdx == -1) return false;    // :37
  if (suggestedIdx == currentIdx + 1) return true;             // :39  相邻递进
  if (current == TeachingPhase.p4Review &&
      suggested == TeachingPhase.p2PracticeLoop) return true;  // :41-43 P4→P2 回退
  return false;                                                // :45
}
```

顺序表 `_kPhaseOrder` = `[p0Engage, p1World, p2PracticeLoop, p3Training, p4Review]`（`:9-15`）。

→ **「只放行相邻递进 + P4→P2」属实**。`P0→P2`（0→2）**非法**。
→ 配套 `nextPhase`（`:21-25`）在 P4 返回 null，且不处理 P4→P2（`:20` 注释明示）。

### 2.2 拦截点：非法即丢弃，不降级、不补偿

`lib/services/chat_service.dart:1106-1134`：

```dart
if (validatePhaseTransition(currentPhaseForValidation, effectivePhase)) {  // :1106
  await _stateRepo.updatePhase(sessionId, effectivePhase.value);           // :1110
  ...                                                                       // :1112-1128 子阶段重置 + 升级卡片
} else {
  debugPrint('[SafeRun] M4-B: 阶段迁移非法已拦截 ...');                      // :1130-1133
}
```

当前阶段取值 `:1102-1105`，state 为空时兜底 `p0Engage`。

### 2.3 自动迁移：确只在 P2 以后，且 P0/P1 无兜底

`lib/services/chat_service.dart:1154-1195` 三重前提：

1. 所有活跃症候已 resolved（`:1155-1156`）
2. `currentPhase != p0Engage && currentPhase != p1World`（`:1161-1162`）——注释 `:1152`「守卫：仅在 P2 及以后触发（P0/P1 阶段迁移由 AI suggested_phase 驱动）」
3. `passRate >= EvaluationThresholds.phasePassRate`（`:1170`）

→ **「自动迁移只在 P2 以后」属实**；**「P0/P1 完全依赖 AI 填的 suggested_phase」属实**。

补充一条转述未提到的事实：路径 1 与路径 2 的互斥开关 `path1Migrated`（`:1036` 初始化、`:1148` 提前 return）**只由「路径 1 成功迁移」置位**（`:1113`）。路径 1 被拦截时不会「回落到路径 2 补迁移」——路径 2 会执行但被 `:1161` 的 P0/P1 守卫挡死。→ **「填 P2 被拦截 = 本轮彻底不迁移」属实**。

### 2.4 第二套校验（N 系）——本次侦察的关键盲区，结论如下

`lib/services/phase_mapper_resolver.dart:74-78`：

```dart
bool _isValidProgression(BeginnerLevel from, BeginnerLevel to) {
  final fromIdx = _kBeginnerOrder.indexOf(from);
  final toIdx = _kBeginnerOrder.indexOf(to);
  return toIdx == fromIdx || toIdx == fromIdx + 1;
}
```

**两套校验不是重复实现，而是串联、作用于不同字段、职责不同**：

| | `phase_mapper_resolver` | `phase_transition` |
|:--|:--|:--|
| 校验对象 | `suggested_beginner_level`（调用点 `:100-103`） | `suggested_phase` → `effectivePhase`（调用点 `chat_service.dart:1106`） |
| 职责 | **信号取舍**：AI 给的迁移信号里哪个算数 | **落库合法性**：算数的那个能不能写进 DB |
| 形状 | N0→N1→N2→N3→N4 同级或 +1，**无回退特例** | 同级 / +1 / P4→P2 |

调用顺序：`chat_service.dart:1088-1096` 先 `resolvePhaseMapper` → `:1106` 再 `validatePhaseTransition`。

**C54 在 N 系里表现完全不同，且差别是决定性的：**

| 学员 N 级 | 命中规则 | `effectivePhase` | C54 表现 |
|:--|:--|:--|:--|
| **N0 / N1 / N2** | 规则1 `:173-187` | `null`，`suggested_phase` 被**整个丢弃**（`:177-179`） | 走不到 `validatePhaseTransition`。P 系**完全冻结** |
| **N3 + AI 填 P1** | 规则3 `:152-161` | **被改写成 `P2_PRACTICE_LOOP`**（`:155`） | ⚠️ 在 current=P0 时必然被 `:1106` 拦截 → **本轮连 P0→P1 也没发生** |
| **N3 + AI 填 P2** | 规则2 `:189-199` | 原样透传 `P2` | 在 current=P0 时被 `:1106` 拦截 |
| **N4** | 规则2 | 原样透传 | 同 N3 |
| **beginner_level 为 null** | 默认回退 `:121-122` | `decisionBeginnerLevel = resolverBeginnerLevel ?? n3Diagnose` → **默认 N3** | 同 N3 |

默认回退与 prompt 一致：`skills_l1_core_p1.dart:61`「如果 N 系进度未知（未存储或丢失）——默认为 N3」。

学员 N 级的实际来源：`lib/services/onboarding_service.dart:50`（问卷/跳过后写入），映射表 `lib/services/onboarding_flow.dart:31-57`（beginner→N0、elementary→N1、intermediate→N2、advanced→N3）。**跳过问卷也是 N0_ENGAGE**（`onboarding_service.dart:60`、`:64`）。

→ 结论：**真正让「填 P1」这个看似安全的选项也失效的，是 resolver 规则 3，不是 `validatePhaseTransition`。** C54 的根因有一半在 N 系门禁里。

### 2.5 `suggested_phase` 完整链路

| 环节 | 位置 |
|:--|:--|
| ① Prompt 契约 | `lib/services/skills_l1_core_p2.dart:111`（字段定义）；迁移动作 `skills_l1_core_p1.dart:74 / 81 / 88 / 95 / 101`；迁移规则 `:103-106` |
| ② 解析（白名单） | `lib/services/diagnosis_parser.dart:179-183`，白名单 `_kValidPhases`（`:24-30`，含 P3/P4） |
| ②′ 二次反序列化（无白名单） | `lib/services/diagnosis_validator.dart:309-311`（见 §附 N2） |
| ③ 信号取舍 | `chat_service.dart:1088-1096` → `resolvePhaseMapper` |
| ④ 落库校验 | `chat_service.dart:1106-1109` → `validatePhaseTransition` → `updatePhase`（`:1110`）+ 子阶段重置（`:1115`）+ 升级卡片（`:1117-1124`） |
| ⑤ 自动迁移兜底 | `chat_service.dart:1154-1195` |
| 调用点 | `:690`（分块诊断 `commitDiagnosisFromContent`）、`:2383`（单次诊断 `_commitDiagnosisAndSuggestions`） |
| UI 旁路 | `lib/widgets/writing_coach_panel_teaching.dart:355-358`（见 §附 N3） |

### 2.6 各阶段进入条件（定义处）

| 迁移 | 定义处 | 条件 |
|:--|:--|:--|
| →P0 | `chat_service.dart:1104-1105`、`writing_coach_panel_teaching.dart:354` | 无显式条件，兜底初值 |
| P0→P1 | `skills_l1_core_p1.dart:73-74`；`skills_beginner_p3.dart:120-126`、`:51` | 用户确认"对" / 展示文本 / 明确请求评价；200+ 字可跳过 P0 |
| P1→P2 | `skills_l1_core_p1.dart:80-81`；`skills_beginner_p3.dart:204` | 首次诊断出症候（syndromes 非空） |
| P2→P3 | `skills_l1_core_p1.dart:87-88` | 症候改善 / 训练达标率 ≥60% |
| P3→P4 | `skills_l1_core_p1.dart:94-95` | 全 consolidating + 学员要求回顾 |
| P4→P2 | `skills_l1_core_p1.dart:100-101` | 复盘完成 / 携新文本重入 |
| P2+ 自动 | `chat_service.dart:1154-1195` | 症候全 resolved 且 passRate ≥0.7 |
| N 系 | prompt `skills_l1_core_p2.dart:112`；代码 `phase_mapper_resolver.dart:61-67, 94-118` | 见 §2.4 |

### 2.7 测试覆盖现状（实测 grep）

- `test/services/chat_service_phase_migration_test.dart`：M4-B 两例（#1 P2→P4 拦截 `:175-202`；#2 P2→P3 放行 `:204-231`）+ M4-C 两例（#3/#4）。**无任何 P0/P1 用例**。
- `test/services/evaluation_service_test.dart:225-310`：`validatePhaseTransition` 纯函数组（含 P0→P4 `:279`、P4→P0 `:307`）。**无 P0→P2**。
- `resolvePhaseMapper` **无独立单测**：`test/` 下 grep `resolvePhaseMapper|phase_mapper_resolver` 仅命中 `chat_service_phase_migration_test.dart:5` 的一行注释。
- 锚点快照 `test/snapshots/skill_prompt_anchor.json`：`prompt.*` 覆盖 9 个用例的 `buildSystemPromptV2` **全输出**指纹（`skill_prompt_anchor_test.dart:8-12`）；`skillContent.*` 覆盖 6 块（`:30-37`，含 `coaching-rhythm`），**`teaching-strategy` 不在其列**（`:29` 注释明示）。

---

## 3. 决策驱动因素

1. **确定性优先于速度**：教学路径不应依赖 LLM 采样（实例 C 自证）。方案的价值排序 = 消除不确定性 > 少花一轮。
2. **不得新增持久化状态**（若可避免）：`teaching_state` 属 DB schema，改动触发 AGENTS.md L110 的独立 ADR + 迁移。
3. **不得破坏既有单向递进不变量**：`chat_service.dart:1034-1035` 明确禁止同轮链式双跳（P1→P2→P3）。
4. **N 系既有设计不动**：规则 1（N0-N2 P 系虚拟挂起）是刻意设计（prompt `skills_l1_core_p1.dart:56`），本次不改。
5. **prompt 改动成本高**：改任何 L1 文本都会破 9 个 prompt 指纹，需 `UPDATE_SNAPSHOTS=true` 重生成 + 人工复查 diff。
6. **P1 那一格有独立教学价值**：`skills_l1_core_p1.dart:76-79`（提问引导用户自己发现问题）。首诊跳过它不是纯损失，但也不应为它牺牲确定性。

---

## 4. 备选方案

### 方案 A：prompt 侧裁决规则

**改什么**
- `lib/services/skills_l1_core_p2.dart:111`：字段说明追加「同一轮多个迁移信号同时成立时，只填与**当前阶段相邻**的那一个，跨级的那一步留到下一轮。」
- `lib/services/skills_l1_core_p1.dart:103-106`：迁移规则段补同一条裁决。

**对 prompt 侧的影响**：新增裁决条文。但**死穴**——系统提示词不注入当前阶段明文（§1.3），AI 必须自己推断。要么新增注入点（破全部 9 个 prompt 指纹），要么靠 coaching-rhythm 切片反推（脆弱，模型可能推错）。

**对代码侧的影响**：零。但**对 N3 学员无效**——规则 3（`phase_mapper_resolver.dart:152-161`）会把 AI 填的 P1 提升成 P2，然后在 P0 上被拦截，等于信号被吃掉。要让 A 闭环，必须同时改 resolver 规则 3，那就不再是「纯 prompt 方案」。

**风险**：**高**。4 个实例已证明模型会自行裁决，加一条规则不能消除采样间不确定性——只是把「没有规则」变成「有规则但可能不遵守」。

**回滚成本**：低。改回文本 + 重生成锚点（每次改动都要走锚点复查流程）。

---

### 方案 B：代码侧首诊仲裁 + pending 记账

**改什么**
- `lib/services/chat_service.dart:1129-1134` 的 else 分支：非法跨级不丢弃，改为落库 `nextPhase(current)`（合法的那一格），并把被跨过的一格记为待迁移。
- 新增 pending 持久化字段（`teaching_state` 或复用 `student_model.teaching_history`）+ **DB migration**。
- 下一轮：路径 1 无有效迁移时，从 pending 取出再走一次 `validatePhaseTransition` 推进。
- 需重新梳理 `path1Migrated` 互斥逻辑（`:1036` / `:1148`），否则可能与路径 2 链式双跳。

**对 prompt 侧的影响**：零（可选补一句澄清）。

**对代码侧的影响**：教学状态机新增持久化状态 + DB schema 变更。

**风险**：**中高**。① pending 可能陈旧（学员长时间不回来），需过期/清理策略；② `teaching_state` 是核心模块，schema 变更要独立 ADR；③ 双跳互斥逻辑变复杂。

**回滚成本**：**高**。代码分支可删，但 DB 字段回滚需要反向迁移 + 数据清理。

---

### 方案 C（推荐）：代码侧收窄降级推进 + 修 resolver 规则 3，**零新状态**

**核心思路**：C54 的根因是「一个字段承载两个信号」。不要求 AI 算出合法目标，而是让代码在**唯一的早期跨级场景**里确定性降级。

**改什么（三处，均为纯函数/分支，不动 DB）**

**C-1** `lib/services/phase_transition.dart` 新增纯函数（不改动 `validatePhaseTransition` 既有语义）：

```dart
/// 早期阶段（P0/P1）跨一格时的降级目标；其他情况返回 null（维持拦截）
TeachingPhase? clampEarlyPhaseSkip(TeachingPhase current, TeachingPhase suggested) {
  final c = _kPhaseOrder.indexOf(current);
  final s = _kPhaseOrder.indexOf(suggested);
  if (c < 0 || s < 0) return null;
  if (c > 1) return null;          // 仅 P0(0) / P1(1)
  if (s != c + 2) return null;     // 仅恰好跨一格
  return _kPhaseOrder[c + 1];      // 降级为相邻递进
}
```

收窄条件的边界（逐条验算）：

| 输入 | c | s | 结果 |
|:--|:-:|:-:|:--|
| P0→P2（C54 首诊） | 0 | 2 | ✅ 降级 P1 |
| P1→P3（首诊后一轮仍跨级） | 1 | 3 | ✅ 降级 P2 |
| **P2→P4** | 2 | 4 | ❌ null（c>1，维持拦截）— **保住既有用例 #1** |
| P0→P3 | 0 | 3 | ❌ null（s≠c+2） |
| P2→P0 / P4→P0（回退） | — | — | ❌ null |
| P0→P1（合法） | 0 | 1 | ❌ null（走原合法路径，不干扰） |

**C-2** `lib/services/chat_service.dart:1129-1134` else 分支改为：

```dart
} else {
  final fallback = clampEarlyPhaseSkip(currentPhaseForValidation, effectivePhase);
  if (fallback != null) {
    await _stateRepo.updatePhase(sessionId, fallback.value);
    await _stateRepo.updateSubphase(sessionId, null);
    // + insertPhaseUpgradeCard（复用 :1117-1124 的 try/catch 包装）
    path1Migrated = true;   // 与 :1113 同口径，防止同轮再走路径 2 造成双跳
  } else {
    debugPrint('[SafeRun] M4-B: 阶段迁移非法已拦截 ...');   // 原文保留
  }
}
```

**C-3** `lib/services/phase_mapper_resolver.dart:152-161` 规则 3 加收窄条件：当 `input.currentPhase` 已知且 `suggestedPhase == p1World` **尚未越过 P1**（即 current 为 null 或 P0）时，不做 P1→P2 提升，原样透传 P1。
理由：规则 3 的设计意图是「P1 世界观对 N3 学员太浅」（`:158` reason 文本、`skills_l1_core_p1.dart:56`），但它在 current=P0 时的实际效果是把一个**合法**的 P0→P1 信号变成一个**非法**的 P0→P2 信号，与意图相反。

**对 prompt 侧的影响**：零。可选补充（低优先）：`skills_l1_core_p2.dart:111` 的取值列表补全为 P0–P4（当前只列 3 个，与 `diagnosis_parser.dart:24-30` 不一致），并加一句「填你判断学员应到达的阶段即可，跨级建议由系统降级为逐格推进，不是错误」。**若做这一步则破 9 个 prompt 指纹**。

**对代码侧的影响**：新增 1 个纯函数 + 1 个分支改造 + 1 条收窄条件。无 DB 变更，无新持久化状态。

**为什么不需要 pending 记账（C 相对 B 的关键简化）**：
首诊后 current 已确定变为 P1。下一轮 syndromes 仍然非空（症候未 resolve），P1→P2 信号（`:80-81`）**必然再次成立**，AI 再填一次 P2 → `validatePhaseTransition(P1, P2)` 放行。**收敛是确定的，不依赖 AI 填了什么**——因为无论 AI 填 P1 还是 P2，代码路径都会落到 P2：
- 填 P1 → C-3 收窄后透传 P1 → `validate(P1,P1)` 合法但无变化；此时靠路径 2（`:1154`）需要症候全 resolved，不一定成立。
- 填 P2 → `validate(P1,P2)` 放行 → 到 P2。✅

诚实声明：若 AI 连续两轮都填 P1，则收敛慢一轮。但配合下面「C′ 确定性补充」可完全消除。

**C′（可选增强，仍无新状态）**：在 `_applyPhaseMigration` 路径 1 之前加一条**代码侧首诊判定**——本轮 `commitDiagnosis` 前 `active_problems` 为空、之后非空（代码可判定，参考 `:1055` / `:1155` 已有的 `listActiveProblems` 调用），且 current == P0 → 直接 `updatePhase(P1)`。这样「首次诊断出症候」这个事实不再依赖 AI 复述，P0→P1 变成确定性事件；P1→P2 由下一轮 AI 信号完成。**代价**：新增一处诊断前后症候数比对逻辑，需评估与分块诊断路径（`:690`）的时序。

**风险**：低。三处改动均为纯函数/分支，可单测全覆盖；不引入新状态；不动 N 系规则 1/2/4。
**回滚成本**：**低**。删函数 + 还原分支 + 还原规则 3 条件即可，无数据迁移。

---

## 5. 方案对比

| 维度 | A（prompt 裁决） | B（代码仲裁 + pending） | **C（收窄降级 + 修规则3）** |
|:--|:--|:--|:--|
| 消除采样不确定性 | ❌ 不消除（只加规则） | ✅ | ✅ |
| 对 N3 学员有效 | ❌ 被规则 3 吃掉 | ✅ | ✅（含 C-3 专项修复） |
| 需 AI 知道当前阶段 | ✅ 需要（且 prompt 未提供） | ❌ 不需要 | ❌ 不需要 |
| DB schema 变更 | 无 | **有（+migration）** | **无** |
| 新增持久化状态 | 无 | **有（pending + 过期策略）** | **无** |
| 破锚点快照 | **9 个 prompt 指纹** | 无 | 无（做 C 的可选 prompt 澄清才破） |
| 影响既有测试 | 锚点测试需重生成 | `chat_service_phase_migration_test` #1 需改预期 | **#1 保持绿色**（收窄条件排除 P2→P4） |
| 同轮双跳风险 | 无 | 中（需重理互斥） | 无（复用 `path1Migrated`） |
| 回滚成本 | 低（文本） | **高（含 DB 反向迁移）** | **低（纯代码）** |
| 落地工作量 | 小 | 大 | 中 |

---

## 6. 推荐方案

**推荐方案 C（含 C-3；C′ 列为第二阶段可选增强），并附带做 C 的可选 prompt 澄清（低优先，可独立排期）。**

**一句话理由**：C54 的根因不在「AI 填错值」（那是症状），而在「代码把两个同时成立的教学信号当成互斥错误处理，且对非法值只丢弃不降级」——所以修复必须是代码侧的确定性降级，而 prompt 侧加规则已经被 4 个实例证明拦不住。

补充三条理由：

1. **C 是唯一同时满足「消除不确定性」+「不动 DB schema」+「不动锚点」的方案**。B 虽然也消除不确定性，但为「少花一轮」引入 pending 持久化状态，违反§3.2，且回滚要反向迁移。
2. **C-3 是必须项而非可选**——它修的是一个独立 bug：规则 3 在 current=P0 时把一个合法信号变成非法信号，与设计意图（`:158`）相反。这一条即使不做 C-1/C-2 也应该单独修。
3. **关于「拖慢一轮」的诚实评估**：P1 那一格有独立教学价值（`skills_l1_core_p1.dart:76-79`），且当前实际行为是「整轮不动」（更慢且不确定）。C 把结果从「不确定/不动」变成「确定推进一格 + 下一轮确定到 P2」，是严格改进。若确实要一轮到位，走 C′（把「首次诊断出症候」交给代码判定），仍然不需要 DB 变更。

---

## 7. 验证方式

### 7.1 纯函数单测（新增）
`clampEarlyPhaseSkip` 覆盖 §4-C-1 边界表全部 6 行，断言 P2→P4 / P0→P3 / P2→P0 / P0→P1 均返回 null（保住既有拦截语义）。

### 7.2 resolver 单测（**新增文件，填补现有空缺**）
新建 `test/services/phase_mapper_resolver_test.dart`。现状是 `resolvePhaseMapper` **零单测**（§2.7）。至少覆盖：
- 规则1：N0/N1/N2 + 任意 suggestedPhase → `effectivePhase == null` 且 `ignoredFields` 含 `suggestedPhase`（`:177-179`）
- 规则3 + current=P0 + N3 + P1 → 修复后 `effectivePhase == p1World`（**C-3 的验收点**）
- 规则3 + current=P2 + N3 + P1 → `effectivePhase == p2PracticeLoop`（既有行为不变）
- 规则2：N3/N4 透传
- 默认回退：beginnerLevel null → decisionBeginnerLevel = N3（`:121-122`）

### 7.3 集成用例（追加到既有文件）
`test/services/chat_service_phase_migration_test.dart` 追加（该文件目前无 P0/P1 用例）：
- `P0 + N3 + suggested_phase=P2_PRACTICE_LOOP` → 落库 `P1_WORLD`（而非保持 P0）
- `P0 + N3 + suggested_phase=P1_WORLD`（C-3 修复后）→ 落库 `P1_WORLD`
- `P0 + N0 + 任意 suggested_phase` → 落库保持 `P0`（规则 1 挂起，既有设计，断言不被误改）
- `P2 + N3 + suggested_phase=P4_REVIEW` → 落库保持 `P2`（**回归守卫：收窄条件不得放宽到 P2+**）

### 7.4 锚点快照验证
- 方案 C 主体（C-1/C-2/C-3）**不动任何 skill 文本** → `flutter test test/services/skill_prompt_anchor_test.dart` 应**全绿且无需重生成**，这是「零 prompt 侵入」的硬证据。
- 若采纳可选 prompt 澄清 → 需 `UPDATE_SNAPSHOTS=true` 重生成并人工复查 diff（`skill_prompt_anchor_test.dart:16`），且 `test/services/coaching_rhythm_phase_slice_test.dart`（切片为原文子串 + 分阶段注入断言）需同步复查。

### 7.5 LLM 实测法（复用既有资产，判定指标要换）
复用 `docs/audits/_prompt_dump/` 导出件做角色扮演，但**断言指标必须从「AI 填了什么值」改为「落库后 `teaching_state.currentPhase` 是什么」**：

> 通过判据：对同一首诊场景**多次采样**，无论模型填 `P1_WORLD` 还是 `P2_PRACTICE_LOOP`，落库结果**恒为 `P1_WORLD`**。

这才是「教学路径不再依赖采样」的直接证据——也是实例 C 那条「换一次采样可能走成另一种」的反向验证。第二轮同样多次采样，落库结果应恒为 `P2_PRACTICE_LOOP`。

### 7.6 回归范围
`flutter test` 全绿，重点：
- `test/services/chat_service_phase_migration_test.dart`（#1/#2/#3/#4 + §7.3 新增）
- `test/services/evaluation_service_test.dart:225-310`（`validatePhaseTransition` 纯函数，语义未变）
- `test/widgets/writing_coach_panel_test.dart:496`（P2 学员整章诊断不应被回退到 P1）
- `test/services/coaching_rhythm_phase_slice_test.dart`、`test/services/advanced_phases_phase_slice_test.dart`（方案 C 不动 skill 文本，应无影响）
- `test/services/skill_prompt_anchor_test.dart`（见 §7.4）

---

## 8. 附：新发现（本次核实中撞到、尚未登记，未做任何修改）

> **编号说明**：本节编号 **从 N7 起**，接续主台账
> `docs/audits/Skill话术与提示词-综合审阅（合并版）-2026-08-30.md` 的 N 系列——
> N1~N6 已在该台账 A.12.9 登记（指向 `chat_service.dart` 的诊断静默丢弃 / 换症候绕过锁定 /
> 孤儿阶段字段等 6 条）。本 ADR 撰写时原按 N1~N6 编号，与台账撞车，故顺延为 N7~N12。
> **其中 N11 与台账已登记的 C58 是同一问题的两个观察面**（见 N11 附注）。

**N7 — `resolvePhaseMapper` 零单测。**
`test/` 下 grep `resolvePhaseMapper|phase_mapper_resolver` 仅命中一行注释（`chat_service_phase_migration_test.dart:5`）。该纯函数承载 4 条决策规则 + N 系递进校验，且规则 3 会**改写 AI 意图**（`phase_mapper_resolver.dart:155`），却没有任何测试守护。建议独立补测（见 §7.2），与 C54 是否采纳无关。

**N8 — 两条 suggested_phase 解析路径不一致。**
`diagnosis_parser.dart:181` 走白名单 `_kValidPhases`（`:24-30`），`diagnosis_validator.dart:309-311` **不走白名单**，直接 `TeachingPhase.fromString`。当前 `fromString` 对未知串返回 null，实际风险低；但两条路径对同一字段的校验强度不同，属隐性不一致。**未验证**是否存在从 `diagnosis_validator` 路径进入 `_applyPhaseMigration` 的链路。

**N9 — UI 旁路已提前完成 P0→P1，C54 只在对话入口成立。**
`lib/widgets/writing_coach_panel_teaching.dart:355-358`：整章诊断前，若 `validatePhaseTransition(current, p1World)` 通过就先 `updatePhase(P1)`。因此**编辑器面板入口不受 C54 影响**（AI 只需填 P1→P2，合法）。**C54 只在学员在对话框直接贴文本时成立。** 方案影响面需按入口分别评估——这可能是实例 A/B 表现不同的原因之一（**推断，未验证**：未确认两次实测分别走的哪个入口）。

**N10 — 字数门槛冲突（100 vs 200）。**
`writing_coach_panel_teaching.dart:327` 整章诊断最低 100 字；`skills_beginner_p3.dart:48` 把「<200 字」列为 P0 自动触发。100–199 字的整章：UI 已把学员推到 P1（`:355`），prompt 却说这是 P0 场景。

**N11 — schema 文档与实现不一致。**
`skills_l1_core_p2.dart:111` 的 `suggested_phase` 取值只列 `P0_ENGAGE / P1_WORLD / P2_PRACTICE_LOOP`，但代码允许 P3/P4（`diagnosis_parser.dart:24-30`），且 prompt 其他处明确要求 AI 填 P3/P4（`skills_l1_core_p1.dart:88`、`:95`）。模型若严格按 schema 字面理解，会认为 P3/P4 不可填——**这可能与实例 B 的行为有关（推断，未验证）**。

> **附注（交叉验证）**：本条与台账登记的 **C58** 是同一问题的两个观察面——C58 从 prompt 侧
> 记录（`:397` 只列三值，但 `:591` / `:598` 要求填 P3/P4），本条从代码侧记录（代码白名单
> 允许五值，是 prompt 自己写窄了）。**两条路径独立得出同一结论**，C58 的可信度因此从
> 「单人阅读」升级为「双向印证」。方向判定：C58/N11 是 **prompt 比代码窄**（误导 AI 不敢填），
> 与 C56（prompt 比代码宽，承诺不存在的 P5）**方向相反**——两个方向都会出错。

**N12 — 规则 3 与设计意图相反（已在 §4-C-3 登记为修复项，非纯登记项）。**
`phase_mapper_resolver.dart:152-161` 在 current=P0 时把合法的 P0→P1 信号改写成非法的 P0→P2，与 reason 文本（`:158`）「P1 世界观对 N3 学员太浅，按 P2 处理」的意图相悖——在 P0 时学员**还没到** P1，不存在「P1 太浅」的问题。

---

*本 ADR 生效条件：舰长确认。确认后按 §7 建测试、再动代码；实施顺序建议 C-3（独立 bug）→ C-1 → C-2 → C′（可选）→ prompt 澄清（可选，独立排期）。*
