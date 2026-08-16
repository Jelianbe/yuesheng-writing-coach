# T5 作品导入链路交付提交日志（M:N 引用 + 文件上传解析方向）

**日期**：2026-08-07
**批次**：T5 作品导入（文件上传解析方向第一批落地）
**范围**：文件解析服务（批次1）+ 作品导入事务链路（批次2），对齐 RN WorkImportModal 流程

---

## 变更概述

M:N 对话内容引用方向调研确认：Flutter 引用注入链路已完整实现（chat_context_builder + session_reference 桥表），真正缺口是**文件解析服务 + 导入链路 + UI 入口**。本次补齐前两个：

1. **批次 1**：`file_parser.dart` 文件解析服务（选文件 → 读内容 → 按章解析），复刻 RN file-parser.ts
2. **批次 2**：`work_import_service.dart` 作品导入链路（事务内建稿件 + 逐章建章节 + 设主引用），复刻 RN WorkImportModal handleCreateWork
3. **批次 3**：`ChatInput` 聊天 UI 入口按钮（+ / @ + entryPoint 占位符切换），对齐 RN ChatInput.tsx L48-82
4. **批次 4a**：`WorkImportSheet` 作品导入弹层 + ChatPage 接线（+ 按钮真闭环）
5. **批次 4b**：`ReferencePicker` 引用选择器 + ChatPage 接线（@ 按钮 → 设主引用）
6. **批次 4c**：`MaterialUploadSheet` + `FileSection` 素材文件管理 + 稿件详情页接线
7. **批次 5a**：`FileViewerModal` 素材内容查看（角色轮换/删除）+ FileSection 点击接线
8. **批次 5b**：mention 模式（`MentionParser` + ReferencePicker mention + 发送解析注入）
9. **批次 6**：`ReferenceBar` 聊天页顶部引用条（缺口清单第 1 项：主引用行 + 展开列表 + 设主/移除/多选批量删除 + 添加引用）
10. **批次 7**：`SessionDrawer` 会话管理抽屉（缺口清单第 2 项：会话列表/切换/新建 + 相对时间/阶段标签）
11. **批次 8**：`SyndromeDetailModal` 症候详情弹层（缺口清单第 3 项：出现次数/趋势/首次发现 + 迷你趋势图 + 诊断记录；数据源 syndrome-tracker 一并落地）
12. **批次 9**：消息卡片渲染扩展（缺口清单第 4 项：reference_change + phase_upgrade 卡片渲染与插入链路）
13. **批次 10**：QuickChips / 聊天头部状态区（缺口清单第 5 项：QuickChips 快捷提问 + ChatHeader 头部状态区 + ChatWelcome 欢迎态 + SubphaseIndicator + TeachingStateBadge + EncouragementText）
14. **批次 11**：设置页（缺口清单第 6 项：API 配置表单 + 测试连接/清空 + 清除缓存 + 反馈 + 关于 + `/settings` 路由）
15. **批次 12**：态度建议横幅（缺口清单 A 类：升级/降级建议横幅 + 建议引擎 + ChatPage 发送后自动检查）
16. **批次 13**：诊断确认/选择（缺口清单 B 类：作品→章节选择弹层 + 成长页入口 + 跨 Tab 自动诊断）
17. **批次 14**：保存到文件（缺口清单 C 类：保存弹层 + 消息气泡操作区按钮 + 主引用目标写入）
18. **批次 15**：放弃练习确认（缺口清单 C 类：阻断式确认弹窗 + 训练跳过接线）
19. **批次 16**：导入成功反馈（缺口清单 B 类：成功引导弹层 + 上传完成接线 + 立即诊断自动触发）
20. **批次 17**：消息卡片类型（缺口清单 B 类：PartialAgreement / PhaseSummary / DiagnosisFailed 三卡 + insert 函数 + 分派）
21. **批次 18**：活跃问题面板（缺口清单 C 类：P2 阶段任务开关 + 活跃问题列表 + 完成标记）
22. **批次 19**：D/E 类只读审计（仅文档：素材/创建项目/会话列表标注无需实施 + 导入确认/项目设置确认真实缺口 + progress-service 误判更正 + skill-lifecycle 标注闭环）
23. **批次 20**：追加章节导入 + 项目设置（缺口清单 D 类两真实缺口：/append-chapters 导入页 + /project-settings 设置页 + 稿件详情「导入」按钮与更多菜单）
24. **批次 21**：进度详情 + progress-service（缺口清单 D/E 类收尾：/progress-detail 学习进度页 + progress_service 四函数 + 书架进度卡入口；**D 类与 E 类至此全部闭环**）

## 提交日志

| Commit | 日期 | 标题 | 摘要 |
|--------|------|------|------|
| `78a1280` | 2026-08-07 | feat: 文件解析服务批次1 | file_parser（pickDocument/readFileContent/parseTxtFile/parseMdFile/parseDocument）+ FileParserLimits + 8 测试 |
| `406b673` | 2026-08-07 | feat: 作品导入链路批次2 | WorkImportService（importFromFile/importFromText/importWork 事务）+ 6 测试 |
| `1e49124` | 2026-08-07 | feat: 聊天输入 UI 入口批次3 | ChatInput + / @ 按钮 + entryPoint + 6 测试 |
| `63f113c` | 2026-08-07 | feat: 作品导入弹层批次4a | WorkImportSheet + workImportServiceProvider + ChatPage 接线 + 6 测试 |
| `16d8cbb` | 2026-08-07 | feat: 引用选择器批次4b | ReferencePicker（作品/素材双 Tab）+ ChatPage @ 接线 + 6 测试 |
| `daee2c8` | 2026-08-07 | feat: 素材文件管理批次4c | MaterialUploadSheet + FileSection + 稿件详情页接线 + 8 测试 |
| 待提交 | 2026-08-07 | feat: 素材查看批次5a | FileViewerModal（内容/角色轮换/删除）+ FileSection 接线 + 4 测试 |
| `af142c0` | 2026-08-07 | feat: mention 模式批次5b | MentionParser + ReferencePicker mention + ChatPage 发送解析 + 8 测试 |
| `ceb1513` | 2026-08-07 | feat: ReferenceBar 批次6 | 聊天页顶部引用条（主引用行/展开列表/设主/移除/多选删除/添加引用）+ 9 测试 |
| `cb19cfb` | 2026-08-07 | feat: SessionDrawer 批次7 | 会话管理抽屉（列表/切换/新建 + 相对时间/阶段标签）+ 12 测试 |
| `45103e4` | 2026-08-07 | feat: SyndromeDetailModal 批次8 | 症候详情弹层 + syndrome-tracker + 诊断卡 chip 入口 + 12 测试 |
| `d2fd809` | 2026-08-07 | feat: 消息卡片批次9 | reference_change + phase_upgrade 卡片渲染与插入链路 + 15 测试 |
| `f8a89f6` | 2026-08-07 | feat: QuickChips/头部批次10 | QuickChips + ChatHeader 头部状态区 + 欢迎态/鼓励/子阶段/状态徽章 + 29 测试 |
| `61c3172` | 2026-08-07 | feat: 设置页批次11 | SettingsPage（API 配置表单 + 测试连接/清空 + 清除缓存 + 反馈 + 关于）+ `/settings` 路由 + 成长页快捷入口 + 12 测试 |
| `7d41fd5` | 2026-08-07 | feat: 态度建议横幅批次12 | AttitudeSuggestionBanner + attitude_advisor 建议引擎 + ChatPage 500ms 自动检查 + 27 测试 |
| `be659a2` | 2026-08-07 | feat: 诊断确认/选择批次13 | DiagnosisPickerSheet 作品→章节弹层 + 成长页入口 + pendingDiagnosisChapterProvider 自动诊断 + 7 测试 |
| `cc5c2d6` | 2026-08-07 | feat: 保存到文件批次14 | SaveToFileSheet 保存弹层 + MessageBubble 操作区按钮 + ChatPage 主引用接线 + 12 测试 |
| `2009a02` | 2026-08-07 | feat: 放弃练习确认批次15 | AbandonPracticeDialog 阻断式确认弹窗 + ChatPage 跳过接线 + 7 测试 |
| `5df2ef7` | 2026-08-07 | feat: 导入成功反馈批次16 | ImportSuccessSheet 成功引导弹层 + ChatPage 上传完成接线 + 6 测试 |
| `163ccaf` | 2026-08-07 | feat: 消息卡片类型批次17 | PartialAgreement/PhaseSummary/DiagnosisFailed 三卡 + 服务层 insert + 分派 + 26 测试 |
| `2043e4f` | 2026-08-07 | feat: 活跃问题面板批次18 | TaskPanel 活跃问题列表 + ChatPage P2 接线 + 8 测试 |
| `7e0c7c7` | 2026-08-07 | docs: D/E类审计批次19 | 缺口清单（素材/创建项目/会话列表无需实施 + 导入确认/项目设置真实缺口 + progress-service 误判更正 + skill-lifecycle 闭环 + 实施顺序/已闭环追加）+ 本日志批次小节（仅文档，无代码改动） |
| `66a971c` | 2026-08-07 | feat: 追加章节导入+项目设置批次20 | AppendChaptersPage 追加章节导入 + ProjectSettingsPage 项目设置 + 两路由 + 稿件详情导入按钮/更多菜单 + 22 测试 |
| `7435245` | 2026-08-07 | feat: 进度详情+progress-service批次21 | ProgressService 四函数 + ProgressDetailPage 学习进度页 + 书架进度卡入口 + 路由 + 14 测试 |

## 批次 1 — 文件解析服务（`78a1280`）

| 文件 | 改动 | 说明 |
|------|------|------|
| `lib/services/file_parser.dart` | 新增 | 复刻 RN file-parser.ts：txt 按「第X章/Chapter N」正则切章、md 按 `# ` 切章、兜底「第一章」、扩展名路由；产物 ParsedFile{title, genre:'未知', chapters} |
| `lib/config/shared_constants.dart` | 修改 | 新增 FileParserLimits（chapterTitleMaxLength=50 / heading1MaxLength=80） |
| `test/services/file_parser_test.dart` | 新增 | 8 测试：中文/英文切章、兜底、过长标题不切、md 切章、无 `# ` 兜底、扩展名路由、无后缀命名 |

## 批次 2 — 作品导入链路（待提交）

| 文件 | 改动 | 说明 |
|------|------|------|
| `lib/services/work_import_service.dart` | 新增 | WorkImportService：importFromFile（pickDocument→readFileContent→parseDocument→入库）、importFromText（粘贴文本）、importWork（事务内 createManuscript + 逐章 createChapter + addReference(sessionId,'chapter',firstChapterId,isPrimary:true)）；返回 WorkImportResult{manuscriptId, firstChapterId, chapterCount, totalWords} 对齐 RN onUploadComplete meta |
| `test/services/work_import_service_test.dart` | 新增 | 6 测试：完整链路（稿件/章节/主引用）/ 重复导入不冲突 / 空章节 StateError / 会话不存在外键失败整体回滚 / 粘贴文本按章拆入 / 粘贴文本兜底第一章 |

## 批次 3 — 聊天输入 UI 入口（待提交）

| 文件 | 改动 | 说明 |
|------|------|------|
| `lib/widgets/chat_input.dart` | 修改 | 新增 onUploadFile（+ 按钮，带边框 secondary）/ onMention（@ 按钮，ghost）/ entryPoint（'manuscript' → 诊断模式占位符）三参数；回调为 null 时按钮不显示（弹层批次接线后自动出现）；isStreaming 仅禁用输入与发送，按钮不受影响（对齐 RN）；28x28 图标按钮对齐 RN INPUT_LAYOUT.iconButtonSize |
| `test/widgets/chat_input_test.dart` | 修改 | +6 测试：未传回调不显示 / + 点击触发 / @ 点击触发 / 双回调+流式仍可点 / entryPoint 占位符切换 / 默认占位符；原有 4 测试保持 |

## 批次 4a — 作品导入弹层（待提交）

| 文件 | 改动 | 说明 |
|------|------|------|
| `lib/widgets/work_import_sheet.dart` | 新增 | 复刻 RN WorkImportModal：选择文件（importFromFile）/ 粘贴文本（importFromText，AlertDialog 输入）；uploading 转圈 + 文案；错误条（release 仅展示可读文案）；取消。导入成功 → 关闭弹层 + onUploadComplete |
| `lib/providers/work_import_providers.dart` | 新增 | workImportServiceProvider（依赖 appDatabaseProvider，测试可 override） |
| `lib/widgets/chat_page.dart` | 修改 | + 按钮接线：_handleUploadFile 打开 WorkImportSheet；_handleUploadComplete 提示「已导入《书名》（N章）」+ _reloadMessages 刷新上下文 |
| `lib/services/work_import_service.dart` | 修改 | WorkImportResult 补 title 字段（对齐 RN onUploadComplete meta） |
| `test/widgets/work_import_sheet_test.dart` | 新增 | 4 测试：粘贴文本导入闭环（稿件/章节/主引用落库 + 回调 + 弹层关闭）/ 对话框取消不导入 / 空文本不导入 / 取消按钮关闭 |
| `test/widgets/chat_page_test.dart` | 修改 | +2 集成测试：+ 按钮点击打开弹层 / 弹层导入 → SnackBar 提示 + 主引用落库 |

## 批次 4b — 引用选择器（待提交）

| 文件 | 改动 | 说明 |
|------|------|------|
| `lib/widgets/reference_picker.dart` | 新增 | 复刻 RN ReferencePicker（default 模式）：作品 Tab（稿件列表 + 展开章节 + 引用整本书）+ 素材 Tab（按稿件分组文件列表）+ 空态 + 取消；选择后 onSelect(refType, refId, title) 并关闭 |
| `lib/widgets/chat_page.dart` | 修改 | @ 按钮接线：_handleMention 打开 ReferencePicker；_handleReferenceSelected → addReference(isPrimary:true) + SnackBar + 刷新；file 类型提示「素材文件暂不支持设为引用」（ref_type CHECK 约束） |
| `test/widgets/reference_picker_test.dart` | 新增 | 5 测试：空态 / 引用整本书 / 展开选章节 / 素材 Tab 选文件 / 取消不触发 |
| `test/widgets/chat_page_test.dart` | 修改 | +1 集成测试：#B4-3 @ → 选章节 → 主引用落库 |

## 批次 4c — 素材文件管理（待提交）

| 文件 | 改动 | 说明 |
|------|------|------|
| `lib/widgets/material_upload_sheet.dart` | 新增 | 复刻 RN MaterialUploadSheet：选择文件（file_parser）/ 粘贴文本 → 素材类型 chips（常规/大纲/素材）+ 文件名输入 → createAttachedFile 落库 + onSaved |
| `lib/widgets/file_section.dart` | 新增 | 复刻 RN FileSection 精简版：素材列表（role 徽章 + 文件名 + 大小）+ 添加素材 + 长按删除（确认对话框）+ 空态（对齐 RN 文案） |
| `lib/widgets/manuscript_detail_page.dart` | 修改 | 章节列表尾部追加 FileSection（ListView itemCount+1）；空章节分支改 ListView（空态 + FileSection） |
| `test/widgets/material_upload_sheet_test.dart` | 新增 | 4 测试：粘贴保存闭环（落库+回调）/ 类型切换 outline / 空粘贴不显示表单 / 取消不保存 |
| `test/widgets/file_section_test.dart` | 新增 | 4 测试：空态 / 文件卡片+徽章 / 打开上传弹层 / 长按删除确认落库 |

## 批次 5a — 素材内容查看（待提交）

| 文件 | 改动 | 说明 |
|------|------|------|
| `lib/widgets/file_viewer_modal.dart` | 新增 | 复刻 RN FileViewerModal：全屏查看（文件名 + 角色徽章 + 大小 + 可选文本内容）+ 更改角色（轮换 general→outline→material，确认对话框）+ 删除文件（确认，落库 + onDeleted + 关闭） |
| `lib/widgets/file_section.dart` | 修改 | 文件卡片 onTap → push FileViewerModal（fullscreenDialog），onDeleted 刷新列表 |
| `test/widgets/file_viewer_modal_test.dart` | 新增 | 4 测试：加载显示 / 文件不存在空态 / 角色轮换落库 / 删除落库+关闭 |

## 批次 5b — mention 模式（待提交）

| 文件 | 改动 | 说明 |
|------|------|------|
| `lib/services/mention_parser.dart` | 新增 | 复刻 RN mention-parser：parseMentions（正则 @W\d+(/[CF]\d+)? → 解析+清理文本）/ buildMentionPath / generatePathCode |
| `lib/providers/work_import_providers.dart` | 修改 | 新增 mentionParserProvider |
| `lib/widgets/reference_picker.dart` | 修改 | 新增 mode('default'/'mention') + onSelectMention；mention 模式显示路径徽章，选择回调 @路径 |
| `lib/widgets/chat_page.dart` | 修改 | @ 按钮改 mention 模式（选中插入 @路径 到输入框，对齐 RN handleMentionSelect）；_handleSend 发送前 parseMentions → 引用添加为会话附加引用（跳过 file，ref_type CHECK 约束）→ 发送清理文本 |
| `test/services/mention_parser_test.dart` | 新增 | 7 测试：generatePathCode / buildMentionPath / @W001 / @W002/C001 / @W001/F001 / 无效引用 / 多引用 |
| `test/widgets/reference_picker_test.dart` | 修改 | +1 mention 模式测试（徽章 + 回调） |
| `test/widgets/chat_page_test.dart` | 修改 | #B4-3 改为 mention 语义：插入路径 → 发送 → 附加引用落库（isPrimary=0） |

## 批次 6 — ReferenceBar 顶部引用条（`ceb1513`）

> 缺口清单（docs/2026-08-07-rn-gap-analysis.md）建议实施顺序第 1 项，复刻 RN `ReferenceBar.tsx`。

| 文件 | 改动 | 说明 |
|------|------|------|
| `lib/widgets/reference_bar.dart` | 新增 | 复刻 RN ReferenceBar：主引用行（图标 + 类型标签（作品/章节（主引用））+ 标题 + 其它引用徽章 +N + 展开箭头）；展开列表（refRow 多选框/类型标签/标题/主引用徽章/移除按钮）；多选操作条（取消/已选 N 项/删除选中）；全选按钮（引用 >1 时）；「+ 添加引用」虚线按钮（自绘 DashedBorderPainter，不引入第三方依赖） |
| `lib/widgets/chat_page.dart` | 修改 | `_buildBody` Column 首个子级插入 ReferenceBar（对齐 RN 顶部常驻，MessageList 上方）；新增 `_handleOpenReferencePicker`（default 模式选择器：file 类型拦截、无主引用时首个自动设主、添加后重建 ReferenceBar）；`_handleUploadComplete` 导入后重建 ReferenceBar；`_refBarKey` 换 key 触发重载 |
| `test/widgets/reference_bar_test.dart` | 新增 | 8 测试：占位文案 / 主引用标签+标题 / +N 徽章 / 展开列表 / 设主引用（DB is_primary 迁移 + SnackBar）/ 移除 / 全选批量删除 / onPressPicker 回调 |
| `test/widgets/chat_page_test.dart` | 修改 | +1 集成测试 #B4-4：ReferenceBar 顶部常驻 + 添加引用 → 主引用落库（isPrimary=1） |

设计决策：
- 变更反馈用组件内 SnackBar（`message_card_service` 无引用变更卡片类型，RN 的 onReferencesChanged 卡片插入暂不落地，见缺口清单 B 类消息卡片）
- 引用行点击（非多选）= 设主引用，对齐 RN refInfo onPress；多选模式点击 = 切换选中
- file 类型设主引用直接拦截提示（setPrimaryReference 对 file 抛 ArgumentError + ref_type CHECK 约束本就不含 file）
- 多选 key 切分用 `indexOf('-')`（refId 为 uuid 含 '-'，RN 用 split 有隐患，Flutter 修正）

## 批次 7 — SessionDrawer 会话管理抽屉（`cb19cfb`）

> 缺口清单（docs/2026-08-07-rn-gap-analysis.md）建议实施顺序第 2 项，复刻 RN `SessionDrawer.tsx`。

| 文件 | 改动 | 说明 |
|------|------|------|
| `lib/widgets/session_drawer.dart` | 新增 | 复刻 RN SessionDrawer：头部「对话」标题 + 会话列表（月字头像当前会话品牌色/其余灰、标题、相对时间、预览兜底「暂无消息」、阶段标签 PHASE_LABELS）+ 空态（还没有会话/发起第一次对话 CTA）+ 底部「+ 新建会话」；用 Scaffold 内置 Drawer（RN Modal 等价物） |
| `lib/utils/time_format.dart` | 新增 | formatRelativeTime（刚刚/N 分钟前/N 小时前/N 天前/yyyy-MM-dd），复刻 RN utils/time.ts |
| `lib/providers/session_providers.dart` | 修改 | SessionBootstrapNotifier 加 `_targetSessionId` + `switchTo`/`createNew`（对齐 RN switchSession/createAndSwitchSession）；build 优先用显式目标，重启后回到 sessions.first |
| `lib/widgets/chat_page.dart` | 修改 | Scaffold 加 drawer（AppBar 自动汉堡 leading）；`_loadSessions`（initState + bootstrap listen 后刷新）；`_handleSwitchSession`/`_handleCreateSession`（对齐 RN：重置练习/评估报告 + 输入框 → bootstrap 切换） |
| `test/utils/time_format_test.dart` | 新增 | 5 测试：刚刚/分钟/小时/天/日期 |
| `test/widgets/session_drawer_test.dart` | 新增 | 5 测试：空态 CTA/列表渲染（标题/预览/时间/阶段标签）/点击选择回调+关闭/底部新建/空态 CTA |
| `test/widgets/chat_page_test.dart` | 修改 | +2 集成测试 #B5-1（汉堡打开 → 切换会话 → 消息列表刷新）、#B5-2（新建会话 → 数量+1） |

设计决策：
- **切换数据流**：bootstrap 是 sessionId 唯一 owner（RN 是 chat-store initSession 等价物），drawer 切换走 `switchTo` → 重新 bootstrap → ChatPage `ref.listen` 自动重载消息/态度/引用列表（对齐 RN currentSessionId useEffect）
- **切换后重置**：复用 PracticeStore.resetPractice + EvaluationReportsStore.resetReports（RN 重置诊断/练习/模态 store 的 Flutter 等价物）
- **阶段标签**：统一竹青淡底 + 竹青字（RN 用 per-phase 配色，月色竹青主题收敛为一套）
- 相对时间手写（不引入 intl 依赖）

## 批次 8 — SyndromeDetailModal 症候详情弹层（`45103e4`）

> 缺口清单（docs/2026-08-07-rn-gap-analysis.md）建议实施顺序第 3 项 + E 类 syndrome-tracker，复刻 RN `SyndromeDetailModal.tsx` + `syndrome-tracker.service.ts`。
> 注：RN 弹层入口目前在 DevToolPanel（调试 mock），Flutter 落地为正式入口——诊断卡症候 chip 点击。

| 文件 | 改动 | 说明 |
|------|------|------|
| `lib/services/syndrome_tracker.dart` | 新增 | 复刻 RN syndrome-tracker.service.ts：SyndromeTracker.loadSyndromeTrends（listDiagnosisHistory 聚合 occurrenceCount/firstSeen/lastSeen/currentSeverity + recentPoints 最近5 + 前后半段平均严重度差分趋势）+ getTrendLabel/getTrendColor |
| `lib/widgets/syndrome_detail_modal.dart` | 新增 | 复刻 RN SyndromeDetailModal：症候 chip + 统计行（出现次数/趋势/首次发现）+ 趋势变化 section（CustomPaint 自绘迷你折线图，不引入图表依赖）+ 诊断记录（严重度色点 + 标签 + 相对时间）；showModalBottomSheet 承载（RN Modal slide 等价物） |
| `lib/widgets/diagnosis_card.dart` | 修改 | 症候 chip 包 InkWell（sessionId 非空可点击）→ `_openSyndromeDetail`（loadSyndromeTrends → 匹配症候 → 打开弹层），对齐 RN SyndromeTag onPress + debugTriggerSyndromeDetail |
| `test/services/syndrome_tracker_test.dart` | 新增 | 7 测试：空列表 / 聚合（次数/首见/末见/当前严重度）/ 截断最近5 / 趋势加重·好转·稳定 / 排序 |
| `test/widgets/syndrome_detail_modal_test.dart` | 新增 | 3 测试：完整渲染 / 空记录 / 关闭 |
| `test/widgets/diagnosis_card_test.dart` | 修改 | +2 集成测试 D5C-1（chip 点击 → 弹层）、D5C-2（无 sessionId 不可点击） |

设计决策：
- **数据源**：SyndromeTracker 从诊断历史（listDiagnosisHistory）聚合，与 RN loadSyndromeTrends 逻辑一致（含近 5 次截断、前后半段平均差 0.3 阈值、严重度降序→次数降序排序）
- **趋势图**：CustomPaint 自绘（Y 轴 L1/L2/L3 三档 + 网格参考线 + 严重度配色点 + 折线），不引入 fl_chart
- **入口**：RN 弹层仅 DevToolPanel 调试入口（release 已移除），Flutter 落正式入口——诊断卡症候 chip 点击（sessionId 非空才可点）
- 趋势色：improving→竹青 / worsening→矿物红 / stable→灰（对齐 RN success/danger/neutral 语义）

## 批次 9 — 消息卡片渲染扩展（`d2fd809`）

> 缺口清单（docs/2026-08-07-rn-gap-analysis.md）建议实施顺序第 4 项（B 类消息卡片类型子集），复刻 RN `message-card-service.ts` 的 ReferenceChangeCardPayload/PhaseUpgradeCardPayload + `message-cards/` 目录。
> 注：RN 的引用变更提示在 changeHint toast（临时提示），Flutter 补为正式卡片（reference_change 落库 + 渲染，替代一次性 toast）。

| 文件 | 改动 | 说明 |
|------|------|------|
| `lib/services/message_card_service.dart` | 修改 | +2 卡片 payload + 插入函数：`ReferenceChangeCardPayload`（action: 'set_primary'/'add'/'remove' + refType + refTitle）+ `insertReferenceChangeCard`（messageType 'reference_change'）；`PhaseUpgradeCardPayload`（from + to + reason?）+ `insertPhaseUpgradeCard`（messageType 'phase_upgrade'） |
| `lib/widgets/reference_change_card.dart` | 新增 | 展示型卡片（无交互）：左竹青条 + 图标 + 标题（按 action：主引用已切换/已添加引用/已移除引用）+ 类型标签（作品/章节）+ 副标题；含 `fromMessageContent(String)` 便利构造（非法 JSON 兜底 action='add'） |
| `lib/widgets/phase_upgrade_card.dart` | 新增 | 庆祝图标 + 「进入新阶段！」+ 阶段名（P1→世界观阶段等映射，对齐 RN phase-constants.ts）+ 解锁描述 + 鼓励语 + 可选 reason；含 `fromMessageContent` 便利构造（非法 JSON 兜底 to='P1_WORLD'） |
| `lib/widgets/message_list.dart` | 修改 | 分派逻辑新增 2 分支（teacher_suggestion 之后）：`reference_change` → ReferenceChangeCard、`phase_upgrade` → PhaseUpgradeCard（均非流式气泡时） |
| `lib/widgets/reference_bar.dart` | 修改 | 新增可选参数 `onReferencesChanged(String action, String refType, String refTitle)?`；设主引用/移除成功后回调 |
| `lib/widgets/chat_page.dart` | 修改 | `_handleReferenceChanged`：insertReferenceChangeCard + _reloadMessages（失败静默）；ReferencePicker onSelect 追加 add 卡片；ReferenceBar 接线 onReferencesChanged |
| `lib/services/chat_service.dart` | 修改 | phase-mapper resolver 阶段迁移处：effectivePhase 变化 → updatePhase 后 insertPhaseUpgradeCard（from=prevPhase ?? P0，to=effectivePhase），失败静默兜底 |
| `test/widgets/reference_change_card_test.dart` | 新增 | 5 测试：set_primary 章节标签 / add 作品 / remove / fromMessageContent 合法 / 非法 JSON 兜底 |
| `test/widgets/phase_upgrade_card_test.dart` | 新增 | 5 测试：P1_WORLD / P2_PRACTICE_LOOP / 未知阶段兜底 / 合法 JSON+reason / 非法 JSON 兜底 |
| `test/widgets/message_list_test.dart` | 修改 | _msg 加 messageType 参数，+2 分派测试（reference_change/phase_upgrade 卡片渲染） |
| `test/widgets/reference_bar_test.dart` | 修改 | buildHost 加 onReferencesChanged 可选参数，+2 测试（#9 设主引用回调 / #10 移除回调） |
| `test/widgets/chat_page_test.dart` | 修改 | +1 集成测试 #B6-1：ReferenceBar 设主引用 → reference_change 卡片渲染 + 落库验证 |

设计决策：
- **取舍**：RN 的 PhaseSummaryCard/DiagnosisFailedCard/PartialAgreementCard 依赖训练评估/失败计数/诊断确认等既有流程，本次仅落地可独立闭环的 reference_change + phase_upgrade 两种，其余三种标注为「待后续流程批次」
- **PhaseUpgradeCard 交互展示为主**：RN 有「开始新阶段/查看学员画像」按钮（依赖 subphase 推进 + 画像路由），Flutter 渲染层暂不绑定交互，保留 reason 展示
- **插入时机**：reference_change 由 UI 操作触发（设主/添加/移除引用），phase_upgrade 由训练阶段迁移触发（chat_service 解析后比对 prevPhase），与 RN 触发点一致

## 批次 10 — QuickChips / 聊天头部状态区（`f8a89f6`）

> 缺口清单（docs/2026-08-07-rn-gap-analysis.md）建议实施顺序第 5 项，复刻 RN `QuickChips.tsx` + `ChatHeader.tsx` + `ChatWelcome.tsx` + `SubphaseIndicator.tsx` + `TeachingStateBadge.tsx` + `EncouragementText.tsx`。

| 文件 | 改动 | 说明 |
|------|------|------|
| `lib/widgets/quick_chips.dart` | 新增 | 复刻 RN QuickChips：横向滑动 3 默认快捷提问（诊断节奏问题/优化对话描写/检查逻辑漏洞）+ 竹青胶囊 chip（primarySoft 底 + primary 边框）+ 点击 onSelect |
| `lib/widgets/chat_welcome.dart` | 新增 | 复刻 RN ChatWelcome：月笙头像 + 「你好，我是月笙」+ 副标题；SingleChildScrollView 包裹防受限高度溢出 |
| `lib/widgets/encouragement_text.dart` | 新增 | 复刻 RN EncouragementText：15 条鼓励文案池 + seed 稳定随机 + 竹青淡底胶囊 |
| `lib/widgets/subphase_indicator.dart` | 新增 | 复刻 RN SubphaseIndicator：P2 子阶段彩色胶囊（诊断中 info 深青 / 练习中 warning 矿物黄 / 反馈中 success 竹青），null 不渲染 |
| `lib/widgets/teaching_state_badge.dart` | 新增 | 复刻 RN TeachingStateBadge：状态色点 + 可选标签（刚识别/训练中/趋稳中/已掌握），sm/md/lg 三档尺寸 |
| `lib/widgets/chat_header.dart` | 新增 | 复刻 RN ChatHeader：头部栏（会话列表按钮/标题「会话」+ 入口徽章（诊断模式/自由对话）/更多按钮）+ 更多菜单（阶段只读 + 子阶段切换 + 态度档位行内选择 + 画像入口）；SingleChildScrollView 包裹防溢出 |
| `lib/widgets/chat_page.dart` | 修改 | AppBar → ChatHeader（`_scaffoldKey` 打开 drawer + `_phase`/`_subphase` 状态 + `_handleNextSubphase` 循环切换 + `_handleQuickChipSelect` 发送 + `_handleOpenProfile` 跳画像路由）；QuickChips（非流式 + 非 P2 显示）；MessageList 空态 → ChatWelcome（emptyWidget）；诊断后显示 EncouragementText（seed=诊断消息时间戳和） |
| `lib/widgets/message_list.dart` | 修改 | 新增 `emptyWidget` 可选参数（未传保留原「有问题尽管问教练」引导，传入则替换为欢迎态） |
| `test/widgets/quick_chips_test.dart` | 新增 | 3 测试：默认 3 条 / 点击回调（id+label+prompt）/ 自定义覆盖 |
| `test/widgets/chat_welcome_test.dart` | 新增 | 3 测试：头像 / 标题 / 副标题 |
| `test/widgets/encouragement_text_test.dart` | 新增 | 3 测试：固定 text / seed 稳定 / 15 条池全覆盖 |
| `test/widgets/subphase_indicator_test.dart` | 新增 | 4 测试：诊断中 / 练习中 / 反馈中 / null 不渲染 |
| `test/widgets/teaching_state_badge_test.dart` | 新增 | 5 测试：四种状态标签 / showLabel=false 无文字 |
| `test/widgets/chat_header_test.dart` | 新增 | 7 测试：标题+徽章 / manuscript 徽章 / 汉堡回调 / 菜单内容 / 态度切换 / 画像 / 子阶段切换 |
| `test/widgets/chat_page_test.dart` | 修改 | +4 集成测试 #B10-1（头部+菜单）/ #B10-2（欢迎态）/ #B10-3（快捷提问发送落库）/ #B10-4（诊断后鼓励文案）；#13 态度切换适配新菜单入口（移除 AttitudeIndicator 头部组件） |
| `test/router/c2_tab2_chat_route_test.dart` | 修改 | 断言 AppBar 标题「月笙写作教练」→ ChatHeader 标题「会话」 |
| `test/router/app_router_test.dart` | 修改 | 同上适配 |

设计决策：
- **ChatHeader 左按钮差异**：RN 头部左为返回（Stack 导航），Flutter ChatPage 为 Tab2 常驻页无上级返回，左按钮改为会话列表（drawer）入口；AttitudeIndicator 移入更多菜单做行内 3 档选择（避免 bottom sheet 内嵌套弹层）
- **状态来源**：`_phase` 复用 loadAttitudeState 返回的 phase；`_subphase` 走 chat_service.loadSubphase（teaching_state.current_subphase）；切换子阶段循环 DIAGNOSIS→PRACTICE→FEEDBACK + setSubphase 持久化失败回滚
- **显示条件对齐 RN**：ChatWelcome = messages.isEmpty；QuickChips = 非流式 + 非 P2 阶段；EncouragementText = 存在 diagnosis_result 消息（RN 的 latestDiagnosis 语义落为消息类型判断），seed 取诊断消息时间戳和（同批诊断稳定、新诊断后变化）
- **ChatSessionCard 不落地**：RN 用于 chat-list 独立页（D 类与 SessionDrawer 二选一），Flutter 会话列表已由 SessionDrawer 覆盖
- **TeachingStateBadge 落地待画像接入**：组件已建（RN 在 StudentProfilePanel 使用），后续画像面板批次接线

## 批次 11 — 设置页（`61c3172`）

> 缺口清单（docs/2026-08-07-rn-gap-analysis.md）建议实施顺序第 6 项，复刻 RN `app/settings.tsx`（API 配置 + 维护 + 关于）。

| 文件 | 改动 | 说明 |
|------|------|------|
| `lib/widgets/settings_page.dart` | 新增 | 3 区块（对齐 RN）：API 配置卡片（API Key 密文 / Base URL / Model 三输入 + 保存配置 / 测试连接 / 填充示例 / 清空配置 + 结果框 + 未配置警告）、维护卡片（清除缓存 + 反馈建议）、关于卡片（应用名称 / 版本 / 包名）；configStorage / llmClient 可注入（测试用 fake） |
| `lib/data/repositories/session_repository.dart` | 修改 | 新增 deleteOrphanSessions：复刻 RN handleClearCache SQL（删除无消息的孤儿会话，外键级联清理），返回删除数 |
| `lib/router/app_router.dart` | 修改 | 注册 `/settings` 顶层路由（AppRoutes.settings）→ SettingsPage |
| `lib/widgets/growth_page.dart` | 修改 | 新增「快捷入口」区块（对齐 RN GROWTH_ENTRIES：设置 / 写作诊断 / 敬请期待），「设置」→ push /settings，「写作诊断」→ 敬请期待提示 |
| `test/widgets/settings_page_test.dart` | 新增 | 10 测试：#1 初始渲染 + 未配置警告 / #2 加载已有配置 / #3 保存写入 storage（去尾斜杠）/ #4 空表单完整提示 / #5 测试连接成功结果框（自动保存）/ #6 填充示例 / #7 清空配置确认 / #8 清除缓存删孤儿会话（保留有消息）/ #9 关于区块 / #10 反馈对话框 |
| `test/widgets/growth_page_test.dart` | 修改 | +1 集成测试 #V5 快捷入口渲染（设置/写作诊断/敬请期待） |
| `test/router/growth_route_test.dart` | 修改 | +1 集成测试 #R4 快捷入口「设置」→ 跳转 /settings 渲染 SettingsPage |

设计决策：
- **清除缓存语义对齐 RN SQL**：仅删无消息的孤儿会话（聊天缓存），不动作品/章节/消息等用户内容；确认对话框明示「不包括作品和章节内容」
- **测试连接先保存**：RN 语义为以当前表单值连通测试，Flutter 先 saveLlmConfig 再 testLlmConnection，保证测试即所见
- **Base URL 去尾部斜杠**：保存/测试统一 trim + `replaceAll(RegExp(r'/$'), '')`，避免拼 URL 时双斜杠
- **填示例/清空文案**：示例固定 deepseek（对齐 RN deepseek-v4-flash）；清空需二次确认（防误删配置）

## 批次 12 — 态度建议横幅（`7d41fd5`）

> 缺口清单（docs/2026-08-07-rn-gap-analysis.md）A 类聊天主链路，复刻 RN `AttitudeSuggestionBanner.tsx` + `attitude-advisor.service.ts`。

| 文件 | 改动 | 说明 |
|------|------|------|
| `lib/services/attitude_advisor.dart` | 新增 | 复刻 RN attitude-advisor.service.ts：`suggestAttitudeAdjustment` 纯函数（消息数 ≥5 / 冷却 10min / 升级 3 条件（高阶段+avg≥2.2+≥2症候 ｜ 连续负反馈 3 次 ｜ ≥15 消息+高阶段+avg≥1.8）/ 降级 2 条件（连续正反馈 4 次 ｜ 低严重度+≤1症候+≥10 消息）/ 升级优先于降级）+ 原因文案生成 + `getAttitudeLabel`；阈值复用 `AttitudeThresholds`（shared_constants） |
| `lib/widgets/attitude_suggestion_banner.dart` | 新增 | 复刻 RN AttitudeSuggestionBanner：升级黄系（warningBg/l2 边框）/ 降级竹青系（primarySoft/primary 边框）+ 箭头图标 + 标题（建议提升指导强度/建议调整为轻松模式）+ 原因（2 行省略）+ 「切换到X」接受 + 「暂不」按钮 |
| `lib/widgets/chat_page.dart` | 修改 | 接线：`_attitudeSuggestion`/`_lastSuggestionTime` 状态 + `_checkAttitudeSuggestion`（从最新 diagnosis_result 消息解析症候严重度列表 → 建议引擎）+ `_scheduleAttitudeCheck`（发送/快捷提问后 500ms，对齐 RN ATTITUDE_CHECK_MS）+ 接受（切换档位 + 关横幅）/暂不；横幅渲染于 ChatHeader 下 ReferenceBar 上；QuickChips 显示条件 + 无建议；切换会话清空建议（lastSuggestionTime 页面级保留，对齐 RN useState） |
| `test/services/attitude_advisor_test.dart` | 新增 | 19 测试：边界 null（消息数/冷却/条件不足/无诊断）+ 升级路径 5（高严重度/连续负反馈/15 消息高阶段/yuesheng→sensei/sensei 封顶）+ 降级路径 3（连续正反馈/低严重度/sensei→yuesheng/doubao 封底）+ reason 文案 2 + 升级优先 1 + getAttitudeLabel 3 |
| `test/widgets/attitude_suggestion_banner_test.dart` | 新增 | 5 测试：升级/降级渲染（标题/箭头/按钮/原因）+ 接受/暂不回调 + sensei 显示「老师」 |
| `test/widgets/chat_page_test.dart` | 修改 | +3 集成测试 #B12-1（预置 sensei+10 消息+L1 诊断 → 发送后触发降级横幅 + QuickChips 隐藏）/ #B12-2（接受「切换到月笙」→ 态度双写 yuesheng + 横幅消失）/ #B12-3（暂不 → 横幅消失 + 态度不变 + QuickChips 恢复） |

设计决策：
- **诊断输入来源**：Flutter 无 latestDiagnosis store，从 messages 取最新 `diagnosis_result` 卡片消息解析 syndromes 严重度列表（失败按无诊断处理，静默）
- **冷却时间页面级**：`_lastSuggestionTime` 为页面级 state（对齐 RN useState 不随会话重置），建议展示随会话切换清空（对齐 RN reset 模态 store）
- **QuickChips 联动**：横幅存在时隐藏快捷提问（对齐 RN `!isStreaming && !isP2Phase && !attitudeSuggestion`）
- **接受即切换**：接受按钮复用 `_handleAttitudeChange`（乐观更新 + persistAttitude 双写 + 失败回滚）

## 批次 13 — 诊断确认/选择（`be659a2`）

> 缺口清单（docs/2026-08-07-rn-gap-analysis.md）B 类诊断交互闭环，复刻 RN `DiagnosisPickerModal.tsx`（选章入口）+ `DiagnosisConfirmationBar.tsx`（确认条，已在批次 5 内置 DiagnosisCard D5-B，本次复用）+ RN `startDiagnosis` 路由语义（选章后跨 Tab 跳对话页自动诊断）。

| 文件 | 改动 | 说明 |
|------|------|------|
| `lib/widgets/diagnosis_picker_sheet.dart` | 新增 | 复刻 RN DiagnosisPickerModal：bottom sheet 弹层，作品列表 → 展开章节 → 选章；章节内容 `<100` 字拦截提示「章节内容少于 100 字，请先编辑章节」（对齐 RN 阈值）；空库引导「去书架创建 →」（`context.go(bookshelf)`）；章节懒加载 `CHAPTER_LIST_INITIAL=50` + 「加载更多（X 章未显示）」每批 50（对齐 RN 常量）；选章后先 `pop` 再回调，由调用方跳转并记录待诊断章节 |
| `lib/providers/chat_store.dart` | 修改 | 新增 `pendingDiagnosisChapterProvider`（StateProvider<String?>）：跨 Tab 传递待诊断章节 ID（对齐 RN URL 参数 startDiagnosis=true&chapterId=X） |
| `lib/widgets/growth_page.dart` | 修改 | 「写作诊断」入口接线：`showModalBottomSheet` 打开 DiagnosisPickerSheet → 回调中写入 `pendingDiagnosisChapterProvider` + `context.go(AppRoutes.writing)`（替换原「敬请期待」占位） |
| `lib/widgets/chat_page.dart` | 修改 | 自动诊断：`ref.listen(pendingDiagnosisChapterProvider)` → `_handleAutoDiagnose`：先清空 pending → 读章节 → `<100` 字 SnackBar 返回 → 超长走 `runProgressiveDiagnosis` + `commitDiagnosisFromContent`（分块渐进诊断）→ 否则构造含 `[YS_DIAGNOSIS]` JSON 格式要求的单次诊断 prompt 走 `_handleSend`；`finally` 复位 streaming + 刷新消息 |
| `lib/config/shared_constants.dart` | 修改 | 新增 `UILimits`（chapterListInitial=50 / chapterListLoadMore=50 / diagnosisWordThreshold=100），复用弹层与自动诊断 |
| `test/widgets/diagnosis_picker_sheet_test.dart` | 新增 | 4 测试：作品列表+展开+选章回调 / 短章节（<100 字）提示且不回调 / 空库引导 / 超过 50 章显示加载更多并可全量展开 |
| `test/widgets/growth_page_test.dart` | 修改 | +1 测试 #V6：点击「写作诊断」→ 章节选择弹层打开（标题 + 作品行出现） |
| `test/widgets/chat_page_test.dart` | 修改 | +2 集成测试 #B13-1（选章后切 Tab → 自动发送诊断 prompt 落库）/ #B13-2（短章节选章 → SnackBar 提示且不发送） |

设计决策：
- **确认条复用而非新建**：RN DiagnosisConfirmationBar 的「诊断结果 + 多症候确认」已由批次 5 DiagnosisCard（D5-B）承载，本次仅补选章入口（PickerModal 缺项），避免重复组件
- **跨 Tab 传递用 Provider 而非 URL**：Flutter Tab 架构下用 `pendingDiagnosisChapterProvider`（StateProvider<String?>）模拟 RN URL 参数语义，选章后切到 Tab2（/writing）由 ChatPage `ref.listen` 消费
- **长文走渐进诊断**：章节超长时复用训练系统的 `runProgressiveDiagnosis`（分块）+ `commitDiagnosisFromContent`，短文构造 `[YS_DIAGNOSIS]` prompt 走单次发送，行为对齐 RN 诊断链路

## 批次 14 — 保存到文件（`cc5c2d6`）

> 缺口清单（docs/2026-08-07-rn-gap-analysis.md）C 类弹层与工具，复刻 RN `SaveToFileSheet.tsx` + `MessageBubble.tsx`（assistant 操作区 onSaveToFile）+ `chat.tsx`（onSaveToFile 接线）。

| 文件 | 改动 | 说明 |
|------|------|------|
| `lib/widgets/save_to_file_sheet.dart` | 新增 | 复刻 RN SaveToFileSheet：bottom sheet 弹层（标题「保存到文件」+ 副标题「保存到《bookTitle》」）+ 文件角色 chips（常规/大纲/素材，对齐 RN FILE_ROLES）+ 文件名输入；文件名预填优先级：suggestedFileName > 内容首行截取 40 字 > 「AI 回复 - 日期」（对齐 RN L52-58）；保存：内容为空拦截提示「内容为空，无法保存」→ `ReferenceRepository.createAttachedFile`（fileName 空兜底「未命名」，对齐 RN finalName）→ pop + onSaved 回调；保存中按钮禁用 + 「保存中...」 |
| `lib/widgets/message_bubble.dart` | 修改 | 新增 `onSaveToFile` 可选回调；assistant 气泡非 streaming 时在时间戳行显示操作区按钮「💾 保存到文件」（对齐 RN messageMetaRow.actionBtnGroup L317-327，仅 `onSaveToFile && !streamingBubble` 显示） |
| `lib/widgets/message_list.dart` | 修改 | 透传 `onSaveToFile` 到 MessageBubble（chat/phase_upgrade 等普通气泡；诊断卡/建议卡等结构化卡片天然无按钮） |
| `lib/widgets/chat_page.dart` | 修改 | `_handleSaveToFile(Message)`：读主引用（`listReferencesOfSession` 找 isPrimary==1）→ 无主引用 SnackBar「请先关联一本书籍」（对齐 RN L451）→ 有则计算 bookId（chapter 主引用用回填的 manuscriptId，manuscript 主引用用自身）+ bookTitle → `showModalBottomSheet` 打开 SaveToFileSheet；MessageList 接线 |
| `test/widgets/save_to_file_sheet_test.dart` | 新增 | 7 测试：渲染（标题/副标题/角色 chips/首行预填）+ 默认角色保存落库 + 切换素材角色 + 空内容拦截不落库 + 空文件名兜底「未命名」+ 长首行截 40 字 + suggestedFileName 优先 |
| `test/widgets/message_bubble_test.dart` | 修改 | +3 测试：onSaveToFile 提供 → 按钮显示且点击回调 / 未提供 → 不显示 / streaming → 不显示 |
| `test/widgets/chat_page_test.dart` | 修改 | +2 集成测试 #B14-1（无主引用 → 提示先关联书籍且不打开弹层）/ #B14-2（chapter 主引用 → 保存落库 file_role=material + 弹层关闭） |

设计决策：
- **目标 = 主引用作品**：对齐 RN primaryRef.manuscript_id；chapter 主引用时 `manuscriptId ?? refId` 取所属作品（ReferenceRepository 建引用时已回填）
- **无成功 toast**：RN addFile + onClose 后无提示，保持忠实；onSaved 回调留给调用方按需刷新
- **按钮仅 assistant 普通气泡**：结构化卡片（诊断/建议/引用变更/阶段升级）不走 MessageBubble，天然不显示保存按钮，对齐 RN 仅 assistant 文本气泡有操作区

## 批次 15 — 放弃练习确认（`2009a02`）

> 缺口清单（docs/2026-08-07-rn-gap-analysis.md）C 类弹层与工具，复刻 RN `AbandonPracticeModal.tsx` + `chat.tsx`（onConfirmSkip 接线 L486）。

| 文件 | 改动 | 说明 |
|------|------|------|
| `lib/widgets/abandon_practice_modal.dart` | 新增 | 复刻 RN AbandonPracticeModal：阻断式确认弹窗（`barrierDismissible: false`，点击遮罩不关闭，对齐 RN onRequestClose 空实现）；警示图标圆底（dangerBg 56x56，对齐 RN iconContainer）+ 标题「确定跳过本次练习？」+ 文案「已输入的内容将丢失，练习进度不会保存。」+ 「继续练习」（primary 实底）/「确认跳过」（描边）双按钮；`show()` 静态方法封装 showDialog |
| `lib/widgets/chat_page.dart` | 修改 | `_handleSkipPractice`：原 `onSkipPractice` 直接清任务 → 改为打开确认弹窗；「继续练习」仅关弹窗（对齐 RN cancelAbandonPractice）；「确认跳过」→ `resetPractice()` 清空练习状态（对齐 RN resetPracticeState）→ 子阶段内存置 DIAGNOSIS + `setSubphase` 持久化（对齐 RN setSubphase('DIAGNOSIS')） |
| `lib/widgets/message_list.dart` | 修改 | **附带布局修复**：练习任务卡/结果指示器从 Column 外部固定渲染移入 ListView item 序列（列表底部，对齐 RN 训练卡在 FlatList 内）——修复消息 + 练习卡叠加时 18px 布局溢出 |
| `test/widgets/abandon_practice_modal_test.dart` | 新增 | 4 测试：渲染（图标/标题/文案/双按钮）+ 继续练习回调 + 确认跳过回调 + 阻断式（点击遮罩不关闭） |
| `test/widgets/chat_page_test.dart` | 修改 | +3 集成测试 #B15-1（点「跳过」→ 确认弹窗出现且任务仍在）/ #B15-2（继续练习 → 弹窗关闭 + 任务保留）/ #B15-3（确认跳过 → 任务清空 + teaching_state 子阶段落库 DIAGNOSIS） |

设计决策：
- **阻断式对齐 RN**：RN onRequestClose 为空实现（点击遮罩不关闭），Flutter `barrierDismissible: false` 等价；仅「继续练习/确认跳过」两个出口
- **确认跳过完整语义**：对齐 RN L486 三步（confirmAbandonPractice 关弹窗 → resetPracticeState 清空练习 → setSubphase('DIAGNOSIS')）；Flutter 合并为 `resetPractice()` + 内存/持久化双写子阶段
- **MessageList 布局修复**：练习卡固定渲染在 Column 外，当消息 + 练习卡共存时总高超视口溢出 18px（真实 bug，批次 15 集成测试暴露）；移入 ListView 后恢复可滚动，行为更贴近 RN

## 批次 16 — 导入成功反馈（待提交）

> 缺口清单（docs/2026-08-07-rn-gap-analysis.md）B 类诊断交互闭环，复刻 RN `reference/ImportSuccessSheet.tsx` + `chat.tsx`（WorkImportModal onComplete → ImportSuccessSheet 接线）。**用户否决 C 类「里程碑庆祝」（"第十个没必要了"），选择本项**。

| 文件 | 改动 | 说明 |
|------|------|------|
| `lib/widgets/import_success_sheet.dart` | 新增 | 复刻 RN ImportSuccessSheet：bottom sheet 弹层（顶部把手 + 成功圆底勾图标 primary 56x56 + 标题「导入成功！」+ 副标题「已成功导入 {chapterCount} 个章节到「{manuscriptTitle}」」+ 引导「是否立即发送给月笙诊断？」+ 「立即诊断」FilledButton /「稍后再说」OutlinedButton）；按钮回调先 pop 再触发外部回调 |
| `lib/widgets/chat_page.dart` | 修改 | `_handleUploadComplete(WorkImportResult)`：原 SnackBar「已导入《X》（N章）」→ `showModalBottomSheet` 打开 ImportSuccessSheet；`onDiagnose`：`pendingDiagnosisChapterProvider` 写 `result.firstChapterId` → 自动诊断链（对齐 RN startDiagnosis=true&chapterId=X 路由语义）；`onClose`/`onDiagnose` 均触发 `_refreshAfterUpload`（刷新引用条 + 重载消息） |
| `test/widgets/import_success_sheet_test.dart` | 新增 | 3 测试：渲染（把手/图标/标题/章节数/双按钮）+ 立即诊断回调 + 稍后再说回调 |
| `test/widgets/chat_page_test.dart` | 修改 | +3 集成测试 #B16-1（导入完成 → 成功引导弹层 + 章节数 + 双按钮）/ #B16-2（立即诊断 → 自动诊断 user 消息落库）/ #B16-3（稍后再说 → 弹层关闭 + 不发送诊断）；修复既有 #B4-2 断言（SnackBar → 「导入成功！」弹层）；双 TextField 歧义修复（find.descendant 限定 AlertDialog 内） |

设计决策：
- **弹层替代 SnackBar**：RN 导入完成弹出 ImportSuccessSheet 而非 toast，Flutter 对齐——原「已导入《X》（N章）」SnackBar 移除
- **立即诊断 = 自动诊断链**：对齐 RN 跳转 `/chat?startDiagnosis=true&chapterId=X`；Flutter 复用批次 13 的 `pendingDiagnosisChapterProvider` 跨 Tab 传递 + `_handleAutoDiagnose`（长文分块渐进/短文单次）
- **按钮先 pop 再回调**：对齐 RN onClose → dismiss + callback 顺序，避免弹层未关就刷新引用条导致布局异常
- **里程碑庆祝用户否决**：C 类 MilestoneCelebration（★）不实施，缺口清单已标注决策

验证：`dart analyze` 0 error/warning（批次 16 文件；32 条 info 均为历史存量文件）/ `dart format` 全过 / `flutter test` 全量 **601 全绿**（595 → 601，新增弹层 3 + ChatPage 集成 3）

## 批次 17 — 消息卡片类型（待提交）

> 缺口清单（docs/2026-08-07-rn-gap-analysis.md）B 类诊断交互闭环，复刻 RN `chat/message-cards/PartialAgreementCard.tsx` + `PhaseSummaryCard.tsx` + `DiagnosisFailedCard.tsx` + `services/message-card-service.ts`（三 insert 函数）+ `MessageBubble.tsx`（message_type 分派分支）。
> **RN 真源中三卡交互回调均为 TODO 占位（console.log）**，本批次为渲染扩展：卡片完整可交互（按钮可点），但回调默认无外部副作用，待后续流程批次接线。

| 文件 | 改动 | 说明 |
|------|------|------|
| `lib/config/shared_constants.dart` | 修改 | `UILimits` 增加 `maxSyndromeChanges = 5`（PhaseSummaryCard 症候变化上限）+ `failureWarningThreshold = 2`（DiagnosisFailedCard 多次失败提示阈值），真源 UI_LIMITS |
| `lib/services/message_card_service.dart` | 修改 | 新增三 payload 类：`PartialAgreementCardPayload`（syndromeId/syndromeName/severity）+ `PhaseSummaryCardPayload`（result/resolvedSyndromeCount/trainingCount/trend/syndromeChanges）+ `SyndromeChangeItem`（简化模型，RN 存完整 SyndromeEvaluationDetail 数组亦可兼容解析）+ `DiagnosisFailedCardPayload`（failureCount）；三 insert 函数（assistant 角色，对齐 RN）：`insertPartialAgreementCard`（平铺参数签名对齐 RN）/`insertPhaseSummaryCard`/`insertDiagnosisFailedCard` |
| `lib/widgets/partial_agreement_card.dart` | 新增 | 复刻 RN PartialAgreementCard：severity 色左边框 + 「请补充不符合的地方」+ severity 矿物色徽标 + 症候名 chip（primarySoft 底）+ 提示文案 + 多行反馈输入框 + 3 快速选项横向 chips（症状描述不准/缺少某个问题/严重度不对）+ 「跳过此症候」（描边）/「提交反馈」（primary，空输入禁用）；`DEFAULT_QUICK_OPTIONS` 常量 + `fromMessageContent` |
| `lib/widgets/phase_summary_card.dart` | 新增 | 复刻 RN PhaseSummaryCard：passed/partial/failed/default 结果配置（图标圆底 + 标题 + 鼓励文案，矿物色）+ 统计行（解决症候数/练习次数/进步趋势 改善/稳定/恶化）+ 症候变化列表（≤5 条截断）+ 「继续训练」（结果色底）/「查看学员画像」+「返回对话」（描边）三按钮；`fromMessageContent` |
| `lib/widgets/diagnosis_failed_card.dart` | 新增 | 复刻 RN DiagnosisFailedCard：搜索图标圆底 + 「未检测到明显问题」+ 提示文案 + 建议列表（默认 3 条 / 外部注入优先，suggestBg 底）+ 「补充内容」（primary）/「继续对话」（描边）+ failureCount ≥ 2 时「提示：多次诊断失败后建议主动描述问题」；`DEFAULT_DIAGNOSIS_SUGGESTIONS` + `fromMessageContent` |
| `lib/widgets/message_list.dart` | 修改 | message_type 分派新增三分支：partial_agreement → PartialAgreementCard / phase_summary → PhaseSummaryCard / diagnosis_failed → DiagnosisFailedCard（对齐 RN MessageBubble L119-181） |
| `test/services/message_card_service_test.dart` | 新增 | 3 测试：三 insert 函数落库断言（assistant 角色 + message_type + content JSON 解析） |
| `test/widgets/partial_agreement_card_test.dart` | 新增 | 6 测试：渲染 / 空输入禁用+提交回调 / 快速选项 / 跳过 / fromMessageContent 合法+非法 |
| `test/widgets/phase_summary_card_test.dart` | 新增 | 7 测试：passed/failed/partial 渲染 / 症候变化超 5 条截断 / 三按钮回调 / fromMessageContent 合法+非法 |
| `test/widgets/diagnosis_failed_card_test.dart` | 新增 | 7 测试：默认建议 / 自定义建议注入 / 失败阈值提示开关 / 双按钮回调 / fromMessageContent 合法+非法 |
| `test/widgets/message_list_test.dart` | 修改 | +3 分派集成测试（批次17 group：三卡消息 → 对应卡片渲染） |

设计决策：
- **渲染层展示为主**：RN 三卡交互回调（onSubmit/onSkip/onContinueTraining 等）在真源中均为 TODO 占位，Flutter 渲染层同样不绑定外部副作用；按钮保持可点击（回调为 null 时无害空实现），提交反馈后清空输入框保证「已提交」语义
- **assistant 角色**：三卡 insert 用 assistant 角色（对齐 RN addMessage 角色参数），与 diagnosis_result/teacher_suggestion（system）区分
- **SyndromeChangeItem 简化**：RN syndromeChanges 存完整 SyndromeEvaluationDetail[]，Flutter 卡片仅用 syndromeName + trend，解析时忽略其余字段，保证 RN 插入数据可被 Flutter 渲染
- **UILimits 补齐**：maxSyndromeChanges=5 / failureWarningThreshold=2 对齐 RN UI_LIMITS（此前 Flutter 仅搬运章节选择器常量）

验证：`dart analyze` 0 error/warning（批次 17 文件；32 条 info 均为历史存量文件）/ `dart format` 全过 / `flutter test` 全量 **627 全绿**（601 → 627，新增 26：服务层 3 + 三卡组件 20 + 分派 3）

## 批次 18 — 活跃问题面板（待提交）

> 缺口清单（docs/2026-08-07-rn-gap-analysis.md）C 类弹层与工具，复刻 RN `chat/TaskPanel.tsx` + `app/chat.tsx`（taskToggle L396-400 + taskPanelContainer L541 + useDiagnosis.loadActiveProblems/handleMarkComplete）。
> **记忆硬约束**：TaskPanel 仅保留活跃问题列表，教学建议部分移除（已移至对话流 TeacherSuggestionCard）——Flutter 版不含 teacherSuggestions 段。

| 文件 | 改动 | 说明 |
|------|------|------|
| `lib/widgets/task_panel.dart` | 新增 | 复刻 RN TaskPanel（仅活跃问题段）：空态（✅ + 「暂无活跃问题」+「完成诊断后会显示需要解决的问题」，对齐 EmptyState）+ header「练习任务」+「N 个问题」徽标 + 分隔线 + 问题行（severity 矿物色左边框 3dp + 圆点 8dp + 症候名 + 严重度中文标签（L1建议/L2注意/L3严重，对齐 SEVERITY_LABELS）+ 「完成」按钮（onMarkComplete 可选，null 时不显示）） |
| `lib/widgets/chat_page.dart` | 修改 | 批次 18 接线：状态 `_showTaskPanel` + `_activeProblems`；`_loadActiveProblems`（DiagnosisRepository.listActiveProblems）+ `_handleMarkComplete`（resolveProblem 落库 + 重载，对齐 RN handleMarkComplete）；`_loadAttitude` 中 phase==P2 时自动加载（对齐 RN useEffect currentPhase 依赖）；build：P2 阶段显示 toggle「任务 (N)」/「收起任务」（对齐 RN taskToggle）+ 展开时 200 高 TaskPanel（对齐 RN taskPanelContainer height 200） |
| `test/widgets/task_panel_test.dart` | 新增 | 5 测试：空态 / 列表渲染（N 个问题 + 症候名 + 严重度标签）/ L3→严重 / 完成回调 / 无回调不显示按钮 |
| `test/widgets/chat_page_test.dart` | 修改 | +3 集成测试 #B18-1（P2 阶段任务开关 + 展开显示问题 + 收起）/ #B18-2（完成 → active_problem status=resolved + 面板空态 + 收起后「任务 (0)」）/ #B18-3（非 P2 不显示开关） |

设计决策：
- **仅活跃问题段**：记忆硬约束（教学建议已移至对话流卡片），RN 的 teacherSuggestions 段不实现
- **P2 可见性对齐**：toggle 与面板均仅 P2 阶段显示（对齐 RN isP2Phase）；面板 200 固定高度（对齐 RN taskPanelContainer）
- **数据流对齐**：进入 P2 自动加载（RN useEffect）、「完成」→ resolveProblem + 重载（RN handleMarkComplete 两步）
- **onMarkComplete 可选**：对齐 RN 可选 prop；为 null 时不渲染「完成」按钮

验证：`dart analyze` 0 error/warning（批次 18 文件；32 条 info 均为历史存量文件）/ `dart format` 全过 / `flutter test` 全量 **635 全绿**（627 → 635，新增 8：TaskPanel 5 + ChatPage 集成 3）

## 批次 19 — D/E 类只读审计（仅文档）

> 按交接建议先只读审计 RN 真源 5 个独立页 + Flutter 现有路由/页面/服务，逐页确认独立页面价值，避免为对齐而造冗余页。**用户决策：本批只更新文档，不写代码**（素材/创建项目两页标注无需实施，会话列表页标注已覆盖）。

| 文件 | 改动 | 说明 |
|------|------|------|
| `docs/2026-08-07-rn-gap-analysis.md` | 修改 | D 类表格逐页标注审计结论；E 类 progress-service 注记更正为误判、skill-lifecycle 标注闭环；建议实施顺序追加第 14 条；已确认无缺口追加 2 项 |

设计决策：
- **素材独立页（materials.tsx）→ 无需实施**：RN 真源 `_layout.tsx` 注册路由但全文无 `router.push('/materials')` 入口（死路由），稿件详情实际用内嵌 FileSection Tab；Flutter 内嵌 FileSection 已覆盖上传/删除/查看/空态 → 不造冗余页
- **创建项目（create-project.tsx）→ 无需实施**：书架「新建作品」弹窗（bookshelf_page.dart `_CreateManuscriptModal`）已覆盖创建语义（标题/简介/类型）；RN 独立页仅多体裁 chips + 语言选择，属形式差异
- **导入确认（import-confirm.tsx）→ 确认真实缺口**：RN 稿件详情 ChapterSection「导入」按钮 → import-confirm 页（选文件 → parseDocument 解析 → 与已有章节标题比对标记「已存在」→ 多选/全选/取消 → createChaptersBatch 批量入库 → ImportSuccessSheet → 回稿件详情）；Flutter 稿件详情仅「+ 新建」单章弹窗，无批量追加章节 UI；`chapter_repository.createChaptersBatch`（复刻同名函数）已备无消费方 → 列入后续实施序列
- **项目设置（project-settings.tsx）→ 确认真实缺口**：RN 从稿件详情 MoreMenuSheet 进入（编辑名称/体裁/简介 + 标签 + 统计 + 删除项目含二次确认，删除级联全部章节/诊断）；Flutter manuscript_detail 无更多菜单、无编辑/删除作品入口；store 层 `updateManuscript`/`deleteManuscript` 已支持无 UI 消费 → 列入后续实施序列
- **进度详情（progress-detail.tsx）→ 捆绑 E 类 progress-service 待评估**：RN 为会话级学习进度页（getProgressSummary/getDiagnosisHistory/getProblemStats/generateReport + SyndromeTrendList + 症候详情弹层复用）；Flutter growth_detail_page 为用户级能力画像（对应 RN growth-detail.tsx），两者不同源
- **E 类 progress-service 误判更正**：缺口清单原注记「Flutter 有 student_profile_compute，疑似对应」经核对应错误——`student_profile_compute.dart` 复刻 RN `student-profile-compute.ts`（用户画像计算），progress-service 在 Flutter 无对应实现
- **E 类 skill-lifecycle → 闭环**：Flutter `skill_layers.dart`（L1/L2 配置 + L2Mode 解析 + resolveL2Mode）+ `skill_dispatcher.dart`（token 估算/组装/注入）等价覆盖 RN skill-lifecycle 核心职责（分层加载/模式切换/token 预算/组装），组织方式差异（RN 会话级管理 vs Flutter dispatcher 式内联）

验证：纯文档批次，无代码改动，不触发 analyze/format/test 四闸；审计基于当前源码实态（真源对照：RN `src/app/*.tsx` + Flutter `lib/router/app_router.dart`/`lib/widgets/*`/`lib/services/*`）

## 批次 20 — 追加章节导入 + 项目设置（待提交）

> 缺口清单（docs/2026-08-07-rn-gap-analysis.md）D 类两真实缺口，复刻 RN `app/import-confirm.tsx` + `components/manuscript/ChapterSection.tsx`（导入按钮）+ `app/project-settings.tsx` + `components/modals/MoreMenuSheet.tsx`。

| 文件 | 改动 | 说明 |
|------|------|------|
| `lib/widgets/append_chapters_page.dart` | 新增 | 复刻 RN import-confirm.tsx：AppBar「追加章节」+「选择导入方式」区（说明「将新章节追加到《title》」+ 虚线边框「选择文件」按钮，loading 转圈）→ `pickDocument`/`readFileContent`/`parseDocument` 解析 → 与 `listChapters` 已有标题比对（`Set(title.trim())`）标记「已存在」→ 章节列表（checkbox + 标题 + 字数 + 已存在徽标，已存在禁选默认不选中）→ 全选/取消（仅作用于新章节，对齐 RN handleSelectAll）→ 底部「已选 N 章」+「确认导入」（0 选禁用，对齐 RN footer）→ `createChaptersBatch` 批量入库（事务内 sort_order MAX+1 递增）→ 复用批次 16 `ImportSuccessSheet`（chapterId 不传 → 立即诊断/稍后再说均回稿件详情，对齐 RN L248-260） |
| `lib/widgets/project_settings_page.dart` | 新增 | 复刻 RN project-settings.tsx：AppBar「项目设置」+ 右侧「保存」→ `getManuscript` 加载（名称/体裁/简介/标签初始=[genre]/创建时间）→ 名称 TextField + 体裁 chips（长篇小说/中篇/短篇，对齐 RN GENRES）+ 简介 TextArea + 标签区（chips + × 删除 + 「+ 添加标签」dialog 输入，本地状态 RN 亦不落库）+ 统计信息「创建于」+ 危险区「删除项目」（二次确认「删除后将无法恢复…」→ `deleteManuscript` 软删除 + go /bookshelf）+ 保存（名称空拦截「请输入作品名称」→ `updateManuscript` → SnackBar「设置已保存」→ 800ms 后返回，对齐 RN setTimeout back） |
| `lib/router/app_router.dart` | 修改 | 新增 `/append-chapters`（AppendChaptersPage：manuscriptId/title extra，缺 ID 占位页）+ `/project-settings`（ProjectSettingsPage：同参数语义）两顶层路由 |
| `lib/widgets/manuscript_detail_page.dart` | 修改 | 批次 20 接线：`_ChapterList` 顶部 header「章节列表」+「导入」按钮（对齐 RN ChapterSection sectionHeader/importButton，空态 ListView 同样显示）→ push `/append-chapters`；AppBar 新增 more_vert 更多菜单 → `_MoreMenuSheet` bottom sheet（导出项目/分享 开发中 tag + 点击提示「开发中，敬请期待」对齐 RN MENU_TEXT + 项目设置 → push `/project-settings` + 分隔线 + 删除项目 → 二次确认弹窗（确认文案对齐 RN project-settings handleDelete；项目硬约束：关键操作需确认）→ deleteManuscript + go /bookshelf） |
| `test/widgets/append_chapters_page_test.dart` | 新增 | 9 测试：空态渲染 / 选择文件取消 / 解析渲染（标题/字数/已选计数）/ 已存在徽标 + 默认不选中 / 已存在禁选 / 全选取消（对齐 RN 全选仅作用新章节）/ 0 选确认按钮禁用 / 确认导入落库 + 成功弹层 / 稍后再说回稿件详情；FilePicker 插件不可测 → `pickAndParseOverride` 注入解析回调（对齐批次 4a 粘贴路径先例） |
| `test/widgets/project_settings_page_test.dart` | 新增 | 7 测试：渲染 / 名称空保存拦截 / 保存成功落库 + 回书架 / 切换体裁保存 / 添加标签 / 删除标签 / 删除项目取消+确认（archived + 回书架）；危险区按钮视口外 → ensureVisible 滚动 |
| `test/widgets/manuscript_detail_page_test.dart` | 修改 | +4 集成测试 #11-14：导入按钮存在（空态+有章节）/ 更多菜单项显示+取消关闭 / 项目设置跳转 / 删除项目确认→archived+回书架；既有 #V4 断言补 padding 条件排除导入按钮（同为 #E8F0EE） |
| `test/router/app_router_test.dart` | 修改 | +2 路由可达测试 #7-8：/append-chapters、/project-settings |

设计决策：
- **复用而非重造**：批量入库复用 `chapter_repository.createChaptersBatch`（复刻同名函数，事务内 MAX+1 递增）；成功弹层复用批次 16 `ImportSuccessSheet`（chapterId 不传即回稿件详情，对齐 RN import-confirm 场景）；store 层 update/delete 复用既有 `ManuscriptStore`
- **可测性注入**：FilePicker 插件在 widget 测试不可用 → `pickAndParseOverride` 可选参数（默认走真实 pickDocument 链路，测试注入解析结果），对齐批次 4a「粘贴文本路径可测」先例
- **删除均需二次确认**：更多菜单与项目设置页的删除都用同一确认文案（对齐 RN project-settings；RN 更多菜单直接删是隐患，按项目硬约束「关键操作需确认」补强）
- **标签不落库**：RN updateManuscript 仅传 title/genre/description，tags 为本地状态 → Flutter 对齐，标签区为 UI 状态
- **全选语义对齐 RN**：`handleSelectAll` 仅选中非已存在章节（RN L94-97），测试 #6 按此语义断言
- **既有测试兼容**：#V4 信息胶囊断言补 padding 条件，避免匹配到同色（#E8F0EE）的「导入」按钮

验证：`dart analyze` 0 error/warning（批次 20 文件；32 条 info 均为历史存量文件）/ `dart format` 全过 / `flutter test` 全量 **657 全绿**（635 → 657，新增 22：append 9 + settings 7 + detail 4 + router 2）

## 批次 21 — 进度详情 + progress-service（待提交）

> 缺口清单（docs/2026-08-07-rn-gap-analysis.md）D/E 类收尾，复刻 RN `services/progress-service.ts` + `app/progress-detail.tsx` + 子组件（ProgressSummaryCard / DiagnosisHistory / SyndromeTrendList / ProblemStats / ProgressReport）+ `app/(tabs)/bookshelf.tsx`（ProgressCard 入口）。**用户决策：完整复刻 + 书架页主入口（最新会话）**。

| 文件 | 改动 | 说明 |
|------|------|------|
| `lib/services/progress_service.dart` | 新增 | 复刻 RN progress-service.ts：`getProgressSummary`（teaching_state + listDiagnosisHistory 聚合 + active_problems 全量统计 + lockedSyndromes 仅 active 按 created_at DESC）、`getDiagnosisHistory`（syndromes JSON → 症候计数，非法 JSON 计数 0）、`getProblemStats`（全量 active+resolved 按 created_at DESC）、`generateReport`（纯文本：学习概览/问题统计/待改进/已解决/解决率，无 IO 可单测）；模型 ProgressSummary/DiagnosisRecord/ProblemStat/LockedSyndrome + 阶段/等级/严重度中文标签常量 |
| `lib/widgets/progress_detail_page.dart` | 新增 | 复刻 RN progress-detail.tsx：AppBar「学习进度」+ 并行加载四数据（Promise.all 对齐）→ ProgressSummaryCard 概览卡（当前阶段/诊断次数/总问题/已解决/待改进）+ DiagnosisHistory 诊断历史（日期/置信度/症候数）+ SyndromeTrendList 症候趋势（severity 色点迷你条 + 出现次数 + 趋势文案，点击 → 复用批次 8 SyndromeDetailModal）+ ProblemStats 问题统计（严重度筛选 chips 全部/L3严重/L2注意/L1建议 + 状态标签 + 发现/解决时间 + 底部汇总）+ 生成学习报告 → `_ProgressReportView` 报告视图（复制 Clipboard + 分享「开发中，敬请期待」对齐批次 20 更多菜单） |
| `lib/widgets/bookshelf_page.dart` | 修改 | 批次 21 接线：顶部 `_ProgressCard`（对齐 RN ProgressCard：标题/阶段徽章/完成度%+进度条/总问题·已解决·待改进/诊断次数+箭头；完成度 = resolved/total）+ `_loadProgressCard`（listSessions updated_at DESC 取最新会话 → getProgressSummary，无会话不显示，加载失败静默）+ 点击 → push `/progress-detail`；EmptyState 分支包 LayoutBuilder+SingleChildScrollView+ConstrainedBox（进度卡共屏空间变小防 RenderFlex 溢出，保持居中） |
| `lib/router/app_router.dart` | 修改 | 新增 `/progress-detail`（ProgressDetailPage：sessionId extra，缺 ID 占位页） |
| `test/services/progress_service_test.dart` | 新增 | 6 测试：空数据默认值 / teaching_state+诊断+问题+锁定症候（DISTINCT 计数、resolved 计数、locked 排序）/ 症候计数解析 / 非法 JSON 计数 0 / 问题统计全量排序 / 报告文本结构 |
| `test/widgets/progress_detail_page_test.dart` | 新增 | 4 测试：空数据默认值+空态 / 有数据概览+诊断历史+症候趋势+问题统计（scrollUntilVisible 底部）/ 生成报告视图+返回 / 症候趋势行点击弹层 |
| `test/widgets/bookshelf_page_test.dart` | 修改 | +3 测试 #8-10：有会话进度卡默认值 / 有数据统计（50% 完成度）/ 点击进度卡跳转详情页 |
| `test/router/app_router_test.dart` | 修改 | +1 路由可达测试 #9：/progress-detail |

设计决策：
- **完整复刻 + 书架主入口**：用户决策——完整复刻（含报告功能）与书架页入口（对齐 RN bookshelf ProgressCard 主入口）；Flutter 无 currentSession 概念 → 用 listSessions 最新一条（updated_at DESC）近似
- **薄聚合复用**：getProgressSummary 复用 TeachingStateRepository + DiagnosisRepository + active_problems 表（drift 直查），不新增仓库方法；lockedSyndromes 与 ProblemStats 同源（RN 亦均为 active_problem 表查询），数据完全对齐
- **generateReport 纯函数**：无 IO 依赖可单测（对齐 RN）；「已锁定症候」行含 lockedSyndromes 映射
- **症候趋势复用批次 8**：SyndromeTracker.loadSyndromeTrends + SyndromeDetailModal 直接复用，页面仅做行 UI（severity 色点迷你条对齐 RN MiniTrendChart）
- **报告分享对齐批次 20**：Flutter 无系统 Share 内置 → 复制实现（Clipboard）、分享 SnackBar「开发中，敬请期待」（对齐批次 20 更多菜单开发中处理）
- **progress-service 误判更正落地**：批次 19 确认 student_profile_compute 对应 RN student-profile-compute.ts（非 progress-service），本批以独立服务落地补齐
- **EmptyState 防溢出**：进度卡与空态共屏时 Expanded 空间变小，EmptyState 包 LayoutBuilder+SingleChildScrollView+minHeight ConstrainedBox（可滚动 + 保持居中），修复 RenderFlex overflow 34px（真实 bug，批次 21 集成测试暴露）

验证：`dart analyze` 0 error/warning（批次 21 文件；32 条 info 均为历史存量文件）/ `dart format` 全过 / `flutter test` 全量 **671 全绿**（657 → 671，新增 14：service 6 + detail 4 + bookshelf 3 + router 1）

## 批次 22 — skill-lifecycle 内容层补齐：L2 按需层搬运（2026-08-08，skill-lifecycle 虚假闭环修复）

> 背景：批次 19 审计将 skill-lifecycle 标注"✅ 已闭环"经 2026-08-08 复核为**虚假闭环**——配置层（skill_layers/skill_dispatcher 组装框架）已对齐，但内容层缺失：skill_registry 仅注册 11 个（8 L1 + 3 态度），L2 按需层 26 个 skill 全部未搬运（dispatcher 静默跳过），L3 症候/技法库为空。chat_service 教学链路（buildSystemPromptV2 → system message）只注入 L1 + 态度档位 + 位置判断引导语。本批为缺口清单第 17 条步骤①。

| 文件 | 状态 | 说明 |
|------|------|------|
| `lib/services/skill_registry.dart` | 修改 | 新增 26 个 L2 Skill 常量 + 注册：beginner 6（beginner-path/gap-detector/coaching-rhythm/narrative-design/plot-design/writer-psychology）+ diagnosis 6（coaching-actions/reader-awareness/genre-guide/writing-style/diagnosis-confirmation/feedback-cognition）+ training 12（training-loop(-v2)/training-templates(-index)/training-evaluation(-v2)/text-surgery(-v2)/coaching-actions-v2/demonstration/comparison/revision-methodology）+ advanced 1（advanced-phases）+ outline 1（outline-diagnosis）；注册表 11 → 37 |
| `test/skill_registry_l2_test.dart` | 新增 | 10 测试：注册完整性（L1 8 + 态度 3 + L2 26 = 37）/ 内容非空非占位 / beginner 组装 6 个 / diagnosis 组装（V2 替换 coaching-actions→v2）/ training 组装（v2 全替换 + 索引加载）/ advanced / outline / validatePrompt token 预算 |

设计决策：
- **内容逐字保留**：RN 真源 `src/assets/skills/*.ts` content 100% 搬运（`\`\`\`` 转义反引号还原为 ```，`${}` 插值原样保留，loadWhen 元数据不搬运——Flutter SkillMeta 只有 id/group/estimatedTokens）
- **V2 开关生效验证**：USE_TRAINING_V2_PILOT=true 下 training/diagnosis 模式 coaching-actions→coaching-actions-v2、training-loop→training-loop-v2 等替换（skill_layers 既有逻辑，本批补齐被替换目标的内容）；diagnosis 模式加载 coaching-actions-v2（标题「教学方法目录」）
- **虚拟索引保留跳过**：syndrome-diagnosis-index / technique-library-index 仍为虚拟 id（dispatcher 跳过），其索引内容与 L3 完整知识库留待步骤②（syndrome-diagnosis.ts / technique-library.ts / training-templates-v2 完整教学知识接入 chat_context_builder）
- **training-templates-index 落地**：V2 下 training 组实际加载 training-templates-index（19 症候一句话索引，RN TRAINING_INDEX_CONTENT），已随本批注册生效

验证：`dart analyze` 0 error/warning（32 条 info 均为历史存量）/ `dart format` 全过 / `flutter test` 全量 **681 全绿**（671 → 681，新增 10：skill_registry_l2_test）+ 3 live skipped（无 API key 自动跳过，不影响四闸）

### 批次 22 步骤② — L3 症候/技法知识库搬运与接入

| 文件 | 状态 | 说明 |
|------|------|------|
| `lib/services/syndrome_knowledge_base.dart` | 新增 | 复刻 RN `syndrome-diagnosis.ts`：`kSyndromeIndexContent`（L2 索引，写作问题→症候 ID 映射表）+ `kSyndromeManualContent`（L3 完整手册，P003-P021 全部定义，逐字保留）+ `getSyndromeContent` 按 ID 提取 |
| `lib/services/technique_knowledge_base.dart` | 新增 | 复刻 RN `technique-library.ts`：`kTechniqueIndexContent`（L2 索引，技法速查表）+ `kTechniqueLibraryContent`（L3 完整技法库，T001-T031）+ `kTechniquesBySyndrome` 映射 + `getTechniqueContent`/`getTechniquesBySyndrome` 检索 |
| `lib/services/skill_registry.dart` | 修改 | 注册 `syndrome-diagnosis-index`/`technique-library-index` 两虚拟索引 skill（内容 = 索引），注册表 37 → 39 |
| `lib/services/skill_dispatcher.dart` | 修改 | 解除虚拟索引跳过逻辑（已注册则加载）；`_getSyndromeContent`/`_getTechniqueContent` 接入真实检索（原返回 null） |
| `lib/services/chat_context_builder.dart` | 修改 | focus 症候 `syndromeContent`/`techniqueSection` 空串替换为真实 L3 注入（getSyndromeContent + getTechniquesBySyndrome，对齐记忆约束「L3 内容加载策略：focus 完整定义+证据，secondary 仅 ID+名称+严重度+一句理由」） |
| `test/syndrome_technique_knowledge_test.dart` | 新增 | 9 测试：症候索引/手册完整性、单/多症候提取、技法提取、按症候取首选+备选、chat_context_builder focus 注入接线（含非 focus 简化不注入 L3） |

设计决策：
- **索引注册 + L3 检索分离**：L2 层只加载索引（syndrome-diagnosis-index / technique-library-index，对齐 RN L2 只含 index），完整知识由 L3 检索按焦点注入（对齐 RN 三级加载 token 优化：117K → 26K）
- **检索函数语义**：dispatcher `_getSyndromeContent`(症候ID) / `_getTechniqueContent`(技法ID) 按 ID 提取；chat_context_builder 用 `getTechniquesBySyndrome`（症候→首选+第一个备选技法）注入 focus
- **内容搬运**：两大知识库（症候手册 835 行 + 技法库 790 行）由并行子代理逐字搬运（raw string，`\`\`\`` 反引号还原），analyze 0 error；抽查 P003/P021/T001/T031 标记均完整

验证：`dart analyze` 0 error/warning（32 条 info 均为历史存量）/ `dart format` 全过 / `flutter test` 全量 **690 全绿**（681 → 690，新增 9：syndrome_technique_knowledge_test）+ 3 live skipped

**步骤②补充 — 训练侧 L3 知识库（training-templates-v2 完整教学知识）**：新增 `lib/services/training_knowledge_base.dart`（kTrainingFullKnowledge 完整教学知识 P003-P021：核心本质/教学要点/常见误区/严重度判断参考/教学素材库，内容逐字保留 RN training-templates-v2.ts + getTrainingContent 按症候检索）；`chat_context_builder.dart` focus 症候注入追加完整训练知识（对齐记忆约束「L3 内容加载策略：focus 症候提供完整定义」训练侧）；`test/syndrome_technique_knowledge_test.dart` +3（完整知识覆盖/单症候提取/多症候+空输入）→ **693 全绿**。注：RN 生产路径未调用 getTrainingContent（仅在测试），Flutter 按记忆约束补齐为超集。

### 批次 22 步骤③ — 行为/构造层全量对照扫描（2026-08-08，用户指示"全停，扫描早期 RN 全部应用行为找漏洞"）

> 触发背景：教学环境验证方式被用户叫停（"我不允许你直接测，你需要构造后在应用里测试"）后，用户要求暂停实施，改为从**行为与构造**两个层面做 RN 全量扫描对照，寻找真实缺口。

执行方式：RN（`yuesheng-android/src`）与 Flutter（`yuesheng-flutter/lib`）双只读全量扫描 → 按页面/交互/服务/存储/错误处理/配置 6 维度提取行为清单 → 逐项对照 → 疑点源码级定向核实（grep/read）。**本轮仅只读审计，未改任何代码**。

**行为层真实缺口（8 项）**：

| 编号 | 行为 | 判定 | 优先级 |
|------|------|------|--------|
| B1 | Mem0 记忆合并（NO_OP：同症候同严重度跳过 INSERT） | **缺口**——Flutter commitDiagnosis 直接落库，诊断历史积累重复记录，影响趋势统计 | ★★★ 高 |
| B2 | effectiveness 计算（teaching_history.effectiveness 写入） | **缺口**——Flutter 注释"P1 不必要"不计算，但 student_profile 有读取逻辑（读有写无，画像永不显示效果信息） | ★★ 中 |
| B3 | 划词诊断（选中 ≥20 字 → 「诊断这段文字」） | **缺口**——Flutter 写作页仅标点栏插入 | ★★ 中 |
| B4 | 首次诊断里程碑庆祝（MilestoneCelebration） | **已决策不做**（批次 16），保留决策仅记录差异 | ★ 低 |
| B5 | 离线模式 + 离线草稿（netinfo 断线 → 横幅 + 禁保存/诊断 + 自动存草稿 + 恢复同步） | **缺口**——Flutter 无离线检测（章节数据安全） | ★★★ 高 |
| B6 | 草稿恢复弹窗（draft.savedAt > updated_at → 是否恢复） | **缺口**——app_state_repository 已有草稿 DAO，无恢复交互 | ★★ 中 |
| B7 | 撤销/重做（useUndoRedo 双栈） | **缺口**——WritingMenuSheet 明确移除 | ★★ 中 |
| B8 | 成长页 ObservationAuditCard | **缺口**——editor_observation 表已实现，缺展示 | ★ 低 |

**构造层核对（纠正旧误判）**：
- C2 三消息卡片调用方：RN 亦**仅 DevToolPanel 调试面板调用**、生产路径不调用 → Flutter 无生产调用方为**对齐非缺口**（纠正）
- C3 ReviewerGate：RN `ENABLED: false` = Flutter `enabled: false` → **对齐**（纠正）
- C5 FSRS：RN T-011 已从生产 import 链彻底移除 → Flutter 未实现为**对齐**（纠正）
- C4 inferCognitiveStyle：RN 跨全表扫描 vs Flutter 仅当前 session → 差异（影响有限，已注释）
- C1 skill-lifecycle 内容层：批次 22 ①②已完成 → 已闭环，剩步骤③实测

**RN 侧缺陷（Flutter 不模仿）**：settings 清除缓存 SQL 引用不存在表 / tags 不落库 / card-list 路由悬空 / attitude-rhythm.json + syndrome-action-map.json 孤儿资产无消费者 / cancelToken 无 UI 接线。

产出：`docs/2026-08-07-rn-gap-analysis.md` 新增 F 章节（行为/构造层缺口表 + 结论）。待用户确认后按优先级排实施批次。

## 批次 23 — 行为层缺口实施（2026-08-08）

> 依据：缺口清单 F-1 行为层缺口，用户确认优先实施 B1（记忆合并）+ B5（离线草稿）。按顺序分两子步骤，每步四闸验证。

### 批次 23 步骤① — B1 Mem0 记忆合并

| 文件 | 状态 | 说明 |
|------|------|------|
| `lib/data/repositories/diagnosis_repository.dart` | 修改 | `commitDiagnosis` 新增步骤 0 记忆合并：查询本会话最新一条诊断 → 逐症候比对 syndrome_id+severity → 同症候同严重度标记 NO_OP → INSERT 仅写入过滤后症候（filteredSyndromes），active_problem 仍 UPSERT 全部症候（含 NO_OP），对齐 RN diagnosis-dao.ts 步骤 0 |
| `test/dao_repository_test.dart` | 修改 | 新增 3 测试：NO_OP 跳过 INSERT（最新记录 syndromes 为空数组 + active_problem 仍存在）/ 严重度变化非 NO_OP 正常 INSERT / 混合场景（NO_OP 与 ADD 并行，仅保留 ADD） |

设计决策：
- **仅比对最近一条诊断**（RN 同）：`getLatestDiagnosis` 取本会话最新一条，非全历史扫描（与 RN `ORDER BY timestamp DESC LIMIT 1` 一致）
- **INSERT 仍发生**：即使全部症候 NO_OP，仍写入一条 syndromes 为空数组的诊断记录（对齐 RN 始终 INSERT）
- **active_problem 不受影响**：NO_OP 症候仍走 UPSERT（严重度/名称更新），保证活跃问题列表不丢

验证：`dart format` 全过 / `dart analyze` 0 error / `flutter test` 全量 **696 全绿**（693 → 696，新增 3：记忆合并）+ 4 skipped

### 批次 23 步骤② — B5 离线模式 + 离线草稿 + 恢复交互

| 文件 | 状态 | 说明 |
|------|------|------|
| `lib/providers/writing_providers.dart` | 修改 | WritingState 新增 `isOffline`/`hasDraft`；WritingStore 新增：`setOffline`（离线→在线且有草稿 → 自动同步）、`saveNow` 离线分支（存本地草稿不写 DB）、`restoreDraft`/`discardDraft`/`syncDraftToChapter`；`loadChapter` 含草稿检测（draft.savedAt > chapter.updatedAt → 标记恢复；更旧 → 清除陈旧草稿） |
| `lib/widgets/writing_page.dart` | 修改 | connectivity_plus 订阅网络状态（initState + 初始 checkConnectivity，平台插件缺失时 onError 容错）；离线横幅（warningBg「当前离线，内容自动保存为本地草稿，恢复网络后将同步」）；草稿恢复弹窗（发现未保存草稿：放弃/恢复，仅弹一次） |
| `test/providers/writing_providers_test.dart` | 修改 | 新增 6 测试（#9-#14）：离线保存草稿 / 恢复网络自动同步 / 草稿恢复检测 / restoreDraft / discardDraft / 陈旧草稿自动清除 |

设计决策：
- **离线编辑不锁编辑器**：Flutter 离线时可继续输入，1s debounce 自动保存改走草稿通道（RN scheduleDraftSave 语义）；RN 的 editable={!isOffline} 为禁写 DB 的产品化表达，草稿是例外通道
- **恢复网络自动同步**：`setOffline(false)` 且 hasDraft → syncDraftToChapter（写入章节 + 清除草稿 + 更新 lastSavedAt）
- **草稿恢复弹窗**：打开章节时若草稿 savedAt 严格晚于章节 updatedAt（对齐 RN `>` 判定）→ 弹窗「发现未保存草稿」放弃/恢复；恢复后草稿保留（待下次保存落库）
- **测试时间精度处理**：章节创建与存草稿可能同 unix 秒（savedAt == updatedAt），测试用 saveNewerDraft helper 将 savedAt 调为章节 updatedAt +100s 确保严格大于判定成立
- **connectivity 容错**：测试环境无平台插件 → onError/catchError 静默降级，离线能力不可用不影响编辑

验证：`dart format` 全过 / `dart analyze` 0 error 0 warning（34 info 全历史存量，本次文件 0 issue）/ `flutter test` 全量 **702 全绿**（696 → 702，新增 6：B5 离线草稿）+ 4 skipped

### 批次 23 步骤③ — B2 effectiveness 计算

| 文件 | 状态 | 说明 |
|------|------|------|
| `lib/services/diagnosis_service.dart` | 修改 | 新增 `calculateEffectiveness`（复刻 RN calculateEffectiveness）：对本次诊断每个症候，跨会话全表 getAllDiagnoses 筛同症候记录按 timestamp DESC 取最近两条，比较严重度——更轻 → improved / 更重 → worsened / 无变化 → 不返回；同症候历史 ≥ repeatSyndromeThreshold(2) 才判定；`commitDiagnosisWithHistory` 追加 teaching_history 时写入 effectiveness（无变化不写字段） |
| `test/services/diagnosis_service_test.dart` | 新增 | 9 测试：calculateEffectiveness（improved L2→L1 / worsened L1→L3 / 无变化 null / 历史<2 null / 空症候 null / 多症候首命中）+ commitDiagnosisWithHistory（effectiveness 写入 / 无变化不写 / teaching_mode 默认 socratic） |

设计决策：
- **跨会话全表**：对齐 RN `getAllDiagnoses()` 无参调用（不限定 sessionId）
- **当前诊断已落库再计算**：calculateEffectiveness 在 commitDiagnosisWithHistory 内于 commitDiagnosis 之后调用（RN 同），getAllDiagnoses 含本次记录 → [0]=本次 [1]=上一次
- **no_change 不写**：RN 类型含 no_change 但逻辑只赋 improved/worsened，无变化时 effectiveness 保持 undefined → Flutter 对齐不写字段（student_profile.buildStrategyEffectiveness 以 `eff != 'no_change'` 与缺失字段兼容）
- **测试时间精度**：两轮诊断同 unix 秒会使 DESC 排序不稳定（当前/上一次颠倒），测试用 backdateFirstDiagnosis 将首条 timestamp -100s 保证判定确定

验证：`dart format` 全过 / `dart analyze` 0 error 0 warning（34 info 全历史存量）/ `flutter test` 全量 **711 全绿**（702 → 711，新增 9：diagnosis_service_test）+ 4 skipped

### 批次 23 步骤④ — B3 划词诊断

| 文件 | 状态 | 说明 |
|------|------|------|
| `lib/widgets/writing_page.dart` | 修改 | TextField 选中捕获（controller listener，Flutter 3.44 TextField 无公共 onSelectionChanged）+ 浮动菜单「诊断这段文字」（Stack 右上角悬浮球）+ `_handleDiagnoseSelection`（trim 后 <20 字 → SnackBar「请至少选择 20 字以上的文本进行诊断」；≥20 → 打开 AI 面板并注入 `_pendingDiagnoseText`） |
| `lib/widgets/writing_coach_panel.dart` | 修改 | 新增 `pendingDiagnoseText` 构造参数 + `_maybeTriggerSelectionDiagnose`（initState postFrame / didUpdateWidget 触发，防重复 `_handledDiagnoseText`）；`_handleDiagnose` 拆分为 `_handleDiagnoseWithText(String? selectedText)`：选段诊断用选中文本（下限 20 字、prompt 标「选中文本/【选段】」、不落库不写 lastDiagnosedAt），整章诊断保持原逻辑（下限 100 字、saveNow、updateChapterDiagnosedAt） |
| `test/widgets/writing_coach_panel_test.dart` | 修改 | 新增 3 测试（B3-1 pendingDiagnoseText 触发选段诊断（内存/DB user 消息含「选中文本」「【选段】」[YS_DIAGNOSIS]）/ B3-2 选段 <20 字 SnackBar 拦截 / B3-3 null 不触发） |
| `test/widgets/writing_page_test.dart` | 修改 | 新增 3 测试（#9 选中 → 浮动菜单出现 / #10 取消选中 → 菜单消失 / #11 选中 <20 字点击 → SnackBar） |

设计决策：
- **对齐 RN 语义**：选段下限 20 字（RN L336-338）vs 整章下限 100 字（RN L239-241）；选段诊断不触发 saveNow/lastDiagnosedAt（RN 选段路径只 saveContent 一次，诊断目标为选段）；两者均 updatePhase(P1_WORLD) 保证 syndrome-diagnosis-index 加载
- **Flutter 3.44 API 适配**：TextField 已无公共 `onSelectionChanged`（内部私有化）→ 改用 `TextEditingController.addListener` 监听 selection 变化
- **面板注入触发**：WritingPage 打开面板时传 pendingDiagnoseText；面板 initState/didUpdateWidget 检查变化即触发（已处理文本防重复）

验证：`dart format` 全过 / `dart analyze` 0 error 0 warning（34 info 全历史存量）/ `flutter test` 全量 **717 全绿**（711 → 717，新增 6：B3 划词诊断）+ 4 skipped

## 批次 24 — B7 撤销/重做 + B8 成长页审计卡（2026-08-08）

### 批次 24 步骤① — B7 撤销/重做（复刻 RN useUndoRedo）

| 文件 | 状态 | 说明 |
|------|------|------|
| `lib/providers/writing_providers.dart` | 修改 | WritingState 新增 canUndo/canRedo；WritingStore 新增历史双栈（_past/_future + _lastCommitted + _historyTimer，debounce 500ms，上限 10）+ `_scheduleHistoryPush`/`_pushHistory`/`commitHistory`/`undo`/`redo`/`_resetHistory`；saveNow 成功落提交点（commitHistory）；loadChapter/restoreDraft 重置历史；dispose 取消定时器 |
| `lib/widgets/writing_page.dart` | 修改 | AppBar actions 新增撤销/重做 IconButton（canUndo/canRedo 驱动禁用态 + 颜色反馈）；`_handleUndo`/`_handleRedo` → store → 同步 controller → 标记 dirty |
| `test/providers/writing_providers_test.dart` | 修改 | 新增 4 测试（#15 commitHistory 提交点 + undo/redo 回退前进 / #16 debounce 500ms 自动提交 / #17 历史上限 10：15 提交 → 撤 10 → 回版本4 / #18 loadChapter 重置历史栈） |
| `test/widgets/writing_page_test.dart` | 修改 | 新增 2 测试（#12 AppBar 撤销/重做初始禁用 / #13 编辑后撤销可用 → 点击撤销回退到章节原文） |

设计决策：
- **双栈 + 提交点**：updateContent 仅更新 localContent 并调度 500ms debounce 历史提交（对齐 RN setValue）；saveNow 成功立即 commitHistory 落提交点（对齐 RN commit，离线草稿保存同样为稳定点）
- **定时器生命周期**：WritingStore.dispose 取消未决 `_historyTimer`，避免 dispose 后回调访问已销毁状态（修复 B7 引入的 pending-timer 回归）
- **历史上限 10**：_past 超限 removeAt(0)，与 RN maxHistory 一致

### 批次 24 步骤② — B8 成长页审计卡（复刻 RN ObservationAuditCard）

| 文件 | 状态 | 说明 |
|------|------|------|
| `lib/data/repositories/editor_observation_repository.dart` | 修改 | 补齐 countObservations / countTriggeredObservations（drift selectOnly + id.count()，对齐 RN count 查询） |
| `lib/widgets/observation_audit_card.dart` | 新建 | 审计卡：折叠态（标题 + 摘要 + 箭头）/ 展开态（总数/教练触发/触发率统计 + 最近 N 条列表（时间·触发标签·pronounced/against + 印象预览）+ 刷新按钮）；无 sessionId → 「无当前会话」空态（独立于错误态） |
| `lib/widgets/growth_page.dart` | 修改 | build 读 chatStoreProvider.currentSessionId → `_GrowthContent(sessionId)` → ListView 末尾追加 ObservationAuditCard（对齐 RN growth.tsx#L122） |
| `test/widgets/observation_audit_card_test.dart` | 新建 | 4 测试（#1 折叠态标题+摘要 / #2 展开有数据：总数2/触发1/率50.0% + 触发未触发标签 + 刷新 / #3 展开无数据空态 / #4 无 sessionId 空态） |

设计决策：
- **数据源对齐**：editor_observation 表与 repository 批次 22 已实现，本次仅补 count 查询 + 展示层
- **FK 约束**：测试 helper 先 addMessage 建真实 message 再插 observation（editor_observation.message_id NOT NULL FK REFERENCES messages）
- **intent_confidence 合法值**：DB CHECK 仅允许 low/moderate/high，测试造数用 moderate

验证：`dart format` 全过 / `flutter analyze --no-pub` 0 error 0 warning / `flutter test` 全量 **727 全绿**（717 → 727，新增 10：B7 4 + B7 UI 2 + B8 4）+ 4 skipped

## 批次 25 — 教学环境重验证（2026-08-08，skill-lifecycle 步骤③）

> 背景：批次 22 ①②已搬运 L2/L3 内容并接线，步骤③（buildSystemPromptV2 组装完整 prompt 实测）此前仅两个**未提交**的 live 草稿（直接调 LlmClient API）。本批次按用户约束「构造后在应用里测试」完成正式验收。

### 批次 25 步骤① — 应用内构造 + Fake LLM 主验收（入四闸）

| 文件 | 状态 | 说明 |
|------|------|------|
| `test/teaching_env_verification_test.dart` | 新建 | 教学环境重验证（应用内构造 + CaptureLlmClient 捕获 system messages），走 ChatService.sendMessage 完整链路，5 场景断言 L1（铁三角/态度档位/位置判断）+ L2（diagnosis/training/beginner 按语境组）+ L3（症候定义+技法，仅活跃症候注入）+ 学员画像 + token 预算（validatePrompt） |

场景矩阵：
- #1 P1 诊断（doubao，无活跃症候）→ L2 diagnosis + **无 L3**
- #2 P2 训练（practice 子阶段 + 活跃症候 P003）→ L2 training + L3（`## 活跃症候详细定义` + `## 聚焦技法详细内容` + `当前教学焦点 P003`）+ 学员画像
- #3 零基础（N1_ELEMENTS + P1）→ L2 beginner
- #4 Sensei 态度（P1）→ attitude-sensei 注入，不含 doubao
- #5 token 预算合规：三场景 validatePrompt 全部通过

设计决策：
- **对齐用户约束**：不直接调 LLM API，用 CaptureLlmClient 捕获最终 system messages，验证完整教学链路组装
- **L3 触发条件验证**：#1（无活跃症候）断言不注入 L3，#2（有活跃症候）断言完整注入——覆盖 6.x 块的门控语义

### 批次 25 步骤② — live 真实链路重构（sendMessage 全链路，live 保留）

| 文件 | 状态 | 说明 |
|------|------|------|
| `test/live_teaching_flow_test.dart` | 重构 | 不再直接调 `LlmClient().chatCompletion`；改为应用内构造场景（DB + P2 诊断子阶段 + 活跃症候 P003）→ `ChatService.sendMessage` 完整链路 → 真实 DeepSeek 流式实测；断言改为 V-03 合规（sendMessage 剥离诊断块后用户可见内容不含 `[YS_DIAGNOSIS]`/编号）+ 诊断落库闭环（`getAllDiagnoses` 扁平症候列表增长） |
| `test/live_deepseek_env_test.dart` | 保留 | LLM 客户端基础设施验证（testLlmConnection/chatCompletion/streamChat SSE），非教学环境验收，不动 |

保护机制：均保留 `@Tags(['live'])` + 无 `DEEPSEEK_API_KEY` 自动 `markTestSkipped`，不影响四闸全量跑。

**真实链路实测（2026-08-08，用户提供 DEEPSEEK_API_KEY）**：
- LLM 客户端三链路全通：testLlmConnection（1375ms）/ chatCompletion / streamChat SSE（23 帧）
- 教学链路闭环：sendMessage 完整组装（L1+L2+L3 + 画像 + 显式诊断指令）→ 真实 DeepSeek 输出 `diagnosis=有(2 症候)` → V-03 合规（用户可见 513 字符无标记/编号泄漏）→ 落库 3 条症候（预置 P003 + 模型 P021/P003）→ **All tests passed**

**构造中发现的问题**：
1. **诊断块依赖 UI 层显式指令（与 RN 一致，非缺陷）**：初版 live 测试用纯文本用户消息 → 模型靠 prompt 内 3.9 协议**不输出** [YS_DIAGNOSIS]（真实缺陷候选 → 经对照排除：RN chat.tsx L212 / Flutter chat_page.dart L236-244 均在**用户消息**里显式追加「重要：诊断说明后必须输出 [YS_DIAGNOSIS]...JSON 块，此结构化数据不可缺少」）。补上显式指令后模型稳定输出诊断块。**普通对话（无显式指令）模型不输出诊断块是预期形态（对齐 RN）**
2. ~~prompt 组装超长（工程关注点）~~ → **误判已更正（2026-08-08 复核）**：P2+diagnosis 组装 63059 字符 ≈ 25223 tokens（Flutter 0.4 估算系数），与 RN 优化后实测 **~26000 tokens**（`skill-layers.ts` 头注释「V2 三级加载：L1 + 一组 L2」）高度一致。RN 2026-07-31 **PROMPT-SIZE-OPT-001** 已把「提示词内容太多」问题处理完毕：L2 症候/技法知识拆 **index + L3 按需检索**（training-templates-index ~1500 / syndrome-diagnosis-index ~1800 / technique-library-index ~900 tokens，完整知识走 L3 按焦点注入），整体从 V0 全量 117000 tokens 降至 ~26000（省 78%）。**Flutter 批次 22 已完整复刻此优化**（skill_registry 三虚拟索引 + syndrome/technique/training 三知识库 + chat_service L3 注入），组装体积与 RN 对齐，**非问题**

验证：`dart format` 全过 / `flutter analyze --no-pub` 0 error 0 warning（info 全历史存量）/ `flutter test` 全量 **732 全绿**（727 → 732，新增 5：教学环境重验证）+ 4 skipped（live 无 key 跳过）；live 实测单独验证通过

## 批次 26 — skill_dispatcher 过时注释清理（2026-08-08）

| 文件 | 状态 | 说明 |
|------|------|------|
| `lib/services/skill_dispatcher.dart` | 修改 | 清理批次 22 遗留的两处过时注释（仅注释，无逻辑改动）：① buildSystemPromptV2 doc 注释「L2 skill 内容尚未全部搬运」→ 更新为「批次 22 已全部搬运（注册表 39 项），缺失跳过保留为防御性兜底」；② injectL3 内部注释「当前批次未实现 syndrome-diagnosis 知识库，L3 注入返回空字符串」→ 更新为「批次 22 步骤② 已接入 syndrome_knowledge_base」 |

验证：`dart format` 全过 / `flutter analyze --no-pub` 0 error 0 warning / `flutter test` 全量 **732 全绿**（无回归）+ 4 skipped（live 无 key 跳过）

## 模拟器端到端验证（2026-08-08，真实 DeepSeek 链路）

> 用户指示「实际看一下 prompt 组装，然后上模拟器测试一下」。对批次 25 live 测试 + 批次 22 prompt 组装做真机级验收。

### 1. prompt 组装审阅（纠正「超长」误判）

- 经用户纠正，查证 PROMPT-SIZE-OPT-001（RN 2026-07-31）：L2 拆 index + L3 按需检索，整体 117000 → ~26000 tokens
- Flutter 批次 22 已复刻：组装 **63059 字符 ≈ 25223 tokens**（charToTokenRatio=0.4，maxBudget=50000，warningRatio=0.8），与 RN ~26000 对齐
- dump 完整 system prompt 到 `tmp_prompt_dump.txt`：19 个 skill 段落结构完整无截断，「教学方式选择」两处为 teaching-strategy 引用 + teaching-modes 完整版（非冗余）
- 结论：**prompt 组装无超长问题，此前标注的工程关注点属误判，已更正**

### 2. 端到端诊断链路（模拟器 AVD yuesheng_test）

环境：AVD yuesheng_test（android-34 x86_64 + WHPX）/ `com.yuesheng.writingcoach` / 设置页配置真实 key（sk-c544…5399）+ https://api.deepseek.com + deepseek-v4-flash

流程：配置 API → 测试连接 2297ms 成功 → 创建作品 TestWorku → 章节 Chapter1（260 字英文）→ 写作页 ⋮ → 「诊断本章」

链路日志（10:06:11 → 10:07:22）：
- `[ChatService] sendMessage 开始`（含显式 [YS_DIAGNOSIS] 指令，对齐 chat_page.dart L236-244 / RN chat.tsx L212）
- SSE 流式 **971 chunks**（fullContent 2191 字）→ 步骤8 检测到 `[YS_DIAGNOSIS]` 标记 → 诊断块拦截模式
- 步骤9 `parseDiagnosis`：displayContent 709 字，**diagnosis=有(3 症候)**
- 步骤10 assistant 消息写入（messageId=f77520d5）→ onComplete 触发

落库查证（pull DB + WAL 合并，`tmp_yuesheng.db`）：
- `messages` 4 条：user 诊断指令（481 字）/ assistant 诊断正文（709 字，**无 [YS_DIAGNOSIS] 标记与 P 编号泄漏，V-03 合规**）/ `diagnosis_result` 卡（syndromeCount=3）/ `teacher_suggestion` 卡（suggestionId 关联）
- `diagnosis_results` 1 条：P003 情绪标签化(L2) + P007 句式节奏单一(L2) + P013 开篇平庸(L1)，含 syndromes 完整定义/evidence/root_cause_analysis/next_focus/focus_reason，confidence 0.85，`current_teaching_focus_id=P003`，target_ref=chapter
- `teacher_suggestion` 1 条：teaching_decision=train，task_type=rewrite（target P003），status=active

UI 渲染（滚动消息列表后）：DiagnosisCard 三症候（症候名 + 证据数 + 点击跳转原文 + 「这个诊断符合你的实际情况吗？」）+ TeacherSuggestionCard（开始练习 / 跳过此建议 / 查看详情 三按钮）全部正常。

### 3. 发现的问题

| 问题 | 证据 | 状态 |
|------|------|------|
| **go_router 创建作品崩溃**：bookshelf_page.dart L162 `Navigator.of(context).pop()` 在创建作品成功后 pop 空栈断言崩溃（`currentConfiguration.isNotEmpty` Failed assertion）。根因：showDialog 默认 `useRootNavigator: true`，dialog 在 root navigator；`Navigator.of(context)` 找到的是 go_router 嵌套 navigator（栈内只有 bookshelf），pop 弹空栈。修复方向：`Navigator.of(context, rootNavigator: true).pop()` | flutter run 日志 10:00:42 Unhandled Exception（PID 4990） | 未修复，待用户排期 |
| UI 语义层 content-desc 教练消息文本重复 + 「月」字 | uiautomator tmp_ui27.xml | 判定为语义 label 合并 artifact：DB 中 assistant 消息仅 709 字一遍，滚动渲染正常，非数据 bug |

### 4. 待办

- ~~go_router 创建作品崩溃修复排期（单行 `rootNavigator: true` + 回归测试，走四闸）~~ → **已由批次 27 完成**

## 批次 27 — go_router 创建作品崩溃修复（2026-08-08，模拟器实测 bug 闭环）

| 文件 | 状态 | 说明 |
|------|------|------|
| `lib/widgets/bookshelf_page.dart` | 修改 | `_handleCreate` 创建成功后的 `Navigator.of(context).pop()` → `Navigator.of(context, rootNavigator: true).pop()`。根因：showDialog 默认 `useRootNavigator: true`，弹窗在 root navigator，旧代码 pop 打到 go_router 嵌套导航栈（bookshelf 为栈底）→ `currentConfiguration.isNotEmpty` 空栈断言崩溃（模拟器 10:00:42 Unhandled Exception 实证） |
| `test/widgets/bookshelf_page_test.dart` | 修改 | 新增 `#11` 回归测试：`MaterialApp.router(routerConfig: appRouter)` 真实 go_router 嵌套场景下创建作品 → 弹窗正常关闭 + 新作品入列表 + DB 落库。**捕获能力已验证**：临时回退修复后 #11 复现崩溃失败，恢复后通过 |
| `test/tmp_prompt_dump_test.dart` | 删除 | 临时 prompt dump 辅助脚本（产物已保留 `tmp_prompt_dump.txt`），清理避免污染测试集 |

验证：`dart format` 全过（bookshelf_page_test.dart 1 处格式化）/ `flutter analyze --no-pub` **0 error 0 warning**（32 条既有 info 非本次文件）/ `flutter test` 全量 **733 全绿 + 4 skipped**（含新增 #11，无回归）/ 文档同步（本日志）

**模拟器复验（2026-08-08 11:xx，新 build 部署 emulator-5556）**：书架页 → AppBar「新建作品」→ 弹窗输入标题 RouterOKu → 点「创建」→ **弹窗正常关闭 + 新作品入列表首位 + SnackBar「已创建：RouterOKu」+ 无任何崩溃**。flutter 日志仅 `[ManuscriptStore] createManuscript 成功`，无 `Unhandled Exception`（对比修复前 10:00:42 空栈断言崩溃日志）。go_router 修复在真实设备链路闭环。

## 批次 28 — 作品详情页三 Tab 分页（2026-08-08，用户优化点 1）

> 用户优化点 1：「书籍界面改为分页式，一个界面只展示一个部分内容，设计章节/文件/相关对话三个标签」。真源：RN 稿件详情页（章节/文件内嵌区）+ 需求新增「相关对话」Tab。复刻方向：详情页固定信息卡顶部 + TabBar 三标签，每 Tab 只渲染对应内容。

| 文件 | 状态 | 说明 |
|------|------|------|
| `lib/data/repositories/session_repository.dart` | 修改 | 新增 `listRelatedSessions(String manuscriptId)`：命中并集（session_reference 引用本书 / 引用本书章节 ∪ sessions.manuscript_id 冗余缓存）+ LEFT JOIN teaching_state 取阶段 + **按 updated_at DESC 活跃度排序**（用户优化点 5 数据层） |
| `lib/widgets/related_sessions_tab.dart` | 新增 | 「相关对话」Tab：空态「还没有相关对话」+ 会话卡（月字头像 + 标题 + 阶段标签 + 预览 + 相对时间 + chevron），对齐 SessionDrawer sessionCard；数据源 `listRelatedSessions` |
| `lib/widgets/manuscript_detail_page.dart` | 修改 | State 加 `SingleTickerProviderStateMixin` + `TabController(length: 3)` + listener setState（Tab 切换重建 AppBar actions / FAB）；信息卡固定顶部（三 Tab 共享）→ TabBar（章节/文件/相关对话）→ TabBarView；「新建章节」AppBar 按钮与 FAB 仅 Tab0 显示；`_ChapterList` 删除 trailing（文件区独立成 Tab） |
| `test/dao_repository_test.dart` | 修改 | +3 测试：listRelatedSessions（命中+排除+排序 / 手动章节引用 / 空列表） |
| `test/widgets/manuscript_detail_page_test.dart` | 修改 | +2 测试 #15（三 Tab 切换）/ #16（相关对话列表渲染） |

设计决策：
- **相关对话命中规则**（用户优化点 5 语义：「通过本书发起对话或引用了书籍的内容的对话」）：三类命中并集——session_reference 主/附加引用本书、引用本书任一章节、sessions.manuscript_id 冗余缓存兜底（写作页章节会话）；排除与本书无关的普通会话
- **活跃度 = updated_at DESC**：与 RN 会话列表排序一致（最近活跃在前），无独立「活跃度分」字段，避免过度设计

## 批次 29 — 对话新建按钮位置调整（2026-08-08，用户优化点 2）

> 用户优化点 2：「调整对话新建按键到合适区域，方便用户发起新对话」。AskUserQuestion 确认：**右上角 ⋮（三个点）左边位置**。真源：RN ChatHeader 无此快捷入口，为 Flutter 增量优化。

| 文件 | 状态 | 说明 |
|------|------|------|
| `lib/widgets/chat_header.dart` | 修改 | 新增 `final VoidCallback onNewSession`（required）；更多按钮（⋮）左侧插入新建对话快捷按钮（`Icons.add_comment_outlined` + tooltip「新建对话」），避免盖住 ⋮ 原功能；**状态栏 inset 修复**：build 外层包 `SafeArea(bottom: false)`（ChatPage 无 AppBar，body 直顶屏幕顶端，整行渲染到状态栏下，顶部按钮被遮挡不可点——模拟器实证 y=76 点击无效、y=138 有效） |
| `lib/widgets/chat_page.dart` | 修改 | ChatHeader 接线 `onNewSession: _handleCreateSession`（复用批次 7 新建链路：重置练习/评估报告 → bootstrap createNew） |
| `test/widgets/chat_header_test.dart` | 修改 | +1 测试 #8：新建对话按钮渲染 + 点击回调 |

设计决策：
- **⋮ 左侧**（用户确认）：汉堡按钮（会话列表）在最左，其后按操作频率排「新建对话」与「更多菜单」，避免极右新入口与系统级按钮争位
- **复用既有链路**：不改 SessionBootstrapNotifier，直接挂 `createNew`，与 SessionDrawer 底部「+ 新建会话」行为一致
- **状态栏 inset 是既有 bug**：ChatHeader 自批次 10 起无 SafeArea（对话页无 AppBar），整行渲染到状态栏下；批次 29 复验时暴露（新按钮同样被遮），一并修复——SafeArea 在测试环境 padding=0 无视觉回归

## 批次 30 — 引用修复：相关对话点击跳转打开会话（2026-08-08，用户优化点 3）

> 用户优化点 3：「引用功能调整，当前似乎无法兼顾章节引用，或者当前引用为死数据」。**模拟器实测复现结论**：ReferenceBar 上章节引用实际可操作（点 TestWorku 行成功切换主引用 + SnackBar「已切换到：TestWorku」），「章节引用不可操作」未复现；**真正的死数据感来自「相关对话」Tab 点击（原为「打开对话功能开发中」占位）**。本批把占位改为真实跳转：点击会话 → 切对话 Tab（/）→ 打开该会话。

| 文件 | 状态 | 说明 |
|------|------|------|
| `lib/providers/chat_store.dart` | 修改 | 新增 `pendingOpenSessionProvider`（StateProvider<String?>）：跨 Tab 传递待打开会话 ID（对齐批次 13 `pendingDiagnosisChapterProvider` 交接模式） |
| `lib/widgets/related_sessions_tab.dart` | 修改 | 新增 `onOpenSession(String sessionId)` 回调；点击占位 SnackBar「打开对话功能开发中」→ `widget.onOpenSession(item.session.id)` |
| `lib/widgets/manuscript_detail_page.dart` | 修改 | 新增 `_handleOpenRelatedSession`：写 `pendingOpenSessionProvider` + `context.go(AppRoutes.writing)`（切到对话 Tab） |
| `lib/widgets/chat_page.dart` | 修改 | 消费端双保险：① `ref.listen(pendingOpenSessionProvider)` 常规路径（书架 push 进入详情页，shell 存活，pending 设置即触发）；② build 期一次性检查 + postFrame 兜底（详情页经 `context.go` 重建 shell 时 ChatPage 全新挂载，`ref.listen` 不 fire 初始值）；`_consumePendingSession`：bootstrap 未就绪先 `await sessionBootstrapProvider.future` 再切换（修复 shell 重建后 bootstrap 仍在加载导致丢切换） |
| `test/widgets/manuscript_detail_page_test.dart` | 修改 | +1 集成测试 #17：预置章节会话 + 更旧 updatedAt + 新建空白会话（保证 bootstrap 默认会话≠目标）→ 详情页相关对话 Tab 点击 → 进入 ChatPage + `sessionBootstrapProvider.sessionId` 切到目标会话 |

设计决策：
- **引用本身可操作**（模拟器实证）：ReferenceBar 章节引用设主/移除链路完整，本次不擅改；死数据感根因是相关对话 Tab 占位，跳转落地后闭环
- **跨 Tab 交接复用 Provider 模式**：对齐批次 13 pendingDiagnosisChapterProvider（growth 选章 → 切 Tab → 自动诊断）的既有先例，不引入路由 extra（ChatPage 在 StatefulShellRoute 内为 `const ChatPage()`，无 extra 通道）
- **双保险原因**：go_router `go`（写作页 onBack 回详情页）会重建 shell 使 ChatPage 全新挂载，此时 pending 已先于 `ref.listen` 注册被设置（Riverpod 2.5 的 `ref.listen` 不 fire 初始值且无 `fireImmediately` 参数）→ 需 build 期一次性检查；postFrame 延迟消费避免 build 期修改 provider 状态
- **等 bootstrap 再切换**：实测暴露 shell 重建后 bootstrap 仍 loading（`bootstrap=null`）→ 直接切会静默丢弃；`await sessionBootstrapProvider.future` 保证切换不丢（修复后 #17 通过）

## 批次 31 — 编辑内容立即保存（2026-08-08，用户优化点 4）

> 用户优化点 4：「编辑内容保存设计为编辑后立即保存，不再设计手动保存」。真源：RN 写作页 onChanged → updateContent 立即落库。原 Flutter 实现有 1s debounce，本批移除改为即时保存。

| 文件 | 状态 | 说明 |
|------|------|------|
| `lib/widgets/writing_page.dart` | 修改 | `_onContentChanged` 去掉 1s debounce Timer，onChanged → updateContent + **立即 saveNow**；dispose 移除 `_debounceTimer?.cancel()`；删除 `Timer? _debounceTimer` 字段；头注释同步「onChanged → updateContent + 立即 saveNow」 |

设计决策：
- **立即保存语义**：每次内容变更即落库（对齐 RN），输入体验无感知（本地 SQLite 写入极快）；离线草稿分支（批次 23 B5）保留原逻辑不受影响
- **历史栈不受影响**：批次 24 B7 撤销/重做依赖 `_scheduleHistoryPush` 的 500ms debounce 独立于保存 debounce，saveNow 成功即 commitHistory 落提交点，语义不变

验证（批次 28-31 合并四闸）：`dart format` 全过 / `flutter analyze` **0 error**（32 条 info 全历史存量）/ `flutter test` 全量 **740 全绿 + 4 skipped**（批次 27 → 740，新增 7：listRelatedSessions 3 + 详情页 #15/#16/#17 3 + ChatHeader #8 1）/ 文档同步（本日志）

## 模拟器端到端复验（2026-08-08，5 优化点 + SafeArea 修复）

> 用户指示「当然」后，对批次 28-31 + SafeArea 修复做模拟器复验（emulator-5556，新 build 部署后逐项操作 + DB 落库查证）。

### 1. 批次 28 — 三 Tab 分页（通过）

- 书架 → RouterOKu → 详情页顶部信息卡固定 + TabBar（章节/文件/相关对话）三标签
- 切「相关对话」Tab → 空态「还没有相关对话」文案正确；「新建章节」AppBar 按钮随 Tab 切换正确隐藏（仅章节 Tab 显示）
- TestWorku 相关对话 Tab → 显示「章节会话」会话卡（月字头像 + 阶段标签「暴露问题」+ 相对时间 + 预览）

### 2. 批次 30 — 相关对话点击跳转（通过，常规 push 路径）

- TestWorku 相关对话 Tab → 点击「章节会话」卡 → **自动切到对话 Tab（底部 Tab2）并打开该会话**：ReferenceBar 显示主引用 TestWorku（+1）、消息列表完整渲染（诊断正文 + DiagnosisCard 三症候 L2/L2/L1 + TeacherSuggestionCard 三按钮 + reference_change 卡「已切换到「TestWorku」」）
- 跳转走「书架 push → shell 存活」常规路径，direct listen 生效

### 3. 批次 29 — 新建对话按钮（通过 + 修复状态栏 bug）

- 头部「新建对话」按钮在 ⋮ **左侧**（[794,146][926,278]，⋮ 在 [926,146][1058,278]）✓
- 点击 → 新会话创建：DB `sessions` 表新增（验证 3 会话：章节会话 1 + 新建会话 2，updated_at 递增）
- **发现并修复状态栏 inset bug**：ChatHeader 无 SafeArea，整行渲染在状态栏区域（y=10-142，状态栏 0-136）→ 顶部按钮被状态栏遮挡不可点（实测 y=76 点击无效，y=138 才命中）；包 `SafeArea(bottom: false)` 后整行下移至 y=146-278，按钮在正常位置可点（实测 y=212 点击创建新会话成功）

### 4. 批次 31 — 编辑立即保存（通过）

- 写作页打开 Chapter1（260 字，无手动保存按钮）→ 文本末尾追加 "ISSUVer"（7 字符）→ **300ms 内拉 DB：content 260 → 267 已落库**（旧 1s debounce 无法在 300ms 内完成，证明立即保存生效）

### 复验结论

5 个优化点全部在真实模拟器链路闭环；批次 29 复验额外发现 ChatHeader 状态栏遮挡既有 bug（影响汉堡/新建对话/更多三按钮可用性），已随批次 29 一并修复并复验通过。

## 四闸验证

- `dart analyze`：0 error / 0 warning（37 条既有 info 非本次文件）
- `dart format --set-exit-if-changed`：全过
- `flutter test`：全量 **569 个测试全绿**（批次递增 542 → 569，新增 attitude_advisor 19 + attitude_suggestion_banner 5 + chat_page 集成 #B12 3 = 27）
- 文档同步：本日志 + 缺口清单（态度建议横幅已闭环）

## 与 RN 的差异说明

- **mention 解析用列表序**：RN 用 getManuscriptByOrder 但稿件 sort_order 恒为 0，@W002+ 实际解析失败；Flutter 用 listManuscripts/listChapters/listAttachedFiles 列表序解析，与生成端（ReferencePicker 列表 index）对称，链路完整可用
- RN 发送时 mentions 含 file 会因 addReference CHECK 约束整体失败 → 回退发原文；Flutter 跳过 file 类型，其余正常解析
- FileViewerModal 的 AttachedFileRow 无时间字段，头部只显示大小
- cleanedText 保留移除后的原始空白（对齐 RN replace + trim 语义）

---

## 批次 32 — 取消创建书籍崩溃修复（2026-08-08，模拟器实测 bug 闭环）

> 用户报告「取消创建书籍疑似会导致应用崩溃」。与批次 27 同根因：showDialog 默认 `useRootNavigator: true`，弹窗在 root navigator；旧 `_closeCreateModal` 用 `Navigator.of(context).pop()` 误 pop go_router 嵌套导航栈（bookshelf 为栈底）→ 空栈断言崩溃。

| 文件 | 状态 | 说明 |
|------|------|------|
| `lib/widgets/bookshelf_page.dart` | 修改 | `_closeCreateModal` 改为 `Navigator.of(context, rootNavigator: true).pop()`（与批次 27 创建成功路径一致） |
| `test/widgets/bookshelf_page_test.dart` | 修改 | 新增 `#12` 回归测试：真实 go_router 场景打开创建弹窗 → 输入标题 → 点「取消」→ 弹窗关闭 + 仍在书架 + 未创建作品。**捕获能力已验证**：临时回退修复后 #12 复现崩溃失败，恢复后通过 |

验证：`flutter analyze` 0 error / `flutter test` 全量通过（新增 #12，无回归）/ 文档同步（本日志）

## 批次 33 — 引用简化：移除 ReferenceBar UI，只留 @（2026-08-08）

> 用户原话：「对话界面存在两个内容引用逻辑，一个是标题层上面的那个，一个是@，我期待只保留@的那个」。RN 考古确认 ReferenceBar 是死代码（src 中零挂载调用），真正的引用入口只有 @ mention；主引用数据层必须保留（usePrimaryReference 仍在 chat.tsx 使用）。

| 文件 | 状态 | 说明 |
|------|------|------|
| `lib/widgets/chat_page.dart` | 修改 | 移除 ReferenceBar 渲染（`_buildBody` Column）、`_refBarKey`、`_handleOpenReferencePicker`、`_handleReferenceChanged`；删除 import `reference_bar.dart`、`message_card_service.dart` |
| `test/widgets/chat_page_test.dart` | 修改 | #B4-4 改为验证 ReferenceBar 不存在；删除 #B6-1（引用变更卡片插入测试，随 ReferenceBar 移除） |

设计决策：
- **数据层保留**：`session_reference` 桥表 + 主引用（`is_primary`）+ @ mention 解析链路不动，仅移除 ReferenceBar 这一 UI 入口（RN 中即为死代码）
- **@ mention 是唯一引用入口**：对齐 RN（ChatInput onMention → ReferencePicker mention 模式 → `@W001/C003` 文本 → 发送时 parseMentions 解析写入引用）

## 批次 34 — 删除书籍/章节（长按 + 二次确认，2026-08-08）

> 用户需求：「增加书架删除书籍的功能和书籍内删除章节的功能」。AskUserQuestion 确认交互：**长按出菜单 + 二次确认**。RN 考古：删除书籍=软删 `archived` 无确认（Flutter 按项目硬约束加确认）；删除章节 RN 无此功能，为 Flutter 新增设计。

| 文件 | 状态 | 说明 |
|------|------|------|
| `lib/data/repositories/chapter_repository.dart` | 修改 | 新增 `deleteChapter`：事务内删章节 + 清理悬空 `session_reference`（ref_type='chapter'），诊断历史保留 |
| `lib/providers/chapter_providers.dart` | 修改 | `ChapterListStore.deleteChapter`：DB 删除 + 列表移除，返回 bool |
| `lib/widgets/bookshelf_page.dart` | 修改 | `_handleManuscriptLongPress`（长按 → bottom sheet → 二次确认 → 软删 archived + SnackBar「已删除」）；`_ManuscriptList`/`_ManuscriptCard` 加 onLongPress |
| `lib/widgets/manuscript_detail_page.dart` | 修改 | `_handleChapterLongPress`（长按章节 → bottom sheet → 二次确认 → deleteChapter）；`_ChapterList`/`_ChapterCard` 加 onLongPress |
| `test/widgets/bookshelf_page_test.dart` | 修改 | 新增 #13 长按删除书籍测试（软删 + 列表移除 + DB 验证） |
| `test/widgets/manuscript_detail_page_test.dart` | 修改 | 新增 #18 长按删除章节测试（含悬空 session_reference 清理验证） |

## 批次 35 — TXT 导入创建书籍（2026-08-08）

> 用户需求：「增加书籍创建逻辑：文本导入，允许用户导入外界书籍，只需要支持 TXT」。RN 考古：`file-parser.ts` parseTxtFile（标题=文件名去扩展名；按「第X章/回/节」或 Chapter N 正则分章；无章节则整篇为第一章）。AskUserQuestion 确认入口：**新建弹窗内加导入**。

| 文件 | 状态 | 说明 |
|------|------|------|
| `lib/widgets/book_import_sheet.dart` | 新增 | 书架 TXT 导入弹层（选文件 → importBookFromFile → onImported）；测试可 override `workImportServiceProvider` |
| `lib/services/work_import_service.dart` | 修改 | `importBookFromFile()` 无会话导入（不建引用）；`importWork` 的 sessionId 可空，null 时不建主引用 |
| `lib/widgets/bookshelf_page.dart` | 修改 | `_openImportSheet`（关闭表单弹窗 + 打开 BookImportSheet）、`_handleImported`（刷新书架 + SnackBar「已导入《X》（N章）」）；`_CreateManuscriptModal` 加 `onImportTap` 参数 + 「从 TXT 文件导入书籍」入口 |
| `test/widgets/bookshelf_page_test.dart` | 修改 | 新增 #14（导入入口打开弹层）/ #15（选文件 → 创建书籍+章节 + 无引用） |

## 批次 36 — 章节编辑标题栏（2026-08-08）

> 用户需求：「章节编辑中增加标题栏，编辑可以修改章节标题」。对齐 RN chapter-editor handleTitleChange（输入即保存，无防抖）。

| 文件 | 状态 | 说明 |
|------|------|------|
| `lib/providers/writing_providers.dart` | 修改 | 新增 `WritingStore.updateChapterTitle`：DB 即时保存（ChapterRepository.updateChapterTitle）+ state.chapter 同步（updatedAt 刷新） |
| `lib/widgets/writing_page.dart` | 修改 | AppBar title 改为可编辑 `TextField`（`_titleController` + onChanged → 即时保存）；ref.listen 同步标题；initState/dispose 管理 controller |
| `test/widgets/writing_page_test.dart` | 修改 | 新增 #14（AppBar 标题输入框存在可编辑）/ #15（修改标题 → DB 落库 + state 同步）；#9/#10/#11 的 EditableText 定位改为 `find.byType(TextField).first`（批次 36 起 AppBar 新增标题输入框，树遍历中正文编辑器在前） |

## 批次 37 — 书籍详情标签简化（2026-08-08）

> 用户原话：「书籍详情栏上面的那个书籍详情标签做一下简化，当前的UI太占空间了」。RN 考古：`ManuscriptHeader` 是紧凑结构——导航行 + 标题 24px + subtitle「体裁 · N 个章节」+ TabBar，不显示简介/字数胶囊/色条。Flutter 原为「4dp 竹青条 + 标题 + 简介 + 双胶囊」大信息卡，本批对齐 RN。

| 文件 | 状态 | 说明 |
|------|------|------|
| `lib/widgets/manuscript_detail_page.dart` | 修改 | 大信息卡 `_ManuscriptInfoCard` + `_InfoChip` 删除，替换为紧凑 `_ManuscriptMetaBar`（单行「体裁 · N 个章节」副标题，AppBar 已承载标题）；删除 `_totalWords` getter |
| `test/widgets/manuscript_detail_page_test.dart` | 修改 | #7 改为验证元信息条（体裁 · 章节数，简介/字数不再展示）；#9 标题仅 AppBar 一次；#V3/#V4 改为验证旧信息卡结构不存在 |

## 批次 38 — 学习进度整合（2026-08-08）

> 用户需求：「将学习进度整合到设置那边去，让书架界面保持纯洁，当前页可以放在其他地方，这个你来推荐」。AskUserQuestion 确认：**设置页区块 + 成长页入口**。书架移除进度卡，设置页加进度区块，成长页「敬请期待」占位替换为「学习进度」真实入口。

| 文件 | 状态 | 说明 |
|------|------|------|
| `lib/widgets/bookshelf_page.dart` | 修改 | 移除 `_ProgressCard`/`_StatItem` 类 + 进度卡加载/跳转逻辑 + 相关 import；body 简化（移除进度卡共屏 LayoutBuilder 分支） |
| `lib/widgets/settings_page.dart` | 修改 | 新增 `_ProgressSection`/`_ProgressStat` + `_loadProgressSummary`（最新会话）+ `_openProgressDetail`；build 首部渲染「学习进度」区块（阶段徽章 + 完成度 + 进度条 + 3 统计 + 查看详情） |
| `lib/widgets/growth_page.dart` | 修改 | `_QuickEntries` 的「敬请期待」占位替换为「学习进度」真实入口（onProgress → 最新会话 progress-detail）；删除 `_showComingSoon` |
| `test/widgets/bookshelf_page_test.dart` | 修改 | #8/#9/#10 改为验证书架不再显示进度卡 |
| `test/widgets/growth_page_test.dart` | 修改 | #V5 改为「学习进度」；新增 #V5b 点击跳转 progress-detail |
| `test/widgets/settings_page_test.dart` | 修改 | 新增 #11（无会话不显示）/ #12（有会话显示区块）/ #13（查看详情跳转） |

验证（批次 32-38 合并四闸）：`dart format` 全过（1 文件自动格式化）/ `flutter analyze` **0 error**（info 全历史存量）/ `flutter test` 全量 **750 全绿 + 4 skipped**（批次 27 → 740，新增 10：bookshelf #12/#13/#14/#15 4 + manuscript #18 1 + writing #14/#15 2 + settings #11/#12/#13 3 + growth #V5b 1，其中 #13/#14/#15/#18 为批次 34/35 已验，本闸汇总）/ 文档同步（本日志）

## 批次 39 — 引用功能死数据修复（2026-08-08）

> 用户反馈「基于文档内容，修复引用功能死数据问题」，AskUserQuestion 确认四现象：引用内容未注入 AI / 相关对话 Tab 仍异常 / 保存到文件不可用 / @ 引用后无反馈。
> 排查结论：引用注入 AI 链路**本身正常**（end-to-end 验证：@ 附加引用 → sendMessage → system prompt 含引用正文），相关对话命中与跳转测试全绿；**真正死数据根因是批次 33 移除 ReferenceBar 后 @ 引用全部为附加引用（isPrimary=0）**——保存到文件只认主引用 → 永远「请先关联一本书籍」；@ 引用落库后无任何 UI 反馈。

| 文件 | 状态 | 说明 |
|------|------|------|
| `lib/widgets/chat_page.dart` | 修改 | `_handleSend` 修复三连：① **无主引用时首条 @ 引用自动设主**（对齐批次 4b 决策「无主引用时首个自动设主」，幂等：已有主引用则后续 @ 均为附加引用）→ 保存到文件/相关对话/AI 主引用标注链路恢复可用；② **@ 引用 SnackBar 反馈**「已引用：标题」→ 消除无反馈死数据感；`_handleSaveToFile` 修复：**无主引用时回退到第一条章节/作品引用**（仅无任何引用才提示「请先关联一本书籍」） |
| `test/widgets/chat_page_test.dart` | 修改 | #B4-3 断言更新：@ 首条引用 isPrimary 0→1 + SnackBar「已引用」反馈断言；新增 #B14-3（无主引用但有 @ 附加引用 → 保存到文件回退第一条引用落库） |
| `test/teaching_env_verification_test.dart` | 修改 | 新增 #6：主引用 + 附加引用均注入 system prompt + 【主引用】标注（引用注入回归保护） |

设计决策：
- **引用注入 AI 已验证正常，不改链路**：end-to-end 测试证明 @ 附加引用正文完整进入 system prompt（buildReferencesContext 15K 预算内），主引用标注（【主引用】/【次要引用】）优先级规则生效
- **@ 首条自动设主恢复主引用语义**：批次 33 移除 ReferenceBar 后主引用机制数据层保留但 UI 无入口，@ 成为唯一入口——无主引用时首条 @ 设主对齐 RN `handleSelectReference`（default 模式 isPrimary:true）+ 批次 4b 决策，让保存到文件/相关对话等依赖主引用的链路恢复
- **保存到文件回退而非硬提示**：主引用优先，无主引用（纯 @ 引用场景）回退第一条引用（chapter 自动回填 manuscriptId），避免「引用了内容却无法保存」的死数据感；完全无引用时仍提示「请先关联一本书籍」
- **相关对话 Tab 不擅改**：批次 30 跳转（pendingOpenSessionProvider 双保险 + 测试 #17）与 listRelatedSessions 命中（dao 测试）均验证正常；用户感知的「相关对话异常」根因是跳转后 ReferenceBar 已移除无引用反馈——本次 @ 首条设主 + SnackBar 反馈在数据层与反馈层闭环，UI 结构保持批次 33 决策（只留 @）

验证：`dart format` 全过 / `flutter analyze` **0 error** / `flutter test` 全量 **752 全绿 + 4 skipped**（750 → 752，新增 2：chat_page #B14-3 + teaching_env #6；#B4-3 断言更新）/ 文档同步（本日志）

## 批次 40 — 训练闭环启动感：教学状态徽章接线（2026-08-08，Sudowrite 研究落地）

> 依据：`docs/2026-08-08-sudowrite-product-comparison.md` 第 7.1 节「即时反馈与阶段迁移可视化（让学员感知进步）+ 训练闭环的启动感」。审计发现：TeachingStateBadge（刚识别/训练中/趋稳中/已掌握）批次 10 建成后**零调用方**，训练反馈与画像页均未呈现教学状态迁移——学员感知不到"症候从刚识别→训练中→趋稳中"的进步轨迹。数据层已齐（`SyndromeEvaluationDetail.teachingState` / `SyndromeAggregation.teachingState`），本次仅 UI 接线 + 补测试，不动服务层。

| 文件 | 状态 | 说明 |
|------|------|------|
| `lib/widgets/evaluation_report_panel.dart` | 修改 | 症候明细行接线 TeachingStateBadge（size=sm + showLabel）——训练反馈即时显示教学状态迁移（达标率已有，补阶段迁移感知） |
| `lib/widgets/growth_detail_page.dart` | 修改 | 症候分布行接线 TeachingStateBadge（数据源 `profile.syndromeProfile[症候ID].teachingState`，画像聚合）——画像页整体感知进步 |
| `test/widgets/evaluation_report_panel_test.dart` | 修改 | #3 补「训练中」断言 + 新增 #3b（identified/consolidating 标签渲染） |
| `test/widgets/growth_detail_page_test.dart` | 修改 | 新增 seedDiagnosis helper + #D1（有数据场景：症候分布 + 教学状态徽章「刚识别」×2 + 严重度 chip） |

设计决策：
- **最小接线不改服务层**：teachingState 数据由 training-evaluator FSM（`transitionTeachingState`）与 student_profile_compute（`inferTeachingState`）已计算，仅 UI 层补齐呈现，与 RN TeachingStateBadge 使用位置（StudentProfilePanel 症候状态行）对齐
- **徽章显示位置**：评估报告症候明细行尾（趋势标签左侧）+ 画像页症候分布行尾（严重度 chip 左侧），showLabel 带文字避免仅色点歧义
- **画像页数据源用 profile 聚合**：ActiveProblemView 无 teachingState 字段，从 `profile.syndromeProfile` 按 syndromeId 取（画像聚合含全部诊断历史，比单条 active_problem 更完整）

验证：`dart format` 全过（2 文件自动重排）/ `flutter analyze` **0 error 0 warning**（32 info 全历史存量，本次文件 0 issue）/ `flutter test` 全量 **754 全绿 + 4 skipped**（752 → 754，新增 2：evaluation #3b + growth #D1；#3 断言更新）/ 文档同步（本日志）

## 批次 41 — 反 AI 味强化：表达密度约束补齐（2026-08-08，Sudowrite 研究落地）

> 依据：`docs/2026-08-08-sudowrite-product-comparison.md` 第 6.3/7.1 节「反 AI 味是差异化机会：态度档位 + 表达密度约束正是对着 Sudowrite 头号差评打」。审计发现：记忆约束「在所有系统内容注入中，在会话历史前追加『临场输出约束』system message 以确保表达密度规则不被后续详细教学内容覆盖」在 Flutter **未实现**——三档态度 skill 无「表达密度」小节，chat_service 无临场输出约束注入。RN 真源 master 亦缺失（RN 曾于提交 e8c46bb 实现但未合入主线），本次按记忆约束 + e8c46bb 原文补齐。

| 文件 | 状态 | 说明 |
|------|------|------|
| `lib/services/skill_registry.dart` | 修改 | 三档态度 skill 各新增「表达密度」小节（对齐 RN e8c46bb 逐字）：doubao（一次只抛一个点 / 最小示范 1-2 句 / 删铺垫，赞美≤30 字）、yuesheng（一次只抛一个点 / 最小示范 / 赞美嵌入诊断句）、sensei（一次只抛一个点 / 无示范只给方向 / 零赞美零铺垫） |
| `lib/services/chat_service.dart` | 修改 | 步骤 6.5：所有教学内容注入后、历史对话前追加「临场输出约束（最高优先级）」system message（内部参考说明 + 表达密度规则 + 分轮展开），利用 LLM recency bias 确保规则不被后续详细内容覆盖 |
| `test/teaching_env_verification_test.dart` | 修改 | #1 补 doubao 表达密度断言；新增 #1b（约束注入在历史前 + 内容三要素）；#4 改为在 attitude-sensei system 消息内断言（无示范只给方向 + 不含 doubao/yuesheng 示范规则） |

设计决策：
- **位置对齐 e8c46bb**：约束注入在教学内容注入（步骤 6.4 L3 结构化症候）之后、历史消息（步骤 7）之前——LLM recency bias 保证约束最近生效；RN 原始提交即此位置
- **逐字搬运表达密度文案**：三档差异化严格度（doubao 允许最小示范+赞美 / yuesheng 赞美嵌入诊断 / sensei 零赞美零示范）为记忆约束明确要求，文案取自 RN e8c46bb 原文
- **测试断言作用域修正**：临场输出约束通用文案含「示范只给最小可感知的一例」，与 sensei 档位「无示范只给方向」语义相反——#4 断言改为在含「态度：Sensei」的 system 消息内做 isNot，避免全局 systemText 误判（首跑暴露，已修）

验证：`dart format` 全过（1 测试文件自动重排）/ `flutter analyze` **0 error 0 warning**（32 info 全历史存量，本次文件 0 issue）/ `flutter test` 全量 **755 全绿 + 4 skipped**（754 → 755，新增 teaching_env #1b；#1/#4 断言更新）/ 文档同步（本日志）

## 批次 42 — 训练闭环启动感：达标率进度条（2026-08-08，Sudowrite 研究落地）

> 依据：`docs/2026-08-08-sudowrite-product-comparison.md` 第 7.1 节「即时反馈与阶段迁移可视化（让学员感知进步）」——批次 40 已补教学状态徽章（阶段迁移感知），本批补达标率可视化的最后一环：评估报告达标率原先仅纯数字「达标率 80%」，无直观进度反馈。设置页 `_ProgressSection` 已有 LinearProgressIndicator 先例，本批复用同款式补进训练评估报告。

| 文件 | 状态 | 说明 |
|------|------|------|
| `lib/widgets/evaluation_report_panel.dart` | 修改 | 详情区统计行与趋势文案之间插入达标率进度条（LinearProgressIndicator，minHeight 6，圆角 4，底色 background，**颜色随趋势**：improving 竹青 / stable 灰 / worsening 矿物红），值 = `passRate.clamp(0,1)` |
| `test/widgets/evaluation_report_panel_test.dart` | 修改 | 新增 #7（进度条值=0.8 + minHeight=6 + 收起后隐藏） |

设计决策：
- **颜色随趋势而非固定竹青**：达标率进度条复用 `_trendConfig` 的 trend.color——改善时竹青、稳定时灰、恶化时矿物红，与 header 趋势徽章语义一致，让"进步/退步"一眼可见（设置页完成度进度条为固定竹青，场景语义不同）
- **位置在详情区**：进度条放统计行下方、summaryText 上方（展开态默认可见）；收起时保留 header「达标率 X%」纯数字，进度条随详情收起（对齐面板展开/收起语义）

验证：`dart format` 全过（0 changed）/ `flutter analyze` **0 error 0 warning**（32 info 全历史存量）/ `flutter test` 全量 **756 全绿 + 4 skipped**（755 → 756，新增 evaluation #7）/ 文档同步（本日志）

## 批次 32-38 RN 考古结论汇总

| 主题 | RN 逻辑 | Flutter 对齐 |
|------|---------|-------------|
| 删除书籍 | 软删 `archived`，无确认（`deleteManuscript` DAO） | 软删 + 长按菜单 + 二次确认（项目硬约束要求确认） |
| 删除章节 | RN 无此功能 | Flutter 新增（物理删除 + 清悬空引用，诊断历史保留） |
| TXT 导入 | `parseTxtFile`：文件名去扩展名作标题；`^(第[一二三…\d]+[章节回幕篇]\|Chapter\s*\d+)$` 正则分章；无章则整篇为第一章 | `file_parser.dart` + `WorkImportService` 事务建书+章，无会话不建引用 |
| 引用入口 | **ReferenceBar 是死代码**（零挂载）；唯一入口 = `@` mention（ChatInput onMention → ReferencePicker mention 模式 → buildMentionPath `@W001/C003` → parseMentions 解析） | 移除 ReferenceBar UI，保留 @ mention + session_reference 数据层 |
| 主引用机制 | `usePrimaryReference`：listReferencesOfSession + is_primary 主引用 + changeHint | 数据层保留（session_reference.is_primary），仅 UI 隐藏 |
| 详情页头部 | `ManuscriptHeader`：标题 24px + subtitle「体裁 · N 个章节」+ TabBar，无简介/字数/色条 | `_ManuscriptMetaBar` 单行副标题对齐 |
| 书架进度卡 | RN bookshelf ProgressCard（最新会话） | 从书架移除，移至设置页区块 + 成长页入口 |

## 批次 43 — Sudowrite 研究落地收尾：候选 3/4 深度复核审计（2026-08-08，纯文档批次）

> 依据：`docs/2026-08-08-sudowrite-product-comparison.md` 第 7.2 节「不做复杂学员画像表单（画像应由诊断历史 + 观察记录自动积累）」+ 第 7.3 节「长期记忆走证据驱动，画像字段跟随证据变化 / 教学焦点不被一次诊断焊死」设计红线。本批对候选 3（画像/诊断历史表单化检查）与候选 4（教学焦点迁移机制验证）做最终深度复核，确认研究红线在 Flutter 已完整落地，**无实施缺口，零代码改动**。

| 候选 | 复核对象 | 审计结论 |
|------|---------|---------|
| 候选 3：画像表单化检查 | `lib/services/student_profile_compute.dart`（computeSyndromeProfile / inferTeachingState / inferProficiency）+ `lib/services/student_profile.dart`（buildStudentContext） | **通过**：画像纯证据驱动——症候画像从诊断历史聚合（diagnosis + active_problem + teaching_history），认知风格由用户消息关键词推断或 onboarding 覆盖，无任何「学员填写画像」表单路径，符合 7.2 红线 |
| 候选 4：教学焦点迁移机制 | `lib/services/focus_resolver.dart`（6 项门控）+ `lib/services/chat_service.dart`（步骤 6.1-6.4 调用链 + `_parseUserFocusFromMessage`）+ `lib/data/repositories/diagnosis_repository.dart`（currentTeachingFocusId 落库） | **通过**：6 项门控完整——在池中 / 非 rejected / 非 resolved / 训练中冲突拒 AI 自主切换 / 频繁切换检测 / userOverride 优先，与 RN focus-resolver 完全对齐；currentTeachingFocusId 用 AI 解析值落库（与 RN diagnosis-validator 一致），教学焦点随证据迁移不被一次诊断焊死，符合 7.3 红线 |

设计决策：
- **候选 3/4 均无实施空间**：两项均为机制性验证而非功能缺口，核心机制（证据驱动聚合 + 6 项门控）已在既有批次（症状体系/训练系统 V2/诊断链路）完整落地，本次仅输出审计结论确认红线守住
- **C4 差异保持现状不修复**：`inferCognitiveStyle` 仅查当前 session（RN 原版跨全表扫描）——该偏差已在 `student_profile.dart` 文件头注释「影响有限」，且为有意设计（Flutter SessionRepository 按 sessionId 隔离，跨会话需新增 DAO 方法，认知风格推断主要依赖近期交互关键词，当前 session 已能反映）。按「禁止顺手优化」铁律，不因一次审计顺手扩大改动
- **批次 43 为纯文档批次**：无代码/测试改动，四闸中格式/分析/测试均不涉及变更，仅文档同步

验证：`dart format` 全过（0 changed，无代码改动）/ `flutter analyze` **0 error 0 warning**（无代码改动）/ `flutter test` 全量 **756 全绿 + 4 skipped**（无代码改动，与批次 42 持平）/ 文档同步（本日志）。**至此 Sudowrite 研究 7.1/7.2/7.3 建议全部落地闭环：候选 1（启动感=批次 40/42）+ 候选 2（反 AI 味=批次 41）+ 候选 3/4（红线验证=批次 43）**

## 批次 44 — 教学状态 FSM 起点真实化（2026-08-08，深度审计发现）

> 依据：项目记忆约束「评估面板需显示真实达标率和教学状态迁移（identified/in_progress/consolidating）」。审计发现：`training_input_builder.dart` 硬编码 `teachingState: TeachingState.identified` 作为 training-evaluator FSM 起点——每次评估 FSM 都从 identified 起步，`identified→in_progress` 后可进但**起点总被重置**，`in_progress→consolidating` 迁移永远无法触发（consolidating 需要 currentState==inProgress 起步）。结果：评估报告教学状态徽章（批次 40 接线）永远到不了「趋稳中/已掌握」，而画像页（growth_detail）用 `inferTeachingState` 推断可到 consolidating——**同一症候两页状态不一致**。RN 真源同样硬编码（training-input-builder.ts L187），属两端共有缺陷，但 Flutter 侧记忆约束为独立要求，按 Flutter 侧增强修复（偏差已注释）。

| 文件 | 状态 | 说明 |
|------|------|------|
| `lib/services/training_input_builder.dart` | 修改 | 教学状态起点改画像同源推断：从 diagnosisRecords（DESC）反转成正序构建 severityHistory（maxSeverity 代理值，与 previousSeverity 同源），调 `inferTeachingState(diagnosisCount, severityHistory, computeTrend, latestSeverity)` 得到 FSM 起点；替代硬编码 identified |
| `test/services/training_input_builder_test.dart` | 新增 | 3 测试：#1 L3→L2→L1→L1 趋势改善 → 起点 consolidating（修复核心）/ #2 诊断<2 条 → null（既有行为保持）/ #3 L1→L2→L1→L2 波动 → 起点 inProgress 不越级（保守） |
| `test/services/evaluation_service_test.dart` | 修改 | 新增 #5 端到端：teaching_history 含 L3→L2→L1→L1 诊断 + training 记录 → `detail.teachingState == consolidating`（评估报告徽章可达「趋稳中」） |

设计决策：
- **画像同源推断而非新建 FSM 逻辑**：复用 `student_profile_compute.inferTeachingState`（画像页权威推断函数），保证评估报告与画像页同源一致，不引入第二套教学状态判定
- **severityHistory 用 maxSeverity 代理**：DiagnosisRecord 不存 per-syndrome severity（与 previousSeverity 同源设计），保守对齐画像页语义；已注释
- **排序修正**：diagnosisRecords 按时间 DESC（最新在前），inferTeachingState 期望正序（旧→新）——先 reversed 再推断，latestSeverity 取正序末位
- **保守不越级**：#3 验证波动历史（无改善趋势）→ 起点 inProgress 而非 consolidating，避免乐观误判
- **偏差记录**：RN 真源仍硬编码 identified（training-input-builder.ts L187），Flutter 侧按记忆约束增强，两侧偏差已在文件头注释

验证：`dart format` 全过（3 文件自动重排）/ `flutter analyze` **0 error 0 warning**（32 info 全历史存量，本次文件 0 issue）/ `flutter test` 全量 **760 全绿 + 4 skipped**（756 → 760，新增 4：training_input_builder #1/#2/#3 + evaluation #5）/ 文档同步（本日志）

## 批次 45 — 诊断卡教学状态色点 + getAllDiagnoses 排序修复 + 注释同步（2026-08-08，深度审计发现）

> 依据：Sudowrite 研究 7.1「阶段迁移可视化」延续——诊断卡是学员诊断后第一眼看到的内容。审计发现三项：① **RN 真源 DiagnosisCard → SyndromeTag 有教学状态色点（P0-3：identified=警告色 / in_progress=信息色 / consolidating=成功色 / mastered=禁用灰）**，Flutter 诊断卡症候标签仅显示严重度色点，教学状态可视化在诊断卡环节缺失；② 接线过程中暴露 **`getAllDiagnoses` 排序偏差**：RN 真源 `ORDER BY timestamp ASC`（旧→新），Flutter 原实现 DESC（新→旧）——`computeSyndromeProfile` 期望正序（latestSeverity 取 last=最新、computeTrend 最近窗口在末尾），DESC 导致画像聚合的 `latestSeverity`/趋势错位（last 取到最旧记录），画像推断（含批次 40 徽章数据源）潜在失真；③ 多处文件头注释与代码现状不符（chat_service 声称 Reviewer/Editor/Teacher 未实现 + onTrainingResult 未接线——实际已实现；message_card_service 声称三卡延后——实际批次 17 已实现；chat_context_builder 声称 L3 知识库未接入——实际批次 22 已接入）。

| 文件 | 状态 | 说明 |
|------|------|------|
| `lib/widgets/diagnosis_card.dart` | 修改 | 症候标签色点改教学状态优先（新增 `_teachingStateDotColor` 映射，复用 TeachingStateBadge 同款配色：identified→warning / inProgress→primaryDeep / consolidating→primary / mastered→disabledText）；sessionId 非空时异步加载画像聚合（`getAllDiagnoses(sessionId)` → `computeSyndromeProfile` → syndromeId→teachingState 映射，与画像页同源），无教学状态时回退严重度色点 |
| `lib/data/repositories/diagnosis_repository.dart` | 修改 | `getAllDiagnoses` 排序 DESC→ASC（对齐 RN 真源 `ORDER BY timestamp ASC`）——修复画像聚合 latestSeverity/趋势错位 |
| `lib/services/chat_service.dart` | 修改 | 文件头注释同步：Reviewer/Editor/Teacher 分支与 onTrainingResult 回调已实现（批次 1-7 补齐） |
| `lib/services/message_card_service.dart` | 修改 | 文件头注释同步：reference_change/phase_upgrade（批次 9）+ 三卡（批次 17）已实现 |
| `lib/services/chat_context_builder.dart` | 修改 | 注释同步：批次 22 已接入症候/技法知识库 |
| `test/widgets/diagnosis_card_test.dart` | 修改 | 新增 #45-1（L3→L2→L1→L1 趋势改善 → 色点 consolidating 竹青而非严重度色）/ #45-2（无诊断历史 → 回退严重度色点）；seed 用直接 insert 绕过 commitDiagnosis 记忆合并 |

设计决策：
- **教学状态色点优先于严重度色点**：对齐 RN SyndromeTag P0-3（`dotColor = teachingState ? teachingStateColors[teachingState] : severityColor`）——诊断卡承载"当前最需关注"信号，教学状态（刚识别需启动/训练中/趋稳中/已掌握）比严重度更能引导学员注意力；严重度仍保留在 chip 背景与文字
- **色点配色复用 TeachingStateBadge**：诊断卡与徽章组件同一映射（warning/primaryDeep/primary/disabledText），避免引入第二套教学状态色
- **数据源画像同源**：诊断卡内部用 `getAllDiagnoses(sessionId)` + `computeSyndromeProfile`（与画像页/growth_detail 完全同源），保证"刚诊断的症候卡"与"画像页状态"一致
- **getAllDiagnoses 排序为真实 bug 修复**：非候选 A 附带改动，是接线过程中由测试 #45-1 暴露的 RN 对齐缺口——DESC 使 `computeSyndromeProfile` 的 `latestSeverity`（取 list 末尾）与 `computeTrend` 最近窗口全部指向最旧记录，画像聚合推断失真；ASC 修复对既有测试无回归（effectiveness 计算内部自行 DESC 排序不受影响）
- **失败静默**：教学状态加载失败色点回退严重度色，不阻断卡片渲染（对齐"诊断失败不阻断主流程"惯例）
- **注释同步仅改注释**：三处文件头注释与代码现状不符（均已完成但注释仍称"延后/未实现"），按"文档向代码真源对齐"原则只改注释不动逻辑

验证：`dart format` 全过（diagnosis_card_test.dart 1 处自动重排）/ `flutter analyze` **0 error 0 warning**（32 info 全历史存量，本次文件 0 issue）/ `flutter test` 全量 **762 全绿 + 4 skipped**（760 → 762，新增 2：diagnosis_card #45-1/#45-2）/ 文档同步（本日志）

## 批次 46 — 全量 Repository 排序对齐审计（2026-08-08，批次 45 排序修复延伸）

> 依据：批次 45 修复 `getAllDiagnoses` 排序（DESC→ASC）后，对 Flutter 全部 11 个 Repository 的排序与 RN 真源逐条对照（审计方向：排序影响画像聚合/列表顺序/消息顺序的正确性）。结论：**除批次 45 已修的 getAllDiagnoses 外，其余排序全部对齐 RN 或为有意差异**——本批仅 2 处注释同步 + 审计记录，无逻辑改动。

**审计结论（全量对照表）**：

| Repository | 查询 | RN 真源排序 | Flutter | 结论 |
|-----------|------|------------|---------|------|
| manuscript_repository | listManuscripts | `sort_order, updated_at DESC` | sortOrder + updatedAt DESC | ✅ 对齐 |
| chapter_repository | listChapters | `sort_order` | sortOrder | ✅ 对齐 |
| session_repository | listSessions / getOrCreateSessionForManuscript / ForChapter | `updated_at DESC` | updatedAt DESC | ✅ 对齐 |
| session_repository | listMessages | `timestamp, id` | 仅 timestamp | ⚠️ 有意差异（见决策） |
| diagnosis_repository | getAllDiagnoses | `timestamp ASC` | ASC（批次 45 修） | ✅ 已修复 |
| diagnosis_repository | listDiagnosisHistory / getLatestDiagnosis / listRecentDiagnoses | `timestamp DESC` | timestamp DESC | ✅ 对齐 |
| editor_observation_repository | getRecentObservations / list | `timestamp DESC` / `ASC` | 对齐 | ✅ 对齐 |
| reference_repository | listReferencesOfSession | `is_primary DESC` | SQL 原文对齐 | ✅ 对齐 |
| reference_repository | listAttachedFiles / ByRole | `sort_order, created_at DESC` | 对齐 | ✅ 对齐 |
| teacher_suggestion_repository | 待办/活跃建议 | `created_at ASC/DESC` | 对齐 | ✅ 对齐 |
| error_log_repository | 查询 | `created_at DESC` | createdAt DESC | ✅ 对齐 |

| 文件 | 状态 | 说明 |
|------|------|------|
| `lib/data/repositories/session_repository.dart` | 修改 | `listMessages` 注释记录审计结论：RN 真源 `ORDER BY timestamp, id` 的 id 为随机 UUID v4（无时间前缀），同秒多条时 id 次级排序产生随机顺序，反而不如 Flutter 仅按 timestamp（SQLite 按插入行序返回更可预期）；真实场景 user/assistant 消息跨秒（LLM 响应延迟）timestamp 已足够——**保持 Flutter 原实现，不模仿 RN 随机次级排序**（仅注释，无逻辑改动） |
| `lib/services/diagnosis_service.dart` | 修改 | 文件头注释同步：`loadSyndromeTeachingStates` 等价能力已由 diagnosis_card 内部直接实现（getAllDiagnoses + computeSyndromeProfile，批次 45），按需加载避免每次会话初始化全量画像聚合（原注释称"不实现，延后"已过时） |

设计决策：
- **排序审计而非逐个修改**：审计结果绝大多数已对齐（批次 45 之前逐 DAO 复刻时已按 RN 原文实现），无需批量改动——避免"为对齐而对齐"
- **listMessages 保持 Flutter 原实现**：RN 的 `ORDER BY timestamp, id` 中 id 是随机 UUID v4，同秒多条时 id 排序结果是**随机的**（不保证插入序），Flutter 仅 timestamp 时 SQLite 按 rowid（插入序）返回更符合"消息先来后到"直觉；且真实聊天中 user/assistant 消息必然跨秒（LLM 响应延迟），timestamp 足以区分。按"不确定价值时保守保留"原则不动逻辑，仅注释记录
- **loadSyndromeTeachingStates 注释同步**：RN 的 chat.tsx 会话初始化加载该函数供 DiagnosisCard 使用；Flutter 已在诊断卡内部按需实现等价逻辑（批次 45），无需单独服务函数——注释更新避免后续误判为缺口

验证：`dart format` 全过（0 changed，仅注释）/ `flutter analyze` **0 error 0 warning**（32 info 全历史存量，本次文件 0 issue）/ `flutter test` 全量 **762 全绿 + 4 skipped**（无逻辑改动，与批次 45 持平）/ 文档同步（本日志）。**排序对齐审计闭环：全量 Repository 排序与 RN 真源对照完成，唯一真实缺口（getAllDiagnoses）已在批次 45 修复**

## 批次 47 — 学习报告系统分享实现（2026-08-08，审计发现的真实迁移缺口）

> 依据：对照 RN 真源 `ProgressReport.tsx`，其头部两个操作（复制 / 分享）均已实现——复制用 `Clipboard.setString`，分享用 `Share.share({ message: report })` 调系统分享面板。Flutter `_ProgressReportView` 复制已实现（批次 21），但分享按钮仍是「分享功能开发中，敬请期待」SnackBar 占位（批次 20 遗留）——**真实迁移缺口**。用户确认后引入 `share_plus` 补齐。

| 文件 | 状态 | 说明 |
|------|------|------|
| `pubspec.yaml` | 修改 | 新增运行时依赖 `share_plus: ^12.0.2`（RN 依赖 react-native Share API → Flutter 平台能力映射，同批次 2+ 的 expo-document-picker → file_picker 映射惯例） |
| `lib/widgets/progress_detail_page.dart` | 修改 | ① 文件头职责注释「分享对齐批次 20 开发中提示」→「复制 + 系统分享，批次 47 对齐 RN」；② 新增 `_handleShare()`：`SharePlus.instance.share(ShareParams(text: report))`，失败/取消静默忽略（对齐 RN handleShare 的 try-catch 注释）；③ 分享按钮 `onPressed` 由 SnackBar 占位改为 `_handleShare` |
| `test/widgets/progress_detail_page_test.dart` | 修改 | 新增 #5 测试：mock share_plus 平台通道（`dev.fluttercommunity.plus/share`），断言分享方法被调用、`text` 参数含报告文本、不再弹「开发中」提示；文件头覆盖路径注释同步 |

设计决策：
- **引入 share_plus 而非自实现分享**：系统分享面板是平台原生能力，RN 侧直接调 react-native `Share`；Flutter 无内置等价物，`share_plus` 为官方推荐跨平台方案（+_plus 系列与 connectivity_plus / file_picker 同族），无需自造平台通道
- **失败/取消静默处理**：对齐 RN `catch { // 用户取消分享，忽略 }`——分享面板被用户关闭不视为错误，不弹错误提示（保持「临场输出」克制风格）
- **分享不传标题**：RN `Share.share({ message: report })` 仅传 message，Flutter `ShareParams(text:)` 一一对应，不额外加 subject/title（对齐而非增强）

验证：`dart format` 全过（0 changed）/ `flutter analyze` **0 error 0 warning**（32 info 全历史存量，本次文件 0 issue）/ `flutter test` 全量 **763 全绿 + 4 skipped**（新增 #5 分享测试）/ 文档同步（本日志）。**真实缺口闭环：学习报告复制 + 分享双操作与 RN 真源完全对齐；MoreMenuSheet 导出/分享仍为两端一致的 WIP 占位，不属缺口**

## 批次 48 — 画像症候分组 + 空态文案修正 + 过时注释同步（2026-08-08，审计发现的三个真实差异）

> 依据：审计发现三处 Flutter 与 RN 真源不符/过时的差异——① RN `StudentProfilePanel` 症候总览按教学状态分 4 组（练习中/待诊断/巩固中/已掌握），Flutter 画像页仅平铺；② RN `ReferencePicker` 空态描述「去素材页添加你的第一个素材文件」，Flutter 空态误写「素材文件暂不支持设为引用」（但文件选择交互实际已实现）；③ `writing_coach_panel` 注释仍称「D2 占位未实现分块 LLM」，而分块链路已实现并接线。用户确认后三项全做。

| 文件 | 状态 | 说明 |
|------|------|------|
| `lib/widgets/growth_detail_page.dart` | 修改 | 症候分布改为按教学状态分组（批次 48）：新增 `_buildSyndromeGroups`，分组顺序对齐 RN `syndromeGroups`（in_progress → identified → consolidating → mastered），分组标题复用 RN `SYNDROME_GROUP_TITLES`（练习中/待诊断/巩固中/已掌握）；无画像记录的症候归入 identified（对齐 RN `byState ?? identified` 兜底）；文件头职责注释同步 |
| `lib/widgets/reference_picker.dart` | 修改 | 素材 Tab 空态文案「素材文件暂不支持设为引用」→「去素材页添加你的第一个素材文件」（对齐 RN ReferencePicker 空态描述；文件选择交互早已实现，原文案误导） |
| `lib/widgets/writing_coach_panel.dart` | 修改 | 分块链路返回 null 的注释「内容 <= THRESHOLD 或 D2 占位未实现分块 LLM」→「内容 <= THRESHOLD，不触发分块」（D2 分块链路已实现：progressive_diagnosis.dart 完整 + writing_coach_panel 已接线，原注释过时） |
| `test/widgets/growth_detail_page_test.dart` | 修改 | 新增 #D2 测试：构造三种教学状态画像（P001 ×1 → identified / P002 ×3 L2 → in_progress / P003 L2,L3,L2,L1 → consolidating），断言分组标题显示、无 mastered 分组、各症候落在对应分组；文件头种子 `seedMultiState` |

设计决策：
- **分组逻辑放页面层而非服务层**：RN 的 `syndromeGroups` 在类型层面定义但搜索不到实际构建函数（仅 mock 测试）；Flutter 画像页已有真实教学状态数据（`profile.syndromeProfile[症候ID].teachingState`，批次 40/45 接线），直接在页面层按同源数据分组，不新增服务函数——避免为 RN 未落地的类型定义造服务
- **分组顺序/标题严格对齐 RN**：in_progress 在前（训练中优先展示），identified/consolidating/mastered 依次；标题文本与 RN `SYNDROME_GROUP_TITLES` 一致（注意与画像文本 `TEACHING_STATE_LABELS`「刚识别/训练中/趋稳中」不同——面板用前者）
- **空态文案以 RN 为准**：素材文件引用能力已存在，空态应引导用户去素材页添加，而非宣称「暂不支持」（文案向能力真源对齐）

验证：`dart format` 全过（0 changed）/ `flutter analyze` **0 error 0 warning**（32 info 全历史存量，本次文件 0 issue）/ `flutter test` 全量 **764 全绿 + 4 skipped**（新增 #D2 分组测试）/ 文档同步（本日志）。**三处差异闭环：画像分组对齐 RN 面板结构、引用空态文案纠正误导、分块链路注释与实现一致**

## 批次 49 — Android 构建链路修复 + 模拟器实测验证（2026-08-08，模拟器实测前置障碍）

> 依据：用户选定方向「模拟器实测验证」后，lutter build apk --debug 失败——AGP 9.0.1 下 :file_picker:checkDebugAarMetadata 报错：lutter_plugin_android_lifecycle（2.0.35，minCompileSdk=36）要求依赖它的模块 compileSdk≥36，而 file_picker 8.3.7 的 build.gradle **写死 compileSdk 34**。此问题为存量隐患（share_plus 引入前 lifecycle 已是 2.0.35），首次在 AGP 9 构建链路上暴露。

| 文件 | 状态 | 说明 |
|------|------|------|
| pubspec.yaml | 修改 | ile_picker: ^8.1.2 → ^10.3.10（10.3.3 起 android/build.gradle 改用 lutter.compileSdkVersion，替代写死 34；10.3.10 含 Tika CVE 修复。**注意 10.3.11 在镜像站 retract**（"retracted":true），pub 解析器不提供，故取最后一个未 retract 的 10.x） |
| pubspec.lock | 修改 | file_picker 解析到 10.3.10；lifecycle 保持 2.0.35（file_picker 10.3.10 约束 ^2.0.22 满足） |
| ndroid/gradle.properties | 修改 | 新增 lutter.compileSdkVersion=36（官方机制，插件模块统一继承；file_picker ≥10.3.3 也读取它）；注释修正「写死 34 被强制抬到 36」的误导说法 |
| ndroid/build.gradle.kts | 修改 | 删除 gradle.projectsEvaluated / subprojects.afterEvaluate 反射覆盖 compileSdk 方案（AGP 9 下分别报 "too late to set compileSdk" / "already evaluated"）——该方案从根上不可行，改走官方 lutter.compileSdkVersion 机制；注释记录原因 |

设计决策：
- **升级 file_picker 而非降级 lifecycle / 反射覆盖**：AGP 9 禁止评估后改写 compileSdk（两条反射路径均已实测失败）；lifecycle 2.0.35 的 AAR 元数据声明 minCompileSdk=36 是官方约束，降级 lifecycle 需回溯到 compileSdk≤34 的旧版（版本映射不确定、有安全隐患）；file_picker 10.3.3 起官方修复写死问题（issue #1842），升级到 10.3.10 是唯一干净出路。API 兼容性已验证：本项目仅用 FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions:) + iles.first.path/name，10.x 未破坏该调用
- **不手改 pub 缓存**：曾在缓存 file_picker-8.3.7 的 build.gradle 下手改 compileSdk 的想法被否——不可复现、升级即失效，违反工程纪律
- **10.3.10 而非 11.0.3**：11.x 破坏性变更未知，按保守原则留在已评估过的 10.x 代内

验证：dart format 全过（0 changed）/ lutter analyze **0 error 0 warning**（32 info 全历史存量）/ lutter test 全量 **764 全绿 + 4 skipped** / 文档同步（本日志）。**构建链路闭环：lutter build apk --debug 成功（72s，210MB debug 包），新 APK 已安装到 emulator-5556**

### 模拟器实测结果（新构建，emulator-5556）

| 验证项 | 结果 | 证据 |
|--------|------|------|
| 批次 48 画像症候分组 | ✅ 通过 | 成长 → 查看完整能力画像：分组标题「待诊断」正确渲染，3 个活跃症候（情绪标签化 L2 / 句式节奏单一 L2 / 开篇平庸 L1）全部归入该组；无 in_progress/consolidating/mastered 组（数据现状仅 identified，符合种子逻辑） |
| 批次 47 学习报告分享 | ✅ 通过 | 学习进度 → 生成学习报告 → 点「分享」：系统分享面板弹出（Nearby Share / 蓝牙 / Chrome / Drive / 复制到剪贴板等目标），文本为「Sharing text」 |
| 对话 Tab 渲染 | ✅ 通过 | 新构建下欢迎语「你好，我是月笙」+ QuickChips（诊断节奏问题/优化对话描写/检查逻辑漏洞）正常渲染，会话抽屉入口正常 |
| 画像页诊断历史 | ✅ 通过 | 显示 8-8 10:07 诊断记录（置信度 85%，三症候） |

### 实测发现的开放缺口（未在本批修复，待用户决策）

**会话恢复缺口**：学习进度页显示「诊断次数 0」——根因排查（导出 SQLite 含 WAL 分析）：诊断数据在会话 1f30e68a（章节会话），而当前会话是后来抽屉「+ 新建会话」产生的空会话。进度页按会话维度展示 0 次诊断**符合 RN 语义**（RN bookshelf 同样跟随 currentSessionId）。但审计发现真实对齐缺口：**RN useBootstrap 通过 SecureStore 持久化 LAST_SESSION_KEY 并在启动时恢复上次会话（chat-store.ts L22/L79/L284-286）**，Flutter SessionBootstrapNotifier.build() 仅取 sessions.first（updated_at DESC，session_providers.dart L125-130）——应用重启后 Flutter 落在「最近更新的会话」而非「上次使用的会话」。涉及 bootstrap + 安全存储持久化，改动面中等，按保守分批原则留待用户确认后单独立批。

## 批次 50 — 会话恢复对齐 RN（SecureStore 持久化 LAST_SESSION_KEY + bootstrap 恢复）（2026-08-08，批次 49 实测缺口闭环）

> 依据：批次 49 模拟器实测发现的会话恢复缺口，用户确认「按顺序来，都做」后执行。真源：RN `chat-store.ts` L22 `LAST_SESSION_KEY = 'yuesheng_last_session_id'`、L79 `initSession` 选定后写入、L284-286 `getLastSessionId`；RN `useBootstrap.ts` L31-37 启动时优先恢复 LAST_SESSION。

| 文件 | 状态 | 说明 |
|------|------|------|
| `lib/services/last_session_storage.dart` | 新增 | `LastSessionStorage` 抽象 + `SecureLastSessionStorage`（flutter_secure_storage，key=`yuesheng_last_session_id` 对齐 RN）。抽象层专为测试注入隔离 |
| `lib/providers/session_providers.dart` | 修改 | 新增 `lastSessionStorageProvider`；`SessionBootstrapNotifier.build()` 会话解析优先级改为：**显式目标（drawer 切换/新建）> LAST_SESSION_KEY > updated_at 最新 > 新建空白会话**，选定后 `setLastSessionId` 持久化（对齐 RN initSession L79） |
| `test/helpers/mock_last_session_storage.dart` | 新增 | 共享 `MemoryLastSessionStorage`（内存 fake，隔离平台通道） |
| `test/providers/session_providers_test.dart` | 修改 | 新增 #7 恢复 LAST_SESSION 优先于 updated_at 最新 / #8 选定后持久化 / #9 createNew 后 LAST_SESSION 更新，共 9 测试 |
| `test/router/app_router_test.dart` | 修改 | setUp 注入 fake；私有 fake 类改共享 helper |
| `test/router/c2_tab2_chat_route_test.dart` | 修改 | 同上 |
| `test/widgets/chat_page_test.dart` | 修改 | 全部 15 处容器构造注入 fake |
| `test/widgets/manuscript_detail_page_test.dart` | 修改 | setUp 容器注入 fake |

设计决策：
- **抽象 + Provider 注入而非直接 Mock MethodChannel**：flutter_secure_storage 的平台通道在 `testWidgets`（fakeAsync）下未 mock 时**永久挂起**（`.timeout` 计时器也不推进，bootstrap future 永不完成 → 加载转圈 → pumpAndSettle 超时）；`test()` 纯 Dart 环境则抛 binding 异常。抽 `LastSessionStorage` 抽象让测试注入内存实现，业务层无感知
- **测试注入模式**：`lastSessionStorageProvider.overrideWithValue(MemoryLastSessionStorage())`，所有触发 `SessionBootstrapNotifier.build()` 的测试（router/chat_page/manuscript_detail/session_providers）统一注入，共享 helper 避免重复实现
- **不做 lastId 有效性校验（对齐 RN）**：RN `getLastSessionId` 直接返回存的值，若对应会话已被删除则 `sessions.first` 兜底逻辑不适用——RN 同样不校验（存在即用之）。为控制改动面，本次严格对齐 RN 行为，会话失效兜底留待后续审计

验证：dart format 全过（0 changed）/ flutter analyze **0 error 0 warning**（32 info 全历史存量）/ flutter test 全量 **767 全绿 + 4 skipped**（较批次 49 新增 3 测试）/ 文档同步（本日志）。

排障记录（本批）：testWidgets 平台通道挂起先导致 router/manuscript_detail/chat_page 大面积失败，逐一注入 fake 后恢复；过程中发现 **并行 SearchReplace 同文件竞态**（manuscript_detail setUp 的 override 与 import 并行编辑丢失），已修复并确认为一次性操作失误。

## 批次 51a — 成长数据服务层 GrowthService（2026-08-08，对齐审计数据层落地）

> 依据：批次 51 对齐审计确认 Flutter GrowthDetailPage 对应 RN growth-detail.tsx 但页面结构偏离（写作总览/能力图谱/写作曲线/症候历史缺失）。先落地数据层（纯服务 + 测试），UI 组件与页面接线在 51b/51c 跟进。真源：`growth-service.ts`（getGrowthOverview / getAbilityScores / getWritingCurve / getSyndromeHistory）。

| 文件 | 状态 | 说明 |
|------|------|------|
| `lib/services/growth_service.dart` | 新增 | GrowthService 四函数 + 四数据类（GrowthOverview/AbilityScore/WritingDataPoint/SyndromeHistoryEvent），customSelect 原生 SQL 复刻 RN 语义 |
| `lib/providers/growth_providers.dart` | 修改 | 新增 `growthServiceProvider` |
| `test/services/growth_service_test.dart` | 新增 | 9 测试：总览空态/聚合、能力六维分类+评分+趋势、曲线空态/近 N 天序列+聚合、历史空态/事件流合并排序 |

设计要点（对齐决策）：
- **评分公式与趋势逐行复刻 RN**：score = clamp(80 - 检测×5 + 解决×3, 30, 95)，无数据维度 70 基线；trend = resolved>0 且 ≥检测×0.5 → improving / 检测>解决 → worsening / 其余 stable。Flutter 侧用 Trend 枚举（improving/worsening/stable）表达 RN 'up'/'down'/'stable'
- **getWritingCurve 日期统一 UTC**：SQL `strftime('%Y-%m-%d', ts, 'unixepoch')` 与 RN `toISOString().slice(0,10)` 均为 UTC，map key 必须 UTC 否则聚合失效；返回从旧到新完整 days 序列（RN `Array.from(map.values)` 插入序）
- **getSyndromeHistory 的 detected 查询不过滤 status（对齐 RN）**：已解决症候同时产生 detected(created_at) 与 resolved(resolved_at) 两条事件——RN 原样行为，测试按 3 条事件断言
- **COALESCE 兜底**：空表时 SQLite SUM() 返回 NULL，Flutter `read<int>` 会抛类型转换错误，COALESCE(...,0) 对齐 RN `?? 0`

验证：dart format 全过（0 changed）/ flutter analyze **0 error 0 warning**（32 info 全历史存量）/ flutter test 全量 **776 全绿 + 4 skipped**（较批次 50 新增 9 测试）/ 文档同步（本日志）。

## 批次 51b — 成长组件层（GrowthOverviewCard / AbilityChart / WritingCurveChart / SyndromeHistoryList）（2026-08-08，对齐审计 UI 组件落地）

> 依据：批次 51a 数据层就绪后补齐 RN growth-detail.tsx 四块 UI 组件。真源：`components/profile/GrowthOverviewCard.tsx` / `AbilityChart.tsx` / `WritingCurveChart.tsx` / `SyndromeHistoryList.tsx`。视觉统一月色竹青（沿用 GrowthDetailPage 左侧竹青条卡片风格）。

| 文件 | 状态 | 说明 |
|------|------|------|
| `lib/config/shared_constants.dart` | 修改 | 新增 `formatWordCount` + `WordCountFormat`（复刻 RN formatWordCount：>=1万 → "1.2万字"，否则千位分隔 "3,256字"） |
| `lib/widgets/growth_overview_card.dart` | 新增 | GrowthOverviewCard 品牌色卡（月笙头像 + 累计创作/诊断次数/已解决 + 详情链接回调） |
| `lib/widgets/ability_chart.dart` | 新增 | AbilityChart 能力图谱（六行维度/描述/分数/趋势箭头 + 分数进度条，着色 80/60/45 阈值） |
| `lib/widgets/writing_curve_chart.dart` | 新增 | WritingCurveChart 写作曲线（摘要行 + 图例 + 横向滚动 14 天柱状图 + 诊断点 + 今天标签） |
| `lib/widgets/syndrome_history_list.dart` | 新增 | SyndromeHistoryList 时间线（发现/解决徽章 + 严重度色字 + 时间 + limit 提示） |
| `test/widgets/growth_detail_components_test.dart` | 新增 | 8 测试：卡片统计/格式化/回调、图谱空态/六行、曲线空态/摘要/今天、历史空态/徽章/limit |

对齐决策：
- **分数/趋势着色与阈值逐行复刻 RN**：getScoreColor（>=80 绿 / >=60 竹青 / >=45 警示 / 其余红）；趋势箭头 ↑绿 / ↓红 / →灰（Trend 枚举映射 RN 'up'/'down'/'stable'）
- **WritingCurveChart 今天高亮**：最后一点竹青深色 + X 轴"今天"标签（对齐 RN isToday 判定 + axisLabelEmphasis）
- **SyndromeHistoryList 事件配色**：resolved 圆点/徽章绿色、detected 圆点按严重度色 + 徽章红色（对齐 RN isResolved 分支）；严重度中文标签 L1轻微/L2中等/L3严重
- **空态三组件统一**：图标 + 标题 + 引导文案（对齐 RN EmptyState），空数组由服务层保证（新用户返回 []）

验证：dart format 全过（0 changed）/ flutter analyze **0 error 0 warning**（32 info 全历史存量）/ flutter test 全量 **784 全绿 + 4 skipped**（较批次 51a 新增 8 测试）/ 文档同步（本日志）。

## 批次 51c — GrowthDetailPage 页面对齐接线（2026-08-08，对齐审计页面落地）

> 依据：批次 51a/51b 数据层与组件层就绪后重构 GrowthDetailPage，布局对齐 RN growth-detail.tsx，同时保留 Flutter 既有画像/症候分布/诊断历史内容（保守不删）。真源：`src/app/growth-detail.tsx`。

| 文件 | 状态 | 说明 |
|------|------|------|
| `lib/providers/growth_providers.dart` | 修改 | GrowthState 新增 overview/abilityScores/writingCurve/syndromeHistory 四字段；loadGrowthData 并行加载七项（原三项 + RN 四数据源） |
| `lib/widgets/growth_detail_page.dart` | 修改 | 页面布局对齐 RN：成长总览卡（GrowthOverviewCard）→ 写作总览六格网格（_OverviewGrid）→ 能力画像卡（保留）→ 症候分布（保留）→ 能力图谱（AbilityChart）→ 写作成长曲线（WritingCurveChart）→ 症候追踪历史（SyndromeHistoryList limit 10）→ 诊断历史时间线（保留）→ 查看学习进度详情链接（_ProgressLink → /progress-detail） |
| `test/widgets/growth_detail_page_test.dart` | 修改 | D1/D2 症候名断言改 findsWidgets（同名症候现同时出现在分布与历史时间线）；新增 D3 总览卡+网格、D4 图谱/曲线/历史/链接；数据场景测试放大视口（800x3000）避免 ListView 懒构建导致 find 不到 |

对齐决策：
- **页面顺序复刻 RN**：总览卡 → 总览网格 → 能力图谱 → 写作曲线 → 症候历史 → 进度链接；Flutter 既有三块（画像卡/症候分布/诊断历史）插在 RN 对应语义位置保留
- **总览卡/进度链接复用批次 51b 组件**：GrowthOverviewCard.onViewDetail 与 _ProgressLink 均跳 /progress-detail（RN growth-detail 顶部卡 + 底部 progressLink 双入口语义一致）
- **六格网格**：写作天数/当前阶段（progressPhaseLabels）/已解决/待改进 + 首次/最近写作整宽两格，复刻 RN overviewGrid 布局；无首末写作显示「暂无」
- **测试视口放大**：页面显著变长后 ListView（SliverChildListDelegate）按视口 + cacheExtent 懒构建，未构建 item 不在 widget 树 → find 不到；数据场景测试统一 `tester.view.physicalSize = 800x3000` 让全页一次构建

验证：dart format 全过（0 changed）/ flutter analyze **0 error 0 warning**（32 info 全历史存量）/ flutter test 全量 **786 全绿 + 4 skipped**（较批次 51b 新增 2 测试）/ 文档同步（本日志）。

## 批次 52 — Teacher 建议卡片三按钮交互接线验证（2026-08-08，三卡交互闭环）

> 依据：用户选定方向「三卡交互接线」。审计结论：TeacherSuggestionCard 三按钮接线（开始练习 → practiceStore / 跳过此建议 → markResolved / 查看详情 → 展开）此前批次已实现，MessageList 与 WritingCoachPanel 均渲染该卡片；本批补齐**真实消息流场景**的端到端交互验证（组件级测试此前已有 6 个，缺对话流集成覆盖）。

| 文件 | 状态 | 说明 |
|------|------|------|
| `test/widgets/chat_page_test.dart` | 修改 | 新增「批次52：Teacher 建议卡片交互」group（3 测试）：B52-1 消息流渲染（症候名称 chip + 三按钮 + 任务描述）、B52-2 点「开始练习」→ PracticeTaskCard 出现（practiceStore 接线）、B52-3 点「跳过此建议」→ 卡片隐藏 + teacher_suggestion 表落库 resolved |

审计结论（记录）：
- **接线完整**：TeacherSuggestionCard 三按钮全部生效——「开始练习」优先外部回调，无则构造 PracticeTask 启动全局 practiceStore（ChatPage `_buildBody` watch practiceStoreProvider → MessageList 顶部渲染 PracticeTaskCard）；「跳过此建议」TeacherSuggestionRepository.markResolved 落库 + 本地隐藏；「查看详情」展开详情块
- **RN 对照**：RN 端 teacher_suggestion 无消息卡片（在 TaskPanel 展示 + onSkipSuggestion），Flutter 对话流三按钮卡片为记忆硬约束的增强设计（"Teacher建议必须作为可交互卡片出现在对话流中"），本批验证其端到端可用
- **seed 完整性**：B52-3 需同时写入 messages（卡片渲染源）与 teacher_suggestion 表（markResolved 目标）两条记录，否则落库断言无意义

验证：dart format 全过（0 changed）/ flutter analyze **0 error 0 warning**（32 info 全历史存量）/ flutter test 全量 **789 全绿 + 4 skipped**（较批次 51c 新增 3 测试）/ 文档同步（本日志）。

