# 交接提示词（2026-08-18）— 粘贴到新对话即可继续

> 用途：在 WorkBuddy 新对话（建议 Craft 模式）继续「月笙写作教练 Flutter 端（yuesheng-flutter）」的开发。本文已推送至远程，本地 HEAD = `c5030e67`，远程 `upstream/main` 已同步。

## 项目背景

你在做「月笙写作教练」的 DSH 插件适配移植：把分析处理体系（诊断/教学/素材）落地到一个 Electron/Flutter 双端，本仓库是 Flutter 端（`D:\ai-teacher\yuesheng-flutter`）。技术栈：Flutter + Riverpod + drift(SQLite)，遵循项目 AGENTS.md 的 GStack 七阶段流程与 R-009/R-010/R-021/R-019/R-027 等规则。

## 已完成的 DSH 路线图项（均已提交并推送）

- **B-0** 消息气泡 markdown 渲染（引入 gpt_markdown）— `62b402a7`
- **A-1** 素材 token 预算止血 — `67b6bfd8`
- **B-1** GenUI v1 交互组件渲染层 — `f4cf9aaf`
- **A-2** 稳定 ID 引用标记：`@[refType:refId]` 替代 `@标题`，解析层 ID 优先 + legacy 兜底，目标被删降级纯文本 — `8059364d`
- **A-3** 选段段落锚点：`excerpt_range` 由字符偏移改为 `{chapterId,startPara,endPara}` 段落锚点，漂移从字符级降到段落级 — `c5030e67`

全量门禁现状：**1793 passed / 14 skipped / 0 failed**（前台运行 flutter test）。

## 当前可继续的方向（按需选一个启动）

1. **B-2 GenUI v2 扩展组件**：扩展 B-1 的渲染层，覆盖更多组件类型（表单/卡片/流程等）。
2. **A-3 方案 Y（手动选区 UI）**：在章节面板增加「高亮选区 → 落段落锚点」的交互，让 `excerpt_range` 真正被写入（目前段落窗口已就绪，但无写入调用方）。
3. **N+1 查询合并**：A-3 遗留的「主引用批量反查章节」合并为单次查询。
4. **非主引用也记选段**：当前仅主引用 chapter 支持 excerpt，按最小范围原则暂缓，等真实需求。

## 必须遵循的纪律（来自 R-019/R-010/R-021/R-027 + 用户反馈）

- **Flutter 工具链**：只在**前台**运行 `flutter`/`dart`，**绝不后台**、**绝不 timeout 杀死进程**（曾因反复 timeout 写坏 flutter_tools.stamp 导致卡死）。慢就给足 timeout（如 600000ms）。
- **最小范围**：不替用户写句子/做决定，不顺手改范围外文件，不写投机/死代码（A-2 曾误加 `ref_title` 死列与气泡实时解析，已回退）。
- **四道门禁**（声称完成前必须全绿）：`dart analyze lib` 零 issue、`flutter test` 全绿、lint 零 error、安全审查通过。
- **核心模块改动**（诊断/教学状态机/IPC/DB schema）先写 ADR，再实施；改动 DB schema 必须 bump `schemaVersion` + `onUpgrade` + PRAGMA 幂等守卫 + 重生成 `database.g.dart`。
- **提交规范**（R-016）：scope 独立提交，中文 commit message，格式 `type(scope): 简述`。
- **区域约定**：股票涨红跌绿（本任务无关，但建可视化时默认）。

## 关键文件指针

- 路线图：`docs/2026-08-18-dsh-plugins-adaptation-plan.md`
- A-2 ADR：`docs/ADR-A2-stable-mention-id.md`（含范围回溯）
- A-3 ADR：`docs/ADR-A3-paragraph-anchor.md`（已 Accepted，采纳方案 X）
- 引用解析：`lib/services/mention_parser.dart`、`lib/widgets/reference_picker.dart`
- 段落锚点：`lib/services/chat_context_builder.dart`（`ParagraphAnchor`/`parseParagraphAnchor`/`extractParagraphWindow`）、`lib/data/repositories/reference_repository.dart`
- 测试：`test/services/chat_context_builder_excerpt_test.dart`、`test/services/mention_parser_test.dart`

## 给新对话的开场白（直接复制）

> 继续「月笙写作教练 Flutter 端」的 DSH 移植工作。当前 HEAD 已推送至 `upstream/main`（c5030e67）。请先读 `docs/2026-08-18-dsh-plugins-adaptation-plan.md` 与 `docs/ADR-A3-paragraph-anchor.md` 对齐上下文，按 GStack 流程与项目纪律（最小范围、前台运行 flutter、四道门禁、核心模块先 ADR）推进下一个路线图项。先列任务清单，等我确认方向再动手。
