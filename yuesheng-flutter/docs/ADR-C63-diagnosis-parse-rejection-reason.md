# ADR-C63：诊断块解析失败的可观测性（N1 / N26 / N5 / N8）

- 状态：**已采纳并实施**（舰长长期授权「未决策项按你推荐的来」；本批方案为推荐方案 A+）
- 日期：2026-09-02
- 关联：AGENTS.md L124（核心模块改动先写 ADR）、R-010 最小化范围、R-019 代码规范、
  R-027 四道门禁、R-028 边界防御
- 影响模块：`lib/contracts/diagnosis_capability.dart`、`lib/services/diagnosis_parser.dart`、
  `lib/services/chat_service.dart`
- 覆盖条目：**N1 / N26 / N5 / N8**（N 系列 33 条中的第一批）
- 本文所有结论均标注 `file:line`；凡未读到代码的一律标「未验证」，不推断为事实。

---

## 1. 背景与问题陈述

### 1.1 现象：诊断块输出了、症候也识别了，但阶段迁移不发生，且全程无报错

这是 N13 / N26 / N38 三条独立发现的**共同放大器**，三者从三个视角指向同一处代码：

| 来源 | 原话 | 视角 |
|:--|:--|:--|
| N13 | 「AI 若填 P5 则被白名单**静默丢弃**（无日志），该轮零迁移」 | 代码侧（阶段体系） |
| N26 | 「prompt 说『会被拒绝』，代码是静默丢弃（无日志）→ 模型以为有反馈回路，实际没有 → **会一直填下去，每一轮都静默失败**」 | 交叉印证 |
| N38 | 「suggested_phase 缺失时静默忽略、无告警……**块输出了、症候也识别了，但阶段迁移不发生，且全程无报错**」 | C53 根因 |

N26 的那句「**这解释了为什么是永久卡死而非抖动一次**」是本 ADR 的核心判据：
静默丢弃不是「偶发失败」，而是**无反馈回路的确定性死锁**——模型永远不会知道自己填错了。

### 1.2 现状：日志记了「结果」，没记「原因」

`chat_service.dart:2207-2210` **已经**在记录诊断成败：

```dart
final rawParse = _diagnosis.parseDiagnosis(fullContent);
debugPrint(
  '[ChatService] 步骤9: parseDiagnosis | displayContent 长度=${...} | '
  'diagnosis=${rawParse.diagnosis != null ? "有(...)" : "无"}',
);
```

它回答了「**失败了吗**」，但没有回答「**为什么失败**」。原因信息在
`diagnosis_parser.dart` 内部产生后就丢了——这正是 C53「查不到根因」的直接成因。

下游 `_recordDiagnosisOutcome`（`chat_service.dart:199-218`）只按成败计数，
连续失败达阈值插诊断失败卡，**同样不知道原因**，因此也无法区分：

- (a) AI 压根没输出 `[YS_DIAGNOSIS]` 块（prompt 没生效 / 模型没遵守）
- (b) AI 输出了块，但被字段校验拒掉（schema 契约问题 / 模型填错值）

这两类的修法完全不同，但当前日志里**长得一模一样**。

### 1.3 逐行盘点：静默点是 12 处，不是此前台账记的 8 处

台账 A.12.9 记 N1 为「诊断失败静默丢弃（`chat_service.dart:2199-2203`）」，
但真正产生静默的是被它调用的纯函数。回源码逐行数：

**A 组 —— 整块丢弃（`diagnosis` 变 null，共 12 处）**

| # | `file:line` | 触发条件 | 建议原因码 |
|:--|:--|:--|:--|
| 1 | `diagnosis_parser.dart:95` | 有开始标记无结束标记 | `marker_end_missing` |
| 2 | `diagnosis_parser.dart:106` | `jsonDecode` 抛异常（**空 `catch (_)`**） | `json_decode_failed` |
| 3 | `:129` | 根对象非 Map | `root_not_object` |
| 4 | `:134` | `syndromes` 非数组 | `syndromes_not_list` |
| 5 | `:137` | `syndromes[i]` 非对象 | `syndrome_item_not_object` |
| 6 | `:143` | `syndrome_id` 非字符串 | `syndrome_id_not_string` |
| 7 | `:144` | `name` 非字符串 | `syndrome_name_not_string` |
| 8 | `:145-146` | `severity` 非字符串 / 不在 L1-L3 | `syndrome_severity_invalid` |
| 9 | `:148` | `evidence` 非字符串数组 | `syndrome_evidence_invalid` |
| 10 | `:149` | `explanation` 非字符串 | `syndrome_explanation_not_string` |
| 11 | `:164-166` | `suggested_actions` 非字符串数组 | `suggested_actions_invalid` |
| 12 | `:172` | `confidence` 非数字 / 越界 | `confidence_invalid` |

**B 组 —— 字段级静默丢弃（整块仍通过，但字段变 null，共 3 处）**

| # | `file:line` | 触发条件 | 后果 |
|:--|:--|:--|:--|
| 13 | `:195` | `suggested_phase` 不在 `kValidPhases` | **阶段迁移不发生** |
| 14 | `:201` | `suggested_beginner_level` 不在白名单 | 零基础等级不推进 |
| 15 | `:207` | `teaching_mode` 不在白名单 | 教学模式不生效 |

**B 组才是 N13 的确切机制**：模型填 `P5_COMPANION`（N22 实测：模型自造字符串），
`:195` 的白名单把它静默改成 `null`，**整块照样落库、诊断照常显示、UI 毫无异样**，
唯独阶段迁移永远不发生。比 A 组更隐蔽——A 组至少还有「诊断失败卡」。

> ⚠️ 台账原记「8 处」为**计数偏差**，实际 15 处（12 + 3）。本 ADR 以逐行盘点为准。

### 1.4 一条此前未登记的潜在崩溃路径（登记为 N39，不在本批范围）

`diagnosis_validator.dart:309-311`：

```dart
suggestedPhase: TeachingPhase.fromString(
  data['suggested_phase'] as String?,
),
```

`as String?` 是硬 cast。而 `validateDiagnosisSchema`（`:67-167`）**只校验
syndromes / suggested_actions / confidence 三项，完全不校验 `suggested_phase` 的类型**
（校验在 `:154` 就结束了，见 `:148-158`）。

→ 若模型输出 `"suggested_phase": 123`，schema 判定 valid，进入 `_mapToParsedDiagnosis`
→ `as String?` 对 `int` 抛 `TypeError`。

**可达性（已核实，非推断）**：
- 生产调用点 2 处——`chat_service.dart:559` 与 `:2243`，**均被 try/catch 包裹**
  （`:566-570` / `:2250-2252`），崩溃当前被兜住，表现为「沿用 rawParse」。
- 公共 API 直接调用点 2 处——`test/contracts/diagnosis_capability_test.dart:39/54`，
  传的是空 map `{}`，不触发。

结论：**潜在，当前不崩溃**。但 `validateDiagnosisOutput` 是 `DiagnosisCapability`
契约上的公开方法（边界层），按 R-028「边界层必须校验」应修。

**不进本批的理由**：修它会改变 `displayContent` 行为——当前因抛异常而跳过的
NL 清洗（`validation.displayContent`）在修复后会生效。这属**行为变更**，
与本批「零行为变更」的定位冲突，需独立评估与真机复核。

→ 登记 **N39**，下一批处理。修法预告：把 `as String?` 换成安全读取（非 String 一律 null），
与 parser 侧 `:195` 的语义对齐。

### 1.5 实施中发现的同类崩溃（N40，本批顺带修）

`diagnosis_parser.dart:157` 原实现：

```dart
readerImpact: s['reader_impact'] as String?,
```

与 N39 是**同一个 bug 类**（硬 cast 可选字段），但位置更糟——它在本批
重写的那几行里，且 `parseDiagnosis` 在文件头第 4 行声明「**不 throw**」，
这条 cast 直接违反了自己的声明。模型填 `"reader_impact": 123` 即抛 `TypeError`。

**本批顺带修**（3 行）：改成 `is String` 安全读取。

**为什么这个不算「行为变更」而 N39 算**：
- N40 的当前行为是**崩溃**，修复后是该字段按缺失处理——崩溃路径上不存在
  任何依赖它的正确行为，没有测试能建立在崩溃之上。
- N39 的当前行为是**被 try/catch 兜住后跳过 NL 清洗**，是一个「能跑通的结果」，
  改它会改变 `displayContent` 的实际取值。

判别式：**崩溃修复 ≠ 行为变更；改变成功路径的输出 = 行为变更。**

---

## 2. 候选方案

### 方案 A：只加日志（在纯函数内部 `debugPrint` + `ErrorHandler`）

改动点最少，直接消除静默。

**驳回**。`diagnosis_parser.dart:4` 文件头明文声明：

```
// 纯函数，无副作用，不 throw
```

在纯函数里写日志等于**削弱一条既有契约**，而这条契约正是它能被 337 行契约测试
（`test/services/diagnosis_contract_test.dart`）干净覆盖的前提。为修 N1 去破
另一条契约，是净负收益。

### 方案 B：纯函数回传原因码，由调用方记录（**推荐**）

`_validateDiagnosis` 返回「结果 + 原因码」，`ParseResult` 携带它，
`chat_service` 接进 `:2209` 那条既有日志。

优点：
1. 守住 `diagnosis_parser.dart:4` 的纯函数声明；日志仍落在服务层（它本就是 IO 层）
2. **原因码可被测试直接断言**——比捕获 `debugPrint` 输出可靠一个量级
3. 让 A 组 / B 组 / 正常三类在日志里可区分，`_recordDiagnosisOutcome` 未来可直接按原因码分流

### 方案 C：回传原因码 + 顺带收紧校验（N5 拦截非法 `syndrome_id`）

**部分采纳**：N5 只做**观测**，不做**拦截**。理由见 §3.2。

---

## 3. 决策

### 3.1 采纳方案 B —— `ParseResult` 携带原因码，零行为变更

`lib/contracts/diagnosis_capability.dart:84-88` 扩为：

```dart
class ParseResult {
  final String displayContent;
  final ParsedDiagnosis? diagnosis;

  /// 整块被拒的原因码（null = 未被拒）。
  ///
  /// 仅当 AI **确实输出了** [YS_DIAGNOSIS] 块、但解析或校验失败时才有值。
  /// 普通聊天（无块）为 null —— 这与「块输出了但没落库」是两回事，不可混淆，
  /// 混淆会把 prompt 未生效误判成 schema 问题（或反过来）。
  final String? rejectReason;

  /// 非阻断观测码。出现这些码时**整块仍然通过**，行为与改造前完全一致。
  final List<String> notes;

  const ParseResult({
    required this.displayContent,
    this.diagnosis,
    this.rejectReason,
    this.notes = const [],
  });
}
```

零行为变更的论证：`displayContent` 与 `diagnosis` 两个既有字段的取值
在**任何输入下都与改造前逐字节相同**；新增的两个字段是纯附加。
全仓 21 处 `ParseResult(` 构造点因新字段有默认值而**无需改动**。

**原因码命名**：全部 snake_case，与项目既有风格一致；只记码不记值
（避免长文本进日志，值可从 `fullContent` 还原）。

### 3.2 N5 —— 只观测，不拦截

`diagnosis_parser.dart:143` 当前只判 `syndromeId is! String`，不校验格式，
而 `kSyndromeCodeRe = RegExp(r'P0\d{2}')` 这个现成武器**已在
`diagnosis_validator.dart:17` 存在，parser 侧从未调用**。

> **落地修正（§7 同记）**：本批**只复用它的模式串，不复用实例**——另立了锚定版
> `_kSyndromeIdRe = RegExp(r'^P0\d{2}$')`。原因：那个正则是为
> 「在正文里找泄漏的编号并替换」设计的（`:179`），非锚定是它的正确形态；
> 但拿它做字段校验时 `hasMatch('XP003')` 会命中，**等于没校验**。
> 已补一条测试专门守这个区分（「N5 锚定」用例）。

**不拦截的理由**：一旦拦截，模型填了非 `P0xx` 格式的 id 就会导致
**整块诊断被丢弃**——这直接放大 C53「输出了但不落库」，与本批要解决的问题同向恶化。

**观测的价值**：`syndrome_id` 填成中文名（如 `"情绪标签化"`）时，当前会
通过解析、落到 `Syndrome.syndromeId`，随后在 `resolveSyndromesBatch` 之类的
按 id 查找处静默失配。这是真实危害，但**危害程度未知**——需要先测量发生率。

→ 记入 `notes`：`syndrome_id_format`。与 `_kMutexSyndromePairs`
（`diagnosis_validator.dart:40-57`）「warning 级起步，观察误伤率后再决定是否升级」
是同一条方法论。

### 3.3 N8 —— 不合并，改用护栏测试断言两条路径等价

N8 原描述：两条 `suggested_phase` 解析路径校验强度不一致
（`diagnosis_parser` 走白名单 / `diagnosis_validator` 不走）。

**不合并的理由**：合并是行为变更，且两条路径的输入域不同
（parser 吃任意 AI 输出，validator 吃已通过 schema 的 Map）。强行统一会
让其中一侧承担不属于它的职责。

**改用护栏**：`TeachingPhase.fromString` 遍历枚举 value 匹配、非法值返回 null
（`lib/types/teaching_types.dart`），**本身就是白名单语义**。所以二者
「形式不一致但语义等价」。这个等价性此前**从未被断言**，属隐性假设。

→ 补测试：对 parser 白名单 `kValidPhases` 的每个合法值 + 一组非法值，
断言两条路径产出相同结果。把隐性假设变成机器可校验的契约。

### 3.4 N6 —— 裁决「暂不修」，附复评触发条件

N6：诊断块字段名大小写硬编码，模型大小写漂移即解析失败。

**不修的理由（两条，均为实证而非偏好）**：

1. **零实证观测**。N22 实测到的是模型**造值**（`P5_COMPANION` / `P5_ACCOMPANY`），
   不是**改键名**（`Syndrome_ID`）。键名漂移目前是**假说，无观测支撑**。
2. **方向相反**。加大小写容错 = 用代码兜住 prompt 契约缺陷，与第 8 批
   「让契约可被机器校验」（N19 四向护栏 / E.8 promptStyle）的方向相反，
   会让 prompt 侧问题更难被发现。

**复评触发条件（写入 ADR 以便未来可判定）**：N39 修复后若观测到
`notes` 中 `syndrome_id_format` 高频出现，或真机日志中出现键名大小写漂移，
则重开 N6。在此之前不修。

---

## 4. 实施范围

| 文件 | 改动 | 行为变更 |
|:--|:--|:--|
| `lib/contracts/diagnosis_capability.dart` | `ParseResult` 加 2 个可选字段 | 无（默认值，21 处构造点零改动） |
| `lib/services/diagnosis_parser.dart` | 12 处整块丢弃挂原因码、3 处字段丢弃挂 note、N5 挂 note；抽 `_validateSyndromes`；**N40**：`reader_impact` 硬 cast 改安全读取（§1.5） | 无（N40 为崩溃修复，见 §1.5 判别式） |
| `lib/services/chat_service.dart` | `:2209` 与 `:543` 的日志接原因码 | 无（日志文本） |
| 新建 `test/services/diagnosis_reject_reason_test.dart` | 15 个原因码逐一覆盖 + N8 等价性护栏 | — |

**不在本批**：N39（validator 侧硬 cast，§1.4）、N6（§3.4）、
`_recordDiagnosisOutcome` 按原因码分流（下游改造，需独立评估）。

### 4.1 关于 R-019 的诚实说明

`_validateDiagnosis` 当前 137 行（`:128-264`），**已超 R-019 的 50 行硬限**，
是既有债务。本批**只抽 `_validateSyndromes`**（`:132-160`，内聚度最高、
含 6 个拒绝点），不全面重构——全面重构会放大本批风险面，且与 R-010 冲突。
重构后该函数仍超限，**如实登记为残留债务，不声称已合规**。

---

## 5. 验证标准

1. **锚点快照字节不变**：`test/snapshots/skill_prompt_anchor.json` 零改动
   （本批不碰 prompt，锚点不变是「零行为变更」的硬证据）
2. **原因码全覆盖**：15 个静默点各有一条断言，逐一构造触发输入
3. **变异测试**：至少 3 组（移除一处原因码 / 改一个码名 / 放开 N5 拦截），
   护栏必须能失败——不能失败的护栏等于没加
4. **四道门禁**：format → analyze → 循环依赖 → test（范围内全跑，范围外抽测）
5. **CRLF = 0**：`git hash-object` 逐个 blob 核验

---

## 6. 风险与回滚

- **风险等级：低**。改动全部是「附加信息 + 日志文本」，不改变任何控制流与返回值。
- **回滚**：单 commit 可整体 revert；`ParseResult` 新字段有默认值，
  即使只回滚 parser 不回滚契约也不会编译失败。

---

## 7. 登记项

- **N39**（新增）：`diagnosis_validator.dart:309` `as String?` 硬 cast 潜在崩溃。
  生产调用点均被 try/catch 兜住，当前不崩溃；修法会改变 `displayContent` 行为，
  需独立评估。下一批。
- **N40**（新增，本批已修）：`diagnosis_parser.dart:157` `reader_impact` 硬 cast，
  违反本文件头「不 throw」声明。同 bug 类见 N39。
- **N1 / N5 / N8 / N26**：本批闭环（N5 仅观测不拦截）。
- **N6**：裁决暂不修，复评条件见 §3.4。
- **R-019 残留**：`_validateDiagnosis` 抽取后仍超 50 行，如实登记。

## 8. 实施结果（2026-09-02 补记）

| 项 | 结果 |
|:--|:--|
| 静默点盘点 | 15 处（12 整块 + 3 字段），台账原记 8 处为计数偏差 |
| 新增测试 | `test/services/diagnosis_reject_reason_test.dart`，29 条全绿 |
| 变异测试 | 3/3 拦住（移除原因码 / 改 note 码名 / N5 改拦截） |
| 四道门禁 | format 0 changed · analyze No issues · circular 289 OK · test 范围内 172 + 范围外抽测 83 |
| 锚点快照 | 零改动 → 零行为变更的硬证据 |
| 顺带修复 | N40（崩溃） |
