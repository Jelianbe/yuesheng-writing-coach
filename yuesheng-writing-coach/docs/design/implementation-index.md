# 月笙写作教练 V2.0 - 前端实现索引

## 概述

本文档是月笙写作教练前端 V2.0 版本的完整实现索引。基于全新的设计系统（浅色系、柔和曲线、现代简约风格），所有组件均为重新实现，非对现有代码的修改。

---

## 文件清单

### 样式文件（3 个）

| 文件路径 | 说明 |
|---------|------|
| `src/renderer/styles/variables.css` | CSS 变量定义（颜色、字体、间距、圆角、阴影、过渡） |
| `src/renderer/styles/globals.css` | 全局样式（Tailwind 指令、滚动条、动画、Markdown 渲染样式） |
| `tailwind.config.js` | Tailwind CSS 配置扩展（自定义颜色、字体、圆角、阴影） |

### 公共组件（4 个）

| 文件路径 | 说明 | Props 接口 |
|---------|------|-----------|
| `src/renderer/components/common/Button.tsx` | 可复用按钮，5 种变体、3 种尺寸、loading 状态 | `ButtonProps` |
| `src/renderer/components/common/Card.tsx` | 卡片容器，hover 阴影加深、键盘可访问 | `CardProps` |
| `src/renderer/components/common/Badge.tsx` | 徽章/标签，6 种颜色变体 | `BadgeProps` |
| `src/renderer/components/common/EmptyState.tsx` | 空状态展示，支持自定义图标和描述 | `EmptyStateProps` |

### 布局组件（2 个）

| 文件路径 | 说明 | 依赖 Store |
|---------|------|-----------|
| `src/renderer/components/layout/AppHeader.tsx` | 顶部栏：Logo、态度选择器、面板切换、设置按钮 | config.store |
| `src/renderer/components/layout/Sidebar.tsx` | 可折叠侧边栏：页签切换、会话搜索、会话列表 | session.store, config.store |

### 聊天组件（3 个）

| 文件路径 | 说明 | 依赖 |
|---------|------|------|
| `src/renderer/components/chat/MessageBubble.tsx` | 消息气泡：用户/AI 不同样式、Markdown 渲染、诊断标签 | react-markdown |
| `src/renderer/components/chat/MessageInput.tsx` | 消息输入框：自动高度、发送/停止按钮切换 | electronAPI |
| `src/renderer/components/chat/TypingIndicator.tsx` | 打字动画指示器：三圆点弹跳 | 纯 CSS 动画 |

### 面板组件（2 个）

| 文件路径 | 说明 | 依赖 Store |
|---------|------|-----------|
| `src/renderer/components/panels/DiagnosisPanel.tsx` | 诊断面板：症候列表、严重度、证据片段、建议动作 | diag.store |
| `src/renderer/components/panels/TeachingProgressPanel.tsx` | 教学进度面板：阶段进度条、活跃问题、下一步建议 | teaching-state.store |

### 页面组件（3 个）

| 文件路径 | 说明 | 依赖 Store |
|---------|------|-----------|
| `src/renderer/components/pages/ChatPage.tsx` | 聊天页面：消息列表、自动滚动、空状态 | chat.store, session.store |
| `src/renderer/components/pages/TasksPage.tsx` | 训练任务页面：统计卡片、任务列表、问题标签筛选 | task.store |
| `src/renderer/components/pages/ConfigPage.tsx` | 配置页面：API 表单、连接测试、字段校验 | config.store |

### 根组件（1 个）

| 文件路径 | 说明 | 依赖 |
|---------|------|------|
| `src/renderer/App.tsx` | 根组件：组装所有子组件、IPC 事件监听、Store 集成 | 全部 Store |

---

## 设计系统

### 色彩

```
主背景：#F8F9FA（浅灰）
卡片背景：#FFFFFF（纯白）
强调色：#4C6EF5（靛蓝）
成功色：#20C997（薄荷绿）
警告色：#FAB005（琥珀）
危险色：#FA5252（珊瑚红）
```

### 圆角

```
sm: 6px（小元素）
md: 10px（卡片、输入框）
lg: 16px（面板）
xl: 24px（大容器）
```

### 阴影

```
sm: 0 1px 2px rgba(0,0,0,0.05)
md: 0 4px 6px -1px rgba(0,0,0,0.1)
lg: 0 10px 15px -3px rgba(0,0,0,0.1)
```

### 字体

```
Sans: Inter, Noto Sans SC
Serif: Noto Serif SC
Mono: JetBrains Mono
```

---

## IPC 通道兼容性

新前端完全兼容现有后端 IPC 通道：

| 通道名 | 用途 | 使用组件 |
|-------|------|---------|
| `config:get` | 获取配置 | AppHeader, ConfigPage |
| `config:save` | 保存配置 | ConfigPage |
| `config:test` | 测试连接 | ConfigPage |
| `chat:send` | 发送消息 | MessageInput |
| `chat:stop` | 停止生成 | MessageInput |
| `session:list` | 获取会话列表 | Sidebar |
| `session:create` | 创建新会话 | Sidebar |
| `session:load` | 加载会话 | Sidebar |
| `teachingState:get` | 获取教学状态 | TeachingProgressPanel |
| `teachingState:confirm` | 确认教学动作 | TeachingProgressPanel |

---

## 状态管理

### Store 列表

| Store | 文件 | 管理的状态 |
|-------|------|-----------|
| config.store | config.store.ts | API 配置、态度档位 |
| chat.store | chat.store.ts | 消息列表、加载状态 |
| session.store | session.store.ts | 会话列表、当前会话 |
| diag.store | diag.store.ts | 诊断结果、置信度 |
| teaching-state.store | teaching-state.store.ts | 教学进度、活跃问题 |
| task.store | task.store.ts | 任务列表、完成状态 |

### 使用模式

```typescript
// 选择器模式（推荐）
import { useConfigStore, selectAttitudeLevel } from '../stores/config.store';

const attitudeLevel = useConfigStore(selectAttitudeLevel);

// 直接使用（适用于需要调用 actions 的场景）
const { setAttitudeLevel } = useConfigStore();
```

---

## 构建与运行

```bash
# 开发模式
npm run dev

# 类型检查
npm run typecheck

# 构建
npm run build
```

---

## 设计规范参考

完整设计规范文档：[design-specification.md](file:///D:/ai-teacher/yuesheng-writing-coach/docs/design/design-specification.md)

---

## 变更记录

| 日期 | 版本 | 变更内容 | 变更人 |
|------|------|---------|--------|
| 2026-06-02 | V2.0 | 全新前端设计实现，18 个新组件文件 | AI Assistant |
