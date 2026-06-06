# 月笙前端再设计实施计划 V1

> **依据**：FRONTEND_REDESIGN_V1.md（设计规格）  
> **关联**：TASK-SEQUENCE_V1.0.md（M-2~M-5）  
> **创建日期**：2026-06-03  
> **总工时预计**：24h  
> **验证方式**：`npm run typecheck` + `npm run dev:vite` 启动

---

## 一、实施阶段总览

```
Phase 1: 样式基础（2h） → CSS 变量 + Tailwind 更新 + 字体 + 动画
    │
Phase 2: 布局壳（4h） → AppShell + AppHeader + AppSidebar
    │
Phase 3: 聊天组件（4h） → MessageBubble + MessageInput + MessageList
    │
Phase 4: MVP 功能组件（8h） → DiagnosisCard + EditPanel + EvaluationCard + GrowthCard
    │
Phase 5: 侧栏面板（2h） → TeachingProgress + 成长卡片
    │
Phase 6: 集成（4h） → App.tsx 重构 + IPC 对接 + 空状态 + 响应式
```

---

## 二、Phase 1：样式基础（2h）

### 任务
| # | 文件 | 操作 | 工时 |
|---|------|------|------|
| 1.1 | `styles/variables.css` | 新建：依据 FRONTEND_REDESIGN_V1.md 第2-4章定义 CSS 变量（色彩/字体/间距/圆角/阴影） | 0.5h |
| 1.2 | `tailwind.config.js` | 更新：匹配新的 CSS 变量名 | 0.5h |
| 1.3 | `styles/globals.css` | 更新：添加新的动效、滚动条样式、排版样式 | 0.5h |
| 1.4 | `styles/animations.css` | 新建：微交互动效定义 | 0.5h |

### DoD
- [ ] `npm run typecheck` 零错误
- [ ] 页面加载时 CSS 变量正确生效
- [ ] 所有圆角无直角（>=8px）

---

## 三、Phase 2：布局壳（4h）

### 任务
| # | 文件 | 操作 | 工时 |
|---|------|------|------|
| 2.1 | `components/layout/AppShell.tsx` | 新建：整体布局容器，响应式三栏结构 | 1h |
| 2.2 | `components/layout/AppHeader.tsx` | 重构：新品牌色、柔和圆角、态度选择器优化 | 1h |
| 2.3 | `components/layout/AppSidebar.tsx` | 新建：基于现有 Sidebar 重构，增加功能区图标+文字组合 | 1.5h |
| 2.4 | `components/common/Button.tsx` | 重构：新变体（primary/secondary/ghost/danger）+ 微动效 | 0.5h |

### 结构图
```
AppShell
├── AppHeader (48px, 品牌色 Logo + 态度档位 + 设置)
├── AppSidebar (280px, 功能区 + 会话列表)
└── Main Content (flex-1, Chat 流)
```

### DoD
- [ ] 三栏布局正确渲染
- [ ] Sidebar 响应式折叠（768px/1024px 断点）
- [ ] Header 高度固定 48px

---

## 四、Phase 3：聊天组件（4h）

### 任务
| # | 文件 | 操作 | 工时 |
|---|------|------|------|
| 3.1 | `components/chat/MessageBubble.tsx` | 重构：新样式（用户右/月笙左/系统居中）+ 圆角规则 + 微动效 | 1h |
| 3.2 | `components/chat/MessageList.tsx` | 新建：消息列表容器，自动滚动到最新，空状态 | 1h |
| 3.3 | `components/chat/MessageInput.tsx` | 重构：新样式 + 聚焦发光 + 发送按钮 | 1h |
| 3.4 | `components/chat/TypingIndicator.tsx` | 重构：新的动画点样式 | 0.5h |
| 3.5 | `components/common/EmptyState.tsx` | 重构：多种空状态场景支持 | 0.5h |

### 消息气泡样式
| 类型 | 对齐 | 背景 | 圆角 |
|------|------|------|------|
| 用户 | 右 | `--color-accent` | `--radius-lg`（右下 `--radius-sm`）|
| 月笙 | 左 | `--surface-secondary` | `--radius-lg`（左下 `--radius-sm`）|
| 系统 | 居中 | 无背景 | 居中文字 |

### DoD
- [ ] 消息发送和接收正常
- [ ] 自动滚动到最新消息
- [ ] 打字指示器动画正常

---

## 五、Phase 4：MVP 功能组件（8h）

### 任务
| # | 文件 | 操作 | 工时 |
|---|------|------|------|
| 4.1 | `components/diagnosis/DiagnosisCard.tsx` | 新建：折叠诊断卡片，默认显示摘要，点击展开详情 | 2h |
| 4.2 | `components/diagnosis/EditPanel.tsx` | 新建：内联编辑区，原文只读 + 修改可编辑 | 1.5h |
| 4.3 | `components/diagnosis/EvaluationCard.tsx` | 新建：AI 评估结果卡片，状态标签 + 对比视图 | 1.5h |
| 4.4 | `components/diagnosis/GrowthCard.tsx` | 新建：一句话成长记录卡片 | 1h |
| 4.5 | `hooks/useDiagnosisFlow.ts` | 新建：诊断→修改→评估 流程 hook | 1h |
| 4.6 | `components/common/Badge.tsx` | 重构：新变体（accent/success/warning/error） | 0.5h |
| 4.7 | `components/common/Card.tsx` | 重构：新圆角 + 阴影规则 | 0.5h |

### 诊断→修改→评估 流程
```
用户点击"定位根因" → DiagnosisCard 展开
  → 用户点击"尝试修改" → EditPanel 内联展开
  → 用户修改后提交 → EvaluationCard 作为新消息显示
  → GrowthCard 显示进步摘要
```

### DoD
- [ ] DiagnosisCard 默认折叠，点击后展开
- [ ] EditPanel 原文只读，编辑区可写
- [ ] EvaluationCard 显示 ✅/⚠️/❌ 状态
- [ ] GrowthCard 从 IPC 获取对比数据

---

## 六、Phase 5：侧栏面板（2h）

### 任务
| # | 文件 | 操作 | 工时 |
|---|------|------|------|
| 5.1 | `components/teaching/TeachingProgress.tsx` | 重构：新样式，进度条 + 聚焦方向选择 | 1h |
| 5.2 | 整合到 AppSidebar | 功能区切换时显示对应面板内容 | 1h |

### DoD
- [ ] 教学进度显示正常
- [ ] 功能区切换时面板内容正确更新

---

## 七、Phase 6：集成（4h）

### 任务
| # | 文件 | 操作 | 工时 |
|---|------|------|------|
| 6.1 | `App.tsx` | 重构：使用 AppShell 新布局，集成所有新组件 | 1.5h |
| 6.2 | `index.html` | 更新：添加 Google Fonts 链接（DM Sans + Noto Sans SC） | 0.5h |
| 6.3 | IPC 集成 | 确保新组件的 IPC 调用与现有后端 channel 匹配 | 1h |
| 6.4 | 响应式测试 | 验证 3 个断点的布局正确性 | 0.5h |
| 6.5 | 类型检查 | `npm run typecheck` 零错误 | 0.5h |

### 现有 IPC 通道清单（复用）
| Channel | 用途 | 对应新组件 |
|---------|------|-----------|
| `chat:send` | 发送消息 | MessageInput |
| `chat:stop` | 停止生成 | MessageInput |
| `chat:stream-data` | 流式接收 | MessageList |
| `chat:stream-end` | 流结束 | MessageList |
| `diagnosis:update` | 诊断更新 | DiagnosisCard |
| `diagnosis:submitRewrite` | 提交修改 | EditPanel |
| `diagnosis:getComparison` | 获取对比 | GrowthCard |
| `teaching:state-updated` | 教学状态 | TeachingProgress |
| `config:test-connection` | 测试连接 | ConfigPage |

### DoD
- [ ] `npm run typecheck` 零错误
- [ ] `npm run dev:vite` 启动正常
- [ ] 所有 IPC 通道正确对接

---

## 八、文件变更清单

### 新建文件
```
src/renderer/styles/variables.css        # CSS 变量（Phase 1）
src/renderer/styles/animations.css       # 动效定义（Phase 1）
src/renderer/components/layout/AppShell.tsx     # 布局壳（Phase 2）
src/renderer/components/layout/AppSidebar.tsx   # 侧边栏重构版（Phase 2）
src/renderer/components/chat/MessageList.tsx    # 消息列表（Phase 3）
src/renderer/components/diagnosis/DiagnosisCard.tsx  # 诊断卡片（Phase 4）
src/renderer/components/diagnosis/EditPanel.tsx      # 修改编辑（Phase 4）
src/renderer/components/diagnosis/EvaluationCard.tsx # 评估卡片（Phase 4）
src/renderer/components/diagnosis/GrowthCard.tsx     # 成长卡片（Phase 4）
src/renderer/hooks/useDiagnosisFlow.ts         # 流程 hook（Phase 4）
src/renderer/components/teaching/TeachingProgress.tsx # 教学进度面板（Phase 5）
```

### 修改文件
```
src/renderer/styles/globals.css          # 更新动效+排版（Phase 1）
tailwind.config.js                       # 更新 CSS 变量名（Phase 1）
src/renderer/components/layout/AppHeader.tsx  # 重构样式（Phase 2）
src/renderer/components/common/Button.tsx     # 重构（Phase 2）
src/renderer/components/chat/MessageBubble.tsx # 重构（Phase 3）
src/renderer/components/chat/MessageInput.tsx  # 重构（Phase 3）
src/renderer/components/chat/TypingIndicator.tsx # 重构（Phase 3）
src/renderer/components/common/EmptyState.tsx  # 重构（Phase 3）
src/renderer/components/common/Badge.tsx       # 重构（Phase 4）
src/renderer/components/common/Card.tsx        # 重构（Phase 4）
src/renderer/App.tsx                           # 重构（Phase 6）
src/renderer/index.html                        # 添加字体链接（Phase 6）
```

---

## 九、验证清单

```
Phase 1: 样式基础
□ CSS 变量在浏览器中正确加载
□ 字体（DM Sans / Noto Sans SC）正确加载
□ 动画关键帧定义完整

Phase 2: 布局壳
□ AppShell 三栏布局渲染正确
□ Header 品牌图标 + 态度选择器
□ Sidebar 功能区切换 + 会话列表
□ 响应式断点（768/1024/1280）正确

Phase 3: 聊天组件
□ 消息气泡样式正确
□ 输入框聚焦发光
□ 自动滚动到最新

Phase 4: MVP 组件
□ 诊断卡片折叠/展开
□ 编辑面板原文+修改区
□ 评估卡片状态标签
□ 成长记录卡片

Phase 5: 侧栏面板
□ 教学进度条
□ 功能区面板切换

Phase 6: 集成
□ typecheck 零错误
□ dev:vite 启动正常
□ IPC 通道对接正确
□ 空状态显示正确
```

---

## 十、变更记录

| 版本 | 日期 | 变更内容 |
|------|------|---------|
| V1.0 | 2026-06-03 | 初始版本：6 阶段前端实施计划 |
