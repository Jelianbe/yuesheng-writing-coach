# ADR-C73：splitContent 单段超长死循环修复 + 批次 I 四函数拆分

- **状态**：**已实施（2026-09-04，commit ad3ebcdf 基线 + 待 commit F 台账同步落定）**
- **日期**：2026-09-04
- **涉及模块**：`lib/services/progressive_diagnosis.dart`（分块诊断核心链路）/
  `lib/services/teacher_validator.dart` / `lib/services/training_evaluator.dart` /
  `lib/data/repositories/diagnosis_repository.dart`
- **起因**：批次 H 补测侦察（2026-09-04）实锤 `splitContent` 死循环缺陷；
  批次 G/H 合计补测 24 例、22/22 变异拦截后，四个 51–58 行函数护栏齐备，
  具备拆分条件。本 ADR 覆盖批次 I 全部改动（3 个行为不变重构 + 1 个行为
  变更修复），供新会话照做。

---

## 1. 结论先行

1. **`splitContent` 对单段超长文本死循环**：单段 ≥2998 字符（pLen≥3000）且
   总长 >3000 时，首段即达阈值 → `endIndex == startIndex` → 行 130 的
   max() 不推进 startIndex → while 永真（§2 证据链）。
2. **修复选方案 A（整段成块）**：首段即超阈值时强制 `endIndex = startIndex + 1`，
   单段无段落边界可切，整段独立成块（块可超 3000，保语义完整）（§3）。
3. **四函数拆分**：splitContent 拆 2 + 修死循环；checkTeacherConsistency
   职责级拆 2；**detectDeterioration 删冗余解包不拆**；
   _updateDiagnosisSummary 拆 1（§4）。
4. **全部为同文件私有方法拆分**，非 part/extension 伪拆分（X-025-ARCH 定性）。
5. **锚点快照零漂移**：四个文件均不在 `skill_registry` 内（ADR-C69 §6.4
   已证 progressive_diagnosis 不在内；其余三个同理）。

---

## 2. 死循环证据链（批次 H 侦察，2026-09-04）

### 2.1 代码推理（progressive_diagnosis.dart:87-144）

```
行 96   while (startIndex < paragraphs.length) {
行 101-109  for (i = startIndex; ...) { if (length + pLen >= SIZE) break; ... endIndex = i + 1; }
        ↑ 首段即超阈值：循环在 i == startIndex 就 break，endIndex 保持 startIndex
行 116   chunk = paragraphs.sublist(startIndex, endIndex)  ← 空块
行 121   overlapStart = endIndex - 1  ← = startIndex - 1 < startIndex
行 122   while (overlapStart > startIndex)  ← 不进
行 130   startIndex = overlapStart > startIndex ? overlapStart : startIndex  ← 不变
        → while 永真
```

### 2.2 实证

| 实验 | 结果 |
|:--|:--|
| `splitContent('X' * 4000)`（单段无 `\n\n`） | **三次全部挂死**，flutter test 零输出，进程被外部 SIGTERM |
| `splitContent('X' * 2999)`（同结构反证） | 正常返回单块，秒过 |
| 挂死时 `timeout: Timeout(Duration(seconds: 10))` | **不生效**——同步死循环阻塞 event loop，Timer 回调永不调度 |

### 2.3 生产影响

`runProgressiveDiagnosis` 入口阈值 `kDiagnosisChunkThreshold = 4000`（`:23`），
仅 >4000 字走分块链路。学员提交一篇 **>4000 字且中间无空行分段**的正文 →
诊断链路挂死 isolate（UI 冻结）。触发条件真实可达。

> 附带发现：flutter test 的用例级 Timeout 对同步死循环无效，进程级超时
> （如 `_verify_batch_h_coverage.py` 的 240s + taskkill /T）是唯一兜底。

---

## 3. 修复方案选项

| 方案 | 做法 | 判定 |
|:--|:--|:--|
| **A（已裁决）** | 首段即超阈值（`endIndex == startIndex` 且 reachedThreshold）时强制 `endIndex = startIndex + 1`，单段整块切出 | ✅ 终止性恢复；语义完整；块可超 3000（LLM 可处理，分块目的是控制上下文而非硬限） |
| B | 超长单段按 3000 字符硬切子段 | ❌ 机械破坏语义（句子/对话拦腰截断），违背「按段落分块」设计 |
| C | 超长单段跳过分块、整篇走单次链路 | ❌ >4000 字正是分块链路存在的原因，等于放弃该场景 |

方案 A 的语义：**单段是不可再分的原子单元**——段落是分块算法的边界，
段内不再切。与既有 overlap/末块合并逻辑正交。

修复后须补专属判据用例：「单段 4000 字符 → 返回非空且不挂死」（预期
1 块整段；变异验证用进程级超时兜底，复用 `_verify_batch_h_coverage.py`
的 H4 处理方式）。

---

## 4. 四函数拆分明细

| 函数 | 现状 | 方案 | 拆后预估 |
|:--|:--|:--|:--|
| `splitContent` 58<br>`progressive_diagnosis.dart:87` | 拆 2 + 修死循环 | 抽 `_overlapStartIndex(paragraphs, endIndex, startIndex)`（行 119-128 回溯段）+ `_mergeSmallLastChunk(chunks)`（行 133-141）；主循环加方案 A 的强制推进 | ~44 + ~12 + ~10 |
| `checkTeacherConsistency` 56<br>`teacher_validator.dart:404` | 职责级拆 2 | `_checkDecisionTaskConsistency(result, violations)`（行 407-431）+ `_checkLanguageHygiene(result, violations)`（行 433-455） | ~10 + ~26 + ~24 |
| `detectDeterioration` 52<br>`training_evaluator.dart:222` | **删冗余不拆** | 行 223-229 是 7 行纯解包（本地变量直抄 `input.` 字段），删除后改用 `input.xxx` | 45 |
| `_updateDiagnosisSummary` 51<br>`diagnosis_repository.dart:590` | 拆 1 | 抽 `_buildTopSyndromes(List<ActiveProblem> active)`（行 599-610 排序+截断+map） | ~40 + ~13 |

`detectDeterioration` 选删不选拆：AGENTS.md「多种实现选最简单」+ 删冗余
diff 最小。行为等价（纯名替换），由 H2 系变异兜底验证。

四个宿主文件（483–655 行）均已是登记债务状态，同文件加私有方法不新增
文件级违规。

---

## 5. 变异脚本锚点适配清单（`tool/_verify_batch_h_coverage.py`）

拆分改变代码形态，以下锚点须同步适配（其余锚点文本不变、仅行号漂移）：

| 变异 | 原锚点 | 拆分后的问题 | 适配 |
|:--|:--|:--|:--|
| H1-V2 排序 | `      const order = {...}`（6 空格，锚定行 601 区别于行 380） | 排序 map 搬进 `_buildTopSyndromes` 后缩进变 4 空格，**与行 380 的另一处撞车**（同为 4 空格） | 锚点扩为「排序 map + `active.take(3)`」多行块（在 `_buildTopSyndromes` 内唯一） |
| H2-V1 门槛2 | 多行锚点含 `consecutiveFailures >= 2` | 删解包后该行变 `input.consecutiveFailures >= 2`，且条件行可能因长度重排 | 锚点按拆分后实际文本重写 |
| H4-V1 恰等边界 | `if (content.length <= kDiagnosisChunkSize) {` | 文本不变，仍在 splitContent 内 | 无需改，仅确认仍唯一 |

适配后必须全量重跑：**15/15 拦截 + 新增死循环判据 ≥1** 方算护栏完好。

---

## 6. 影响面

| 面 | 影响 |
|:--|:--|
| 教学状态机 | 不触碰（detectDeterioration 行为等价） |
| DB schema | 不触碰 |
| 诊断解析 / 校验链路 | 不触碰 |
| **锚点快照** | **零漂移**（四文件均不在 skill_registry，无需 UPDATE_SNAPSHOTS） |
| 模型行为 | 仅死循环场景：挂死 → 正常分块诊断（预期内修复，**建议真机复核**一篇超长无分段正文） |
| R-019 基线 | **220 → 216**（清偿 4 个），须重生成 + V4.14 逐函数验证 |

---

## 7. 实施步骤（新会话照做）

1. 只读核对：git log -3 / git status / `python tool/check_r019.py --baseline
   tool/r019_baseline.json`（预期：HEAD 见交接快照、同步、基线 220、无超限）
2. 读本 ADR §4 逐函数拆分；**先改 splitContent + 修死循环 + 补「单段超长
   不挂死」用例**（progressive_diagnosis_test.dart，参考批次 H 的 #5 用例，
   输入 'X' * 4000）
3. 其余三函数按 §4 拆分/删冗余
4. 按 §5 适配 `_verify_batch_h_coverage.py` 锚点，全量重跑至
   15/15 + 新判据全拦截
5. `python tool/check_r019.py --json tool/r019_baseline.json` 重生成基线
   （**绝不带 `--baseline`**，V4.14 最阴的坑），确认 220→216
6. V4.14 验证：`tool/_verify_r019_baseline.py` 撑大 4 个函数至 55 行，
   确认新基线仍能拦（4/4），验证完恢复（V4.10）
7. 六道门禁 `bash scripts/gate.sh`；test 文件格式盲区手动补查（gate.sh
   门禁 0 只扫 lib——批次 G/H 两次实证）
8. 台账同步：批次 I 完成标注 + 基线 220→216 + 本 ADR 状态改「已实施」
9. 分 commit（代码+测试 / 基线 / 文档），推送先问舰长

---

## 8. 实施记录（2026-09-04 新会话回填）

- **代码改动**：
  - commit `f76ec872` `fix(svc): splitContent 拆 2 + 修单段超长死循环`
    progressive_diagnosis.dart splitContent 58→49；新 `_overlapStartIndex` (12) /
    `_mergeSmallLastChunk` (8)；死循环修复（首段即超阈值时整段成块 + `continue`）
  - commit `e2cae8b2` `refactor(svc): checkTeacherConsistency 拆 2`
    teacher_validator.dart 主函数 56→7；新 `_checkDecisionTaskConsistency` (22) /
    `_checkLanguageHygiene` (18)
  - commit `fc9516c7` `refactor(svc): detectDeterioration 删冗余解包`
    training_evaluator.dart 删 7 行解包；52→45；`input.xxx` 直引
  - commit `d691ccba` `refactor(repo): _updateDiagnosisSummary 拆 1`
    diagnosis_repository.dart 主函数 51→38；新 `_buildTopSyndromes` (14)
- **死循环判据用例**：progressive_diagnosis_test.dart
  - `#6 单段超长（>= SIZE 且无 \n\n）不挂死，整段成块`（输入 `'X' * 4000`）
  - `#7 字符串中间夹杂 \n\n 但首段即 ≥ SIZE → 首段成块 + 后续正常切`
- **变异复验**：`_verify_batch_h_coverage.py` 全量 **15/16 拦住**
  - H1-V1/V2/V3、H2-V1/V2/V3/V4/V5/V6、H3-V1/V2/V3/V4/V5、H5-V1 共 15 真覆盖
  - H4-V1 漏网：变异等价（`<=` → `<` 对 #5 单块断言无差别），按 V4.15 不硬凑
  - 新增 H5-V1 单段原子变异（挂死形式拦截），复用 240s + taskkill /T 兜底
  - 锚点适配 6 处（H5 新增；H2 五锚 input. 前缀；H1 两锚扩多行块）
- **基线重生成**：commit `ad3ebcdf` `chore(r019): 基线 220→216`
  - **`python tool/check_r019.py --json tool/r019_baseline.json`**（**绝不带 `--baseline`**）
  - 清偿 4 函数全部移出 baseline
- **V4.14 验证**：`_verify_r019_baseline.py` 4/4 通过
  - splitContent 撑到 94 → 拦住（退出码 1）
  - checkTeacherConsistency 撑到 52 → 拦住
  - detectDeterioration 撑到 55 → 拦住
  - _updateDiagnosisSummary 撑到 59 → 拦住
  - 恢复字节一致 + 恢复后退出码 0 ✅
- **门禁**：6 道门禁实质全绿（沙箱下门禁 2 用本地 wrapper `C:\Users\NewName\flutter_env.bat` 注入 PROGRAMFILES 跑全量，其他 5 道 `bash scripts/gate.sh` 直过）
  - 全量测试 **2364 passed / 14 skipped**（基线 2362 + 新增 #6 #7）
- **真机复核**：**未做**（生产路径 `runProgressiveDiagnosis` 死循环场景，sandbox 跑会触发 wrapper + 代理问题，建议舰长在真机或本地 developer 环境下做一次端到端：构造 `>4000` 字无 `\n\n` 长文走 D2 WritingCoachPanel 提交，确认不再挂死 isolate）
