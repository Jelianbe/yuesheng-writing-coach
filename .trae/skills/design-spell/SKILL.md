---
name: design-spell
description: 前端设计生成工具。根据需求描述生成高质量、可运行的前端组件和页面，支持 React、Tailwind CSS、现代 CSS 布局。适用于快速原型设计、UI 组件开发、交互效果实现。
---

# Design Spell

## 触发场景
- 用户要求创建前端组件时
- 需要快速原型展示交互时
- 需要设计 UI 界面时
- 需要实现特定视觉效果时
- 需要生成演示页面时

## 设计原则

### 1. 视觉优先
- 生成的代码必须是**可直接运行**的
- 避免占位符和 TODO，提供完整实现
- 每个组件都应该是独立可复用的

### 2. 现代 CSS
- 使用 Tailwind CSS 进行样式设计
- 响应式布局（移动端优先）
- 支持暗色模式
- 使用 CSS 变量管理主题色

### 3. React 最佳实践
- 使用函数组件 + Hooks
- 组件拆分遵循单一职责原则
- 状态管理使用 Zustand（如需要）
- 类型安全的 Props 定义

## 输出规范

### 组件模板
```tsx
import React from 'react';

interface ComponentNameProps {
  // Props 类型定义
}

export const ComponentName: React.FC<ComponentNameProps> = ({ /* props */ }) => {
  return (
    <div className="...">
      {/* 组件内容 */}
    </div>
  );
};
```

### 样式规范
| 类别 | 规则 |
|------|------|
| 颜色 | 使用 Tailwind 语义色（primary, secondary, accent） |
| 间距 | 使用 Tailwind 间距系统（p-4, m-2, gap-3） |
| 字体 | 使用 Tailwind 字体系统（text-sm, font-bold） |
| 响应式 | 使用断点前缀（sm:, md:, lg:, xl:） |
| 动画 | 使用 Tailwind animate 或自定义 CSS transition |

### 文件结构
```
components/
├── ComponentName.tsx          # 主组件
├── ComponentName.stories.tsx  # Storybook 故事（可选）
└── index.ts                   # 导出文件
```

## 工作流程

1. **理解需求**
   - 确认组件功能
   - 确认交互行为
   - 确认视觉风格

2. **设计结构**
   - 确定组件层次
   - 确定状态管理方式
   - 确定 Props 接口

3. **实现代码**
   - 编写 TypeScript 类型
   - 实现组件逻辑
   - 添加样式和动画

4. **验证运行**
   - 确保代码无语法错误
   - 确保类型检查通过
   - 提供运行说明

## 注意事项

- **不生成空壳组件**：每个组件必须有实际功能
- **不硬编码数据**：使用 Props 传递数据，便于复用
- **考虑边界情况**：空状态、加载状态、错误状态
- **保持简洁**：避免过度设计，满足需求即可
- **遵循项目规范**：如果项目已有设计系统，优先使用

## 常用组件模式

| 模式 | 说明 | 适用场景 |
|------|------|---------|
| 卡片 | 信息展示容器 | 文章卡片、产品卡片 |
| 列表 | 数据列表展示 | 消息列表、任务列表 |
| 表单 | 用户输入收集 | 登录表单、配置表单 |
| 模态框 | 弹出层交互 | 确认对话框、详情弹窗 |
| 导航 | 页面导航组件 | 侧边栏、顶部导航 |
| 仪表盘 | 数据可视化展示 | 统计面板、进度展示 |
