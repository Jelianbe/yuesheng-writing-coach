# ADR-C74 K-9 收尾报告 — ChatService 真分解：DiagnosisFlowHandler + MessageInjector

> 日期：2026-09-05｜批次：ADR-C74 K-9（含 K-7 装配收尾）
> 归档：docs/audits/｜类型：重构收尾审计（B 类 · 债务清偿）

---

## 一、任务定义

| 项 | 内容 |
|:--|:--|
| **分类** | B 类（功能/体验/债务） |
| **复杂度** | 🏗️ 大型（≥4 文件） |
| **目标** | 清偿 ChatService 超限函数，真分解为独立类 + 显式 DI（禁 extension，X-025-ARCH 教训） |
| **验收** | R-027 六道门禁全绿 + R-019 基线收紧（V4.14）+ K-9 mutation 验证 |

## 二、交付内容

### 2.1 K-7 MessageInjector（`lib/services/message_injector.dart`，1463 行）

5 公开 API + 11 helper + `_insertPhaseSummaryOnMastered` + 4 缓存字段，承载 ChatService 迁出的引用注入逻辑。

### 2.2 K-9 DiagnosisFlowHandler（`lib/services/diagnosis_flow_handler.dart`，903 → 1169 行）

从 ChatService 迁出 4 个诊断链方法，本次收尾新增：

- **parseAndPersist（155 行 → 主方法 + 7 helper）**：拆为
  `_parseAndValidate` / `_persistContentArtifacts` / `_validateDiagnosisBlock` /
  `_triggerTeacherForDiagnosis` / `_persistParsedOutput` / `_resolveFinalAssistantContent` /
  `_abortedResult`，并用 3 个 record typedef（`ParseAndPersistResult` / `_ParsedOutput` /
  `_TeacherOutcome`）具名化中间结果。
- **commitDiagnosisFromContent（147 行 → 主方法 + 5 helper）**：`_parseDiagnosisFromContent` /
  `_persistOutlineAndStrip` / `_writeAssistantMessage` / `_resolvePrimaryRef` /
  `_persistDiagnosisFromContent`。
- **commitDiagnosisAndSuggestions（97 行 → 主方法 + 5 helper）**：`_insertGenuiCardIfAny` /
  `_commitDiagnosisWithCard` / `_buildDiagnosisInput` / `_persistStyleProfileIfAny` /
  `_persistTeacherSuggestionIfAny`。
- **handleTrainingResult（51 行 → 主方法 + `_recordTrainingFeedback`）**。

### 2.3 chat_service.dart（1654 → 859 行）

- 删除 3 个 extension（ChatServiceDiagnosis / ChatServiceSendParse / ChatServiceSendPersist）
- 新增字段 `final DiagnosisFlowHandler _diagnosisFlowHandler;` + 构造参数 `required diagnosisFlowHandler`
- 委派 `_diagnosisFlowHandler.*`

### 2.4 chat_message_types.dart（59 行，新建）

拆出 `SendMessageCallbacks` / `SendMessageOptions`，打破 SendMessage 类型与 ChatService 的循环依赖。

### 2.5 session_providers.dart 装配

`diagnosisFlowHandlerProvider`（161-181 行）+ `chatServiceProvider` 注入 `diagnosisFlowHandler: ref.watch(...)`。

## 三、fixture 修复战役（本批核心工作）

v1-v3 Python 装配脚本在 23 个测试文件留下畸形诊断块（空参头 + 参数被 `),` 包裹 + 整块重复 2 份 + 24 处 `\),` 残留），本批修复路径：

1. `_k9_fix_fixtures.py`：修复 23/23 文件畸形块（计数判据通过）
2. **import 库路径错误**：`DiagnosisCapabilityImpl` 真身在 `diagnosis_parser.dart:458`，
   修正 26 处错误 import + 删除 186 处 unused import（`_k9_fix_imports.py`）
3. **SendMessageCallbacks/Options 未定义**：22 个测试 + 1 个 lib part 补 import（`_k9_fix_cmt_imports.py`）
4. **DiagnosisFlowHandler 缺 required messageInjector**：26 文件 29 块补配（`_k9_fix_dh_message_injector.py`，
   v2 配对规则规避 v1 的自污染 bug）
5. **phase_migration 游离碎片** + **live_full_loop 错位** + **chat_page_test 假构造**：人工修复

修复后计数判据：`diagnosisFlowHandler: DiagnosisFlowHandler(` 次数 == `\bChatService\(` 次数，`\),` 残留 0，空参块 0。

## 四、R-019 净化（函数 ≤ 50 行硬上限）

K-9 新增 3 个超限函数已拆（见 2.2），最后一个 parseAndPersist（155 行）本次拆完：

- **拆分手段**：record typedef 具名化 + 7 个私有 helper（R-019 扫描器按掩码配平计数，
  多行 record 签名起点为 `parseAndPersist({` 所在行，必须压到 ≤50）
- **门禁 5 止血模式**：`python tool/check_r019.py --baseline tool/r019_baseline.json` → 0 新增超限 ✓
- **基线收紧（V4.14 硬约束）**：`python tool/check_r019.py --json tool/r019_baseline.json`
  （**绝不带 --baseline**）→ 重生成 204 条
- **验证仍能拦**：`python tool/_verify_r019_baseline.py`（parseAndPersist 撑到 80 行 →
  报出 + 退出码 1；恢复字节一致 + 恢复后止血模式退出码 0）✓

## 五、K-9 mutation 验证（判据级，V4.20/V4.21 精神）

`tool/_k9_mutation.py`（try/finally 恢复 + 锚点校验 + 基线健康校验 + 收尾 git diff 复核）：

| 变异 | 判据 | 结果 |
|:--|:--|:--|
| M1 | `_triggerTeacherForDiagnosis` 只诊断边界反转 | **拦截** ✓（补 FT-22 判据测试：streamChat 计数 == 1） |
| M2 | `_validateDiagnosisBlock` JSON 二次校验跳过 | **拦截** ✓ |
| M3 | `_resolveFinalAssistantContent` 空响应判真故障失效 | **拦截** ✓ |
| M4 | `_persistParsedOutput` aborted 反转 | **拦截** ✓ |
| M5 | `_resolveFinalAssistantContent` outline 兜底计数反转 | **漏网**（known 预存盲区，见 §六.2） |

未拦截变异：**无**（M5 标记 known 不计入失败）。退出码 0。

## 六、已知债务 / 遗留

### 6.1 门禁 1（analyze lib）

仅剩 7 个 K-1 预存 warning（diagnosis_committer.dart：6 unused_field + 1 unintended_html），
与交接基线一致，无 error。

### 6.2 M5 预存盲区（✅ 2026-09-05 已补测，见 §十）

`_resolveFinalAssistantContent` 的空诊断 + chapter outline 兜底分支
（`else if (_ensureOutlineService() != null && primaryRef?.refType == 'chapter')`
→ `if (c > 0) treatAsValid = true`）在 K-9 收尾时**任何现有测试中都不可达**——没有测试给
DiagnosisFlowHandler 装配 outlineRepo，`_ensureOutlineService()` 恒为 null。

- 预存逻辑（从原 ChatService 逐行搬移），非 K-9 新增判据
- 2026-09-05 已补测：`test/services/diagnosis_flow_outline_fallback_test.dart` 3 例
  （装配 outlineRepo + 四层 fixture + FakeLlmClient('') 空响应），M5 变异
  （`c > 0` → `c < 0`）被 #1 判据拦截，详见 §十

## 七、六道门禁结果（R-027）

| 门禁 | 命令 | 结果 |
|:--|:--|:--|
| 0 format | `dart format --set-exit-if-changed -o none` | ✓ 0 changed |
| 1 analyze | `flutter analyze lib --no-pub` | ✓ 7 K-1 预存 warning（无 error） |
| 2 test | `flutter test --no-pub` | ✓ **2374 passed + 14 skipped** |
| 3 循环依赖 | `python scripts/check_circular.py . --baseline ...` | ✓ 294 modules，0 存量环 |
| 4 密钥 | `python tool/_k9_check_secrets.py`（bash 等价的 PowerShell 可跑版） | ✓ OK |
| 5 R-019 | `python tool/check_r019.py --baseline ...` | ✓ 0 新增超限 |

> 注：本机 PowerShell 无 bash，`scripts/check_secrets.sh` / `scripts/gate.sh` 无法直接跑，
> 密钥扫描用 Python 等价实现（正则逻辑一致），其余门禁逐道手跑。

## 八、验证方式与覆盖范围

- **验证方式**：六道门禁逐道手跑 + 全量测试 2374 通过 + mutation 5 变异（4 拦截 1 known）
- **覆盖范围**：诊断链 4 个方法全部拆完；K-9 fixture 修复 23 文件 + 3 层连环问题全解决
- **仍存在的缺口**：门禁 1 的 7 个 K-1 warning 待后续消费 capability 时消除（M5 盲区已补测闭环）

## 九、临时脚本处置

- **保留**：`tool/_k9_mutation.py`（K-9 护栏验证，可复跑）
- **保留**：`tool/_k9_check_secrets.py`（密钥扫描 PowerShell 版）
- **清理**：`tool/_k9_split_parseandpersist.py`、`tool/_k9_split_commit.py`、`tool/_k9_patch_fixtures.py`、
  `tool/_k9_fix_fixtures.py`、`tool/_k9_fix_imports.py`、`tool/_k9_fix_cmt_imports.py`、
  `tool/_k9_fix_dh_message_injector.py`、`tool/_k9_backup_dh.py` 等一次性修复脚本（保留 mutation + secrets 两个）
- **备份**：`D:\ai-teacher\_k9_backup_stash\`（23 文件修复前 + dh_fix2 子目录 26 文件补丁前）

---

*建立：2026-09-05｜ADR-C74 K-9 收尾*

## 十、M5 盲区补测（2026-09-05）

- 新文件：`test/services/diagnosis_flow_outline_fallback_test.dart`（3 例）
- #1 空响应 + 无诊断 + chapter 有 outline 实体 → 兜底判真不 abort（onError 不触发 + assistant 落库「诊断完成。」）
- #2 无实体 → abort（onError「AI 返回为空」）
- #3 主引用非 chapter → abort
- 变异验证：`tool/_k9_m5_mutation.py`（try/finally 恢复 + 锚点校验），`c > 0` → `c < 0` 被 #1 拦截 ✓，恢复后 diff 为空
- 全量回归：`flutter test --no-pub` 结果见 §七
