# RWR 王牌任务链（Master Chain）

> **权威依据**：[系统重构规格文档](../dev-docs/designs/2026-06-17-system-rewrite-spec.md)
> **所有设计决策以此为准，禁止偏离。如有疑问，先查规格文档，再查 TASK-CHAIN.md，最后问用户。**
>
> **当前基点**：`56208ff`（FB-021 终态，RWR-P1-6 ✅）
> **创建日期**：2026-06-17

---

## 一、已完成（a5ec9d9 包含）

| 任务 | 内容 | 涉及文件 |
|:-----|:-----|:---------|
| P0-1 | DB 数据模型扩展 | `021_teaching_progress.sql`（diagnosis.teachingProgress + student_model） |
| P0-2 | progress.store | `stores/progress.store.ts` |
| P0-3 | Store 导出路径统一 | `stores/index.ts`（barrel export）+ 删除旧 rightPanelService |
| P0-4 | 项目 IPC + 项目表 migration | `022_projects.sql` + `ipc/project.ipc.ts` |
| P0-5 | 数据迁移脚本 | `023_data_migration.sql` |
| P0-6 | useRightPanel hook + SettingsPanel | `hooks/useRightPanel.ts` + 设置面板 |
| P1-1 | AppShell 三栏独立布局 | `components/layout/AppShell.tsx` + `.module.css` |
| P1-3 | ProjectSelector + InputToolbar + AttitudeIndicator | `components/layout/ProjectSelector.tsx`、`components/chat/InputToolbar.tsx`、`components/chat/AttitudeIndicator.tsx` |

---

## 二、待执行（按依赖顺序排列）

### Phase A：导航与输入（P1 布局收尾）

#### A-1 [P1-2] SoloSidebar 三标签 [对话][项目][训练]

| 属性 | 值 |
|:-----|:-----|
| 前置 | P1-1 ✅ |
| 目标 | 现有 SoloSidebar（当前 ModeSwitch 只有 [对话][项目]）→ 三标签 [对话][项目][训练] |
| 涉及文件 | `SoloSidebar.tsx`（改）、`SoloSidebar.module.css`（改） |
| DoD | □ [对话][项目][训练] 三个 tab 可见可切换<br>□ [训练] 点击后中间栏进入训练视图<br>□ 原有拖拽/折叠/宽度记忆不破坏 |
| 依据 | 规格 §6.1 左侧栏设计 |

#### A-2 [P1-4] 输入区 1/6 屏高重构

| 属性 | 值 |
|:-----|:-----|
| 前置 | A-1 |
| 目标 | ChatView 输入区从当前固定高度 → 屏幕高度 1/6（max 180px） |
| 涉及文件 | `ChatView.tsx`（改）、`ChatView.module.css`（改）、`MessageInput.tsx`（改） |
| DoD | □ 输入区高度 = `min(max(1/6 屏高, 60px), 180px)`<br>□ 输入区顶部放 InputToolbar<br>□ AttitudeIndicator 显示在输入区左下角<br>□ 输入区自适应文字增多而增加（不超过 max） |
| 依据 | 规格 §5（输入区域设计） |

---

### Phase B：教学进度（核心反馈层）

#### B-1 [P1-5] TeachingProgressBar + ProgressTimeline ✅ (c6f0e64)

| 属性 | 值 |
|:-----|:-----|
| 前置 | A-1（左侧栏）、P0-2 ✅（progress.store） |
| 目标 | 右侧栏教学进度面板 0/N，按阶段分组（认知→工具→技能），点击展开详情 |
| 涉及文件 | `TeachingProgressBar.tsx`（新）、`ProgressTimeline.tsx`（新）+ drawer-constants / drawer.store / panel-session.store / right-panel.store 扩展 |
| DoD | ✅ 进度条显示 resolvedIssues / totalIssues<br>✅ 分母只增不减，按 status 分组<br>✅ 点击展开 ProgressTimeline（概览，不暴露诊断细节）<br>✅ 当前指针标记（第一个非 mastered issue） |
| 依据 | 规格 §4.2（教学进度追踪） |

**当前指针 → B-2 [P1-6]**

#### B-2 [P1-6] 诊断表与进度联动 + 教学决策记录

| 属性 | 值 |
|:-----|:-----|
| 前置 | B-1、P0-1 ✅ |
| 目标 | 诊断完成后自动更新 progress.store；TeachingDecisionLog 写入 DB（先写不读） |
| 涉及文件 | `diagnosis.service.ts`（改）、`progress.store.ts`（改）、`teaching-state-machine/`（改） |
| DoD | □ 诊断产生后自动更新 progressMap<br>□ TeachingDecisionLog 数据结构落地（不涉及前端渲染）<br>□ 不暴露症候细节给用户 |
| 依据 | 规格 §8（教学决策记录层）、§4.2 进度条"不暴露症候" |

---

### Phase C：反馈增强

#### C-1 [P1-7] 画像增强

| 属性 | 值 |
|:-----|:-----|
| 前置 | P0-1 ✅（student_model 表已存在） |
| 目标 | studentModel 中新增 `teachingHistory[]`，每项含 action/syndromeId/outcome/timestamp |
| 涉及文件 | `student-model.service.ts`（改）、`types-teaching.ts`（改） |
| DoD | □ 每次教学回合后写入一条 teachingHistory<br>□ 历史画像支持按 sessionId 查询<br>□ attitudePreference 持久化 |
| 依据 | 规格 §4.4（画像增强） |

#### C-2 [P1-8] 右侧栏"进步摘要"卡片

| 属性 | 值 |
|:-----|:-----|
| 前置 | B-2（进度数据就绪）、P0-6 ✅（useRightPanel 就绪） |
| 目标 | 右侧栏新增"进步摘要"工具，展示节拍图表、弱项对比、时序点击展开 |
| 涉及文件 | `ProgressSummary.tsx`（新）、`ProgressSummary.module.css`（新） |
| DoD | □ 节拍图表（复用 SF-004 BeatCheckChart）<br>□ 弱项对比卡片<br>□ 点击展开详细时间线<br>□ 不暴露诊断原始数据 |
| 依据 | 规格 §4.5（右侧栏用户角） |

#### C-3 [训练反馈回路]（原 P2-2 提级）

| 属性 | 值 |
|:-----|:-----|
| 前置 | A-1（[训练] tab）、P0-2 ✅（progress.store） |
| 目标 | 训练完成后自动更新进度（resolvedIssues++ / totalIssues 不变） |
| 涉及文件 | `training.service.ts`（改）、`progress.store.ts`（改） |
| DoD | □ 完成训练 session → 进度更新<br>□ 不重新计算 totalIssues |
| 依据 | 规格 §4.6（训练三层体系中的 L3） |

---

### Phase D：增强与打磨

#### D-1 [P2-1] LearningLogPanel

| 属性 | 值 |
|:-----|:-----|
| 前置 | B-2（进度数据存在）、P0-6 ✅（useRightPanel） |
| 目标 | 右侧栏"学习日志"工具，展示用户完成的教学项、掌握度变化 |
| 涉及文件 | `LearningLogPanel.tsx`（新） |
| DoD | □ 按时间倒序排列<br>□ 每个条目显示技法名 + 完成状态 + 时间<br>□ 点击跳转到对应会话 |
| 依据 | 规格 §4.6（右侧栏进阶） |

#### D-2 [P2-3] IPC 错误处理 + 骨架屏

| 属性 | 值 |
|:-----|:-----|
| 前置 | 无（可随时做） |
| 目标 | IPC invoke 统一 try/catch 包裹，失败时静默展示；左侧栏 + 右侧栏骨架屏 |
| 涉及文件 | `utils/ipc.ts`（改）、各组件 |
| DoD | □ IPC 调用失败不弹窗<br>□ 错误在内容区展示<br>□ 左侧栏列表 + 右侧栏工具有 skeleton |
| 依据 | 规格 §13.5 |

#### D-3 [P2-4] 空状态全覆盖 + placeholder 轮换

| 属性 | 值 |
|:-----|:-----|
| 前置 | 无（可随时做） |
| 目标 | 所有面板的空状态 + 输入框 placeholder 随机轮换 |
| 涉及文件 | `WelcomeCard`、`SessionList`、`WorkTreePanel` 等 |
| DoD | □ 无会话 → 空状态<br>□ 无项目 → 空状态<br>□ 输入框 placeholder 随机轮换 |
| 依据 | 规格 §7（空状态设计） |

---

### Phase E：调研与收尾

#### E-1 [P3-5] 外部项目代码研究

| 属性 | 值 |
|:-----|:-----|
| 前置 | 无（可随时做，建议在 E 阶段） |
| 目标 | Clone 并研读 6 个外部项目，输出可落地模式参考 |
| 研究范围 | **代码级**：InkOS（状态机+真相文件）、OpenWrite（Codex UI+项目管理）、Letta（记忆调度）<br>**产品级**：91Writing（提示词库+进度可视化）、SoloEnt（故事宪法）<br>**论文级**：CoachGPT（Scaffolding 教学）、Khan Academy WC |
| DoD | □ InkOS Truth File 实现报告<br>□ OpenWrite Codex 组件树报告<br>□ Letta 记忆调度分析<br>□ 其他项目产品级参考笔记 |
| 依据 | 规格 §附录B、附录C、决策日志 Letta 记录 |

#### E-2 [P3-1] 文件上传 + 分章

| 属性 | 值 |
|:-----|:-----|
| 前置 | P0-4 ✅（项目 IPC 就绪） |
| 目标 | 用户上传文件（txt/docx）自动导入为作品、插入分章 IPC 失败路径 |
| 涉及文件 | 文件选择器组件 + IPC 通道 |
| DoD | □ 支持 txt/docx 上传<br>□ 上传后自动创建项目章节<br>□ 失败时静默提示 |
| 依据 | 规格 §7（文件上传） |

#### E-3 [P3-2~4] 全局清理与遗留评估

| 属性 | 值 |
|:-----|:-----|
| 前置 | 全部 A~D 完成 |
| 目标 | TypeScript 全局清理（as / ts-ignore）、旧待定任务决策（SKILL/DIST/INFRA）、V4 评估 |
| 涉及文件 | 全局 |
| DoD | □ 所有 `as` 断言清理（除 DOM API）<br>□ 旧待定任务标记为保留/关闭/外迁<br>□ 决策日志中有记录 |
| 依据 | R-019、决策日志 |

#### E-4 [P3-6] 全链路验收测试

| 属性 | 值 |
|:-----|:-----|
| 前置 | 全部 E-1~E-3 完成 |
| 目标 | 验证完整教学闭环：对话→诊断→教学→训练→验证 |
| DoD | □ `npm run gate` 全绿<br>□ 教学闭环可走通<br>□ 进度一致性验收<br>□ 数据迁移验收<br>□ IPC 失败降级验收<br>□ 加载态覆盖验收 |
| 依据 | 规格 §15（验收标准） |

---

## 三、依赖图

```
Phase A ─── Phase B ─── Phase C ─── Phase D ─── Phase E
  │            │            │            │            │
  A-1          B-1          C-1          D-1          E-1 (独立)
  │            │            │            │            │
  A-2 ──── B-2 ──┬─── C-2   D-2 (独立)  E-2
                  │         D-3 (独立)  │
                  └─── C-3              E-3
                                       │
                                       E-4
```

---

## 四、执行纪律

1. **先读规格再动手** — 每个 Phase 开始前，重读 `system-rewrite-spec.md` 对应章节
2. **不跳步** — A 未完成不进入 B，B 未完成不进入 C
3. **不顺手改无关文件** — R-021 约束
4. **交付前跑门禁** — `npm run gate`（typecheck + test + lint）
5. **失败回退** — 一个任务超过 2 小时或遇到阻塞，停手问用户
6. **完成标记** — 每个 DoD 项目打 ✅ 后，更新 TASK-CHAIN.md + TASK-TABLE.md 状态

---

## 五、引用索引

| 引用文件 | 用途 |
|:---------|:-----|
| `dev-docs/designs/2026-06-17-system-rewrite-spec.md` | 设计权威来源，所有实现以此为准 |
| `docs/tasks/TASK-CHAIN.md` | 全景依赖图 + 历史已完成任务 |
| `docs/tasks/TASK-TABLE.md` | 优先级总表 + 状态追踪 |
| `docs/tasks/REWRITE-TASK-DETAILS.md` | 每个任务的详细目标/DoD/涉及文件 |
| `docs/decision-log.md` | 关键决策历史 |
| `AGENTS.md` | 项目规则入口 |
