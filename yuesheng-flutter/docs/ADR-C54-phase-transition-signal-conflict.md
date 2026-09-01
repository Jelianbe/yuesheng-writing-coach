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
> **§9（C56 / P5 幽灵阶段）核实阶段的新发现接续本列表，编号从 N13 起，见 §9.6。**

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

## 9. C56：P5 幽灵阶段（prompt 承诺了枚举里不存在的阶段）

> 台账编号 **C56 / P1**。本章为后补章节，追加在文末（不重编号 §1–§8）——
> 既有外部文档已引用 `ADR §7.2`（resolver 补测）与 `ADR §8`（N 系列登记），
> 重编号会让这些引用失效。本章体例与 §4/§5/§6/§7 对齐。
>
> 同构先例：**第 4 批 C52（`gap-detector` 幽灵链路）**，按 A.9.5 方案 A 止血——
> 「删虚构的协作层与输出契约，把模式判定交还模型并配兜底，同时保留真实的识别能力」
> （`docs/audits/Skill话术与提示词-综合审阅（合并版）-2026-08-30.md:19`、`:798`、`:1853`）。
> C56 与 C52 的差别：C52 承诺一个**机制**，C56 承诺一个**阶段**
> （同上文档 `:1449-1451`：「区别只是 C52 承诺一个"机制"、P5 承诺一个"阶段"」）。

### 9.1 核实结果（五问逐条）

**Q1 — `TeachingPhase` 枚举到底有几个值？**

`lib/types/teaching_types.dart:6-11`（**注意：不是 `lib/models/`，本项目无 `lib/models/` 目录**）：

```dart
enum TeachingPhase {
  p0Engage('P0_ENGAGE'),
  p1World('P1_WORLD'),
  p2PracticeLoop('P2_PRACTICE_LOOP'),
  p3Training('P3_TRAINING'),
  p4Review('P4_REVIEW');   // :11  分号收尾，无第 6 个值
}
```

→ **5 个值，p4 之后没有 p5。属实。**

**Q2 — 代码某处是否有对 P5 的分支处理？**

全量 grep（`lib/`、`test/`、`docs/designs|plans|tasks`）结果：

| 搜索 | 命中 |
|:--|:--|
| `P5_` in `lib/`（排除 `skills_*.dart`） | **0** |
| `P5_` in `test/` | **0** |
| `P5_` in `docs/designs\|plans\|tasks` | **0** |
| `p5Engage` / `p5[A-Z]` in `lib/` | **0** |
| `P5` in `lib/`（全量） | 仅 **3 个 prompt 文本文件 + 1 处注释**：`skills_advanced_outline_p5.dart`（11 行）、`skills_advanced_outline_p7.dart`（切片锚点常量 + 注释，5 行）、`skills_diagnosis_p3.dart`（2 行）、`skill_layers.dart:83`（注释） |

→ **P5 纯在 prompt 文本里，代码侧零分支、零枚举、零测试。属实。**

**Q3 — 这段 P5 内容有没有被注入生产 system prompt？在哪个 skill 下？受不受 `contentForPhase` 裁剪影响？**

三个独立结论，其中**第三个推翻了「删掉就不用管」的直觉**：

**(a) 挂在 `advanced-phases` 下。** `skills_advanced_outline_p1.dart:177-186`：`const Skill _advancedPhases = Skill(meta: SkillMeta(id: 'advanced-phases', group: 'advanced', ...), content: _advancedPhasesBody1 + _advancedPhasesBody2, contentForPhase: advancedPhasesContentFor)`。P5 文本位于 `_advancedPhasesBody2`（`skills_advanced_outline_p5.dart:7`）。

**(b) 只在 P3/P4 注入。** 装载链路：`advanced-phases` 仅挂在 `L2Mode.advanced`（`skill_layers.dart:83`）；`resolveL2Mode` 只在 `phase == p3Training || phase == p4Review`（且非 isBeginner）时返回 `L2Mode.advanced`（`skill_layers.dart:189-191`）。P0 → `L2Mode.none`（`:194-195`），P1 → `diagnosis`（`:184-186`），P2 → `diagnosis`/`training`（`:173-180`）——**P0/P1/P2 根本不加载这个 skill**。

> 这一条**收窄了影响面**：P5 不是「常驻注入给所有人」，只在 P3/P4 出现。
> 但它同时**放大了危害**：恰恰是在 P4，注入的正是「P4→P5 条件 + 动作：填 suggested_phase」那一段。

**(c) 裁剪结果：P5「段」被裁掉了，但「迁往 P5 的指令」被注入了。**

`advancedPhasesContentFor`（`skills_advanced_outline_p7.dart:57-88`）：
- 非 P3/P4 → 返回**完整原文**（`:61-63`）——但此时该 skill 根本不被加载，无实际影响。
- P4 档：main = `_apHead4.._apHead5`（`:70-72`），attitude = `_apAttitude4.._apAttitude5`（`:73-75`），moveNext = `_apMoveP4Out.._apMoveP5Back`（`:78`），moveConstraint = `_apMoveConstraint` 至文末（`:79`，**P3/P4 两档都追加**）。

代入 `skills_advanced_outline_p5.dart` 的行号：

| 内容 | 行号 | P3 档 | P4 档 |
|:--|:--|:--:|:--:|
| P5 段（核心定位/教学模式/退出策略） | `:57-90` | ❌ 不注入 | ❌ 不注入 |
| P5 态度策略 | `:110-116` | ❌ 不注入 | ❌ 不注入 |
| **P4→P2 或 P5 段（含「**P4 → P5 条件**」`:146-150` 与「**动作**：在诊断块中填 suggested_phase: 下一个阶段」`:152`）** | `:139-152` | ❌ | ✅ **注入** |
| P5 → P2/P3（回退） | `:154-156` | ❌ | ❌ |
| **迁移约束**（含 `:162`「P4→P5 允许进入持续陪伴模式」、`:163`「P5→P2/P3 允许回退」） | `:158-164` | ✅ **注入** | ✅ **注入** |

→ **P4 学员的 AI 被明确告知：满足 4 个条件就在诊断块填 suggested_phase 进入 P5；而迁移约束明文写着「P4→P5 允许」。**
→ 切片实现方的意图是清楚的——`skills_advanced_outline_p7.dart:17-18` 注释写着「P5 段为远期规划且 `TeachingPhase` 无 P5 枚举值（**不可达**），两档均不注入」。**但只裁掉了「段」，没裁掉「通往它的指令」。**

**Q4 — 是否存在「学员走到 P4 之后就无处可去」？**

需要分开回答，两半都不是你想的那个答案：

**(a) P4 是递进链的终点，但不是教学闭环的终点。**
- `nextPhase` 在 P4 返回 null：`phase_transition.dart:21-25`，`if (idx == -1 || idx >= _kPhaseOrder.length - 1) return null;`（P4 的 idx=4，`length-1=4`）。`:19-20` 注释明示「**P4 无下一阶段返回 null**」。
- 但 P4 有回环出口：`validatePhaseTransition` 放行 P4→P2（`phase_transition.dart:41-43`），prompt 定义为「下一个训练周期重新进入」（`skills_l1_core_p1.dart:89`、`:100-101`）。
→ **递进链终点站 = 是；教学闭环终点站 = 不是。设计上 P4→P2 就是它的出口。**

**(b) 但这个出口是「AI 独占」的，代码侧在 P4 永不兜底——配上 P5 指令就成了死锁。**

逐点核实：
1. 代码侧自动迁移在 P4 永不生效：`chat_service.dart:1171` `final next = nextPhase(currentPhase);` → null → `:1173` `if (next != null && validatePhaseTransition(...))` → false → **不迁移**。（另两重前提 `:1155-1156` 症候全 resolved、`:1170` passRate≥0.7 即便都满足，也卡在 `next == null`。）
2. 所以 P4 的唯一出口是 AI 在诊断块填 `suggested_phase: "P2_PRACTICE_LOOP"`。
3. 而 P4 档 prompt **同时**提供了 P5 出口（`skills_advanced_outline_p5.dart:146-152` + `:162`），与 L1 的「P4→P2」指令（`skills_l1_core_p1.dart:100-101`）**并行注入、无裁决规则**。
4. AI 若选 P5 → `diagnosis_parser.dart:181` `if (sp is String && _kValidPhases.contains(sp))`，而 `_kValidPhases`（`:24-30`）**无 P5** → `suggestedPhase` 静默为 null。
5. 于是 `chat_service.dart:1038-1040` 的 `suggestedPhase != null || suggestedBeginnerLevel != null` 不成立 → 路径 1 整体跳过 → 路径 2 在 P4 又因 `nextPhase == null` 必然空转。
6. → **该轮零迁移。若 AI 持续选 P5，P4 学员永久停留。**

**这是 C56 真正的危害等级：不是「描述了一个不存在的阶段」（措辞问题），而是「在 P4 出口制造了一次与 L1 的信号撞车，且撞车的那一支是死路」。** 与 C54 同构性比台账描述更强——C54 的撞车至少两支都合法（P0→P1、P1→P2），只是只能选一支；C56 的撞车有一支是**不可达的**。

> 附注：第 4 步的「静默」是关键——`suggested_phase` 被白名单丢弃时**没有任何日志**（`diagnosis_parser.dart:179-183` 无 else 分支），与 §8-N8 记的另一条路径不一致问题同源。

**Q5 — 一处转述精度修正**

台账写「`skills_advanced_outline_p5.dart:57-146` 用**整节（约 90 行）**描述了 P5」（同上审计文档 `:1444-1446`）。行号区间属实，但 **57-146 这一段并非全是 P5**：中间穿插了「进阶阶段态度调整」总标题（`:92`）、P3 态度策略（`:94-100`）、P4 态度策略（`:102-108`）、阶段迁移规则总标题（`:120`）、P2→P3（`:122-129`）、P3→P4（`:131-137`）——这些都是**真实存在、必须保留**的内容。

真正讲 P5 的行（改动作用域）：

| 内容 | 行号 | 行数 |
|:--|:--|:--:|
| P5 段（核心定位 `:61-65` / 教学模式 `:67-82` / 退出策略 `:84-88`） | `:57-90` | 34 |
| P5 态度策略 | `:110-116` | 7 |
| P4 → P5 条件 | `:146-150` | 5 |
| P5 → P2/P3（回退） | `:154-156` | 3 |
| 迁移约束中的 P5 两行 | `:162-163` | 2 |
| **合计** | | **51** |
| （需连带重写）P4→P2 或 P5 段标题与「动作」行 | `:139`、`:152` | 2 |

→ 改动跨度 `:57-163`，但**删减量约 51 行，不是 90 行**。这直接影响方案的工作量估算。

### 9.2 决策驱动因素（承接 §3）

1. **与 C52 处置范式保持一致**：删虚构契约、保留真实能力。第 4 批已就此达成结论，C56 不应另起一套判准。
2. **P4 已有设计出口（P4→P2）**，删 P5 不产生能力真空——删的是**承诺**，不是**能力**。
3. **不得引入 DB schema 变更**（§3.2）：`teaching_state.currentPhase` 有 CHECK 约束（`tables.dart:191-201`），真实现 P5 属表重建级迁移，需独立 ADR。
4. **P5 的产品形态超出当前架构能力**：P5 要求「连续 3 个月没有求助，教练主动发送问候」（`skills_advanced_outline_p5.dart:87`）——这是**主动触达**能力。当前是否为纯响应式对话架构，**未验证**（未排查是否存在推送/定时任务/后台调度）。
5. **影响面按阶段收窄**：P5 只在 P3/P4 出现（§9.1-b），不是全量用户的紧急问题——支持**独立排期**而非与 C54 捆绑。

### 9.3 候选方案

#### 方案 D：删 P5，承认 P4→P2 是唯一出口

**改什么（5 处文件）**
1. `skills_advanced_outline_p5.dart`：删 `:57-90`（P5 段）、`:110-116`（P5 态度）、`:154-156`（P5 回退）、`:162-163`（迁移约束 P5 两行）；把 `:139` 标题改为 `### P4 → P2（重新开始）`，`:146-150` 的「P4 → P5 条件」整块删除（该块 4 个条件均专为 P5 而设），`:152`「动作」行改为显式「在诊断块中填 `"suggested_phase": "P2_PRACTICE_LOOP"`」。
2. `skills_advanced_outline_p7.dart`：**必须同步删锚点常量** `_apHead5`（`:25`）、`_apAttitude5`（`:32`）、`_apMoveP5Back`（`:35`）——否则 `_apSlice`（`:39-44`）的 end 锚点 `_apMoveP5Back` 失配会 `e < 0` → `raw.substring(s)` 取到文末，把 P5 回退段重新带回 P4 档，造成**静默行为漂移**；`:78` 的 moveNext 切片 end 需改为文末或新锚点；`:15`、`:17-18` 注释同步更新。
3. `skills_diagnosis_p3.dart`：`:110` 表格行「| **P5 持续陪伴** | 风格深化是 P5 的核心工作之一… |」删除；`:151`「P4/P5 阶段的核心工作是**风格深化**」改为「P4 阶段…」。
4. `skill_layers.dart:83` 注释「(P3/P4/**P5** 完整指引)」改为「(P3/P4 完整指引)」。
5. 新增防复发断言（见 §9.5）。

**对 prompt 侧的影响**：advanced-phases 与 writing-style 两个 skill 文本变化。
**对代码侧的影响**：**零。**

**锚点快照影响**（按 `skill_prompt_anchor_test.dart:168-202` 的取锚方式推算）：

| 锚点 | 是否变 | 依据 |
|:--|:--:|:--|
| `skillContent['advanced-phases']` | ✅ 变 | `:180` 取 `skill.content`（**完整原文，非切片**），故 57-90 虽不注入也算进指纹 |
| `prompt['advanced_sensei']`（P3） | ✅ 变 | 迁移约束 `:158-164` 在 P3 档（p7.dart:79） |
| `prompt['advanced_p4_yuesheng']`（P4） | ✅ 变 | `:139-152` 与 `:158-164` 均在 P4 档 |
| `prompt['diagnosis_yuesheng']`（P2-diagn） | ✅ 变 | writing-style 挂在 `L2Mode.diagnosis`（`skill_layers.dart:59`），改了 `:110/:151` |
| 其余 5 个 prompt 指纹 | ❌ 不变 | 其余用例的 L2 mode 均不含这两个 skill（`resolveL2Mode`，`skill_layers.dart:155-196`） |
| 其余 5 个 `skillContent` 指纹 | ❌ 不变 | 另外 5 块未改 |

→ **「3 个变、11 个不变」是方案 D 改动被收窄在 P3/P4/diagnosis 档的硬证据**（见 §9.5）。

**影响既有测试**：`test/services/advanced_phases_phase_slice_test.dart` **两处必挂**——
- `:62` `expect(p4, contains('### P4 → P2（重新开始）或 P5（进入持续陪伴）'))`（标题被改）
- `:75` `expect(p4, contains(_slice('### P4 态度策略', '### P5 态度策略')))`（`_slice` 内部 `:23` 的 `expect(s, greaterThanOrEqualTo(0), reason: '原文缺锚点')` 会因 `### P5 态度策略` 被删而失败）
另 `:53`（P3 档不含 `## P5 持续创作陪伴`）删除后仍为绿，可保留作护栏。

**同轮双跳风险**：无（纯文本改动，不涉及迁移逻辑）。
**回滚成本**：**低**（文本还原 + 锚点重生成）。
**落地工作量**：**中**（5 个文件 + 2 处测试断言 + 锚点重生成 + 人工复查 diff）。

**风险**：丢掉「持续创作陪伴」这段产品设想。缓解：该设想代码侧从未存在（`_kValidPhases`/枚举/DB CHECK 三处皆无），删的是不可达承诺；如未来真要实现，按 §9.3 方案 F 走独立 ADR + DB 迁移，届时本文 §9 可作为需求底稿。

---

#### 方案 E：把 P5 内容改造为 P4 内部的形态（不引入新阶段）

**改什么**：把 P5 的三种模式——定期共读（`skills_advanced_outline_p5.dart:69-72`）/ 瓶颈研讨（`:74-77`）/ 风格深化（`:79-82`）——改写为 P4 复盘后的**三条下一周期可选路线**，挂进 P4 段（`skills_advanced_outline_p4.dart:129-160`）或作为 P4→P2 的分支指引。

**语义冲突（本方案的主要成本）**：P4 的定位是「**周期收尾**」——进步可视化 / 经验总结 / 问题归档 / **目标设定** / 能力地图（`skills_advanced_outline_p4.dart:133-139`），第五步是「下一阶段你想重点解决什么问题？设定一个具体的目标」（`:152-153`）。而 P5 的定位是「**终身陪伴，不设毕业**」（`skills_advanced_outline_p5.dart:86-88`：「P5 不设"毕业"——写作是终身的」）。两者硬塞进同一段，会让 P4 同时说「设定下一个周期目标」和「不设毕业」。

**对 prompt 侧的影响**：advanced-phases 的 P4 段 + P5 段整体重写，约 90 行。
**对代码侧的影响**：零。

**锚点快照影响**：`skillContent['advanced-phases']` + `prompt['advanced_p4_yuesheng']` + `prompt['advanced_sensei']`（若 P3 档也动）+ `prompt['diagnosis_yuesheng']`（若改 writing-style）。与方案 D 同量级或略大。

**影响既有测试**：同方案 D 的两处，另加 P4 段内容重写后 `:73` `expect(p4, contains(_slice('### P4 教学重点', '### P4 教学流程')))` 需复查。

**同轮双跳风险**：无。
**回滚成本**：**中**（文本可还原，但重写量大，回滚后需重新确认语义等价）。
**落地工作量**：**大**——内容重写 + 语义等价确认，属 `ADR-skill-orthogonal-model.md` §3.2 明列的「大工程，必须立项，不能顺手做」。

**风险**：**中高**。教学行为会被实质改变（P4 从「收尾设定目标」变成「收尾 + 提供三条长期陪伴路线」），需 LLM 实测确认 AI 不会在 P4 阶段就进入「终身陪伴」语气而跳过目标设定。

---

#### 方案 F：真实现 P5（代码侧加枚举 + 迁移链）

**改什么（清单，逐点核实）**
| 层 | 位置 | 改动 |
|:--|:--|:--|
| 枚举 | `lib/types/teaching_types.dart:6-11` | 加 `p5Companion('P5_COMPANION')` |
| 递进表 | `phase_transition.dart:9-15` | `_kPhaseOrder` 加值；`:21-25` `nextPhase` 自动跟随（P4→P5 变合法递进，P5 无下一阶段） |
| 解析白名单 | `diagnosis_parser.dart:24-30` | 加 `'P5_COMPANION'` |
| **DB schema** | `tables.dart:191-201` | **`currentPhase` 的 CHECK 约束只允许 P0–P4，需表重建级迁移**（drift 需新 `MigrationStrategy` + 建新表/拷数据/改名） |
| UI 标签 | `progress_service.dart:98-104` | `progressPhaseLabels` 加 P5 条目 |
| UI 消费 | `growth_detail_page.dart:374`、`progress_detail_page.dart:259`、`settings_page.dart:708` | 三处均走 `progressPhaseLabels[...] ?? ...`，加条目后自动跟随（**未逐一验证三处的渲染是否有阶段数假设**） |
| N 系门禁 | `phase_mapper_resolver.dart:152-206` | P5 在 N 系下归哪一档、走规则 1 还是规则 2，**当前无任何设计，需新决策** |
| 注入管线 | `skills_advanced_outline_p7.dart:61` | `phase != p3Training && phase != p4Review` 的裁剪判断需加 P5 档；`_apHead5`/`_apAttitude5`/`_apMoveP5Back` 锚点需改为「P5 档注入 P5 段」 |
| L2 路由 | `skill_layers.dart:189-191` | P5 走 `L2Mode.advanced` 还是新 mode，**未设计** |
| 子阶段 | `chat_service.dart:1115`、`:1175` | P5 是否重置 subphase，**未设计** |

**对 prompt 侧的影响**：无需删改（P5 描述变真实），但需新增 P5 档的注入规则。
**对代码侧的影响**：**核心模块（教学状态机 + DB schema）双改动**，按 AGENTS.md L110 需**独立 ADR**。

**锚点快照影响**：新增 P5 档 → `advancedPhasesContentFor` 的 P3/P4 分支不变（若只加 P5 分支），故 `prompt['advanced_sensei']` / `prompt['advanced_p4_yuesheng']` **可能不变**；但 `skillContent['advanced-phases']` 若因锚点调整而动则变。**是否新增 P5 prompt case 需与舰长确认**（新增会改变 `meta.promptCases`，属基线结构变更）。

**影响既有测试**：`evaluation_service_test.dart:225-310`（`validatePhaseTransition` 用例组：P4→P5 从非法变合法，需改断言；P5→P2/P3 需新增用例）、`chat_service_phase_migration_test.dart`（需补 P4→P5 / P5→P2 路径）、`advanced_phases_phase_slice_test.dart`（需加 P5 档断言）。

**同轮双跳风险**：**中**——P4→P5 变合法递进后，`chat_service.dart:1171-1173` 的自动迁移在 P4 将从「永不触发」变为「可触发」，需重新评估与 `path1Migrated`（`:1036`/`:1148`）的互斥，避免 P4→P5→P2 链式双跳。

**回滚成本**：**高**——代码可还原，但 DB 需**反向迁移**，且已落库 `currentPhase = 'P5_COMPANION'` 的会话要清理/降级。

**落地工作量**：**很大**，且含表重建级 DB 迁移。

**风险**：**高**。除工作量外还有两个未决项：① P5 要求主动触达（`skills_advanced_outline_p5.dart:87`），当前架构是否支持**未验证**；② P5 在 N 系的归属无设计，而 N 系门禁是 P 系迁移的前置（`chat_service.dart:1088-1096`），设计缺失会直接导致 P5 不可达——**即方案 F 可能修完仍走不通**。

### 9.4 方案对比与推荐

| 维度 | **D（删 P5）** | E（改造进 P4） | F（真实现 P5） |
|:--|:--|:--|:--|
| 消除 P4 出口死锁（§9.1-b） | ✅ | ✅ | ✅（但见下方风险） |
| 与 C52 处置范式一致 | ✅ | ❌（另起炉灶） | ❌ |
| DB schema 变更 | **无** | 无 | **有（表重建级迁移）** |
| 需独立 ADR | 否 | 否 | **是（AGENTS.md L110）** |
| 代码侧改动 | **零** | 零 | 核心模块多文件 |
| 语义冲突 | 无 | **有**（周期收尾 vs 终身陪伴） | 无 |
| 锚点快照影响 | 3 变 / 11 不变 | 3–4 变 / 10–11 不变 | 0–1 变（+可能的结构变更） |
| 影响既有测试 | 2 处断言必改 | 2–3 处必改 | 3 个测试文件需补/改 |
| 同轮双跳风险 | 无 | 无 | **中**（`:1171-1173` 从永不触发变可触发） |
| 回滚成本 | **低** | 中 | **高**（含 DB 反向迁移） |
| 落地工作量 | 中 | 大 | 很大 |
| 遗留风险 | 丢掉产品设想（可留作底稿） | 教学行为实质改变 | N 系归属未设计 → 可能修完仍不可达 |

**推荐：方案 D。**

**一句话理由**：P5 在代码侧的**三个门槛**（`TeachingPhase` 枚举 `teaching_types.dart:6-11`、解析白名单 `diagnosis_parser.dart:24-30`、DB CHECK `tables.dart:191-201`）**全部不存在**，而 P4 已有设计出口 P4→P2（`phase_transition.dart:41-43`）——所以正确动作是删掉这个不可达承诺（与 C52 同范式），而不是为一段 prompt 文本去改 DB schema。

**是否需要与 C54 方案 C 合并实施：否，独立排期；但共享一次锚点重生成，且建议 D 先落地。**

理由：
1. **改动面不重叠**：C54 方案 C 是**纯代码侧**（`phase_transition.dart` 加纯函数 + `chat_service.dart` 分支 + resolver 规则 3 收窄），**不动任何 skill 文本，锚点零影响**；C56 方案 D 是**纯 prompt 侧**（5 个 skill/配置文件），**不改任何代码**。合并实施没有共享的改动点，没有收益。
2. **但可共享一次锚点流程**：方案 D 必破锚点，需 `UPDATE_SNAPSHOTS=true` 重生成 + 人工复查 diff（`skill_prompt_anchor_test.dart:16`）。若 C54 最终也采纳了可选 prompt 澄清（§4-C 末尾），两次重生成可并为一轮复查。
3. **建议 D 先于 C54 的 LLM 实测**：方案 D 落地后，`suggested_phase` 的取值域从「prompt 说可填 P5 / 代码只认 P0–P4」收敛为一致，C54 §7.5 的实测不再需要考虑 P5 分支，判定更干净。

### 9.5 验证方式

**锚点（硬判据）**
`flutter test test/services/skill_prompt_anchor_test.dart` 重生成后，diff 必须**恰好**是以下 3 项，多一项少一项都说明改动溢出：
```
prompt.advanced_sensei.len / .fnv
prompt.advanced_p4_yuesheng.len / .fnv
prompt.diagnosis_yuesheng.len / .fnv
skillContent.'advanced-phases'.len / .fnv
```
其余 11 个锚点（5 个 prompt + 5 个 skillContent + `l3Inject` 4 条）**必须一字不变**。

**防复发护栏（新增，成本低）**
在 `test/services/advanced_phases_phase_slice_test.dart` 增加两条原文级断言：
```dart
expect(_raw, isNot(contains('P5')), reason: 'advanced-phases 不得再出现幽灵阶段 P5（C56）');
expect(skillRegistry['writing-style']!.content, isNot(contains('P5')), reason: 'writing-style 不得再出现幽灵阶段 P5（C56）');
```
并在 `test/services/skill_prompt_anchor_test.dart` 之外补一条 grep 型守护（或 CI 脚本）：`lib/` 下 `P5_` 出现次数必须为 0。

**切片测试同步**
- `:62` 断言改为 `expect(p4, contains('### P4 → P2（重新开始）'))`
- `:75` 改为 `expect(p4, contains(_slice('### P4 态度策略', '### 迁移约束')))`（或改用新的文末锚点）
- `:53` 保留（P3 档不含 P5 段）——删除 P5 后天然为绿，作为护栏
- 新增：P3/P4 两档 `expect(x, isNot(contains('P5')))`

**代码侧前提锁定（方案 D 不改代码，但应把死锁前提钉进测试）**
在 `test/services/evaluation_service_test.dart` 的 `validatePhaseTransition（M4-B）` 组（`:225`）补两条，把「P4 唯一出口」变成可执行契约：
```dart
expect(nextPhase(TeachingPhase.p4Review), isNull,
    reason: 'P4 无下一阶段（phase_transition.dart:23）——P4 出口只能是 AI 填 P2');
expect(validatePhaseTransition(TeachingPhase.p4Review, TeachingPhase.p2PracticeLoop), isTrue,
    reason: 'P4→P2 是 P4 的唯一出口（phase_transition.dart:41-43）');
```

**LLM 实测（复用导出件）**
用 `docs/audits/_prompt_dump/advanced_p4_yuesheng.txt`（或重新导出 P4 档）构造场景：「P4 复盘完成 + 所有核心症候 ≤L1 + 学员说『我想自己写，但希望有人看』」（即 `skills_advanced_outline_p5.dart:146-150` 的 4 个条件全部满足）。多次采样，断言：
> ① AI 输出中**不出现** `P5` / `P5_` 字样；
> ② 若输出 `suggested_phase`，取值**必须**是 `P2_PRACTICE_LOOP`（P4 唯一合法出口）。

实测前（改动前）同一场景应能复现「AI 填 P5 或含糊其辞」——若复现不了，说明 §9.1-b 的死锁推断需要降级为「理论风险」。**这是 §9.1-b 唯一尚未被实测验证的一环，建议实施前先做一次前测。**

**回归范围**
`flutter test` 全绿，重点：`advanced_phases_phase_slice_test.dart`、`skill_prompt_anchor_test.dart`、`evaluation_service_test.dart:225-310`；`chat_service_phase_migration_test.dart` 与 `writing_coach_panel_test.dart:496` 不受影响（方案 D 不改代码）。

### 9.6 本次核实的新发现（接续 §8，编号 N13 起，均未做任何修改）

**N13 — P4 出口存在死锁路径（方案 D 之外也应单独登记）。**
P4 的唯一出口是 AI 填 `P2_PRACTICE_LOOP`（`phase_transition.dart:41-43`），代码侧自动迁移在 P4 **永不触发**（`nextPhase` 返回 null，`phase_transition.dart:23`；`chat_service.dart:1171-1173` 的 `next != null` 守卫）。同时 P4 档 prompt 提供 P5 出口（`skills_advanced_outline_p5.dart:146-152`、`:162`），AI 若选 P5 则被 `diagnosis_parser.dart:181` 白名单**静默丢弃**（无日志），该轮零迁移。详见 §9.1-b。

**N14 — 切片逻辑自相矛盾：裁掉了 P5「段」，却注入了通往 P5 的「指令」。**
`skills_advanced_outline_p7.dart:17-18` 注释称 P5 段「不可达，两档均不注入」，但 `:78` 的 P4 moveNext 切片 `_apMoveP4Out.._apMoveP5Back` **包含 P4→P5 条件与填字段动作**（`skills_advanced_outline_p5.dart:146-152`），`:79` 的 moveConstraint（两档都追加）明文「P4→P5 允许进入持续陪伴模式」（`:162`）。且 `advanced_phases_phase_slice_test.dart:62` 已把这条**锁进断言**——修复时必须同步改测试，否则改不动。

**N15 — P5 引用不止 `advanced-phases` 一处，且另一处暴露面更广。**
`skills_diagnosis_p3.dart:110`（writing-style 表格行「| **P5 持续陪伴** | 风格深化是 P5 的核心工作之一… |」）与 `:151`（「P4/P5 阶段的核心工作是**风格深化**」）。`writing-style` 挂在 `L2Mode.diagnosis`（`skill_layers.dart:59`）与 `L2Mode.advanced`（`:88`），即 **P1 / P2-diagnosis / P3 / P4 均注入**——比 `advanced-phases`（仅 P3/P4）更广。且 writing-style **不在** phase3 六块锚点内（`skill_prompt_anchor_test.dart:30-37`），故改它不破 `skillContent`，只破 `prompt`。

**N16 — 真实现 P5 的硬门槛是 DB CHECK 约束。**
`tables.dart:191-201` 的 `currentPhase` CHECK 只允许 `'P0_ENGAGE'…'P4_REVIEW'` 五个值 → 需表重建级 drift 迁移。另 `progressPhaseLabels`（`progress_service.dart:98-104`）需加条目，其消费点在 `growth_detail_page.dart:374`、`progress_detail_page.dart:259`、`settings_page.dart:708` 三处（三处的**渲染逻辑是否有阶段数假设未逐一验证**）。

**N17 — P3 档也会收到 P4→P5 与 P5→P2/P3 的迁移约束。**
`skills_advanced_outline_p7.dart:79` 的 moveConstraint 是**无条件**追加（P3/P4 两档都加），故 P3 学员的 AI 已被告知一个不存在的阶段及其回退规则（`skills_advanced_outline_p5.dart:162-163`）。危害低于 P4 档（P3 档不含「填 suggested_phase 进 P5」的动作行），但同属幽灵引用。

**N18 — `skill_layers.dart:83` 的注释与切片实现方的判断不一致。**
该行注释写「`SkillRef('advanced-phases'), // ~4200 tokens (P3/P4/**P5** 完整指引)`」，而 `skills_advanced_outline_p7.dart:17` 已判定 P5「不可达」。两处对同一事实给出相反描述，是文档内部不一致（也说明 P5 幽灵状态**早已被实现方识别，但只做了局部处理**）。

**N19 — 与台账 C58 构成「双向偏差」，建议反向验证双向做。**
本 ADR §8-N11 记的是「prompt 的 `suggested_phase` 取值只列 P0/P1/P2，代码允许 P3/P4」（`skills_l1_core_p2.dart:111` vs `diagnosis_parser.dart:24-30`）；台账 C58 记的是同一处（`docs/audits/Skill话术与提示词-综合审阅（合并版）-2026-08-30.md:1471-1483`），并已点明方向性：「**C58 是 prompt 比代码窄**（误导 AI 不敢填）；**C56（P5）是 prompt 比代码宽**（承诺了不存在的阶段）。两个方向都会出错，反向验证必须双向做」（同文档 `:1488-1491`）。→ **建议把「枚举一致性」作为一项独立的双向校验加入验收**：prompt 声明的取值集合与 `_kValidPhases` 必须**双向相等**，而不是单向包含。

**N20 — 迁移约束里有一句是准确的，不要误删。**
`skills_advanced_outline_p5.dart:164`「不允许跳过（**P2→P4 或 P2→P5 会被拒绝**）」与代码一致（`validatePhaseTransition` 只放行 +1，`phase_transition.dart:39`）。改动 `:158-164` 时这一行应**保留**（P5 提法或需改写为「P2→P4 会被拒绝」）。这说明 `skills_advanced_outline_p5.dart` 的 P5 相关内容**并非全错**，需逐行甄别，不可整段删除。

---

*本 ADR 生效条件：舰长确认。确认后按 §7 建测试、再动代码；实施顺序建议 C-3（独立 bug）→ C-1 → C-2 → C′（可选）→ prompt 澄清（可选，独立排期）。*
