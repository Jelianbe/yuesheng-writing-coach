# Flutter 与 RN 功能缺口分析（2026-08-07）

> 对比真源：`yuesheng-android/src`（RN） vs `yuesheng-flutter/lib`（Flutter）
> 结论：Flutter 主链路（文件解析 / 作品导入 / 引用选择 / 素材管理 / 内容查看 / mention 模式 / 训练 / 诊断 / 成长）已闭环，
> 以下为与 RN 相比仍未构建的缺口，按重要度分层。

---

## A. 聊天主链路缺口（影响核心体验）

| 缺口 | RN 组件 | 说明 | 优先级 |
|------|---------|------|--------|
| ReferenceBar | `components/reference/ReferenceBar.tsx` | 当前主引用显示条：导入/引用作品后对话中无直观反馈 | ★★★ 最高 |
| 会话管理 | `chat/SessionDrawer.tsx` + `app/chat-list.tsx` | 多会话列表/切换抽屉；Flutter 单会话（`session_repository` 已支持多会话，缺 UI） | ★★★ |
| QuickChips | `chat/QuickChips.tsx` | 快捷提问 chips（「描述问题」「请诊断」等）；**批次 10 已落地 `lib/widgets/quick_chips.dart`（3 默认 + 点击发送，非流式 + 非 P2 显示）** | ★★ |
| 聊天头部/状态 | `chat/ChatHeader.tsx` / `ChatWelcome.tsx` / `SubphaseIndicator.tsx` / `TeachingStateBadge.tsx` / `EncouragementText.tsx` / `ChatSessionCard.tsx` | 会话名、阶段指示、教学状态徽章、欢迎态、鼓励文案；**批次 10 已落地 ChatHeader（标题/入口徽章/会话列表/更多菜单：阶段+子阶段+态度+画像）+ ChatWelcome + SubphaseIndicator + TeachingStateBadge + EncouragementText；ChatSessionCard 由 SessionDrawer 会话行覆盖（D 类 chat-list 二选一）** | ★★ |
| 态度建议横幅 | `chat/AttitudeSuggestionBanner.tsx` | AI 建议切换态度档位（attitude-advisor 服务）；Flutter 仅手动切换 UI；**批次 12 已落地 `lib/widgets/attitude_suggestion_banner.dart`（升级/降级横幅 + 接受/暂不）+ `lib/services/attitude_advisor.dart`（suggestAttitudeAdjustment 阈值/冷却/文案）+ ChatPage 发送后 500ms 自动检查** | ★★ |

## B. 诊断交互闭环

| 缺口 | RN 组件 | 说明 | 优先级 |
|------|---------|------|--------|
| 症候详情弹层 | `diagnosis/SyndromeDetailModal.tsx` | 点击症候查看定义/证据/教学法（L3 症候数据已加载） | ★★★ |
| 诊断确认/选择 | `diagnosis/DiagnosisConfirmationBar.tsx` / `DiagnosisPickerModal.tsx` | 诊断结果确认、多症候选择；**批次 13 已落地 `lib/widgets/diagnosis_picker_sheet.dart`（作品→章节选择弹层：<100 字拦截/空库引导/50 章懒加载）+ 成长页入口 + `pendingDiagnosisChapterProvider` 跨 Tab 自动诊断；确认条已在批次 5 内置 DiagnosisCard（D5-B）** | ★★ |
| 消息卡片类型 | `chat/message-cards/*`（DiagnosisFailedCard / PartialAgreementCard / PhaseUpgradeCard / PhaseSummaryCard） | Flutter `message_card_service.dart` 已覆盖诊断结果 + Teacher 建议；**批次 9 新增 reference_change + phase_upgrade；批次 17 已落地 `lib/widgets/partial_agreement_card.dart`（反馈输入 + 3 快速选项 + 跳过/提交）+ `lib/widgets/phase_summary_card.dart`（结果统计 + 症候变化 + 三按钮）+ `lib/widgets/diagnosis_failed_card.dart`（建议列表 + 失败阈值提示）+ 三 insert 函数 + MessageList 分派**（三卡交互回调 RN 亦为 TODO 占位，Flutter 渲染层展示为主） | ★★ |
| 导入成功反馈 | `reference/ImportSuccessSheet.tsx` | 导入完成后的引导弹层；**批次 16 已落地 `lib/widgets/import_success_sheet.dart`（「导入成功！」+ 章节数 + 「是否立即发送给月笙诊断？」+ 立即诊断/稍后再说双按钮）+ ChatPage 上传完成接线（原 SnackBar 被弹层替代；立即诊断 → `pendingDiagnosisChapterProvider` 写待诊断章节触发自动诊断）** | ★ |

## C. 弹层与工具

| 缺口 | RN 组件 | 说明 | 优先级 |
|------|---------|------|--------|
| 保存到文件 | `modals/SaveToFileSheet.tsx` | 保存 AI 输出到章节/文件；**批次 14 已落地 `lib/widgets/save_to_file_sheet.dart`（角色 chips + 文件名预填 + 空内容拦截）+ MessageBubble「保存到文件」按钮 + ChatPage 主引用读取接线** | ★★ |
| 放弃练习确认 | `modals/AbandonPracticeModal.tsx` | 训练中放弃练习的确认流程；**批次 15 已落地 `lib/widgets/abandon_practice_modal.dart`（阻断式确认弹窗：继续练习/确认跳过）+ ChatPage「跳过」接线（确认跳过 → 清空练习状态 + 子阶段回 DIAGNOSIS）** | ★★ |
| 里程碑庆祝 | `shared/MilestoneCelebration.tsx` | 达成里程碑的庆祝动画 | ★ |
| 活跃问题面板 | `chat/TaskPanel.tsx` | 活跃问题列表；**批次 18 已落地 `lib/widgets/task_panel.dart`（练习任务 header + N 个问题徽标 + severity 色左边框/圆点 + 严重度中文标签 + 完成按钮；空态「暂无活跃问题」）+ ChatPage 接线（P2 阶段 toggle「任务 (N)」/「收起任务」+ 200 高面板 + 进入 P2 自动加载 + 完成 → resolveProblem 落库刷新）；教学建议部分已按记忆约束移除（移至对话流卡片）** | ★ |

## D. 独立页面（Flutter 路由缺失）

| 缺口 | RN 页面 | 说明 | 优先级 |
|------|---------|------|--------|
| 设置页 | `app/settings.tsx` | 应用设置（`llm_config_storage` 已有配置存储，缺 UI）；**批次 11 已落地 `lib/widgets/settings_page.dart`（API 配置表单 + 测试连接/清空 + 清除缓存 + 反馈 + 关于）+ `/settings` 路由 + 成长页快捷入口** | ★★ |
| 素材独立页 | `app/materials.tsx` | 素材管理独立页（Flutter 素材区内嵌稿件详情）；**批次 19 审计：RN 真源为死路由（`_layout.tsx` 注册但全文无入口，稿件详情实际用内嵌 FileSection Tab），Flutter 内嵌 FileSection 已覆盖（上传/删除/查看/空态）→ 无需实施** | ★ |
| 创建项目 | `app/create-project.tsx` | 新建项目引导；**批次 19 审计：书架「新建作品」弹窗已覆盖创建语义（标题/简介/类型），RN 独立页仅多体裁 chips + 语言选择，属形式差异 → 无需实施** | ★ |
| 导入确认 | `app/import-confirm.tsx` | 导入确认页；**批次 20 已落地 `lib/widgets/append_chapters_page.dart`（追加章节导入页：选择文件/解析/与已有章节标题比对标记「已存在」/多选/全选/取消/`createChaptersBatch` 批量入库 → 复用批次 16 ImportSuccessSheet → 回稿件详情）+ `/append-chapters` 路由 + 稿件详情章节列表 header「导入」按钮（空态/有章节均显示，对齐 RN ChapterSection）** | ★ |
| 进度详情 | `app/progress-detail.tsx` | 进度详情页；**批次 21 已落地 `lib/widgets/progress_detail_page.dart`（会话级学习进度页：ProgressSummaryCard 概览卡 + DiagnosisHistory 诊断历史 + SyndromeTrendList 症候趋势（复用批次 8 弹层）+ ProblemStats 问题统计（严重度筛选）+ 生成学习报告 → ProgressReport 报告视图（复制；分享开发中提示））+ `/progress-detail` 路由 + 书架页进度卡入口（最新会话，对齐 RN bookshelf ProgressCard）** | ★ |
| 项目设置 | `app/project-settings.tsx` | 项目设置；**批次 20 已落地 `lib/widgets/project_settings_page.dart`（编辑名称/体裁 chips/简介 + 标签添加删除 + 统计信息 + 危险区删除项目二次确认 → deleteManuscript 回书架）+ `/project-settings` 路由 + 稿件详情 AppBar 更多菜单（导出/分享 开发中提示 + 项目设置 + 删除项目，对齐 RN MoreMenuSheet）** | ★ |
| 会话列表 | `app/chat-list.tsx` | 独立会话列表页（与 SessionDrawer 二选一）；**批次 19 审计：SessionDrawer（批次 7）已覆盖 → 无需实施** | ★★ |

## E. 服务层缺口（部分可能已内联实现，待二次确认）

| 缺口 | RN 服务 | 说明 |
|------|---------|------|
| attitude-advisor | `services/attitude-advisor.service.ts` | 态度建议（对应 A 类横幅）；✅ 已落地：`lib/services/attitude_advisor.dart`（建议引擎 + 阈值/冷却/文案，2026-08-07 批次 12） |
| ~~syndrome-tracker~~ | `services/syndrome-tracker.service.ts` | ✅ 已落地：`lib/services/syndrome_tracker.dart`（loadSyndromeTrends 聚合 + 趋势计算，2026-08-07 批次 8） |
| progress-service | `services/progress-service.ts` | 进度统计；**批次 21 已落地 `lib/services/progress_service.dart`（getProgressSummary/getDiagnosisHistory/getProblemStats/generateReport 四函数 + ProgressSummary/DiagnosisRecord/ProblemStat/LockedSyndrome 模型）；批次 19 注记「student_profile_compute 疑似对应」经核为误判（复刻的是 RN student-profile-compute.ts），progress-service 实际为薄聚合：复用 TeachingStateRepository + DiagnosisRepository + active_problems 表** |
| skill-lifecycle | `services/skill-lifecycle.ts` | 技能生命周期；⚠️ **部分闭环（2026-08-08 复核更正，原「✅ 已闭环」为虚假闭环/批次 19 审计漏判）**：配置层已对齐——`skill_layers.dart`（L1/L2 配置 + L2Mode 解析 + resolveL2Mode + V2 开关）+ `skill_dispatcher.dart`（buildSystemPromptV2 组装 + token 估算 + validatePrompt）。**内容层缺失**：`skill_registry.dart` 仅注册 11 个 skill（8 L1 + 3 态度档位）；L2 按需层 23 个独特 skill 全部未搬运（beginner 6 / diagnosis 7 / training 9 / advanced 1 / outline 1，含 v2 变体共 28 个源文件），dispatcher 静默跳过不报错；L3 症候知识库（RN `syndrome-diagnosis.ts`）与技法库（RN `technique-library.ts`）未搬运，`chat_context_builder.dart` 中 syndromeContent/techniqueSection 显式为空。**影响**：chat_service 教学链路（buildSystemPromptV2 → system message）只注入 L1 + 态度档位 + 位置判断引导语，缺少 diagnosis/training/beginner/advanced/outline 各组的核心教学知识（症候索引、coaching-actions、技法库、训练循环、示范/对比、修订方法论等）与 L3 症候/技法详情 |
| context-injector | `services/context-injector.ts` | 训练引擎注入管线（Flutter 由 chat_context_builder 覆盖引用注入） |

---

## 建议实施顺序

1. ✅ **ReferenceBar**（★3）：已实施（`lib/widgets/reference_bar.dart` + ChatPage 顶部接线 + 9 测试）
2. ✅ **SessionDrawer**（★3）：已实施（`lib/widgets/session_drawer.dart` + ChatPage drawer + 会话切换/新建 + 12 测试）
3. ✅ **SyndromeDetailModal**（★3）：已实施（`lib/widgets/syndrome_detail_modal.dart` + `services/syndrome_tracker.dart` + DiagnosisCard chip 入口 + 12 测试）
4. ✅ **消息卡片渲染扩展**（★2）：已实施（reference_change + phase_upgrade 卡片渲染与插入链路 + 15 测试；PartialAgreement/PhaseSummary/DiagnosisFailed 待后续流程批次）
5. ✅ **QuickChips / 聊天头部状态区**（★2）：已实施（QuickChips 快捷提问 + ChatHeader 头部状态区（标题/入口徽章/会话列表/更多菜单：阶段+子阶段+态度+画像）+ ChatWelcome 欢迎态 + SubphaseIndicator + TeachingStateBadge + EncouragementText，2026-08-07 批次 10）
6. ✅ **设置页**（★2）：已实施（`lib/widgets/settings_page.dart`：API 配置表单（保存/测试连接/填充示例/清空）+ 维护（清除缓存/反馈）+ 关于 + `/settings` 路由 + 成长页快捷入口，2026-08-07 批次 11）
7. ✅ **态度建议横幅**（★2）：已实施（`lib/widgets/attitude_suggestion_banner.dart` 升级/降级横幅（接受「切换到X」/暂不）+ `lib/services/attitude_advisor.dart` 建议引擎（消息数/冷却/严重度/连续反馈阈值）+ ChatPage 发送/快捷提问后 500ms 自动检查 + QuickChips 隐藏联动，2026-08-07 批次 12）
8. ✅ **诊断确认/选择**（★2）：已实施（`lib/widgets/diagnosis_picker_sheet.dart` 作品→章节选择弹层（章节 <100 字拦截提示 / 空库引导去书架 / 50 章懒加载 + 加载更多）+ 成长页「写作诊断」入口 + `pendingDiagnosisChapterProvider` 跨 Tab 传递 + ChatPage 自动诊断（长文分块 runProgressiveDiagnosis / 短文单次诊断），2026-08-07 批次 13；确认条复用批次 5 DiagnosisCard D5-B）
9. ✅ **保存到文件**（★2）：已实施（`lib/widgets/save_to_file_sheet.dart` 保存弹层（角色 chips 常规/大纲/素材 + 文件名预填 指定>首行40字>日期 兜底 + 空内容拦截）+ MessageBubble assistant 操作区「保存到文件」按钮 + ChatPage 接线（读主引用 → 无则提示「请先关联一本书籍」→ createAttachedFile 写入主引用作品），2026-08-07 批次 14）
10. ✅ **放弃练习确认**（★2）：已实施（`lib/widgets/abandon_practice_modal.dart` 阻断式确认弹窗（警示图标 + 「确定跳过本次练习？」+「已输入的内容将丢失，练习进度不会保存。」+ 继续练习/确认跳过，点击遮罩不关闭）+ ChatPage「跳过」接线（确认 → resetPractice 清空练习状态 + 子阶段持久化回 DIAGNOSIS），2026-08-07 批次 15；附带修复：MessageList 练习卡移入列表滚动区，消除消息+练习卡叠加布局溢出）
11. ✅ **导入成功反馈**（★）：已实施（`lib/widgets/import_success_sheet.dart` 成功引导弹层（顶部把手 + 成功圆底勾图标 + 「导入成功！」+ 章节数副标题 + 「是否立即发送给月笙诊断？」+ 立即诊断/稍后再说双按钮）+ ChatPage 上传完成接线（原 SnackBar 被弹层替代；立即诊断 → `pendingDiagnosisChapterProvider` 写待诊断章节 → 自动诊断链（长文分块/短文单次），对齐 RN startDiagnosis=true&chapterId=X），2026-08-07 批次 16）

> 注：C 类「里程碑庆祝」（★）经用户确认**不做**（2026-08-07 批次 16 决策），不再进入实施序列。
12. ✅ **消息卡片类型**（★2）：已实施（`lib/widgets/partial_agreement_card.dart`（「请补充不符合的地方」+ severity 矿物色徽标 + 症候名 chip + 多行反馈输入 + 3 快速选项（症状描述不准/缺少某个问题/严重度不对）+ 跳过此症候/提交反馈双按钮）+ `lib/widgets/phase_summary_card.dart`（passed/partial/failed 结果图标圆底 + 解决症候数/练习次数/进步趋势统计 + 症候变化列表 ≤5 + 继续训练/查看学员画像/返回对话三按钮）+ `lib/widgets/diagnosis_failed_card.dart`（「未检测到明显问题」+ 默认 3 建议 + 补充内容/继续对话 + failureCount≥2 多次失败提示）+ message_card_service 三 insert 函数（assistant 角色）+ MessageList 分派接线，2026-08-07 批次 17；三卡交互回调 RN 真源亦为 TODO 占位，Flutter 渲染层展示为主）
13. ✅ **活跃问题面板**（★）：已实施（`lib/widgets/task_panel.dart` 活跃问题列表（「练习任务」header + 「N 个问题」徽标 + severity 矿物色左边框/圆点 + 症候名 + 严重度中文标签（L1建议/L2注意/L3严重）+ 「完成」按钮（可选回调）+ 空态「暂无活跃问题/完成诊断后会显示需要解决的问题」）+ ChatPage 接线（P2 阶段显示 toggle「任务 (N)」/「收起任务」对齐 RN chat.tsx L396-400 + 展开时 200 高面板对齐 taskPanelContainer + 进入 P2 自动 loadActiveProblems 对齐 RN useEffect + 「完成」→ resolveProblem 落库 + 重载对齐 RN handleMarkComplete），2026-08-07 批次 18；教学建议部分按记忆约束移除（已移至对话流 TeacherSuggestionCard））
14. 📋 **D/E 类只读审计**（仅文档，2026-08-07 批次 19）：按「先审计真源、避免为对齐造冗余页」原则逐页确认——素材独立页（RN 死路由 + FileSection 已覆盖）/ 创建项目（书架新建弹窗已覆盖）/ 会话列表（SessionDrawer 二选一已覆盖）→ **标注无需实施**；导入确认「追加章节」（Flutter 无入口）+ 项目设置（无编辑/删除入口）→ **确认真实缺口，列入后续实施序列**；进度详情 → 捆绑 E 类 progress-service 待评估；E 类 skill-lifecycle → **标注已闭环**（skill_layers + skill_dispatcher 等价覆盖）→ ⚠️ **2026-08-08 复核更正：虚假闭环**，仅配置层对齐，L2 内容层 23 个 skill 与 L3 症候/技法知识库全部缺失（详见 E 类表格 skill-lifecycle 行），progress-service 注记「疑似对应」经核为误判
15. ✅ **导入确认 / 项目设置**（★）：已实施（`lib/widgets/append_chapters_page.dart` 追加章节导入页（选择文件/解析/已存在标记/多选/全选/取消/批量入库/复用 ImportSuccessSheet）+ `lib/widgets/project_settings_page.dart` 项目设置页（编辑名称/体裁/简介/标签 + 统计 + 删除项目二次确认）+ `/append-chapters` `/project-settings` 两路由 + 稿件详情「导入」按钮 + AppBar 更多菜单（导出/分享 开发中 + 项目设置/删除项目），2026-08-07 批次 20）
16. ✅ **进度详情 / progress-service**（★）：已实施（`lib/services/progress_service.dart` 学习进度服务（getProgressSummary/getDiagnosisHistory/getProblemStats/generateReport 四函数，复用 TeachingStateRepository + DiagnosisRepository + active_problems 表）+ `lib/widgets/progress_detail_page.dart` 会话级学习进度页（概览卡/诊断历史/症候趋势复用批次 8/问题统计筛选/生成学习报告 → 报告视图）+ `/progress-detail` 路由 + 书架页进度卡入口（最新会话，对齐 RN ProgressCard），2026-08-07 批次 21；⚠️ **2026-08-08 复核更正：原「至此 D 类与 E 类全部闭环」不成立**——E 类 skill-lifecycle 内容层缺失（见 E 类表格与第 17 条），D 类页面闭环成立）
17. 📋 **skill-lifecycle 内容层补齐**（2026-08-08 复核新增，核心链路修复，优先级最高）：① ✅ **已完成（2026-08-08 批次 22）**：L2 按需层 26 个 skill 内容搬运入 `skill_registry.dart`（beginner 6：beginner-path/gap-detector/coaching-rhythm/narrative-design/plot-design/writer-psychology；diagnosis 6：coaching-actions(-v2)/reader-awareness/genre-guide/writing-style/diagnosis-confirmation/feedback-cognition；training 12：training-loop(-v2)/training-templates(-index)/training-evaluation(-v2)/text-surgery(-v2)/coaching-actions-v2/demonstration/comparison/revision-methodology；advanced 1：advanced-phases；outline 1：outline-diagnosis；内容逐字保留 RN 真源，`\`\`\`` 转义反引号还原，loadWhen 元数据不搬运）→ 注册表 11→37 个；`test/skill_registry_l2_test.dart` 10 测试（注册完整性/五组组装断言/V2 替换生效/虚拟索引跳过/validatePrompt）全过；四闸验证（format/analyze 0 error/681 test 全绿）通过；② ✅ **已完成（2026-08-08 批次 22 步骤②）**：L3 知识库搬运与接入——`lib/services/syndrome_knowledge_base.dart`（RN `syndrome-diagnosis.ts`：kSyndromeIndexContent 索引 + kSyndromeManualContent 完整手册 P003-P021 + getSyndromeContent 检索）+ `lib/services/technique_knowledge_base.dart`（RN `technique-library.ts`：kTechniqueIndexContent 索引 + kTechniqueLibraryContent 完整技法库 T001-T031 + getTechniqueContent/getTechniquesBySyndrome 检索 + kTechniquesBySyndrome 映射）；`syndrome-diagnosis-index`/`technique-library-index` 两虚拟索引注册入 skill_registry（39 个），dispatcher 跳过逻辑解除（索引已注册则加载）、`_getSyndromeContent`/`_getTechniqueContent` 接入真实检索；`chat_context_builder.dart` syndromeContent/techniqueSection 空串替换为真实 L3 注入（focus 症候完整定义 + 首选/备选技法，对齐记忆约束「L3 内容加载策略」）；`test/syndrome_technique_knowledge_test.dart` 9 测试（索引/手册完整性/单/多症候提取/技法提取/按症候取技法/focus 注入接线）全过；四闸验证（format/analyze 0 error/690 test 全绿）通过；**训练侧 L3 补齐（2026-08-08 批次 22 步骤② 补充）**：`lib/services/training_knowledge_base.dart`（RN `training-templates-v2.ts`：kTrainingFullKnowledge 完整教学知识 P003-P021 核心本质/教学要点/常见误区/严重度判断/教学素材库 + getTrainingContent 检索）+ `chat_context_builder.dart` focus 症候追加完整训练知识注入（对齐记忆约束「L3 内容加载策略：focus 症候提供完整定义」训练侧），测试 +3 至 **693 全绿**；**待实施 ③** 教学环境重验证：buildSystemPromptV2 组装完整 prompt（L1+L2+L3）+ DeepSeek 实测输出合规性 → ③ ✅ **已完成（2026-08-08 批次 25）**：教学环境重验证闭环——`test/teaching_env_verification_test.dart`（应用内构造 + CaptureLlmClient 走 sendMessage 完整链路，5 场景断言 L1（铁三角/态度档位/位置判断）+ L2（diagnosis/training/beginner 按语境组）+ L3（症候定义+技法，仅活跃症候注入）+ 学员画像 + token 预算）入四闸（+5 至 **732 全绿**）；`test/live_teaching_flow_test.dart` 重构为 sendMessage 完整链路 + 真实 DeepSeek 输出合规性（[YS_DIAGNOSIS]/JSON/不泄漏编号 + 落库闭环），live 保留（无 key 自动跳过）

## 已确认无缺口（Flutter 已闭环）

- 文件解析 / 作品导入（事务）/ 引用选择（default + mention）/ 素材管理 / 内容查看 / @引用 插入解析
- **ReferenceBar**（顶部引用条：主引用行 + 展开列表 + 设主/移除/多选批量删除 + 添加引用，2026-08-07 批次 6）
- **SessionDrawer**（会话管理抽屉：月字头像/相对时间/预览/阶段标签 + 切换/新建会话，2026-08-07 批次 7）
- **SyndromeDetailModal**（症候详情弹层：出现次数/趋势/首次发现 + 迷你趋势图 + 诊断记录，2026-08-07 批次 8；数据源 syndrome-tracker 一并落地）
- **消息卡片渲染扩展**（reference_change 引用变更卡片 + phase_upgrade 阶段升级卡片，2026-08-07 批次 9）
- **QuickChips / 聊天头部状态区**（QuickChips 快捷提问 + ChatHeader（标题/入口徽章/更多菜单）+ ChatWelcome 欢迎态 + SubphaseIndicator + TeachingStateBadge + EncouragementText，2026-08-07 批次 10）
- **设置页**（API 配置表单 + 测试连接/清空 + 清除缓存（删孤儿会话）+ 反馈 + 关于，2026-08-07 批次 11）
- **态度建议横幅**（升级/降级建议 + 接受「切换到X」/暂不 + 建议引擎阈值/冷却/文案 + 发送后 500ms 自动检查 + QuickChips 隐藏联动，2026-08-07 批次 12）
- **诊断确认/选择**（作品→章节选择弹层 + 成长页入口 + 跨 Tab 自动诊断（startDiagnosis 语义）+ <100 字拦截 + 50 章懒加载，2026-08-07 批次 13；确认条复用批次 5 DiagnosisCard D5-B）
- **保存到文件**（保存弹层（角色 chips + 文件名预填）+ assistant 气泡操作区按钮 + 主引用目标写入 attached_files，2026-08-07 批次 14）
- **放弃练习确认**（阻断式确认弹窗 + ChatPage 跳过接线（清空练习状态 + 回 DIAGNOSIS），2026-08-07 批次 15）
- **导入成功反馈**（成功引导弹层（章节数 + 立即诊断/稍后再说）+ 上传完成接线（立即诊断触发自动诊断链），2026-08-07 批次 16）
- **消息卡片类型**（PartialAgreement 部分认同反馈 + PhaseSummary 阶段总结 + DiagnosisFailed 诊断失败三卡，2026-08-07 批次 17）
- **活跃问题面板**（P2 阶段任务开关 + 活跃问题列表 + 完成标记落库，2026-08-07 批次 18）
- ~~**skill-lifecycle**~~（⚠️ 2026-08-08 复核：**移出「已确认无缺口」**——配置层（skill_layers + skill_dispatcher 组装框架）已闭环，但内容层缺失：L2 按需层 23 个独特 skill 未搬运 + L3 症候/技法知识库未接入，详见 E 类表格 skill-lifecycle 行与实施顺序第 17 条）
- **D 类无需实施标注**（素材独立页：RN 死路由 + 内嵌 FileSection 已覆盖；创建项目：书架新建弹窗已覆盖；会话列表：SessionDrawer 二选一已覆盖，2026-08-07 批次 19 审计）
- **追加章节导入**（/append-chapters：选择文件/解析/已存在标记/多选/全选/取消/批量入库/成功弹层回稿件详情，2026-08-07 批次 20）
- **项目设置**（/project-settings：编辑名称/体裁/简介/标签 + 统计 + 删除项目二次确认；稿件详情更多菜单入口，2026-08-07 批次 20）
- **progress-service**（getProgressSummary/getDiagnosisHistory/getProblemStats/generateReport，复用既有 repo 的薄聚合，2026-08-07 批次 21）
- **学习进度详情页**（/progress-detail：会话级概览/诊断历史/症候趋势/问题统计/学习报告；书架页进度卡入口，2026-08-07 批次 21）
- 训练系统闭环（任务卡 → 作答 → 结果 → 评估报告）/ 态度切换（persistAttitude 双写）
- 诊断链（DiagnosisCard / 渐进诊断 / Teacher 建议卡片）/ 成长页 / 书架 / 稿件详情 / 写作页
- 对话引用上下文注入（chat_context_builder 15K 预算）

---

## F. 行为/构造层缺口（2026-08-08 全量行为对照扫描）

> 扫描方式：RN（`yuesheng-android/src`）与 Flutter（`yuesheng-flutter/lib`）双只读全量扫描，
> 按 6 维度（页面/交互/服务/存储/错误处理/配置）提取行为清单后逐项对照，再对疑点做源码级定向核实。
> 本表为行为/构造层面的**真实差异**，与 A-E 类（页面/组件/服务缺口）互补。

### F-1 行为层缺口（RN 生产路径有，Flutter 缺失或弱化）

| 编号 | 行为 | RN 真源 | Flutter 现状 | 判定 | 优先级 |
|------|------|---------|-------------|------|--------|
| B1 | **Mem0 记忆合并（NO_OP）** | `db/dao/diagnosis-dao.ts`：诊断落库前与最近一条比对，同症候同严重度 → 跳过 INSERT（不追加重复记录），active_problem 仍 UPSERT | ✅ **已实施（2026-08-08 批次 23 步骤①）**：`diagnosis_repository.dart` commitDiagnosis 新增步骤 0 记忆合并，INSERT 仅写入过滤后症候，active_problem 仍 UPSERT 全部 | ~~★3 高~~ → 已闭环 |
| B2 | **effectiveness 计算** | `services/diagnosis-service.ts` calculateEffectiveness：历史同症候 ≥ REPEAT_SYNDROME_THRESHOLD 时比较前后 severity → 写入 teaching_history.effectiveness（improved/no_change/worsened） | ✅ **已实施（2026-08-08 批次 23 步骤③）**：`diagnosis_service.dart` 新增 calculateEffectiveness（跨会话全表 + 最近两条比较严重度）+ commitDiagnosisWithHistory 写入 effectiveness（无变化不写，对齐 RN） | ~~★2 中~~ → 已闭环 |
| B3 | **划词诊断** | `app/chapter-editor.tsx`：onSelectionChange 捕获选中文本 → ≥20 字 → 浮动菜单「诊断这段文字」→ 发送诊断消息 | ✅ **已实施（2026-08-08 批次 23 步骤④）**：`writing_page.dart` 选中捕获（controller listener）+ 浮动菜单「诊断这段文字」+ <20 字 SnackBar；`writing_coach_panel.dart` pendingDiagnoseText 注入 → 选段诊断（下限 20 字，prompt 标【选段】） | ~~★2 中~~ → 已闭环 |
| B4 | 首次诊断里程碑庆祝 | `app/chat.tsx` L186-197：latestDiagnosis 含症候且首次 → MilestoneCelebration 庆祝动画（hasShownMilestoneRef 仅一次） | 无（仅有 `phase_upgrade_card.dart` 阶段升级卡） | **行为差异**——2026-08-07 批次 16 用户已决策「不做」，保留该决策，仅记录差异 | ★ 低（已决策） |
| B5 | **离线模式 + 离线草稿** | `app/chapter-editor.tsx`：useNetInfo 断线 → 顶部离线横幅 + 禁保存/禁诊断 + 内容自动存本地草稿（DRAFT_DEBOUNCE）+ 恢复网络自动同步 | ✅ **已实施（2026-08-08 批次 23 步骤②）**：`writing_providers.dart` isOffline/hasDraft + saveNow 离线分支存草稿 + setOffline 恢复自动同步；`writing_page.dart` connectivity_plus 订阅 + 离线横幅 + 草稿恢复弹窗（发现未保存草稿：放弃/恢复） | ~~★3 高~~ → 已闭环 |
| B6 | **草稿恢复弹窗** | `app/chapter-editor.tsx` L129-135：打开章节时 draft.savedAt > ch.updated_at → Alert「发现未保存草稿，是否恢复？」（放弃/恢复） | ✅ **已实施（2026-08-08 批次 23 步骤②）**：随 B5 一并落地（loadChapter 草稿检测 + 恢复弹窗），对齐 RN 严格 `>` 判定 | ~~★2 中~~ → 已闭环 |
| B7 | **撤销/重做** | `hooks/useUndoRedo.ts`（debounce 500ms / maxHistory 10，TextInput 历史双栈） | `widgets/writing_page.dart` WritingMenuSheet 注释 E3 明确「移除 4 个开发中占位项」含撤销/重做 | ✅ **已实施（2026-08-08 批次 24 步骤①）**：`writing_providers.dart` WritingStore 历史双栈（_past/_future + _lastCommitted，500ms debounce，上限 10）+ AppBar 撤销/重做按钮（canUndo/canRedo 禁用态）+ loadChapter/restoreDraft 重置 + saveNow 落提交点 + dispose 取消定时器（6 测试） | ~~★★ 中~~ → 已闭环 |
| B8 | 成长页审计卡 | `app/(tabs)/growth.tsx` L122 渲染 `components/profile/ObservationAuditCard.tsx`（观察-判定审计统计） | 无对应卡片（editor_observation 表与 repository 已实现，缺展示） | ✅ **已实施（2026-08-08 批次 24 步骤②）**：`editor_observation_repository.dart` 补齐 countObservations/countTriggeredObservations + `widgets/observation_audit_card.dart`（折叠/展开、统计、最近列表、空态）+ `growth_page.dart` 接入（4 测试） | ~~★ 低~~ → 已闭环 |

### F-2 构造层核对（纠正此前「已知缺口」误判）

| 编号 | 项 | RN 状态 | Flutter 状态 | 判定 |
|------|-----|---------|-------------|------|
| C1 | skill-lifecycle 内容层 | `assets/skills/*.ts` 47 个 skill + L3 syndrome-diagnosis.ts / technique-library.ts / training-templates-v2.ts | 批次 22 已搬运 L2 26 skill + 三知识库（注册表 39 项），L3 注入已接线；批次 25 教学环境重验证完成 | ✅ **已闭环（2026-08-08 批次 25）**：应用内构造（Fake LLM）+ live 真实链路双重验收通过 |
| C2 | 三消息卡片调用方 | `message-card-service.ts` 三 insert 函数**仅 DevToolPanel 调试面板调用**，chat-service 生产路径不调用 | `message_card_service.dart` 三 insert 函数已定义，**同样无生产调用方** | ✅ **对齐，非缺口**（纠正旧判定；本质为调试工具，生产路径未启用） |
| C3 | ReviewerGate | `config/shared-constants.ts` REVIEWER_GATE.ENABLED = **false** | `config/shared_constants.dart` ReviewerGate.enabled = **false** | ✅ **对齐**（纠正旧判定） |
| C4 | inferCognitiveStyle 作用域 | `services/student-profile.ts` 跨所有 session 全表扫描 | `services/student_profile.dart` L13 注释明确仅当前 sessionId（RN 全表） | ⚠️ **差异**（影响有限：认知风格依赖近期关键词，单会话已能反映；已显式注释） |
| C5 | FSRS 间隔重复 | `services/diagnosis-service.ts` T-011：syndrome-scheduler 已从 import 链**彻底移除**（P1 不必要） | 未实现 FSRS | ✅ **对齐**（纠正旧判定；RN 生产路径同样无） |
| C6 | error_logs | `services/error-logger.ts` | `data/repositories/error_log_repository.dart` 完整 | ✅ 对齐 |
| C7 | editor_observation | 有 editor-observation 实现 | `data/repositories/editor_observation_repository.dart` 完整 | ✅ 对齐 |
| C8 | 训练知识库注入 | RN 生产路径不注入 trainingContent | 批次 22 步骤②补充后已回退训练侧注入，严格对齐 RN | ✅ 对齐 |

### F-3 RN 侧缺陷（Flutter 不应模仿，仅记录）

- `settings.tsx` 清除缓存 SQL 引用**不存在**的表（RN 缺陷，Flutter 批次 11 已用正确 SQL）
- tags 标签**不落库**（RN 缺陷，Flutter project_settings_page 已真实持久化）
- `card-list` 路由悬空（RN 死路由，无入口）
- 孤儿资产 `assets/skills/attitude-rhythm.json` / `syndrome-action-map.json`：无代码消费者（Flutter 无需搬运）
- cancelToken 在 RN 无 UI 接线（Flutter 相同）

### F-4 结论

- **行为层缺口（批次 23/24 全部闭环）**：✅ B1 Mem0 记忆合并（★★★）→ ✅ B5 离线模式/离线草稿（★★★）→ ✅ B2 effectiveness 写入（★★）→ ✅ B3 划词诊断（★★）→ ✅ B6 草稿恢复弹窗（★★）→ ✅ B7 撤销/重做（★★，批次 24 步骤①）→ ✅ B8 审计卡展示（★，批次 24 步骤②）— **F 章节行为层缺口全部闭环**
- **B4 里程碑庆祝**：保持批次 16「不做」决策，如用户改变主意可重新评估
- **构造层无新增缺口**：C2/C3/C5 旧「已知缺口」判定经源码核实为**对齐误判**，已纠正
