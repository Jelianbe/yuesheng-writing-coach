# RQ-11：前端方案调研 — 可直接执行的提示词

> 安排人做调研时，把这份提示词发给对方即可。

---

## 背景（直接发给调研人员）

我们正在做一个**写作教练 AI 产品**（月笙写作教练），技术栈是 **Electron 28 + React 18 + TypeScript + CSS Modules + Zustand**。目前是纯桌面应用，即将启动移动端（H5/小程序）适配。

我们刚完成了一个意图路由模块（Intent Router），后端能识别 5 类用户意图：**diagnose（诊断）/ learn（学习）/ train（训练）/ review（复盘）/ general_chat（闲聊）**。现在需要确定移动端前端的组件方案。

### 当前前端现状
- **没有使用任何第三方 UI 组件库**——所有 UI 都是手写 CSS Modules
- 样式体系：CSS 变量（design tokens）+ CSS Modules
- 图标库：lucide-react
- 流式响应：通过 Electron IPC 事件通信（非 SSE）
- 聊天 UI：全手写（ChatView / MessageList / MessageBubble / TypingIndicator）
- **移动端支持：零**——纯桌面设计，无响应式断点

### 我们已有的移动端设计
我们有详细的移动端设计文档，包含：
- 5 类意图的气泡样式和交互方案（含色号 #E8F4F8 / #F0F9F0 / #FFF7E6 / #F5F3FF / #F8F8F8）
- 单栏布局（1主聊天 + 2侧抽屉 + 1底部输入栏）
- 意图识别反馈（关键词命中静默 / LLM 分类中加载进度条 / 降级提示）
- 输入侧意图预判、纠错入口、语音输入适配等

---

## 调研目标

回答一个核心问题：**移动端 H5/小程序的前端组件，是继续手写，还是引入组件库？**

因为项目纯桌面端过来的，手写组件在移动端会遇到大量新问题（触摸事件、手势、软键盘、不同屏幕尺寸、加载骨架屏等）。需要调研确定最佳方案。

---

## 调研方向

### 方向 A：继续手写（保持现状 + 扩展移动端）

**要回答的问题：**
1. 手写一套移动端聊天 UI（含 5 种气泡样式、骨架屏、底部浮层、Touch 事件）需要多少工时？
2. 手写能力上有哪些风险？（触摸事件兼容性、无障碍 a11y、软键盘弹出时布局错位）
3. 当前 CSS Modules + design tokens 方案扩展到移动端需要改多少？

**评估标准**：
- 优点：无外部依赖、包体积小、样式完全可控
- 风险：工时大、移动端兼容性需自行处理

### 方向 B：引入轻量移动端组件库

**候选方案**（不要全查，挑 1-2 个重点查）：

| 库 | 为什么值得看 |
|:---|:-------------|
| **Ant Design Mobile** (antd-mobile) | 国内最成熟移动端组件库，教育类 App 常用，有 Skeleton/Steps/Card/Tabs 等配套组件 |
| **Zarm** (有赞出品) | 轻量 React 移动端组件库，适合中后台转移动端场景 |
| **NutUI** (京东出品) | 面向 H5/小程序的 React 组件库，小程序兼容性好 |

**要回答的问题：**
1. 是否有流式聊天气泡组件？没有的话自定义难度？
2. 是否有骨架屏（Skeleton）/ 加载指示器组件？
3. 是否有 Bottom Sheet / Drawer 等移动端常用交互组件？
4. 与现有 CSS Modules 混用是否方便？（会不会有样式冲突）
5. 包体积增加多少？
6. 小程序端是否兼容？（Phase A 有小程序需求）

### 方向 C：引入通用 React 组件库 + 手写适配

**候选方案**：

| 库 | 为什么值得看 |
|:---|:-------------|
| **Radix UI** | 无样式 Headless UI，提供交互原语（Dialog/Popover/Collapsible），样式完全由 CSS Modules 控制，与现有技术栈最匹配 |
| **shadcn/ui** | Radix 上层的预制组件，Copy-paste 模式，不引入额外依赖，样式用 Tailwind 控制 |

**要回答的问题：**
1. Radix/shadcn 提供聊天/消息组件吗？不提供的话手写成本？
2. Radix 的 Dialog（底部浮层）、Collapsible（折叠展开）等原语是否够用？
3. shadcn 的移动端适配度如何？
4. 与现有 CSS Modules 的集成方式？（shadcn 默认用 Tailwind，需要适配）

---

## 具体需要做的调研事项

1. **antd-mobile 组件检查**（1-2 小时）
   - 查看 Skeleton、Steps、Card、Tabs、Drawer、Toast 等组件是否满足需求
   - 检查自定义主题色方案：能否覆盖为我们的设计色号？
   - 注意：antd-mobile 和 antd 是不同库，不要查错

2. **手写移动端成本评估**（1-2 小时）
   - 列出移动端特有但当前手写方案未覆盖的能力清单（Touch 事件、手势滑动、软键盘适配、多屏适配）
   - 结合现有 MessageBubble/MessageList 代码评估改动量
   - ✨ 可以看一下 **Tailwind CSS 的响应式断点**是否比当前硬编码宽度更省力

3. **Radix UI 原语检查**（1 小时）
   - Collapsible（折叠气泡）→ 对应 diagnose 折叠展开
   - Dialog（对话框）→ 对应 Bottom Sheet 浮层
   - Popover（弹出层）→ 对应快捷提问、输入意图图标
   - 注意 Radix 只提供交互逻辑，不提供样式，样式需自行用 CSS Modules 写

4. **如果选择方向 C（Radix + 手写）**，请额外查看**Tailwind CSS 是否有助于减少移动端适配的 CSS 代码量**，并给出对比（用 Tailwind 写需要多少 CSS 类 vs 当前 CSS Modules 方案）。

---

## 最终输出要求

用表格给出结论：

| 方案 | 优点 | 缺点 | 预估工时 | 推荐指数 |
|:-----|:-----|:-----|:---------|:---------|
| A：纯手写 | | | 人天 | ★/★★/★★★ |
| B：antd-mobile | | | 人天 | ★/★★/★★★ |
| C：Radix + 手写 | | | 人天 | ★/★★/★★★ |

**并给出明确的推荐方案和理由。**

---

## 参考信息

### 项目现有文件
- 移动端设计文档：[dev-docs/research/research-requirements-v2.md](file:///d:/ai-teacher/yuesheng-writing-coach/dev-docs/research/research-requirements-v2.md) 第三部分（RQ-11 ~ RQ-13）
- 现有聊天 UI 组件位置：`src/renderer/components/chat/`
- 设计 tokens：`src/renderer/styles/variables.css`
- 包依赖：`package.json`（无 UI 组件库，有 lucide-react / tailwindcss / postcss）

### 相关需求
本调研关联 RQ-11（组件库选型），输出将直接影响移动端 Phase A 的架构决策。

---

*本提示词关联 Issue #34 / sprint-2 / Phase B / intent-router-v1.md*
