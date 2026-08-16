# B54 功能盘点 — 80/20 审视（Sudowrite 研究借鉴点 C）

**日期**：2026-08-08
**类型**：纯文档 + 审计（无代码改动）
**背景**：Sudowrite 研究 §5.2 行业误区 1"功能越多越好 → 学习成本高、80/20 定律"。月笙经 53 个批次后功能庞大，立项一次产品级盘点，防重蹈"功能堆砌"覆辙。
**方法**：app_router 路由表 + lib/widgets 目录全量 + 关键组件入口抽查；使用率预期为静态推断（无埋点数据，标注局限）。

---

## 1. 功能全景（按功能域）

### 1.1 三大 Tab（导航层）
| 功能 | 入口 | 核心闭环归属 | 使用率预期 |
|------|------|------------|----------|
| 书架（BookshelfPage） | Tab1 | 作品管理（前置） | 高（默认页） |
| 对话（ChatPage） | Tab2 | **诊断→训练→反馈主战场** | 高 |
| 成长（GrowthPage→GrowthDetailPage） | Tab3 | **反馈**（画像/症候/曲线） | 高 |

### 1.2 作品管理域
| 功能 | 入口 | 归属 | 使用率 | 建议 |
|------|------|------|-------|------|
| 作品详情（ManuscriptDetailPage） | /manuscript-detail | 前置 | 高 | 保留 |
| 章节写作（WritingPage + WritingCoachPanel + WritingMenuSheet + PunctuationBar） | /writing/:chapterId | 核心（训练素材来源） | 高 | 保留 |
| 作品导入（BookImportSheet / WorkImportSheet） | 对话+按钮 / 书架 | 前置 | 中高 | 保留 |
| 追加章节（AppendChaptersPage） | 稿件详情「导入」 | 前置 | 中 | 保留 |
| 项目设置（ProjectSettingsPage） | 稿件详情更多菜单 | 外围 | **低** | **观察**：仅标题编辑，价值存疑 |

### 1.3 引用/上下文域（诊断依据）
| 功能 | 入口 | 归属 | 使用率 | 建议 |
|------|------|------|-------|------|
| 顶部引用条（ReferenceBar） | 对话页常驻 | 核心（诊断上下文） | 中高 | 保留 |
| 引用选择器（ReferencePicker + @mention） | 对话输入 | 核心 | 中高 | 保留 |
| 素材管理三件套（MaterialUploadSheet / FileSection / FileViewerModal） | 稿件详情 | 支撑 | **中低** | **观察**：RN 对齐功能，学员需先传素材才有价值 |
| 保存到文件（SaveToFileSheet） | 消息气泡操作区 | 支撑 | **低** | **观察**：导出低频 |

### 1.4 对话域（核心闭环 UI）
| 功能 | 归属 | 使用率 | 建议 |
|------|------|-------|------|
| 头部状态（ChatHeader / SubphaseIndicator / TeachingStateBadge） | 核心 | 高 | 保留 |
| 输入（ChatInput） | 核心 | 高 | 保留 |
| 快捷提问（QuickChips，3 个） | 核心 | 中高 | **保留 + 扩展**（见批次56 动作场景化） |
| 欢迎/鼓励（ChatWelcome / EncouragementText） | 核心（启动感） | 高 | 保留 |
| 消息流与卡片（MessageList / MessageBubble + DiagnosisCard / TeacherSuggestionCard / PracticeTaskCard / PracticeResultIndicator / PhaseSummaryCard / PartialAgreementCard / DiagnosisFailedCard / PhaseUpgradeCard / ReferenceChangeCard / AttitudeSuggestionBanner / ObservationAuditCard） | 核心 | 高 | 保留 |
| 会话抽屉（SessionDrawer） | 支撑 | 中 | 保留 |
| 态度切换（AttitudeIndicator） | 核心（反 AI 味） | 中 | 保留 |

### 1.5 训练域
| 功能 | 归属 | 使用率 | 建议 |
|------|------|-------|------|
| 活跃问题面板（TaskPanel） | 核心 | 高 | 保留 |
| 症候详情（SyndromeDetailModal） | 支撑 | 中高 | 保留 |
| 诊断选择（DiagnosisPickerSheet） | 核心 | 中高 | 保留 |
| 放弃练习确认（AbandonPracticeDialog） | 核心 | 中 | 保留 |
| 导入成功引导（ImportSuccessSheet） | 核心 | 中 | 保留 |

### 1.6 反馈/成长域
| 功能 | 归属 | 使用率 | 建议 |
|------|------|-------|------|
| 评估报告（EvaluationReportPanel） | 核心 | 高 | 保留 |
| 学习进度（ProgressDetailPage + RelatedSessionsTab） | 核心 | 中高 | 保留 |
| 成长展示（GrowthOverviewCard / AbilityChart / WritingCurveChart / SyndromeHistoryList / ProficiencyRing / SeverityBar / TeachingStateBadge） | 核心 | 中高 | 保留 |
| 写作风格卡（批次53） | 核心（新） | 待观察 | 保留 |
| 新手问卷（OnboardingQuestionnaire） | 核心 | 高（一次性） | 保留 |

### 1.7 系统域
| 功能 | 归属 | 使用率 | 建议 |
|------|------|-------|------|
| 设置页（SettingsPage：API/缓存/反馈/关于） | 支撑 | 中 | 保留 |
| 占位页（PlaceholderPage） | 开发 | — | 保留（兜底） |

---

## 2. 分析结论

### 2.1 核心闭环（诊断→训练→反馈）完整且密度合理
对话域 + 训练域 + 反馈域合计 30+ 组件，但**全部服务于闭环**，非堆砌。QuickChips/欢迎态/态度切换等是对核心价值的强化，不是外围功能。

### 2.2 外围功能风险清单（3 项"观察"）
| 功能 | 风险 | 处置 |
|------|------|------|
| 项目设置（ProjectSettingsPage） | 仅标题编辑，价值低 | 观察：若使用率低，可在更多菜单折叠或合并 |
| 素材管理三件套 | 需先上传素材才有价值，使用门槛中 | 观察：保留但**不在核心流中推广** |
| 保存到文件（SaveToFileSheet） | 导出低频 | 观察：保留，消息气泡操作区已折叠 |

### 2.3 风险分级
- **中风险**：功能总数 57 组件 / 10 路由，新学员认知负担上升。缓解：三大 Tab 已将主要入口收敛，外围功能均在二级/三级菜单（详情页、操作区、更多菜单）。
- **低风险**：外围功能已全部折叠在二级入口，不进入首屏。

### 2.4 与 Sudowrite 教训的对照
- Sudowrite 失败在"功能堆在首屏"；月笙的外围功能已通过 Tab+二级菜单收敛 → **未重蹈覆辙，但需持续监控**
- 唯一建议收敛：**项目设置**（观察项）

---

## 3. 结论

1. **无紧急裁剪项**——外围功能已折叠，核心闭环完整，未出现 Sudowrite 式功能堆砌
2. **1 项观察**：ProjectSettingsPage（价值存疑，暂不动）
3. **1 项扩展**：QuickChips 是"动作场景化"（批次56）的天然入口
4. **后续监控**：建议在核心闭环（诊断→训练→反馈）的漏斗转化上收集真实使用数据，替代静态推断（盘点局限：无埋点）

## 提交

| Commit | 日期 | 标题 |
|--------|------|------|
| （本次） | 2026-08-08 | docs: 批次54 功能盘点（80/20 审视）——57 组件/10 路由全量归类，核心闭环完整无紧急裁剪项，3 项观察 + QuickChips 为动作场景化入口 |

## 验证

- 纯文档批次，无代码改动，不涉及四闸（参照批次 19 审计惯例）
- 盘点方法：路由表 + widgets 目录 + 入口抽查；使用率预期为静态推断（局限已标注）
