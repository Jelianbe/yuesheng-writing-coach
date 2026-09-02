# ADR-C64：validator 侧可选字段硬 cast（N39）——反转 ADR-C63 的推迟裁决

- 状态：**已采纳并实施**（舰长长期授权「未决策项按你推荐的来」；本批方案为推荐方案 C）
- 日期：2026-09-02
- 关联：ADR-C63 §1.4（被本文反转的裁决）、AGENTS.md L124（核心模块改动先写 ADR）、
  R-010 最小化范围、R-019 代码规范、R-027 四道门禁、R-028 边界防御
- 影响模块：`lib/services/diagnosis_validator.dart`、`lib/types/teaching_types.dart`
- 覆盖条目：**N39**（主）+ **N40 补完**（共享类型层同源点，ADR-C63 遗漏）
- 本文所有结论均标注 `file:line` 或标注实测来源；凡未验证的一律标「未验证」，不推断为事实。

---

## 1. 背景：ADR-C63 §1.4 的裁决，及其为何站不住

### 1.1 原裁决原文

ADR-C63 §1.4 登记 N39 后写下的推迟理由：

> **不进本批的理由**：修它会改变 `displayContent` 行为——当前因抛异常而跳过的
> NL 清洗（`validation.displayContent`）在修复后会生效。这属**行为变更**，
> 与本批「零行为变更」的定位冲突，需独立评估与真机复核。

同节还给出了判别式：

> **崩溃修复 ≠ 行为变更；改变成功路径的输出 = 行为变更。**
> - N40 的当前行为是**崩溃**，修复后是该字段按缺失处理
> - N39 的当前行为是**被 try/catch 兜住后跳过 NL 清洗**，是一个「能跑通的结果」

### 1.2 反转理由（实测，非推断）

写 ADR-C63 时我按代码结构推断「跳过 NL 清洗」只是「降级」。**这次实测证明它是缺陷。**

探针（临时文件，已删）复刻 `chat_service.dart:588-596` 的 try/catch 结构，
输入 `displayContent='正文 P012 泄漏'` + `next_focus: 123`：

```
[探针7] 被 try/catch 兜住: type 'int' is not a subtype of type 'String?' in type cast
[探针7] 最终 displayContent=正文 P012 泄漏
[探针7] 是否仍含裸编号 P012: true
[探针7] 是否已被清洗为【症候】: false
```

对照组（无漂移）输出 `displayContent=正文 【症候】 泄漏`。

**结论**：崩溃的唯一后果不是「降级」，而是 **`validateNaturalLanguage` 已算好的
清洗结果被整份丢弃**——V-03（编号泄漏拦截）在这个路径上完全失效，用户直接
看到 `P012` 这类内部症候编号。

V-03 属于真拦截集合（`diagnosis_validator.dart:60`
`_kBlockingFixTypes = {'V-03', 'V-04'}`），其设计意图就是「编号绝不泄漏给用户」。
一个能让真拦截规则静默失效的路径，不能被称为「一个能跑通的结果」。

### 1.3 判别式修正

原判别式的问题：它只问「输出变不变」，没问「变之前那个输出对不对」。

**修正后的判别式（供后续引用）**：

> 先判定当前输出是否符合该函数的**契约 / 设计意图**：
> - 符合 → 改它是**行为变更**，需独立评估
> - 不符合 → 改它是**缺陷修复**，属修复范围
>
> 「崩溃被兜住」不等于「行为正确」。兜住只保证进程不死，不保证语义正确。

按此重判两者：

| 条目 | 函数契约 | 当前输出 | 判定 |
|:--|:--|:--|:--|
| N40 | `parseDiagnosis` 文件头声明「不 throw」 | 抛 `TypeError` | 违反契约 → **修复** |
| N39 | `validateDiagnosisOutput` 返回 `displayContent: nlValidation.cleaned`（`:273`） | 返回未清洗原文 | 违反契约 → **修复** |

两者实为**同一类**：都是「输出与自身契约不符」。ADR-C63 把它们分成两类是错的，
当时的区分依据（「有没有 try/catch 兜住」）只影响崩溃的**传播范围**，
不影响「是不是缺陷」。

---

## 2. 范围修正：不是 1 处，是 9 处

ADR-C63 §1.4 只登记了 `suggested_phase` 一处（`:309-311`）。逐行盘点
`_mapToParsedDiagnosis`（`:281-321`）后，同模式硬 cast 共 **9 处**。

### 2.1 schema 保证了什么（这些 cast 是安全的）

`validateDiagnosisSchema`（`:67-167`）校验到 `:154` 结束，覆盖了：

| 字段 | schema 校验位置 | 下游 cast | 是否安全 |
|:--|:--|:--|:--|
| `syndromes` | `:80` 非空 List + `:87` 元素为 Map | `:282` `as List`、`:284` `as Map` | ✅ 安全 |
| `suggested_actions` | `:141-142` List 且元素全 String | `:288` `as List` | ✅ 安全 |
| `confidence` | `:150` num 且 0-1 | `:305` `as num` | ✅ 安全 |
| `teaching_plan` | **无** | `:291` `is Map` 守卫 | ✅ 有守卫 |
| `teaching_plan.next_step` | **无** | `:296` `is String` 守卫 | ✅ 有守卫 |

### 2.2 schema 没校验、cast 会崩的 9 处

`validateDiagnosisSchema` **完全不校验任何可选字段的类型**。以下 9 处
在 `jsonValidation.valid == true` 时仍会抛 `_TypeError`：

> **状态更新（实施后）**：上表 5 处「未实测」已由护栏测试
> `test/services/diagnosis_type_drift_test.dart` 逐一覆盖（9/9 全测），
> 全部确认为同一致崩模式。下表状态以实施后为准。

| # | 位置 | 字段 | 实测状态 |
|:-:|:--|:--|:--|
| 1 | `:300` | `next_focus` | ✅ 实测崩溃 → 已修 |
| 2 | `:309-311` | `suggested_phase`（N39 原登记点） | ✅ 实测崩溃 → 已修 |
| 3 | `:306` | `root_cause_analysis` | ✅ 护栏覆盖 → 已修 |
| 4 | `:308` | `feedback_summary` | ✅ 护栏覆盖 → 已修 |
| 5 | `:312-314` | `suggested_beginner_level` | ✅ 护栏覆盖 → 已修 |
| 6 | `:315` | `teaching_mode` | ✅ 护栏覆盖 → 已修 |
| 7 | `:316-317` | `teaching_plan.current_teaching_focus_id` | ✅ 实测崩溃 → 已修 |
| 8 | `:318` | `teaching_plan.focus_reason` | ✅ 护栏覆盖 → 已修 |
| 9 | `teaching_types.dart:175` | `syndromes[].reader_impact` | ✅ 实测崩溃 → 已修 |

### 2.3 第 9 处是 ADR-C63 的遗漏（N40 只修了一半）

`Syndrome.fromJson`（`lib/types/teaching_types.dart:164-177`）第 175 行：

```dart
readerImpact: json['reader_impact'] as String?,
```

ADR-C63 §1.5 修的 N40 是 `diagnosis_parser.dart:157` 的**同一字段**，但那是
parser 路径。**validator 路径走 `Syndrome.fromJson`（`diagnosis_validator.dart:285`），
这处从未被修**——上一批只修了调用方之一，漏了共享类型层。

教训：**改共享类型层的字段前，先 grep 全部调用方。** 本例中同一个语义字段
（`reader_impact`）在两条解析路径上各有一份实现，修一处不等于修完。

`Syndrome.fromJson` 内其余 cast（`syndrome_id` / `name` / `severity` / `evidence` /
`explanation`）均由 schema 保证（见 §2.1 表），且 `evidence` 用 `.toString()`
而非 cast，故均安全——**本批不动**，避免过度修改。

---

## 3. 方案

### 3.1 为什么不能只改成安全读取

最省事的修法是把 `as String?` 换成 `v is String ? v : null`。**但这会把一个可见
故障换成不可见故障**：

- 崩溃路径上，用户至少能看到「诊断内容不对」（裸编号泄漏）
- 静默置 null 后，字段悄悄消失、无任何痕迹——正是 ADR-C63 §1.3 判定的
  「比整块丢弃更隐蔽」那一类（N13 的机制）

按 ADR-C63 刚建立的纪律（不新增静默点），改为 **安全读取 + 漂移留痕**。

### 3.2 方案 C：安全读取 + 类型漂移 warning（推荐，已采纳）

三个动作：

1. **安全读取**：9 处硬 cast → `is String` 守卫，非 String 一律按缺失处理。
   崩溃消失 → `displayContent` 恢复到清洗后的版本 → **V-03 恢复生效**。

2. **漂移留痕**：新增 `_collectOptionalFieldDrifts`，在映射前扫描 9 个字段，
   类型不符时生成 warning 文本，合并进 `jsonValidation.warnings`。

3. **不改 `valid`**：漂移**不**判为 schema 错误。
   理由——判为错误会让整块诊断被丢弃（`validateDiagnosisOutput:267` 的
   `if (jsonValidation.valid ...)` 不成立 → `diagnosis = null`），
   放大「输出了但不落库」，与 N5 的裁决（只观测不拦截）同向恶化。

留痕载体选择：`DiagnosisValidationResult.warnings`（`contracts:33`）已存在且
被用于互斥症候 warning，语义一致，无需扩契约。

**零行为变更边界**：无漂移输入下，`warnings` 保持空、`valid` 不变、
`diagnosis` 逐字段相同——既有行为完全不变。

### 3.3 被否决的方案

| 方案 | 否决理由 |
|:--|:--|
| A. 纯安全读取（不留痕） | 把可见故障换成不可见故障，违反 ADR-C63 刚建立的纪律 |
| B. 漂移判为 schema 错误 | 丢弃整块诊断，放大「输出了但不落库」；且与 N5 裁决自相矛盾 |
| D. 不动，只加 try/catch | 掩盖问题；V-03 继续失效；违反 R-028 边界防御 |

---

## 4. 落地清单

| 文件 | 改动 | 行为变更 |
|:--|:--|:--|
| `lib/services/diagnosis_validator.dart` | 9 处安全读取；新增 `_collectOptionalFieldDrifts`；`validateDiagnosisOutput` 合并 warnings | 崩溃路径上：从不清洗 → 清洗（**缺陷修复**） |
| `lib/types/teaching_types.dart` | `Syndrome.fromJson:175` 安全读取 | 同上 |
| `test/services/diagnosis_type_drift_test.dart` | 新增护栏（9 处全覆盖 + V-03 恢复 + 零回归） | 无 |

`chat_service.dart` **不改**——两处调用点已有 try/catch，修复后异常不再发生，
兜底路径自然不再触发。

---

## 5. 验证与代价

### 5.1 四道门禁（R-027）实测结果

| 门禁 | 结果 |
|:--|:--|
| `dart format --set-exit-if-changed` | **0 changed**（退出码 0） |
| `flutter analyze lib` | **No issues found** |
| `python scripts/check_circular.py` | **OK: no circular imports（289 modules）** |
| `flutter test`（范围内全跑） | **128 passed** |
| `flutter test`（范围外抽测） | **151 passed** |

范围内：8 个诊断链路测试文件（含新增 `diagnosis_type_drift_test.dart` 48 条）。
范围外抽测：`four_libraries_consistency` / `chat_gates` / `enum_consistency` /
`prompt_style_contract` / `skill_prompt_anchor`（共享类型层改动，故抽类型侧）。

**锚点快照零改动** —— 本批不改任何 prompt 语料。

### 5.2 变异测试（护栏必须能失败）

| 变异 | 结果 |
|:--|:--|
| A：`next_focus` 安全读取退回硬 cast | ✅ 拦住（6 处断言失败） |
| B：漂移留痕失效（`check` 条件恒假） | ✅ 拦住（7 处断言失败） |
| C：`reader_impact` 安全读取退回硬 cast | ✅ 拦住（3 处断言失败） |

变异 B 首次跳过：锚点 `if (v != null && v is! String) {` 在 `check` 与
`checkPlan` 中各出现一次，非唯一。**变异锚点必须带上下文**，与 ADR-C63 §5.3
记录的「or 语义」陷阱同属一类——变异设计本身会骗人，不只是护栏会失效。

### 5.3 落地中踩到的坑

1. **`FORMAT_EXIT=$?` 拿的是 `tail` 的退出码**，不是 `dart format` 的。
   管道后取 `$?` 恒为 0，会让红门禁看起来是绿的。必须重定向到文件再取。
2. **`--set-exit-if-changed -o none` 只检查不写入**。返回 1 时需先跑一次
   `dart format <file>` 写入，再重新校验，否则门禁永远红。
3. **测试断言写反**：初版断言 `passed == true`，但本测试语料故意含 `P012`，
   会触发 V-03 **真拦截**（`_kBlockingFixTypes` 含 `V-03`）→ `passed` 恒为 false。
   这不是代码缺陷，是断言错误。教训：断言前先确认被测值的**设计意图**，
   与本 ADR §1.3 的判别式修正同源——先问「什么是对的」，再问「变没变」。

### 5.4 代价

2 个源文件 + 1 个测试文件；不引入新依赖；不改任何公开签名；
`chat_service.dart` 零改动。

---

## 6. 收尾与遗留

- **N39**：本批闭环。
- **N40 补完**：本批闭环（共享类型层 `Syndrome.fromJson`）。
- **N 系列剩余**：27 条 → 26 条。
- **N6 复评触发条件**（ADR-C63 §3.4 已写死）：N39 修复后若观测到
  `syndrome_id_format` 相关的诊断漂移，重评大小写鲁棒性。本批不改 N6。
- **新登记（本次发现，不入本批）**：`Syndrome.fromJson` 其余 cast 依赖
  schema 保证（§2.1），若未来 schema 放宽必填校验，这 5 处会变成新的崩溃点。
  已在 `Syndrome.fromJson` 加注释标记此依赖，供后人检索。
