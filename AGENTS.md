# 月笙写作教练 — AI 协作规则入口

> 本文档遵循 R-024（AGENTS.md 机制），是 AI 工具接入项目的第一站。
> 详细规则见 `.trae/rules/` 对应 R-XXX 文件。
> **最后更新：2026-08-29（V4）** — 技术栈已迁移至 Flutter，本文件同步重写。

---

## ⚠️ 动手前先确认：你在对的项目里

| 目录 | 状态 | 说明 |
|:--|:--:|:--|
| **`yuesheng-flutter/`** | ✅ **唯一活跃真源** | Flutter + Dart，**所有开发在这里** |
| `yuesheng-writing-coach/` | 归档维护 | Electron+React+TS，**已不再开发**，勿在此改代码 |
| `yuesheng-android/` | 已废弃 | — |

工作目录：`yuesheng-flutter/`

> 历史版本的本文件曾整篇描述 Electron 技术栈并指向 `yuesheng-writing-coach/`，
> 与真源完全脱节。若你看到其它文档仍指向 Electron 目录，以本文件为准。

---

## 技术栈

- **框架**：Flutter + Dart
- **状态管理**：Riverpod
- **持久化**：drift（SQLite）。生成文件 `database.g.dart` 勿手改
- **测试**：`flutter test`（当前基线 **2035 用例全绿**）
- **样式**：设计令牌（`lib/config/app_theme.dart` 的 `AppTextStyles` / `AppColors`），不写裸字面量
- **Prompt 真源**：`lib/services/skill_registry.dart` + 各 `skills_*.dart`（不是任何 .md 文件）

## 核心禁止事项

1. 不替用户写句子或做决定（R-009 用户主权，产品定位，最高优先）
2. 不顺手格式化 / 重构任务范围外的文件（R-010）
3. 不新增 A→B 静态映射表
4. 不硬编码 API Key 或敏感配置（R-029）
5. 不私造业务语义（Widget 内不得直接操作全局状态，须经 Provider）
6. 不引入当前未使用的新框架或第三方库

## 代码硬上限（R-019）

- **函数 ≤ 50 行**——这是**硬上限**，比文件行数更重要
- 文件 ≤ 300 行（现 76 个文件超限，已登记债务）
- **禁止用 `part` / `extension` 机械拆分服务层凑行数**
  → 批次 X-025-ARCH 已定性为**伪拆分**并回退 13 个 commit。
  实证代价：`ChatService.sendMessage` 迁至 extension 后，测试替身
  `_FakeChatService` 的 `@override` 契约断裂，触发 9 例 `pumpAndSettle` 超时。
  真分解 = 独立类 / 显式接口 / 依赖注入 / 职责级重构。
- 服务层超 300 行需走 **ADR 决策**，不得直接动手拆

## 边界防御（R-028）

- **边界层**（Repository / LLM Client / 平台通道 / 表单）：必须校验与 try/catch
- **内部层**（Provider 之间、纯函数之间）：不做防御性包装，信任类型系统
- **禁止空 catch**；确需静默降级必须留痕，用 `lib/services/decode_guard.dart`
- 例外：`error_log_repository.dart` 是日志写入方，内部不得调 `captureError`（会递归）

## 构建与测试（四道门禁，R-027）

声称完成前**四道必须全绿**：

```bash
# 1 格式 —— 只带本次改动的具体文件（禁止对整个目录跑）
dart format --set-exit-if-changed -o none <改动文件>

# 2 静态分析 —— 全 lib（import 变化可能影响其他文件）
flutter analyze lib --no-pub

# 3 循环依赖
python scripts/check_circular.py

# 4 全量测试（排除需真实 API Key 的用例）
flutter test --exclude-tags live,external --no-pub
```

> **CRLF 核验的口径陷阱（2026-09-02 实证，V4.4）**：项目要求「CRLF = 0」，
> 但这个 0 指的是**提交进仓库的内容（blob / 索引）**，**不是工作区文件字节**。
>
> 本仓库 `core.autocrlf = true`：add 时 CRLF→LF，checkout 时 LF→CRLF。
> 因此全仓 **721 个受版本控制文件里有 259 个工作区文件是 CRLF**（另有 4 个
> mixed）——这是配置的正常结果，**不是违规**。
>
> 直接读工作区字节去数 `\r\n` 会得到**假警报**：2026-09-02 我就据此误判
> 「本批引入了 145 / 460 处 CRLF」，实际 `git diff --cached --stat` 显示
> 只是 35 / 218 行的内容级改动，blob 始终是全 LF。
>
> **正确做法**——用 `git ls-files --eol`，看 **`i/` 列**（索引）：
> ```bash
> git ls-files --eol -- <改动文件>     # i/lf = 合规；i/crlf = 违规
> ```
> 判别口诀：**看 `i/` 不看 `w/`，看 blob 不看工作区。**
>
> 反过来说，也**不要**因为工作区是 CRLF 就去批量转 LF——`autocrlf=true`
> 下下次 checkout 又会变回 CRLF，纯属无效churn。

> **⚠️ format 门禁的退出码陷阱（2026-09-02 实证，V4.5）**：两件事会让
> 格式门禁**假绿**，且都不报任何错误：
>
> 1. **管道后取 `$?` 拿到的是管道最后一条命令的退出码**——
>    ```bash
>    dart format --set-exit-if-changed -o none lib | tail -3; echo $?
>    # ↑ 这是 tail 的退出码，恒为 0，与 dart format 完全无关。
>    #   实测：文件确实需要格式化（exit 1），屏幕上却打出 FORMAT_EXIT=0。
>    ```
>    正确做法——重定向到文件再取退出码：
>    ```bash
>    dart format --set-exit-if-changed -o none lib > /tmp/fmt.txt 2>&1
>    echo "FORMAT_EXIT=$?"; cat /tmp/fmt.txt
>    ```
>    同理适用于任何 `cmd | tail` / `cmd | grep` 之后取 `$?` 的场景。
>
> 2. **`--set-exit-if-changed -o none` 只检查、不写入**。它返回 1 时文件
>    并未被修改，需要先跑一次不带 `--set-exit-if-changed` 的
>    `dart format <file>` 写入，再重新校验——否则门禁会一直红。
>    ```bash
>    dart format <file>                                  # 先写入
>    dart format --set-exit-if-changed -o none <file>    # 再校验
>    ```

> Windows 注意：`flutter test` 需保证系统 TEMP 所在盘有足够空间
> （编译产物数百 MB）；磁盘满会报 `errno = 112`。

> **测试跑不起来先查代理**（2026-08-31 实证）：若环境注入了 `HTTP_PROXY`
> /`HTTPS_PROXY`（AI 工具会话常见）而**未设 `NO_PROXY`**，flutter_tester 的
> 本地 WebSocket 会被代理劫持，报
> `Unable to connect to flutter_tester process: WebSocketException:
> Invalid WebSocket upgrade request`。
> **这是 `Failed to load`（进程级），不是断言失败**——表现为所有测试文件
> 无一例外全部起不来，与代码改动无关。判别方法：跑一个完全不相关的测试
> 做对照，若同样失败即为环境问题。
> 解法：跑测试时剥掉代理变量。
> ```bash
> env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
>     NO_PROXY="localhost,127.0.0.1" no_proxy="localhost,127.0.0.1" \
>     flutter test --exclude-tags live,external --no-pub
> ```
>
> **⚠️ 反向陷阱（2026-09-02 实证，比上一条更危险）**：上面这条命令**只在
> 环境里确实有代理变量时**才成立。当前会话已无代理变量（AI 工具会话不注入
> 是常态），此时 `env -u HTTP_PROXY ...` 在 Git Bash / Windows 下会让整条
> 命令**静默失效——exit 0、stdout 与 stderr 全空**。
> 这比 `Failed to load` 危险得多：后者会报错，前者看起来像"测试全部通过"。
> 实证形态：`flutter test <任意文件>` 有输出，加上 `env -u ...` 前缀后变成
> 零输出；连 `env -u ... dart --version` 都不打印版本号。
> **正确做法**：先确认再决定要不要剥——
> ```bash
> echo "[$HTTP_PROXY][$HTTPS_PROXY][$http_proxy]"   # 全空就直接跑，不加 env -u
> flutter test --exclude-tags live,external --no-pub
> ```
> 判别口诀：**有输出在跑，零输出先查是不是被 `env -u` 吃掉了。**

## Prompt 入口规则

- 教练定位：不替写、不替决定、找根因
- 态度档位：豆包（默认）/ 月笙如歌 / sensei
- 安全词："轻一点"无条件降档
- 真源：`lib/services/skills_attitude.dart`
- 改 Skill 内容 = 改注入 prompt，会改变 AI 行为 → 属高风险，需人工确认（R-027 门禁 4）

## 不确定时的默认行为

- 风格冲突 → 沿用目标文件已有风格
- 多种实现方式 → 选最简单的那一个
- 改动范围有争议 → 只改最小必要范围
- 未验证的功能 → 必须明确声明"未验证"
- 涉及核心模块（诊断 / Skill 注入 / 教学状态机 / DB schema）→ 必须先写 ADR

## 规则索引

| 编号 | 主题 | 层级 | 文件 |
|:----:|------|:----:|------|
| **R-009** | **用户主权（兜底条款）** | **L1** | `.trae/rules/R-009-用户主权.md` |
| **R-029** | **安全与隐私（密钥零硬编码）** | **L1** | `.trae/rules/R-029-安全与隐私.md` |
| R-019 | 代码规范标准（硬上限） | L1 | `.trae/rules/R-019-代码规范标准.md` |
| R-016 | Git 提交规范 | L1 | `.trae/rules/R-016-Git提交规范.md` |
| **R-027** | **AI 代码质量门禁（四道）** | L3 | `.trae/rules/R-027-AI代码质量门禁.md` |
| R-013 | 测试覆盖率要求 | L3 | `.trae/rules/R-013-测试覆盖率要求.md` |
| R-021 | AI 行为边界 | L3 | `.trae/rules/R-021-AI行为边界.md` |
| R-010 | 最小化范围 | L3 | `.trae/rules/R-010-最小化范围.md` |
| R-017 | 文档与报告管理 | L2 | `.trae/rules/R-017-文档与报告管理规范.md` |
| R-024 | AGENTS.md 机制（本文档） | L3 | `.trae/rules/R-024-AGENTS.md机制.md` |
| R-020 | 循环依赖零容忍 | L3 | `.trae/rules/R-020-循环依赖零容忍.md` |
| R-028 | 防御性编码 | L3 | `.trae/rules/R-028-防御性编码.md` |
| R-006 | 回退机制规范 | L2 | `.trae/rules/R-006-回退机制规范.md` |
| 完整清单 | 全部活跃规则 | - | `.trae/rules/月笙项目开发规则汇总.md` |

## 项目文档（Flutter 真源侧）

| 文档 | 路径 |
|:--|:--|
| **文档总索引（README）** | **`yuesheng-flutter/docs/README.md`** |
| 待办执行清单 / 批次台账 | `yuesheng-flutter/docs/待办执行清单.md` |
| 启动提示词 | `yuesheng-flutter/docs/启动提示词.md` |
| 宪法草案 | `yuesheng-flutter/docs/yuesheng-flutter-宪法草案.md` |
| 设计文档 | `yuesheng-flutter/docs/designs/` |
| 体检 / 审计报告 | `yuesheng-flutter/docs/audits/` |
| Skill 速查表 | `yuesheng-flutter/docs/tasks/SKILLS-QUICKREF.md` |
| 反馈报告模板 | `yuesheng-flutter/docs/tasks/FEEDBACK-REPORT-TEMPLATE.md` |
| 代码审查清单 | `yuesheng-flutter/docs/standards/CODE_REVIEW_CHECKLIST_V1.0.md` |

## 最后更新

2026-08-29 — V4：技术栈由 Electron 迁移至 Flutter，工作目录改至
`yuesheng-flutter/`；门禁改为四道 Flutter 命令；移除整节 IPC 规范；
补入函数 50 行硬上限与 part/extension 伪拆分禁令；文档索引指向 Flutter 真源侧。
（V4.1：补入文档总索引与 R-030 三份流程模板的路径，原缺口已补齐。）
（V4.2：门禁节补入「测试跑不起来先查代理」——HTTP_PROXY 无 NO_PROXY 时
flutter_tester 本地 WebSocket 被劫持，表现为所有测试 Failed to load。）
（V4.3：同节补入反向陷阱——**没有**代理变量时 `env -u` 会让命令静默失效，
exit 0 且零输出，看起来像"测试全过"。先 `echo $HTTP_PROXY` 再决定要不要剥。）
（V4.4：CRLF 核验的口径陷阱——要求「CRLF=0」指提交进仓库的 blob，不是工作区
字节；本仓 `autocrlf=true`，721 个文件里 259 个工作区文件本就是 CRLF。
正确口径是 `git ls-files --eol` 的 `i/` 列。口诀：看 `i/` 不看 `w/`。）
（V4.5：format 门禁的退出码陷阱——① `cmd | tail` 之后取 `$?` 拿到的是 tail
的退出码，会让红门禁显示为绿；② `--set-exit-if-changed -o none` 只检查不写入，
需先 `dart format` 写入再校验。）
（V4.6：抽测文件名凭记忆写的假失败陷阱——`flutter test` 对不存在的路径报
`Failed to load "..." : Does not exist`，红得很像真实回归失败，实际只是文件名
猜错了。本仓测试命名多为 `<被测对象>_<修饰>_test.dart`（如
`focus_resolver_coverage_test.dart`），凭记忆补后缀极易错。
**抽测前先 `ls test/ -R | grep -i <关键词>` 确认真实文件名**，别直接把猜测的路径
喂给 flutter test。判别：报错信息里带 `Does not exist` 的一律先查路径。）
（V4.7：源码扫描护栏的「出现过」假判据陷阱——2026-09-03 ADR-C66 实证。用
`src.contains('UILimits.xxx')` 断言「某文件引用了某常量」**拦不住改坏其中一处**：
同一标识符在同一文件内多处出现时（阈值处 1 次 + 文案插值 1 次），把阈值写回字面量
后，文件里**仍然出现**该常量名，`contains` 依旧为 true。实测变异测试显示
**全部通过**——护栏是假的。此外配套的裸数字正则只匹配「数字 + 字」，
拦不住 `if (text.length < 20)`（数字后面没有「字」）。
**修正：凡护栏针对「多处应当一致」的不变量，必须断言出现次数
（`'Xxx'.allMatches(src).length == 期望值`）或逐处位置，不能只断言存在性。**
推论：**新护栏必须做变异测试**才能发现这类假判据——只看「测试绿了」毫无意义，
ADR-C66 的三个变异里正是 B 这个「看起来最该被拦住」的漏了网。
另：裸数字类正则要覆盖「数字 + 单位」之外的形态，或改用计数判据兜底。）
（V4.8：源码扫描护栏的「总数 ≥ N」假判据陷阱——2026-09-03 ADR-C67 实证。
V4.7 说「不能只断言存在性」，本条补其延伸：**也不能只断言总数**。
断言「N 个文件里某标识符的**总**出现次数 ≥ N」拦不住「其中一处缺失、别处
重复」——实测：三处封顶说明删掉一处后，因该文件别处也有同名字样，总数
恰好仍是 3，断言通过。凡是「每处都应当满足」的不变量，必须**逐处**断言
（对每个文件各自 `>= 1`），不能先求和再与处数比。
口诀：**逐处判，别求和。**）
（V4.9：prompt 类改动前必须查证「这段文本真的会被注入」——2026-09-03
ADR-C67 实证。写在源码文件里 ≠ 模型看得到。症候库 / 手册类内容常按 ID
**切片注入**（`_extractSyndromeSection` 只提取 `### P0XX` 段，且刻意排除
手册尾部的「类型速查 / 诊断规范 / 重叠规则」），导致台账记的「无上限侧 6 处」
里**只有 1 处真正进入模型输入**——首轮改动改到了模型看不到的地方，白加 65 字。
判别方法：① 查该常量被谁引用、怎么注入；② 改完跑锚点看漂移——**零漂移即零生效**。
已固化为护栏断言（ADR-C67 §5 断言 ⑤）：分工说明必须落在会被注入的常量区间内。）
