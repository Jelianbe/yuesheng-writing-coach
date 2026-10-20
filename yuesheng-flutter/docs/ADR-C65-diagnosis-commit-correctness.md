# ADR-C65：诊断落库正确性（N2 成功不落库 / N3 锁定可绕过）

- **状态**：已实施
- **日期**：2026-09-02
- **涉及模块**：诊断解析 / 落库 / 教学焦点（核心模块，触发 AGENTS.md:124 的 ADR 门禁）
- **相关**：ADR-C63（解析可观测性）、ADR-C64（类型漂移）

---

## 1. 结论先行

| 项 | 裁决 | 依据 |
|:--|:--|:--|
| **N2** 诊断成功不落库 | **修**（缺陷修复） | 代码与自身注释声明的设计意图不符 |
| **N3-a** `current_teaching_focus_id` 未校验 ∈ syndromes | **修**（置 null + 留痕） | prompt 三处明写契约；且 prompt 已声明「缺失时走 fallback」，置 null 是**契约内既有行为** |
| **N3-b** `DiagnosisLock.minConfidence` / `minEvidenceCount` 零使用 | **只观测不拦截** | 拦截无契约依据，且会丢弃诊断，与 N5 裁决同向恶化 |

三条统一用 ADR-C64 §3 建立的判别式：

> 先判定当前输出是否符合该函数的**契约 / 设计意图**——
> 符合 → 改它是行为变更；不符合 → 改它是缺陷修复。

---

## 2. N2：诊断成功也可能不落库

### 2.1 事实链（file:line 均逐条核实）

`chat_service.dart` 步骤 10 的空响应判定：

```dart
// :2343-2346  注释声明的设计意图
//   - diagnosis 解析成功 或 已落库实体 → 说明可能被协议块（YS_DIAGNOSIS/YS_ENTITY）
//     占据首位，拦截器 displayLength=0 导致 combinedContent 空 → 给默认文案「诊断完成。」继续。
bool treatAsValid = false;
if (combinedContent.trim().isEmpty &&
    _ensureOutlineService() != null &&        // ← 前置条件 A
    primaryRef?.refType == 'chapter') {       // ← 前置条件 B
  if (diagnosis != null) {
    treatAsValid = true;
  } else { ... _readOutlineEntityCount ... }
}
if (combinedContent.trim().isEmpty && !treatAsValid) {
  callbacks.onError('AI 返回为空');
  return (aborted: true, ..., diagnosis: diagnosis, ...);   // :2363 diagnosis 非 null
}
```

调用方：

```dart
if (parsed.aborted) return;                              // :3051
await _commitDiagnosisAndSuggestions(...);               // :3054 ← 步骤 11 落库
```

**后果**：`diagnosis` 非 null 却被 `aborted` 提前 return，**步骤 11 的 `commitDiagnosisWithHistory` 永不执行**——AI 输出了合法且完整的诊断块，用户收到「AI 返回为空」，诊断永久丢失。

### 2.2 触发条件与可达性

同时满足四点即命中：

1. `combinedContent.trim().isEmpty` —— AI 只输出诊断块、或协议块占据首位导致 `displayLength=0`
2. `diagnosis != null` —— 诊断块本身合法
3. **前置条件 A 或 B 不成立** —— 未装配大纲服务，或当前主引用不是 `chapter`

第 3 点是关键：注释说「diagnosis 解析成功就该放宽」，代码却额外要求「且装配了大纲服务且是章节」。
**诊断能否落库，与有没有装配大纲服务毫无关系。**

补充证据：`_readOutlineEntityCount`（`:539-551`）内部第一行就是 `if (outlineService == null) return 0;`——
它自己已经判空，外层再加一道 `_ensureOutlineService() != null` 对 `diagnosis != null` 分支纯属多余。

### 2.3 修法

```dart
bool treatAsValid = false;
if (combinedContent.trim().isEmpty) {
  if (diagnosis != null) {
    treatAsValid = true;                    // 与注释一致：无条件放宽
  } else if (_ensureOutlineService() != null &&
             primaryRef?.refType == 'chapter') {
    final c = await _readOutlineEntityCount(primaryRef!.refId);
    if (c > 0) treatAsValid = true;
  }
}
```

- `diagnosis != null` 分支去掉两个无关前置条件
- 实体计数分支**原样保留**两个前置条件（`primaryRef!.refId` 依赖 `primaryRef != null`，由 B 保证）
- 三空齐发（正文空 + 诊断空 + 实体空）→ 仍走 `onError`，RN 原语义不动

### 2.4 为什么是缺陷修复不是行为变更

用 §1 判别式：注释 `:2343-2346` 白纸黑字写「diagnosis 解析成功 → 给默认文案继续」，
实际代码却给 `diagnosis != null` 加了一个与诊断无关的前置条件。
**当前输出不符合自身注释声明的设计意图 → 缺陷修复。**

用户可见变化：原本 `onError('AI 返回为空')` 的场景，改为写入「诊断完成。」并落库 + 出卡片。
诊断确实完成了，报错才是误报。

---

## 3. N3-a：`current_teaching_focus_id` 未校验「∈ 本轮 syndromes」

### 3.1 prompt 侧契约（三处明写）

| 位置 | 原文 |
|:--|:--|
| `skills_l1_core_p2.dart:124` | 必须从本轮 syndromes 中选取……**缺失时走 fallback 优先级表** |
| `syndrome_kb_content.dart:77` | 当前教学焦点症候 ID（如 P019，必须从 syndromes 中选取） |
| `syndrome_kb_content.dart:99` | 必须从本轮 syndromes 中选取 |

### 3.2 代码侧：零校验

```dart
// diagnosis_parser.dart:354-355
final ctf = teachingPlan['current_teaching_focus_id'];
if (ctf is String) currentTeachingFocusId = ctf;       // 只验类型，不验成员

// diagnosis_validator.dart:331 / 349
final focusIdRaw = teachingPlan?['current_teaching_focus_id'];
...
currentTeachingFocusId: focusIdRaw is String ? focusIdRaw : null,   // 同样
```

### 3.3 绕过链条（纯代码可复现，无需真机）

```
AI 输出 syndromes:[P012]，却填 current_teaching_focus_id = "P007"
  ↓ parser :355 只验 is String → 放行
  ↓ commitDiagnosis 落库 diagnosis_results.current_teaching_focus_id = P007
  ↓ 下轮 chat_service :1346  getLatestTeachingFocus  →  P007
      （diagnosis_repository.dart:323-326：return latest?.currentTeachingFocusId）
  ↓ focus_resolver :246-249  candidateFocusId = aiSuggestedFocusId = P007
  ↓ focus_resolver :249-276  校验 1「在池中」：P007 是历史 active_problem → 通过
  ↓ 焦点切到 P007 —— 原锁定症候 P012 被绕过
```

**关键在最后一步**：`focus_resolver` 的「在池中」校验看似兜住了，实际兜不住——
`commitDiagnosis`（`diagnosis_repository.dart:154-175`，注释 `:99` 明写「DAO 只负责落库，不做业务校验」）
会把本轮诊断的每个症候 UPSERT 进 `active_problem`，**落库先于校验**，池子已被污染。

### 3.4 修法：置 null + 留痕，不阻断落库

```dart
// parser / validator 两侧一致处理
if (ctf is String) {
  if (syndromeIds.contains(ctf)) {
    currentTeachingFocusId = ctf;
  } else {
    currentTeachingFocusId = null;              // 置 null → 走 fallback
    notes.add('focus_not_in_syndromes');        // 留痕
  }
}
```

**安全性由 prompt 自身保证**：`skills_l1_core_p2.dart:124` 明写「缺失时走 fallback 优先级表」——
置 null 走 fallback 是**契约内既有行为**，不是新造路径。fallback（`focus_resolver._selectFallback`）
按优先级表从本轮症候中选，比 AI 指定的越界 id 更合理。

**不阻断诊断落库**：只影响焦点选择，不丢弃 `syndromes`。遵守 ADR-C63「不放大『输出了但不落库』」。

### 3.5 已识别的测试影响

`test/services/diagnosis_type_drift_test.dart:262` 用 `current_teaching_focus_id: 'F001'`，
而 `F001` 不在该用例的 syndromes 中——加校验后会被置 null，`:275` 的断言失效。

该用例本意是「合法 String 值不被误判为漂移」。修法：把 `F001` 换成 syndromes 中真实存在的 id
（保留原测试意图，且更贴近契约）。**不是删断言绕过去。**

---

## 4. N3-b：`DiagnosisLock` 阈值零使用 —— 裁决只观测

### 4.1 事实

```dart
// shared_constants.dart:50-55
class DiagnosisLock {
  static const double minConfidence = 0.7;
  static const int minEvidenceCount = 2;
  static const int consecutiveFailThreshold = 2;   // ← 有用
  static const int disputeThreshold = 2;           // ← 有用
}
```

grep `lib/` + `test/` 结果：

- `minConfidence` —— **仅定义处命中，零使用点**
- `minEvidenceCount` —— **仅定义处命中，零使用点**
- `consecutiveFailThreshold` / `disputeThreshold` —— `diagnosis_service.dart:109-116` 正常使用

同类的四个常量，两个接线、两个悬空。**解锁有阈值，锁定没有门槛。**

### 4.2 为什么拦截无依据

| 常量 | prompt 侧对应 | 性质 |
|:--|:--|:--|
| `minConfidence = 0.7` | `skills_l1_core_p2.dart:113`「0.0-1.0，**0.7+ 为高置信**」 | 数值吻合，但这是**语义描述**，不是「低于 0.7 不得落库」的禁令 |
| `minEvidenceCount = 2` | `skills_l1_core_p3.dart:11`「evidence (string[])：文本证据」 | prompt 侧**无任何条数要求** |

`minConfidence` 数值虽与 prompt 吻合，但 prompt 从未承诺低置信度诊断不得落库。
在没有 prompt 配合的情况下单边收紧，会让 confidence=0.6 的合法诊断整块消失——
**与 N5「只观测不拦截」的裁决同向恶化**（N5 的结论：放大「输出了但不落库」比漏拦更糟）。

`minEvidenceCount` 更弱：prompt 侧完全无对应要求，属代码侧单方面想象。

### 4.3 裁决

**只观测不拦截**：落库前计算并留痕（低置信 / 证据不足），不改 `valid`、不丢弃诊断。
待观测数据积累后，若确认 AI 普遍输出高置信诊断（即拦截不会误伤），再评估是否转为拦截。
届时**必须先补 prompt 侧禁令**（明确写「confidence < 0.7 时不要输出诊断块」），
否则又是「代码单边收紧、AI 不知情」的循环。

---

## 5. 改动清单

| 文件 | 改动 |
|:--|:--|
| `lib/services/chat_service.dart` | N2：`treatAsValid` 判据——`diagnosis != null` 分支去掉无关前置条件 |
| `lib/services/diagnosis_parser.dart` | N3-a：focus id 校验 ∈ syndromes，越界置 null + note |
| `lib/services/diagnosis_validator.dart` | N3-a：同上（两条解析路径必须一致，否则重演 N8 的老问题） |
| `test/services/diagnosis_lock_contract_test.dart` | 新建护栏 |
| `test/services/diagnosis_type_drift_test.dart` | 修正 `F001` → 合规 id（保留原测试意图） |

**不改**：`DiagnosisLock.minConfidence` / `minEvidenceCount` 的消费方（N3-b 只观测，本批不接线）。

---

## 6. 验证与代价

- **四道门禁**：format 0 changed（`--set-exit-if-changed` 退出码经重定向取真值，
  不接管道——V4.5 陷阱）/ analyze No issues / circular 289 OK / test
- **实测数据**：范围内 **240 passed**（诊断链路 148 + chat_service 92）·
  范围外抽测 **184 passed**（含 `focus_resolver_coverage` + `phase_mapper_resolver`
  ——N3-a 的落点会影响 focus-resolver 的输入，必须回归）·
  锚点快照**零改动**
- **变异测试**：3 组**全部拦住**
  - A：parser 越界校验条件恒真
  - B：validator 成员检查恒真
  - C：N2 恢复旧实现（把无关前置条件加回 `diagnosis != null` 分支）
- **零回归断言**：
  - 合规 focus id（∈ syndromes）逐字段不变
  - N2 的三空齐发场景仍 `onError`（RN 原语义不动）——由对照组用例守护

代价：约 25 行生产代码 + 1 个测试文件；不引入新依赖；不改公开签名。

---

## 7. 残留

- **N3-b 未接线**：本批只登记观察口径，未加观测代码——避免为「可能永远不看」的数据
  增加常驻开销。转为拦截前，先补 prompt 侧禁令（§4.3）。
- **N2 的 UI 影响未实测**：本批改变的是失败路径（onError → 成功落库），
  需真机确认 UI 对「诊断完成。」+ 卡片的呈现无异常。属行为层，代码侧无法自证。
