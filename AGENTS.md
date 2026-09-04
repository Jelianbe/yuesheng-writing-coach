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
- **测试**：`flutter test --exclude-tags live,external --no-pub`（当前基线 **2298 用例全绿**，2026-09-03 A.12.37 核）
- **变异验证脚本**：`yuesheng-flutter/tool/_c68_mutation.py`（ADR-C68）、`_c69_mutation.py`（ADR-C69）；改源码做验证的脚本范式，见 V4.10
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

## 构建与测试（六道门禁，R-027）

声称完成前**六道必须全绿**。编号与 `scripts/gate.sh` 一致（0–5），一键跑全六道：

```bash
bash scripts/gate.sh          # 日志落 outputs/gate/，报告 gate-report.md
```

手动逐道：

```bash
# 0 格式
dart format --set-exit-if-changed -o none <改动文件>

# 1 静态分析 —— 全 lib（import 变化可能影响其他文件）
flutter analyze lib --no-pub

# 2 全量测试
flutter test --no-pub

# 3 循环依赖（止血：存量 3 环豁免，只卡新增）
python scripts/check_circular.py . --baseline tool/circular_baseline.json

# 4 安全 / 密钥
bash scripts/check_secrets.sh

# 5 R-019 函数行数（止血模式：存量豁免，只卡新增）
python tool/check_r019.py --baseline tool/r019_baseline.json
```

> **门禁 2 的两种跑法，别混用**
> - `scripts/gate.sh` 里是 `flutter test` **全量**（门禁口径，收尾前跑）。
> - 日常改动后可先**抽测**受影响的测试文件，最后再跑一次全量收敛。
>   抽测前先 `ls test/ -R | grep -i <关键词>` 确认真实文件名（V4.6：凭记忆
>   写路径会得到「找不到文件」的假失败，看上去像测试挂了）。
> - 需真实 API Key 的用例用 `--exclude-tags live,external` 排除。

> **门禁 5 的止血模式与「清偿后必须收紧基线」（V4.14）**
> `tool/r019_baseline.json` 是存量债务快照（当前 **235 条，只计手写代码**），
> 带上 `--baseline` 时**只卡新增**超限，存量全部豁免——这是刻意的，否则 235
> 个函数会让此后每个提交都红灯，门禁会被当噪音绕过。
> 扫描器**默认排除生成文件**（`*.g.dart` / `*.freezed.dart`，`--include-generated`
> 可计入）：`database.g.dart` 一个文件就贡献 27 条超限，改了会被 build_runner
> 覆盖，**永不可清偿**——不排除它，「清偿完就转全量卡口」这个目标永远达不成。
> **代价**：基线一旦生成就不会自动变严。**每清偿一个函数，必须重生成基线**，
> 否则该函数被永久豁免、门禁形同虚设：
> ```bash
> python tool/check_r019.py --json tool/r019_baseline.json
> ```
> **重生成时绝不能带 `--baseline`**——脚本落盘的是**过滤后**的结果，
> 带 `--baseline` 时写进去的只是「新增项」，等于把 262 条债务一笔勾销，
> 且此后所有新超限都被当成存量豁免。这是本条最阴的坑：**同一个参数，
> 拿来「检查」是对的，拿来「重生成」就是自杀。**
> 重生成后**必须验证新基线仍然能拦**：把刚修好的函数临时撑回 60 行，
> 止血模式应报出且退出码非 0；验证完再恢复（V4.10：改源码验证务必恢复）。
> 可复现脚本：`yuesheng-flutter/tool/_verify_r019_baseline.py`。
>
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
- 改 Skill 内容 = 改注入 prompt，会改变 AI 行为 → 属高风险，需人工确认（R-027）

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
| **R-027** | **AI 代码质量门禁（六道）** | L3 | `.trae/rules/R-027-AI代码质量门禁.md` |
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
`yuesheng-flutter/`；门禁改为四道 Flutter 命令（**2026-09-03 起扩为六道**：
新增安全 / 密钥扫描与 R-019 函数行数，编号 0–5，见「构建与测试」节）；
移除整节 IPC 规范；
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
（V4.10：改源码做验证的脚本必须 **try/finally 恢复**，且备份要校验锚点存在
——2026-09-03 ADR-C68 实证。变异测试脚本「注入变异 → 跑测试 → 恢复」的
三段式里，跑测试那一步抛异常（python 子进程找不到 `flutter`）会直接终止
进程，**恢复逻辑从未执行**，源码被永久留在「已变异」状态。更隐蔽的是：
脚本下一轮把「已损坏的文件」当成备份基线，于是后续 4 个变异的结果全部
被污染，表现为「删掉 JSON 段说明」却报 N35 断言失败——**症状与病因相隔
两个文件**，差点误判成护栏写错。
三条硬要求：
① 注入与恢复之间必须用 `try/finally`，异常路径也要恢复；
② 变异注入前先校验锚点片段存在，找不到就 **INJECT-FAILED** 并显式报出，
   不要静默 continue（本批正是靠这条发现了污染）；
③ 验证跑完后必须 `git diff` 复核工作区与预期一致，不能只信脚本自述。
**判别：任何「验证脚本改过源码」的任务，收尾时都要人工比对一次 diff。**）
（V4.11：护栏的位置判据要**同时设上界和下界**——2026-09-03 ADR-C68 实证。
V4.9 已要求「说明必须落在会被注入的区间内」，但只判「在 A 之后、在 B 之前」
仍留盲点：把说明插在 A 的内容末尾与 B 的声明之间，位置判据照样通过，
而那里并不在模型逐段遵循的路径上。
补法：把下界收紧到**最近的语义锚点**（ADR-C68 用的是「## 输出格式」标题），
并补一个专门验证该下界的变异（变异 H 实测命中）。
**判别：位置类断言要能回答「挪到哪里会失败」，若只能想到一个失败位置，
说明下界太松。**）
（V4.12：**清单 / 范围 / 计数这类"同一事实的多处表述"，要么由单一真源派生，
要么必须有覆盖一致性护栏——没有第三种选择**——2026-09-03 ADR-C69 实证。
长文本分块 prompt 硬编码了 19 个症候，而注册表已扩到 39 个，缺失的 20 个
在分块路径下**从未可用**，且潜伏了整个项目周期。
漏了整整两次扩容的原因有两条，都值得单独记住：
① **一致性测试的覆盖范围本身就是盲区来源**——`four_libraries_consistency_test`
   覆盖了「四库」，`progressive_diagnosis.dart` 不在其列，于是扩容时既没同步、
   也没测试报错。测试绿 ≠ 没漏，只说明**被测到的地方**没漏。
② **锚点测试只覆盖 `skill_registry` 内的 skill**——`kChunkSystemPrompt`
   是独立常量，改它**零锚点漂移**。所以「锚点没动」不能当作此处的安全信号。
判别口诀：**新增任何枚举 / 清单 / 范围类内容时，先问两句——
「它由谁派生？」和「扩容时谁会同步它？」，两句都答不上来就别手写。**）
（V4.13：**注释不是代码，判据要锚定生效位置**——2026-09-03 ADR-C69 实证。
护栏断言「源码中不得出现字面量 X」时，若直接全文扫描，会把 ADR 注释里
**记录历史**的那一句（「原硬编码 X」）也判为违规。
同类还有：把 prompt 里所有 `- ` 开头的行都算作清单行，结果把例外指引
（`- P003例外：…`）也算进去，每个 ID 都被误判重复。
补法：断言锚定**生效位置**（如「症候编号 」之后跟的必须是插值而非字面量），
而不是全文匹配裸字符串。
**判别：源码扫描类断言若出现无法解释的红，先查是不是扫到了注释或同形结构。**）
（V4.14：**「豁免基线」不会自己变严，清偿后必须重生成并验证仍能拦**
——2026-09-03 R-019 止血模式实证。为让新门禁可落地，用
`tool/r019_baseline.json` 做豁免基线，只卡新增。
这是必要的妥协，但有两个反直觉的副作用：
① **基线一旦生成就永久宽松**：清偿完的函数仍留在基线里，若不清基线，
   它此后**再涨回 100 行也不会被拦**——门禁从「止血」退化成「装饰」。
   故每清偿一批必须重生成基线（本批 264 → 262，再因排除生成代码 → 235）。
② **基线收紧本身也要验证**：重生成后把已修函数临时撑回 60 行，
   止血模式必须报出且退出码非 0；若仍静默通过，说明基线没真正生效。
   本批实测：撑回 83 行 → 报出 + 退出码 1，验证通过后才提交。
③ **基线里混进「永不可清偿」的条目，会让终点永远到不了**——
   `database.g.dart`（Drift 生成）一个文件贡献 27 条，改了会被 build_runner
   覆盖。判据：**豁免基线里的每一条都必须是「人能改的」**，否则它不是债务，
   是噪音。此类文件应在扫描阶段排除，而不是塞进基线豁免。
**判别：任何带「存量豁免 / allowlist / 基线」的门禁，都要问一句
「已修的东西回归了会不会被拦」，答不上来就等于没门禁。**）
（V4.15：**护栏失效有三种无声形态，「测试绿了」一个都证明不了**
——2026-09-03 门禁 3 实证。循环依赖扫描跑了无数次、次次计入「通过」，
实际**一个文件都没扫过**。三层缺陷叠加，任一层单独存在就足以让它失效：
① **环境错误 + 失败开放**：gate.sh 传 Git Bash 路径 `/d/...`，Windows 原生
   python 解析不了 → `lib not found`，而脚本此时 **return 0 静默放行**。
   护栏的缺省必须是**拦下**，不是放行——否则环境一出错它就消失得无声无息。
② **输入不完整**：建图只认 `./` 和 `../` 开头的相对导入，而本项目 177 条边
   （占内部边 21.7%）是裸写形式 `import 'app_theme.dart';`，全部不进图。
   等于在缺了五分之一边的图上做环检测——扫了，但什么也看不见。
③ **报告与判据脱节**：汇总按退出码算出「6 通过」，表格却按 `grep 'OK:'` 显示
   「FAIL」，同一份报告自相矛盾，反而把问题藏得更深。
**新护栏 / 新门禁的验收要做两次变异，缺一不可：**
   - **能失败**：喂一个已知坏输入（真环 / 超长函数 / 错误路径），必须报出且退出码非 0；
   - **能抓到真问题**：在**真实代码**里造一个符合项目写法的问题（不是教科书写法），
     确认它抓得到——本次若不按项目实际用的裸相对导入去造环，第 ② 层缺陷就发现不了。
另：**报告里的一切判定都要回到退出码**，不要二次解读日志文本。
修复后它立刻暴露出 3 个真实存量环（Dart 允许循环 import，此前毫无症状），
再次印证 V4.9 那条：**没报问题，常常不是因为没问题，而是因为它没在看。**）
（V4.16：**变异「漏网」时，先分清是测试失灵还是变异本身等价**
——2026-09-04 token_budget_guard 补测试实证。变异测试报「漏网」，第一反应
容易是「测试没写好」，但还有另一种可能：**这个变异根本不改变可观测行为**。
实证：`_planRemovals` 首行就是 `if (current <= maxBudget) break`，所以主函数的
`if (total <= maxBudget)` 改成 `<` 后，即便走进裁剪分支也会立即跳出，
结果与 no-op **完全一致**——这个变异是可观测等价的，任何测试都拦不住它。
强改测试去「抓住」一个等价变异，是自欺欺人。正确做法：换一个能真正区分
行为的变异（本次换成「把 no-op 分支的 totalAfter 清零」）。
另：判据不能用「用例名出现在输出里」——flutter test 通过和失败**都会**打印
用例名，那样判据恒为真（V4.7「出现过」假判据的重演）。要判定该行带失败标记
`[E]`，或直接用结构化 reporter。
**判别：变异漏网先问「这个改动在行为上能被观测到吗」，答不上来就换变异。**）
（V4.17：**`dart format` 实际写入时会把整个文件重置为 LF**
——2026-09-04 R-019 清偿实证。本仓 `core.autocrlf=true`，工作区文件是 CRLF。
用 `dart format <file>`（不带 `-o none`）**改动文件**后，全文件行尾变 LF；
而 `--set-exit-if-changed -o none` 只检查不写入，**不比较行尾**，所以门禁 1
不会报错——问题只在后续步骤才暴露：用 CRLF 锚点做脚本注入的文本处理全部失效
（本次 162 行被悄悄改成 LF，导致验证脚本的锚点匹配全部落空）。
**判别：凡是用 Edit 改过、又跑过 format 写入的文件，若后续有锚点类脚本，
先核一遍行尾**。`git ls-files --eol` 的 `i/` 列仍会是 `lf`（提交层面无损），
所以这个坑不会被任何门禁拦下。）
（V4.18：**跑 `flutter test` 前必须清空会话的 HTTP 代理环境变量**
——2026-09-04 ADR-C72 收尾实证。症状：所有测试（**包括上一轮刚跑全绿的**）
集体报 `Failed to load ...: Unable to connect to flutter_tester process:
WebSocketException: Invalid WebSocket upgrade request`。排查方向很容易跑偏：
flutter 工具链完好、`flutter_tester.exe` 能正常启动、无残留进程、沙箱外也一样
——真正的元凶是会话注入的 `HTTP_PROXY=http://127.0.0.1:<port>`：Dart VM 连
flutter_tester 的 **localhost WebSocket 也被送去代理**，握手被吃掉。
解法：`env HTTP_PROXY= HTTPS_PROXY= http_proxy= https_proxy= \
NO_PROXY=localhost,127.0.0.1 flutter test ...`（`scripts/gate.sh` 同理）。
**这个故障格外阴险**：加载失败的输出行**同样带 `[E]` 失败标记**，所以变异验证
脚本的「拦截成功」判据会假绿——看起来每个变异都被拦住了，其实测试根本没跑起来。
故变异/验证脚本必须先做**基线健康校验**（无变异时须 `All tests passed`），
不绿就直接 abort，不要让坏环境冒充好结果。）
（V4.19：**核算 prompt 漂移量要直接比源字符串长度，别按 diff 行求和**
——2026-09-04 ADR-C72 锚点归因实证。快照里的 `len` 是 Dart `String.length`，
即 **UTF-16 code units**，不是 UTF-8 字节数（中文 3 字节 vs 1 code unit，差 3 倍）。
按 `git diff` 的 +/- 行求和还会**漏掉新增行的换行符**，结果总是差 1。
正确做法：`re` 提取两个版本的 `const String _xxxBody = '''...'''` 正文直接比长度，
与快照漂移数对账。判据是「13 个 case 等量漂移 = 新增长度」，差一个字符都要停下排查。）
