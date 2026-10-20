# ADR-C92 四个已写好未接入门禁的脚本 — 接入裁定（slug: ungated-scripts-gate-accession）

- 状态：**已接受并实施**（2026-09-12 舰长批准方案②）
- 日期：2026-09-12
- 决策者：舰长（原稿由 software-gate-adhoc 团队起草，经主理人核验后补正）
- 关联：ADR-C70（循环依赖全量卡口）/ ADR-C91（LLM 多账号）/ `scripts/gate.sh`（十一道门禁）/ `scripts/check_coverage.py`（三态语义范式）

---

## 实施结果（2026-09-12）

**舰长裁定：方案②——先修检查器假阳性，再接入门禁。**

### 关键前置：修掉 11/12 假阳性（这是本批最重要的发现）

原稿只讨论了「接不接门禁」，**未检查脚本本体的判定质量**。主理人实测发现
`check_prompt_antipattern.py` **假阳性率 11/12 ≈ 92%**：

| 规则 | 命中 | 判定 |
|:--|:--|:--|
| `report-tone` | 4 条全含「置信度」 | **4/4 假阳性**——3 条是诊断块 **JSON 协议字段定义**（`confidence (number): 诊断置信度`，产品必需），1 条是否定句（「**不要**…降低置信度」） |
| `assert-conclude` | 1 条 | **假阳性**——`❌` 标注的反例说明 |
| `cross-dup` | 6 条 | **假阳性**——有意的跨文件教学规则一致性 |
| `force-trigger` | 1 条 | **真阳性**，保留 |

**根因**：检查器只做字面正则，不理解语义上下文。`report-tone` 把月笙**核心产品
概念「诊断置信度」**错当报告腔。

**为什么必须修而不能改 prompt（R-009/R-010）**：改 prompt 去迎合有缺陷的检查器 =
让工具缺陷倒逼教学内容，违反用户主权与最小化范围原则。

**修复内容**（`check_prompt_antipattern.py`）：
1. `report-tone`：加三类排除——协议字段行（`confidence (`/schema 类型标注）、
   否定语境（前 30 字含 不要/禁止/不得/不能/≠/避免/无需/不应）、
   复合协议名词（`(症候|诊断|识别|确认|情绪)置信度`）
2. `assert-conclude`：加反例标记排除（`❌`/说太早/反例/错误示范/否定词）
3. `cross-dup`：降级为**信息型**——`--diff-baseline` 模式不参与 FAIL，仅全量报告列出
4. 新增 `--expect-rule-count 4` 守卫（防规则被静默删减）

**修复中发现的 fail-open bug（已修）**：`_diff_by_text` 原返回三元组丢掉了 `rule`
字段，导致 `x[0] in VIOLATION_RULES` 恒为假 ⇒ **diff 模式永远 exit 0（假绿）**。
即"门禁接入后永远不会失败"。**只有负向测试能抓到**——已通过注入测试证实修复。

### 门禁接入（`gate.sh`：7 道 → **11 道**）

| 门禁 | 脚本 | 阻断模式 |
|:--|:--|:--|
| **7** | `check_prompt_antipattern.py --diff-baseline --expect-rule-count 4` | 有新增命中 → FAIL |
| **8** | `check_content_metadata.py --strict` | 有 finding → FAIL |
| **9** | `check_interaction_regression.py` | 仅 P0 → FAIL（P1 报告） |
| **10** | `check_split_shape.py --baseline tool/split_shape_baseline.json --expect-rule-count 3` | 有新增违规 → FAIL |

`skill_consistency_scan` **不接门禁**（rc 恒 0 的 advisory 候选生成器），维持原状。

**fail-closed 设计**（每个新门禁）：
- `PY_BIN` 缺失 → SKIP（计入 degraded）
- 门禁 7：`lib/services` 不存在 → SKIP（避免脚本"找不到目录 return 1"被误当真问题）
- 门禁 9：`lib` 下无 `.dart` → SKIP（**空扫会 rc=0 假绿**）
- 门禁 10：基线缺失 → SKIP
- 脚本自身 `exit 2`（环境错误）→ FAIL

### 验证（全部实测）

| 项 | 结果 |
|:--|:--|
| 全量门禁 | **11 通过 / 0 失败 / 0 未执行**，`GATE_EXIT=0` |
| 门禁 7 假阳性消除 | 12 条 → 7 条（1 真阳性 + 6 信息型） |
| 门禁 7 负向 | 注入「每轮都必须输出」→ exit 1；还原 → exit 0 |
| 门禁 10 判据 | S1=3 / S2=5 / S3=4（与规格一致） |
| 门禁 10 A 类豁免 | 零泄漏（`skill_registry` 5852 行家族、三大 KB 正确排除） |
| 门禁 10 负向 | 注入新 part → exit 1；还原 → exit 0 |
| fail-closed | 目录不存在 → exit 2；基线缺失 → SKIP |
| 基线陷阱防护 | `--json` + `--baseline` 同传 → exit 2 |

---

## 背景

四个脚本已写好、能跑、却从未进入任何门禁，意味着它们真正能拦到的问题被**静默放过**：

1. `scripts/check_prompt_antipattern.py` — Prompt 话术反模式扫描
2. `scripts/skill_consistency_scan.py` — Skill 一致性家族扫描（advisory）
3. `scripts/check_content_metadata.py` — 内容增减规范元数据头巡检（advisory）
4. `scripts/check_interaction_regression.py` — 交互/导航回归扫描

本 ADR **仅起草方案**，不改动 `gate.sh`/任何脚本、不提交。以下结论均经实测复核，非转述。

### 实测复核（命令 + 真实输出 + 退出码）

执行环境：`C:/Users/NewName/.workbuddy/binaries/python/versions/3.13.12/python.exe`，cwd = `D:/ai-teacher/yuesheng-flutter`。

| 脚本 | 命令 | 退出码 | 实测结果 |
|------|------|--------|----------|
| check_prompt_antipattern.py | `python scripts/check_prompt_antipattern.py` | **1** | 共 12 条命中（force-trigger 1 / assert-conclude 1 / report-tone 4 / cross-dup 6）。例如 `skills_diagnosis_p1.dart:227`「诊断后必须追加确认提问」、`skills_beginner_p3.dart:197`「你的问题是…」 |
| check_prompt_antipattern.py | `… --diff-baseline` | **1** | 相对基线新增 1 条（`skills_diagnosis_p1.dart:185`）。基线 `prompt_antipattern_baseline.json` 已存在 |
| skill_consistency_scan.py | `python scripts/skill_consistency_scan.py` | **0** | 扫描 7389 行，49 条候选（enum-token 7 / threshold 35 / …）。脚本 docstring 明示「候选生成器不是判决器」，threshold/conflict-pair 需人工裁决 → **恒 rc=0** |
| check_content_metadata.py | `python scripts/check_content_metadata.py` | **0** | 扫描 53 文件、14 个元数据头、finding 0 条（已内置存量豁免：无头文件零命中）。含 `--strict` 模式（有 finding 时 rc=1） |
| check_interaction_regression.py | `python scripts/check_interaction_regression.py` | **0** | P0=0、P1=若干候选（P1-5 业务动作无防抖守卫、P1-4 裸路径）。当前无 P0 命中 ⇒ 通过 |

**结论**：`check_prompt_antipattern.py` 确为 **EXIT=1 且拦到真实问题**（高优先接入理由）；另三个当前不阻断，但各有清晰的价值与风险面。

### 是否已有部分接入（调研）

- 全树 Grep 四个脚本名：仅命中脚本自身 + `docs/audits/*`、`docs/待办执行清单.md` 等**审计/文档**，**无任何 `gate.sh`、hook、`flutter_ci.yaml` 调用**。
- `scripts/git-hooks/` 仅有 `pre-commit`，且其逻辑是 `bash scripts/gate.sh`（即接入 `gate.sh` 即自动覆盖本地 pre-commit 与 CI 两条路径）。
- ⚠️ **核验偏差（需舰长知悉）**：本 checkout 的 `yuesheng-flutter/` 下**不存在 `.github/` 目录**，与 brief「覆盖率从 `flutter_ci.yaml` 搬回本地」的前提不符。CI 配置可能在他分支/他仓或已移除；但「四个脚本全树未接入」这一结论不受影响。
- `tool/check_r019.py --dir scripts` → `文件数=0`，证明 R-019 检查器**只扫 `.dart`，对 Python 脚本不可见**。

### 前车之鉴（接入必须避免）

`check_coverage.py` 接入时曾出现两处 fail-open：(a) lcov 被并发测试抽走时记 SKIP 不阻断；(b) 删掉一条 `--t2` 规则后剩余仍全 PASS 致假绿（已用 `--expect-t2-count` 守卫修复）。**任何新检查都必须显式 fail-closed：绝不允许「无法检查 ≠ 通过」**。`gate.sh` 已统一三态：`PASS(0)` / `FAIL(非0)` / `SKIP`（环境缺失，计入 `degraded`，终判 `[ fail==0 ] && [ degraded==0 ]`）。

---

## 决策（推荐方案）

**3 个接为 `gate.sh` 独立新门禁（门禁 7/8/9），1 个保持 advisory 仅作 CI 报告型**。

| 门禁 | 脚本 | 阻断模式 | 优先级 |
|------|------|----------|--------|
| **门禁 7** | `check_prompt_antipattern.py --diff-baseline` | 有新增命中 → FAIL | **高**（已确证 EXIT=1 拦到真问题） |
| **门禁 8** | `check_content_metadata.py --strict` | 有 finding → FAIL（存量豁免，只卡新增头） | 低（当前 0 finding） |
| **门禁 9** | `check_interaction_regression.py`（**仅 P0**） | P0 命中 → FAIL；P1 仅报告 | 高（防运行时崩溃） |
| — | `skill_consistency_scan.py` | **不接门禁**；CI 产物/PR 注释（非阻断） | — |

理由：
- `pre-commit` → `gate.sh` 已打通，新增门禁 7/8/9 即自动覆盖本地 + CI，无需另写 CI 步骤（也避开本 checkout 无 `.github` 的现状）。
- 三个门禁各管一条正交质量轴（话术反模式 / 元数据完整性 / 交互安全），复用 `log_result` 与 `degraded` 核算，报告可读、每闸可独立 SKIP 核算。
- `skill_consistency_scan` 是候选生成器（rc 恒 0），接为硬门禁要么恒绿（零价值）要么翻成阻断即误报海啸，**否决接门禁**（见被否方案）。

---

## fail-closed 设计（每检查）

| 检查 | PASS | FAIL | SKIP（仅环境缺失） | 静默删减守卫（类比 `--expect-t2-count`） |
|------|------|------|------|------|
| 门禁 7 prompt_antipattern | 退出码 0（无新增命中） | 退出码 1（新增命中） | `PY_BIN` 缺失；或 `lib/services` 不存在（wrapper 先 `[ -d lib/services ]` 判，否则 SKIP，避免脚本「找不到目录 return 1」被误当真问题） | 脚本 `KEYWORD_RULES` 现 5 族；接入口加 `--expect-rule-count 5`（或 wrapper 解析打印的规则族数），删规则致数量不符 → FAIL |
| 门禁 8 content_metadata | `--strict` 退出码 0 | `--strict` 退出码 1（finding） | `PY_BIN` 缺失 | `REQUIRED_FIELDS` 现 9 项；加 `--expect-field-count 9`，删字段致数量不符 → FAIL |
| 门禁 9 interaction_regression | 退出码 0（P0=0） | 退出码 1（P0 命中） | `PY_BIN` 缺失；**或 `lib` 下无 `.dart` 文件**（wrapper 先 `find lib -name '*.dart'` 判，否则 SKIP——否则空扫 → rc=0 → 假绿，正是 lcov 教训） | `PUSHNAMED_PATTERN`/`CONTEXT_NAV_PATTERN` 两条 P0 规则；加 `--expect-p0-count 2`，删规则致数量不符 → FAIL |
| skill_consistency_scan（CI 报告） | 恒 0，仅产出候选清单 | 永不（非阻断） | `PY_BIN` 缺失则 CI 步骤 WARN | 无（不阻断，删规则只少报，不影响构建） |

所有新门禁块统一沿用 `gate.sh` 现有范式：
```bash
if [ -n "$PY_BIN" ] && <前置环境判据>; then
  if "$PY_BIN" scripts/<x>.py <args> > "$X_LOG" 2>&1; then RC=0
  else RC=1; cat "$X_LOG"; fi
else
  echo "SKIP: (NOT EXECUTED) ..." > "$X_LOG"; RC=SKIP
fi
log_result "<名称>" "$RC"
```
`RC=2`（脚本自身环境错误，如元数据头路径/编码坏）映射为 **FAIL**（失败关闭，把原因钉在报告上），不归 SKIP。

---

## 被否方案

- **合并进现有门禁**（如并入门禁 5 R-019）：否决。各为新质量轴，合并会模糊报告、打乱 `degraded` 逐闸核算，且失去「哪条检查没跑」的可观测性。
- **`skill_consistency_scan` 接为硬门禁**：否决。它 rc 恒 0（advisory 候选生成器），接门禁 = 恒绿（零价值）或若改判则 threshold/conflict-pair 35+ 条候选直接误报海啸。正确归宿是 CI 报告/PR 注释。
- **四个全接为独立门禁**：否决 skill_consistency 接门禁（同上）。
- **门禁 7 用全量扫描（非 `--diff-baseline`）**：否决。全量现会一次性 FAIL 12 条存量命中，阻断所有提交。遵循门禁 5（止血基线）/ 门禁 6 先例，用 `--diff-baseline` 祖父现有 12 条、只卡新增；12 条真问题列入后续清零（参考 ADR-C70 去基线）。

---

## R-019 合规性

- `tool/check_r019.py` 仅扫描 `.dart`（`if not fn.endswith('.dart'): continue`），**对 Python 脚本不可见**（实测 `--dir scripts` → `文件数=0`）。R-019 是 Dart 宪法规则，Python 工具不在其内。
- 手工逐函数测量（物理行，含空行/注释，与 R-019 口径一致）：

  | 脚本 | 超 50 行函数 | 最长函数行数 |
  |------|--------------|--------------|
  | check_prompt_antipattern.py | `main` | **≈60**（超） |
  | skill_consistency_scan.py | 无 | `main` ≈47（内） |
  | check_content_metadata.py | 无 | `parse_headers` ≈45（内） |
  | check_interaction_regression.py | 无 | `_scan_file` ≈44（内） |

- **拆分预案（真分解，非伪拆分）**：仅 `check_prompt_antipattern.py::main` 超 50 行。建议将 `main()` 内的「收集命中」（`files` 遍历 + `findings` 聚合，约 14 行）抽为 `collect_findings(files) -> dict`，将「全量报告渲染」（约 13 行）抽为 `render_full_report(findings)`。**职责级拆分（收集 vs 呈现）**，严禁以 `part`/`extension` 机械拆服务层凑行数（X-025-ARCH 定性伪拆分、曾回退 13 commit）。
- 注：上述为良好实践建议，**非接入阻塞项**（R-019 不约束 Python）。后续可选扩一个 Python 行数检查，但不在本 ADR 范围。

---

## 验证（接入后如何验证）

- 本地 `bash scripts/gate.sh` → 七道升为**十道**；`outputs/gate/gate-report.md` 顶部 DEGRADED 横幅在任一 SKIP 时出现。
- 正向：临时在 `skills_*.dart` 注入一句「每轮都要…」→ 门禁 7 FAIL；删一条 `--t2`/规则守卫触发 → 对应门禁 FAIL。
- 负向（fail-closed）：并发跑 `flutter test --coverage` 抽走 `lcov` → 门禁 6 FAIL（既有）；`lib/services` 改名 → 门禁 7 SKIP（degraded，非 PASS）。
- `pre-commit` 钩子注释仍写「五道/四闸」，接入后顺手改为「十道」避免误导（非阻塞）。

---

## 补充：历史伪拆分存量（2026-09-12 追加，舰长指令）

**本条为舰长在评审本 ADR 时追加的质询：「针对过去已经执行伪拆分的组件的处理呢？」——
原稿只规定了「未来接入时别伪拆分」，对存量只字未提，属本 ADR 的漏项。**

独立侦察报告：`D:/ai-teacher/docs/audits/pseudo-split-legacy-inventory-2026-09-12.md`

### 机制性发现（关键）

**R-019 的「文件 ≤300 行」与「禁止伪拆分」两条，从来没有机器执行点。**

- `R-019-代码规范标准.md:14` 声明了这两条
- `R-019-代码规范标准.md:21` 指定的 machine_check 是 `tool/check_r019.py`
- 但 `tool/check_r019.py:293` 只过滤 `.dart`、只统计**函数**行数（基线 `limit=50`），
  `tool/r019_baseline.json` 里**没有任何文件行数或 part 结构字段**
- `R-019:20` 的 enforcement 自认是「代码审查拦截」⇒ **纯人眼，无工具**

⇒ **伪拆分是唯一一种「七道门禁全绿也无法察觉」的代码劣化形态。**

### 存量实测

| 项 | 实测值 |
|:--|:--|
| 手写 `part` 从属文件 | **72 个** |
| 宿主文件 | **10 个**（71 处 part 声明） |
| 超 300 行文件总数 | **94 个**（排除 `.g.dart`） |

**豁免边界（防误判）**：`R-019:57-60` 明文豁免 A 类纯常量知识库
（`skill_registry` + `skills_*.dart`、三大知识库）。⇒ 4 个服务层宿主（51 part）
**不是伪拆分**。

**确凿伪拆分（R-019 未豁免的 `lib/widgets/` 层）6 个**：

| 宿主 | 宿主行 | 超限 part | 判据 |
|:--|--:|:--|:--|
| `writing_coach_panel.dart` | 267 | `teaching.dart` **664**、`builders.dart` 338 | P0 |
| `manuscript_detail_page.dart` | **1336** | `manuscript_detail_chapter.dart` 462 | P0 |
| `chat_page.dart` | **431** | `chat_teaching.dart` **405**（比宿主还长） | P0 |
| `growth_detail_page.dart` | **803** | `growth_content.dart` 399 | P1 |
| `writing_page.dart` | **1187** | —（「拆了没拆动」） | P1 |
| `bookshelf_page.dart` | **892** | — | P1 |

**判据**：宿主仍超 300 **且** 拆出的 part 自身也超 300
⇒ 切分点不是职责边界，是行数。

### X-025-ARCH 回退范围疑问

`R-019:50-51` 记载 X-025-ARCH 已回退「13 commit / 12 host / 41 parts」，
但实测仍有 10 宿主 / 71 part。**推断**（非实测）：那 12 host 指服务层
（实证代价是 `ChatService.sendMessage`，见 `R-019:52-54`），
**Widget 层伪拆分从未被处理**。需舰长确认。

### 本 ADR 的处理

**舰长裁定：伪拆分存量与本批一起做** —— 已实现为**门禁 10**
（`scripts/check_split_shape.py` + 基线 `tool/split_shape_baseline.json`）。

- 判据（实测 S1=3 / S2=5 / S3=4）
- A 类豁免白名单已实现（`R-019:57-60`）
- 存量 12 条违规走基线**止血**（同门禁 5 先例），只卡新增
- **修复原则（写进规则）**：**禁止再拆一层 part**（伪拆分的递归形态），
  正确路径 = 独立类 / 显式接口 / 依赖注入 / 职责级重构（`R-019:55`）
- **基线维护**：每清偿一条必须重生成——
  `python scripts/check_split_shape.py --json tool/split_shape_baseline.json`
  （**绝不能带 `--baseline`**；脚本已内置防护：同传 → exit 2）

---

## 后续

- **清零基准**：门禁 7 祖父的 12 条存量命中应在后续批次修复并 `--update-baseline`（参考 ADR-C70 去基线节奏），否则门禁长期停在「只卡新增」弱化态。
- **历史伪拆分存量**：见 `docs/audits/pseudo-split-legacy-inventory-2026-09-12.md`；
  修复原则——**禁止再拆一层 part**（伪拆分的递归形态），
  正确路径 = 独立类 / 显式接口 / 依赖注入 / 职责级重构（`R-019:55`）。
- **落实守卫（执行期，不在本起草范围）**：`--expect-rule-count 5` / `--expect-field-count 9` / `--expect-p0-count 2` 与「空 `lib` 检测」需对各脚本做小改；本 ADR 仅定方案，修改由执行期完成。
- **skill_consistency_scan 接入 CI 报告**：产出 artifact / PR 注释，不阻断构建。
- 可选：扩 Python 侧函数行数检查（R-019 精神外延）。

---

## 裁定建议（供舰长）

> ⚠️ **前置修正（2026-09-12，主理人核验后）**：下述「门禁 7 摩擦低」的表述**不准确**。
> 架构师实测 `--diff-baseline` **仍 EXIT=1**（相对基线有 1 条新增命中
> `skills_diagnosis_p1.dart:185`）。⇒ **直接接入会让门禁 7 立刻红灯、阻断所有提交**。
> 接入前必须先二选一：**(a)** 修复该条新增命中；**(b)** 将其纳入基线。
> 建议执行 (a)——因为它是**真实新增的反模式**，正是门禁 7 想拦的东西。

- **接受（高优先）**：门禁 7 `check_prompt_antipattern --diff-baseline`（**接入前先清掉那 1 条新增命中**）、
  门禁 9 `check_interaction_regression`（P0→FAIL）。前者已确证拦到真问题，后者防运行时崩溃。
- **接受（低风险）**：门禁 8 `check_content_metadata --strict`，当前 0 finding。
- **需舰长拍板 ①**：`skill_consistency_scan` **不接门禁、仅 CI 报告**——请确认其保持 advisory 定位（否决硬门禁）。
- **需舰长拍板 ②**：**历史伪拆分存量**（6 个 `lib/widgets/` 宿主，见上节）——
  是否要求本批同时补 `check_split_shape.py`，还是另立批次？
- **前置条件（随接入一并执行）**：三条 fail-closed 守卫（规则计数 + 空 lib 检测）必须落地，否则重蹈 `--t2` 假绿。
- **知悉项**：本 checkout 无 `.github/`，CI 接入前提与 brief 不符；四个脚本全树确证未接入，裁定不受此影响。
