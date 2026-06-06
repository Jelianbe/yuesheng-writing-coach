# 月笙写作教练 - 前端设计规范 V2.0

## 1. 设计哲学

### 1.1 核心理念
- **简约现代**：去除视觉噪音，让内容成为焦点
- **浅色系主导**：明亮、清爽的配色方案，降低视觉疲劳
- **柔和曲线**：大量使用圆角设计，营造温和、专业的氛围
- **清晰层次**：通过留白、色彩、尺寸建立明确的信息层级

### 1.2 设计原则
1. **内容优先**：界面元素服务于内容展示，不喧宾夺主
2. **一致性**：统一的间距、圆角、色彩系统
3. **响应式**：适配桌面端、平板、移动端
4. **可访问性**：符合 WCAG 2.1 AA 标准

---

## 2. 色彩系统

### 2.1 主色调（浅色方案）

| 色彩变量 | 色值 | 用途 |
|---------|------|------|
| `--bg-primary` | `#F8F9FA` | 主背景色 |
| `--bg-secondary` | `#FFFFFF` | 卡片、面板背景 |
| `--bg-tertiary` | `#F1F3F5` | 悬停、选中状态 |
| `--bg-hover` | `#E9ECEF` | 交互悬停 |
| `--border-color` | `#DEE2E6` | 边框、分割线 |

### 2.2 强调色

| 色彩变量 | 色值 | 用途 |
|---------|------|------|
| `--accent-primary` | `#4C6EF5` | 主操作按钮、链接 |
| `--accent-secondary` | `#20C997` | 成功状态、正面反馈 |
| `--accent-warning` | `#FAB005` | 警告、中等严重度 |
| `--accent-danger` | `#FA5252` | 错误、高严重度 |
| `--accent-info` | `#228BE6` | 信息提示 |

### 2.3 文字色

| 色彩变量 | 色值 | 用途 |
|---------|------|------|
| `--text-primary` | `#212529` | 主要文字 |
| `--text-secondary` | `#495057` | 次要文字 |
| `--text-muted` | `#868E96` | 辅助文字、占位符 |
| `--text-inverse` | `#FFFFFF` | 深色背景上的文字 |

---

## 3. 排版系统

### 3.1 字体族

```css
--font-sans: 'Inter', 'Noto Sans SC', -apple-system, BlinkMacSystemFont, sans-serif;
--font-serif: 'Noto Serif SC', 'Source Han Serif SC', serif;
--font-mono: 'JetBrains Mono', 'Fira Code', monospace;
```

### 3.2 字号比例

| 级别 | 字号 | 行高 | 字重 | 用途 |
|-----|------|------|------|------|
| H1 | 24px | 1.3 | 600 | 页面标题 |
| H2 | 20px | 1.3 | 600 | 区块标题 |
| H3 | 16px | 1.4 | 500 | 卡片标题 |
| Body | 14px | 1.6 | 400 | 正文内容 |
| Small | 12px | 1.5 | 400 | 辅助信息 |
| Tiny | 11px | 1.4 | 400 | 标签、徽章 |

---

## 4. 间距系统

基于 4px 基础单位的间距比例：

| 变量 | 值 | 用途 |
|-----|-----|------|
| `--space-1` | 4px | 紧凑元素间距 |
| `--space-2` | 8px | 元素内部间距 |
| `--space-3` | 12px | 相关元素间距 |
| `--space-4` | 16px | 标准间距 |
| `--space-5` | 24px | 区块间距 |
| `--space-6` | 32px | 大区块间距 |
| `--space-8` | 48px | 页面边距 |

---

## 5. 圆角系统

| 变量 | 值 | 用途 |
|-----|-----|------|
| `--radius-sm` | 6px | 小元素（按钮、标签） |
| `--radius-md` | 10px | 卡片、输入框 |
| `--radius-lg` | 16px | 面板、模态框 |
| `--radius-xl` | 24px | 大容器 |
| `--radius-full` | 9999px | 圆形、药丸形 |

---

## 6. 阴影系统

```css
--shadow-sm: 0 1px 2px rgba(0, 0, 0, 0.05);
--shadow-md: 0 4px 6px -1px rgba(0, 0, 0, 0.1), 0 2px 4px -1px rgba(0, 0, 0, 0.06);
--shadow-lg: 0 10px 15px -3px rgba(0, 0, 0, 0.1), 0 4px 6px -2px rgba(0, 0, 0, 0.05);
--shadow-xl: 0 20px 25px -5px rgba(0, 0, 0, 0.1), 0 10px 10px -5px rgba(0, 0, 0, 0.04);
```

---

## 7. 组件库

### 7.1 按钮

| 类型 | 样式 | 用途 |
|-----|------|------|
| Primary | 蓝色背景，白字，圆角 | 主要操作 |
| Secondary | 浅灰背景，深灰字 | 次要操作 |
| Ghost | 透明背景，悬停变色 | 辅助操作 |
| Icon | 仅图标，圆形 | 工具栏操作 |

### 7.2 卡片

- 白色背景
- 圆角 10px
- 轻微阴影
- 悬停时阴影加深

### 7.3 输入框

- 圆角 10px
- 浅灰边框
- 聚焦时蓝色边框 + 阴影
- 支持多行文本

### 7.4 消息气泡

- 用户消息：蓝色背景，白字，右下角尖角
- AI 消息：白色背景，深灰字，左下角尖角
- 最大宽度 70%
- 圆角 12px

### 7.5 徽章/标签

- 药丸形状
- 小字号
- 不同颜色表示不同状态

---

## 8. 交互模式

### 8.1 状态反馈

| 状态 | 反馈方式 |
|-----|---------|
| 加载中 | 骨架屏 + 脉冲动画 |
| 成功 | 绿色提示 + 淡出 |
| 错误 | 红色提示 + 抖动动画 |
| 空状态 | 图标 + 说明文字 |

### 8.2 过渡动画

| 类型 | 时长 | 缓动函数 |
|-----|------|---------|
| 淡入淡出 | 200ms | ease-in-out |
| 滑入滑出 | 300ms | cubic-bezier(0.4, 0, 0.2, 1) |
| 缩放 | 150ms | ease-out |

### 8.3 手势支持

- 侧边栏滑动收起/展开
- 面板拖拽调整宽度
- 长按显示操作菜单

---

## 9. 响应式断点

| 断点 | 宽度 | 适配设备 |
|-----|------|---------|
| sm | 640px | 手机竖屏 |
| md | 768px | 手机横屏 |
| lg | 1024px | 平板 |
| xl | 1280px | 桌面 |
| 2xl | 1536px | 大桌面 |

---

## 10. 可访问性标准

### 10.1 WCAG 2.1 AA 合规

- 对比度 ≥ 4.5:1（正常文字）
- 对比度 ≥ 3:1（大文字）
- 键盘导航支持
- 屏幕阅读器兼容
- 焦点可见指示器

### 10.2 ARIA 标签

所有交互元素必须有明确的 ARIA 标签和角色定义。

---

## 11. 文件结构

```
src/renderer/
├── App.tsx                      # 根组件
├── main.tsx                     # 入口文件
├── styles/
│   ├── globals.css             # 全局样式
│   ├── variables.css           # CSS 变量
│   └── animations.css          # 动画定义
├── components/
│   ├── layout/                 # 布局组件
│   │   ├── AppHeader.tsx       # 顶部栏
│   │   ├── Sidebar.tsx         # 侧边栏
│   │   └── MainContent.tsx     # 主内容区
│   ├── pages/                  # 页面组件
│   │   ├── ChatPage.tsx        # 聊天页面
│   │   ├── TasksPage.tsx       # 训练任务页面
│   │   └── ConfigPage.tsx      # 配置页面
│   ├── panels/                 # 面板组件
│   │   ├── DiagnosisPanel.tsx  # 诊断面板
│   │   └── TeachingProgressPanel.tsx  # 教学进度面板
│   ├── chat/                   # 聊天相关组件
│   │   ├── MessageBubble.tsx   # 消息气泡
│   │   ├── MessageInput.tsx    # 消息输入框
│   │   └── TypingIndicator.tsx # 打字指示器
│   ├── tasks/                  # 任务相关组件
│   │   ├── TaskCard.tsx        # 任务卡片
│   │   └── TaskFilter.tsx      # 任务筛选器
│   └── common/                 # 公共组件
│       ├── Button.tsx          # 按钮
│       ├── Card.tsx            # 卡片
│       ├── Badge.tsx           # 徽章
│       ├── EmptyState.tsx      # 空状态
│       └── LoadingSkeleton.tsx # 加载骨架
├── stores/                     # 状态管理
│   ├── config.store.ts         # 配置 Store
│   ├── chat.store.ts           # 聊天 Store
│   ├── session.store.ts        # 会话 Store
│   ├── diag.store.ts           # 诊断 Store
│   ├── teaching-state.store.ts # 教学状态 Store
│   └── task.store.ts           # 任务 Store
└── shared/                     # 共享资源
    ├── types.ts                # 类型定义
    ├── constants.ts            # 常量
    └── utils.ts                # 工具函数
```

---

## 12. 技术实现指南

### 12.1 React 组件规范

```tsx
// 组件模板
import React from 'react';

interface ComponentProps {
  /** 属性描述 */
  propName: string;
}

export const ComponentName: React.FC<ComponentProps> = ({ propName }) => {
  return (
    <div className="component-class">
      {/* 组件内容 */}
    </div>
  );
};
```

### 12.2 Zustand Store 规范

```typescript
import { create } from 'zustand';

interface StoreState {
  // 状态
  value: string;
  // 动作
  setValue: (value: string) => void;
}

export const useStore = create<StoreState>((set) => ({
  value: '',
  setValue: (value) => set({ value }),
}));

// 选择器
export const selectValue = (state: StoreState) => state.value;
```

### 12.3 IPC 调用规范

```typescript
// 前端调用示例
const result = await window.electronAPI.invoke('channel:name', payload);

// 错误处理
try {
  const result = await window.electronAPI.invoke('channel:name', payload);
  // 处理成功
} catch (error) {
  // 处理错误
  console.error('IPC调用失败:', error);
}
```

### 12.4 样式编写规范

- 使用 Tailwind CSS 工具类
- 复杂样式使用 CSS Modules
- CSS 变量用于主题定制
- 响应式使用 Tailwind 断点前缀

---

## 13. 兼容性说明

### 13.1 后端 API 接口兼容

新前端完全兼容现有 IPC 通道定义：

| 通道名 | 类型 | 用途 |
|-------|------|------|
| `config:get` | invoke | 获取配置 |
| `config:save` | invoke | 保存配置 |
| `config:test` | invoke | 测试连接 |
| `chat:send` | invoke | 发送消息 |
| `chat:stop` | invoke | 停止生成 |
| `session:list` | invoke | 获取会话列表 |
| `session:create` | invoke | 创建新会话 |
| `session:load` | invoke | 加载会话 |
| `session:delete` | invoke | 删除会话 |
| `teachingState:get` | invoke | 获取教学状态 |
| `teachingState:update` | invoke | 更新教学状态 |
| `teachingState:confirm` | invoke | 确认教学动作 |
| `task:list` | invoke | 获取任务列表 |
| `task:getProgress` | invoke | 获取任务进度 |

### 13.2 数据类型兼容

所有组件使用 `shared/types.ts` 中定义的类型，确保与后端数据格式完全一致。

---

## 变更记录

| 日期 | 版本 | 变更内容 | 变更人 |
|------|------|---------|--------|
| 2026-06-02 | V2.0 | 初始设计规范，基于参考模板重新设计 | AI Assistant |
