# R-019 函数行数实测（2026-09-03）

- **性质**：审计 / 侦察报告（**未改任何生产代码**）
- **范围**：`yuesheng-flutter/lib`，阈值 **50 行**（R-019 函数硬上限）
- **工具**：`tool/check_r019.py`（本次新增，只测不拆）
- **结论一句话**：R-019 的实际债务是 **237 个手写函数**（另 27 个为生成代码），
  且**四道门禁没有一道检查它**——这是它长期停留在「已登记债务」却无人推进的直接原因。

---

## 1. 结论先行

1. **R-019 无门禁**：`gate.sh` 的四道（format / analyze / test / circular）**都不检查
   函数行数**。本次补上测量工具 `tool/check_r019.py`。
2. **实测 264 个函数超 50 行**（289 个文件中）。剔除生成代码 27 个，**手写 237 个**。
3. **近半在 UI 层**：`lib/widgets` 153 个（58%），其中 **`build` 方法 83 个、合计 8141 行**。
   这些的正解是**拆 Widget**，不是抽函数——抽函数只会把大函数拆成一串小函数，
   类本身仍然臃肿。
4. **当前登记的开工点位置有误**：台账记的「`_validateDiagnosis`」在
   **`lib/services/diagnosis_parser.dart:273`（145 行）**，不在 `diagnosis_validator.dart`。
5. **chat_service.dart 实测 14 个**（台账记 12 个），最长的 `_sendMessageCore` 311 行。

---

## 2. 测量方法

`tool/check_r019.py`：字符串 / 注释感知的括号配平（先把源码生成等长掩码，
把字符串与注释区间置为空格，再在掩码上匹配签名与配平块），避免
`{'a': 1}`、`'${x}'`、`// }` 之类干扰。

**判据踩过的三个坑**（都已修，脚本内留有注释）：

| # | 坑 | 表现 | 修法 |
|:--|:--|:--|:--|
| 1 | 灾难性回溯 | 掩码把长字符串掏成超长空白行，`[\w<>?,\s\[\]]+?` 在其上反复回溯；**扫 507 文件跑 15 分钟未完成** | ret 段限长 `{1,60}?` + 跳过 > 300 字符的行 + 加进度输出（现几秒完成） |
| 2 | 函数类型参数被当签名 | `required void Function(String) markStage,` → 报「`Function` 261 行」 | 函数名为 `Function` 跳过；行以 `,` 结尾跳过 |
| 3 | 函数调用被当定义 | `onCreate` 回调里的 `await customStatement(...)` → 报「402 行的假冠军」 | **参数列表配平后，紧跟的必须是 `{`（允许 `async`）而非 `;`** |

抽查验证两条：`_sendMessageCore`（2797→3107 = 311 行）、
`_buildContent`（16→296 = 281 行），均与实际闭合行一致。

---

## 3. 实测数据

### 3.1 总量与分布

| 目录 | 超限函数数 |
|:--|--:|
| `lib/widgets` | **153** |
| `lib/services` | 68 |
| `lib/data` | 37 |
| `lib/providers` | 4 |
| 其他（`main_dev.dart` / `preview`） | 2 |
| **合计** | **264** |
| 其中生成代码（`.g.dart` 等，建议豁免） | −27 |
| **手写代码实际债务** | **237** |

### 3.2 行数分布

| 区间 | 数量 | 说明 |
|:--|--:|:--|
| 51–60 | 60 | **最易还清**（手写 53 个），改动小、风险低 |
| 61–80 | 75 | 中等，多为顺序逻辑可切段 |
| 81–120 | 75 | 需要真正的职责拆分 |
| 121–200 | 44 | 硬骨头 |
| 201+ | 10 | 硬骨头中的硬骨头，6 个在 `chat_service.dart` |

### 3.3 `build` 方法（UI 层的主体）

**83 个 `build` 超限，合计 8141 行**，平均每个 98 行。

这批的特殊性：`build` 变大通常是因为**一个 Widget 类承担了太多子区块**。
抽私有方法（`_buildHeader` / `_buildBody` …）能压行数，但**类本身没变小**，
且容易演化成 AGENTS.md 明令禁止的「机械拆分」。更恰当的是**按子区块拆成
独立 Widget 类**（真分解）。

### 3.4 chat_service.dart（14 个）

| 行数 | 函数 | 起行 |
|--:|:--|--:|
| 311 | `_sendMessageCore` | 2797 |
| 268 | `_injectDiagnosisLock` | 1332 |
| 235 | `_injectChapterObservations` | 1831 |
| 217 | `_applyPhaseMigration` | 1060 |
| 186 | `_parseAndPersist` | 2226 |
| 173 | `commitDiagnosisFromContent` | 562 |
| 149 | `_commitDiagnosisAndSuggestions` | 2415 |
| 137 | `_handleTrainingResult` | 2565 |
| 122 | `_applyFactExtractionFromContent` | 829 |
| 85 / 85 | `_injectOutlineFactsAndFiles` / `_preloadReferenceDetails` | 1743 / 2127 |
| 78 / 73 / 64 | `_applyOutlineEntitiesFromContent` / `_injectProfileAndIntents` / `_injectReferences` | 743 / 1603 / 1678 |

命名上看，8 个是 `_injectXxx` / `_applyXxx` ——**提示词装配型函数**，
它们的共同形态是「按顺序往 StringBuffer 里塞段落」。这类有明确的重构方向
（提取装配管道 / 每段一个策略对象），但属**诊断核心链路**，
按 AGENTS.md 需**先写 ADR** 再动。

### 3.5 诊断链路（28 个，当前登记的开工点所在）

| 行数 | 函数 | 位置 |
|--:|:--|:--|
| **145** | **`_validateDiagnosis`** | **`diagnosis_parser.dart:273`** ← 台账登记的开工点 |
| 145 | `validateEditorSchema` | `editor_validator.dart:131` |
| 142 | `_parseObservation` | `editor_validator.dart:277` |
| 141 | `_parseTrainingTask` | `teacher_validator.dart:260` |
| 138 | `validateOutlineSchema` | `outline_validator.dart:72` |
| 135 | `commitDiagnosis` | `diagnosis_repository.dart:101` |
| 112 | `validateTeacherSchema` | `teacher_validator.dart:147` |
| 101 | `validateDiagnosisSchema` | `diagnosis_validator.dart:67` |
| 81 | `validateNaturalLanguage` | `diagnosis_validator.dart:170` |
| … | （其余 19 个 51–92 行） | |

**观察**：`*_validator.dart` 里的 `validateXxxSchema` 普遍 100–145 行，
形态高度一致（逐字段类型检查 + 收集 errors）。这是一类**可以用统一手法处理**的
债务，修一个的经验能复制到其余四个。

---

## 4. 历史教训的实物印证

`tool/__pycache__/r019_split.cpython-313.pyc` 仍在，但 `.py` 已删。
从其 docstring 可还原：那是 **`part` 分片 + 逐字节保真断言** 的拆分工具
（`mode="top_level"` / `mode="extension"`）。

正是 AGENTS.md 现已明令禁止的做法：

> **禁止用 `part` / `extension` 机械拆分服务层凑行数**
> → 批次 X-025-ARCH 已定性为**伪拆分**并回退 13 个 commit。
> 真分解 = 独立类 / 显式接口 / 依赖注入 / 职责级重构。

**推论**：本轮若要动手，不能走 part 分片的老路。

---

## 5. 建议的分阶段路线（待舰长确认）

237 个函数不可能一次还清，建议按「**先止血、再易后难**」分四期：

| 期 | 目标 | 规模 | 建议做法 | 需 ADR |
|:--|:--|--:|:--|:--:|
| **P0** | **立门禁，止血** | 0 个改动 | `check_r019.py` 接入 `gate.sh`，配合 `--baseline tool/r019_baseline.json`（已入库）：**存量 264 个全部豁免，只卡新增超限**——不阻塞任何现有代码，只阻止债务继续扩大 | 否 |
| **P1** | 易清理项 | 53 个（51–60 行） | 单个函数改动小，多为抽 1–2 个私有方法即可 | 否 |
| **P2** | UI 层 build | 83 个 | **按子区块拆成独立 Widget 类**，不是抽函数 | 视模块 |
| **P3** | 核心链路硬骨头 | 10 个（201+） | 职责级重构（装配管道 / 策略对象） | **是**（诊断核心） |

另一个可选维度是**按模块纵向推进**（如先把诊断链路 28 个清完）——好处是
领域上下文连贯、测试集中；坏处是动到核心模块，每步都要 ADR。

我的推荐：**先做 P0（零风险、立刻见效），再按 P1 → P3 顺序，P2 单独排期**，
理由是 P1 单笔成本最低、P3 是唯一真正伤到架构的部分，而 P2 虽然数量最多
但性质单一（拆 Widget）、可以后期批量化。

---

## 6. 本次改动

| 文件 | 性质 |
|:--|:--|
| `tool/check_r019.py` | **新增**：R-019 扫描（只测不拆；支持 `--baseline` 止血模式） |
| `tool/r019_baseline.json` | **新增**：当前债务快照（264 条），止血模式的基线。放 `tool/` 而非 `outputs/`，因为后者被 `.gitignore:75` 忽略 |
| `docs/audits/2026-09-03-r019-function-length-survey.md` | 本报告 |
| `outputs/r019_scan.json` | 扫描产物副本（被 gitignore，仅本地用） |

**生产代码零改动。**

### 6.1 止血模式已验证可用（未接入 gate.sh）

```
python tool/check_r019.py --baseline tool/r019_baseline.json
→ 模式：止血模式（基线 tool/r019_baseline.json，存量 264 个豁免，只报新增）
→ 无超限函数 ✓           退出码 0
```

反向验证（确认判据不是「永远返回 0」）：临时造一个 60 行函数放进 `lib/`，
扫描**准确报出 1 个新增**并指向该文件；删除后恢复 0。

> **未接入 `gate.sh`**——改门禁会改变每次提交的耗时与行为，属流程变更，
> 等舰长确认后再动。工具与基线已就位，接入只需在 `gate.sh` 加一段。
