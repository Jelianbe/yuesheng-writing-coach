# ADR-C66：诊断字数门槛常量化（N10 UI 侧）

- **状态**：已实施
- **日期**：2026-09-03
- **涉及模块**：UI 层诊断入口校验（非核心模块；但改 shared_constants 属共享配置，按 AGENTS.md:124 习惯前置 ADR）
- **相关**：ADR-C63（解析可观测性）、ADR-C64（类型漂移）、ADR-C65（落库正确性）
- **未纳入**：N28（prompt 侧症候数量上限）另开 ADR-C67 —— 改 prompt 会触碰 skill 锚点快照，须经舰长确认后重生成基线

---

## 1. 结论先行

| 项 | 裁决 | 依据 |
|:--|:--|:--|
| **N10-a** 两处校验点绕过常量（`writing_coach_panel_teaching.dart:327` / `writing_page_selection_ai.dart:97`） | **修**（缺陷修复） | 常量 `UILimits.diagnosisWordThreshold` 已存在且另两处已在用 → 同语义判据存在三套写法，属内部不一致 |
| **N10-b** 提示文案数字硬编码（4 处共 5 条） | **修**（缺陷修复） | 阈值与文案双份维护：改常量后校验生效、文案仍说旧数字 → 用户看到「少于 100 字」却卡在 150 字，属静默错误 |
| **N10-c** prompt 侧 `skills_beginner_p3.dart:48`「< 200 字 = P0」 | **不修** | 复核确认：该判据是**教学阶段路由**（决定从 P0 还是 P1 起步），UI 的 100 字是**输入合法性校验**，两者正交，「够字数」不等于「该从 P1 起步」 |
| **N10-d** 各入口文案措辞不统一 | **不修**（保持逐字不变） | 措辞差异对应不同语境（选章弹层 / 写作面板 / 划词菜单），是刻意设计 → 统一措辞属行为变更，不在本批范围 |
| **新发现-a** 快速观察 50 字（`writing_coach_panel_teaching.dart:246`）/ 择选弹层 10 字（`writing_page_selection_ai.dart:133`） | **顺带纳入**（常量化） | 与诊断门槛同为「UI 字数门槛 + 文案硬编码」，且就在本批改动的同两文件紧邻位置；零行为变更，成本极低 |
| **新发现-b** 超长分块阈值 4000 字（`chat_service.dart:1052` / `progressive_diagnosis.dart:9`） | **登记待办，本批不动** | 位于服务层的诊断路由逻辑，超出本批 UI 层边界；且 `progressive_diagnosis.dart` 属诊断核心模块，改动需单独立 ADR |

统一沿用 ADR-C64 §3 判别式：

> 先判定当前输出是否符合该函数的**契约 / 设计意图**——
> 符合 → 改它是行为变更；不符合 → 改它是缺陷修复。

---

## 2. 事实链（file:line 逐条核实）

### 2.1 台账盘点结论的**两处修正**（第三次状态过期）

上一批盘点记「`diagnosisWordThreshold` 零使用」，实测**不成立**；记「封顶侧 1-3 个症候」，实测为 **1-2 个**。本 ADR 全部结论以实际 grep 输出为准，不沿用台账文字。

### 2.2 四处校验点现状

| # | 文件:行 | 阈值写法 | 提示文案 | 用常量 |
|:--|:--|:--|:--|:--|
| 1 | `lib/widgets/chat_teaching.dart:21` | `< UILimits.diagnosisWordThreshold` | `:24`「章节内容少于 100 字，请先编辑章节」 | 阈值 ✓ / 文案 ✗ |
| 2 | `lib/widgets/diagnosis_picker_sheet.dart:97` | `< UILimits.diagnosisWordThreshold` | `:99-101`「章节内容少于 100 字，请先编辑章节」 | 阈值 ✓ / 文案 ✗ |
| 3 | `lib/widgets/writing_coach_panel_teaching.dart:327` | `isSelection ? 20 : 100`（**全硬编码**） | `:333`「请至少选择 20 字…」/「请至少输入 100 字…」 | ✗ / ✗ |
| 4 | `lib/widgets/writing_page_selection_ai.dart:97` | `< 20`（**硬编码**） | `:99`「请至少选择 20 字以上的文本进行诊断」 | ✗ / ✗ |

- `shared_constants.dart:78`：`static const int diagnosisWordThreshold = 100;`，注释「诊断最短章节字数（<100 字提示先编辑）」。
- 选段门槛 **20** 在 #3 #4 各写死一次，**无任何常量承载**。
- #3 #4 所在文件与 `chat_teaching.dart` 均**未 import** `shared_constants.dart`；仅 `diagnosis_picker_sheet.dart:15` 已 import。

### 2.3 缺陷的可观测后果

把 `diagnosisWordThreshold` 由 100 改为 150：

- 校验行为在 #1 #2 正确收紧到 150 字；
- 但 #1 #2 的提示仍显示「章节内容少于 **100** 字」；
- #3 #4 完全不受影响，仍是 100 / 20。

即：**同一判据分裂为三套真相**，其中两套对用户说谎。当前阈值未改动，故缺陷处于潜伏态——这正符合「缺陷修复 ≠ 行为变更」的判别：修复后在当前取值下**输出逐字不变**。

---

## 3. 实施方案

### 3.1 常量层（`lib/config/shared_constants.dart`）

在 `UILimits` 内 `diagnosisWordThreshold` 之下新增：

```dart
/// 选段诊断最短字数（<20 字提示先扩选）
static const int diagnosisSelectionWordThreshold = 20;
```

不改动 `diagnosisWordThreshold` 的值与注释。

### 3.2 四处调用点

| 文件 | 改动 |
|:--|:--|
| `chat_teaching.dart` | 文案数字改常量插值；补 import |
| `diagnosis_picker_sheet.dart` | 文案数字改常量插值（import 已有） |
| `writing_coach_panel_teaching.dart` | `minLength` 改 `isSelection ? UILimits.diagnosisSelectionWordThreshold : UILimits.diagnosisWordThreshold`；文案插值；补 import |
| `writing_page_selection_ai.dart` | `< 20` 改 `< UILimits.diagnosisSelectionWordThreshold`；文案插值；补 import |

### 3.3 零行为变更的保证

`UILimits.*` 为 `static const int`，Dart 允许在 `const` 字符串中对 const 变量做插值，故四条 `const SnackBar(content: Text(...))` **保留 const 修饰**，插值后文案与原字面量**逐字相同**：

- 「章节内容少于 ${100} 字，请先编辑章节」 == 原文案
- 「请至少选择 ${20} 字以上的文本进行诊断」 == 原文案
- 「请至少输入 ${100} 字后再提交诊断」 == 原文案

---

## 4. 护栏（`test/widgets/diagnosis_word_threshold_test.dart`，新建）

既有测试体系中**没有**源码文本扫描类护栏（grep `File(` 于 `test/` 仅见数据库 / 语料用途）。本类缺陷（数字与常量脱钩）无法在运行时断言——因为修复后输出逐字不变——故只能以源码扫描守住：

1. **常量取值**：五个门槛常量各自等于设计值（防手滑改值）。
2. **出现次数**：每个门槛文件中，相关常量出现次数 = 阈值处 1 次 + 每处文案插值 1 次。
3. **插值写法**：提示文案必须是 `${UILimits.xxx}` 插值，而非字面量数字。
4. **无裸数字**：上述文件的**非注释**代码中不得出现「数字 + 字」字面量（正则 `(?<![\w$}])\d+\s*字`，负向后顾排除插值写法；整行注释先行剔除，避免误伤说明文字）。
5. **护栏自检**：四个目标文件可读非空，且正则自测「命中字面量 / 不误伤插值」——防止文件重命名后扫描静默落空。

### 4.1 变异验证（门禁要求「新护栏须能失败」）

| 变异 | 操作 | 结果 |
|:--|:--|:--|
| A 文案回退为字面量 | `panel_teaching` 文案改回 `'请至少输入 100 字后再提交诊断'` | ✅ 断言 3 + 断言 4 双重捕获（`缺少片段` / `存在硬编码字数门槛：100 字`），自检组仍全绿 |
| B 阈值回退为字面量 | `selection_ai` 改回 `if (text.length < 20)` | ❌ **初版漏网** → 见 §4.2 |
| C 常量改值 | `diagnosisWordThreshold` 100 → 150 | ✅ 断言 1 捕获（`Expected: <100> / Actual: <150>`） |

### 4.2 初版护栏不完整，已修正（实测记录）

变异 B 首次执行时**全部测试通过**——护栏是假的。两个原因叠加：

1. 断言 2 初版写作「文件中**出现过** `UILimits.diagnosisSelectionWordThreshold`」。但该文件文案插值里同样含这个常量名，阈值写死为 `20` 后，文件中仍出现 1 次 → 断言成立。
2. 断言 4 的裸数字正则只匹配「数字 + 字」，而 `text.length < 20` 后面没有「字」→ 不命中。

**修正**：断言 2 由「是否出现」改为「**出现次数**」（阈值 1 + 每处文案 1）。修正后重跑变异 B → ✅ 捕获（`出现 1 次，期望 2 次`）。

> 推论（已写入 AGENTS.md V4.7）：**源码扫描护栏中，「文件是否包含某标识符」是假判据**——同一标识符在同一文件内多处出现时，改坏其中一处不会改变「包含」这一布尔结果。凡护栏针对「多处应当一致」的不变量，必须断言**次数**或**逐处位置**，而非存在性。

---

## 5. 影响面

- 不涉及诊断解析 / 落库 / 教学状态机 / DB schema。
- 不涉及任何 skill 正文 → **skill 锚点快照（FNV-1a 指纹）不受影响**，无需 `UPDATE_SNAPSHOTS`。
- 改动文件 5 个（1 常量 + 4 UI），新增测试 1 个。
