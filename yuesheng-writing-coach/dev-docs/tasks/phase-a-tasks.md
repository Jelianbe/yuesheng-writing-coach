# Phase A — 移动端 V1 数据对接 任务清单

> Issue: Sprint 18 Phase A
> Sprint: sprint-18
> 状态: ✅ **Done** (2026-07-02)

---

## 任务 1：AppShell 响应式布局

**核心目标**：< 768px 时三栏 → 单栏 + 双侧抽屉

### 改动文件
| 文件 | 改动 |
|:-----|:-----|
| `src/renderer/styles/variables.css` | 新增 `--breakpoint-mobile: 768px`、`--sidebar-mobile-width: 100vw` 变量 |
| `src/renderer/components/appshell/index.module.css` | 追加 @media (max-width: 768px) 规则 |
| `src/renderer/components/appshell/index.tsx` | 新增 `isMobile` 状态 + 抽屉 overlay 逻辑 |

### 实现要点
1. **CSS 断点规则**：
   - `.root` 在移动端向下堆叠（flex-col）
   - 左栏/右栏变为 fixed overlay，默认隐藏，通过 `data-open` 控制显示
   - 中央区域 `.main` 占满全宽
   - bottom bar 固定在底部
2. **TSX 逻辑**：
   - `useEffect` 监听 `window.innerWidth`，小于 768px 设 `isMobile=true`
   - `isMobile` 时，左栏/右栏渲染为 overlay `<div>` + 遮罩层
   - 遮罩层点击关闭抽屉
   - 标题栏右侧添加「菜单」和「工具」按钮，控制抽屉开关
3. **现有功能零影响**：桌面端行为不变，断点检测只在 resize 时触发

### 验收标准
- [x] 桌面端（> 768px）布局完全不变
- [x] 移动端（< 768px）单栏聊天，左右抽屉可滑动/点击打开
- [x] 遮罩层点击关闭抽屉
- [x] 横竖屏切换正常

---

## 任务 2：MessageBubble 意图样式

**核心目标**：5 类意图气泡差异化展示

### 改动文件
| 文件 | 改动 |
|:-----|:-----|
| `src/renderer/components/chat/MessageBubble.tsx` | 新增 `intent?: IntentType` prop + 样式映射 |
| `src/renderer/shared/types-chat.ts` | 新增 `IntentType` + 消息 `intent` 字段 |

### 实现要点
1. **意图 → 配色映射**：

| 意图 | 底色 | 标签 |
|:-----|:-----|:-----|
| diagnose | `#E8F4F8`（浅蓝） | 12px 灰色「诊断」标签 |
| learn | `#F0F9F0`（淡绿） | 12px 灰色「学习」标签 |
| train | `#FFF7E6`（暖黄） | 12px 灰色「训练」标签 |
| review | `#F5F3FF`（淡紫） | 12px 灰色「复盘」标签 |
| general_chat | 不变（纯白） | 无标签 |

2. **折叠展开**：diagnose 诊断结果默认折叠为 2 行，点击展开
3. **移动端适配**：气泡宽度 `max-width: 85%`（移动端）/ `70%`（桌面）
4. **传递链路**：ChatOrchestrator → ChatView → MessageList → MessageBubble，（通过 `RouteResult` 中的 intent 字段）

### 验收标准
- [x] 5 类意图的气泡底色正确区分
- [x] 标签只在第一条连续同意图消息显示
- [x] 折叠展开正常
- [x] 桌面端/移动端视觉一致

---

## 任务 3：移动端加载反馈

**核心目标**：LLM 分类中 + 意图切换 + 降级提示

### 改动文件
| 文件 | 改动 |
|:-----|:-----|
| `src/renderer/components/chat/TypingIndicator.tsx` | 新增骨架屏形态（移动端） |
| `src/renderer/components/chat/ChatView.tsx` | 新增意图切换 Toast |

### 实现要点
1. **骨架屏**：
   - 现有 TypingIndicator（三点脉冲动画）保持不变
   - 新增 `skeleton` prop，启用时显示 3 行灰色占位条 + 闪烁动画
   - 仅在移动端且 LLM 分类等待时显示
2. **意图切换 Toast**：
   - 从 messages 监听 intent 变化（对比 lastIntentRef）
   - 检测到意图切换时，弹出 30px 半透明 Toast，1.5s 自动消失
   - 文案：「已切换到 XX 模式」
3. **降级提示**：
   - MessageBubble 新增 `degraded` prop
   - 低置信度降级时，回复末尾追加 12px 灰色小字提示
   - 仅在移动端显示（CSS 媒体查询就绪）

### 验收标准
- [x] 骨架屏 `skeleton` prop 开发完成
- [x] 意图切换 Toast 弹出和消失时机正确
- [ ] 降级提示显示但不突兀（等待后端传入 degraded 信号）

---

## 任务 4：底部输入栏热区适配

**核心目标**：移动端输入体验

### 改动文件
| 文件 | 改动 |
|:-----|:-----|
| `src/renderer/components/chat/ChatView.tsx` | 输入框区域添加 `mobile` class |
| `src/renderer/components/chat/CenterPanel` 相关 | 输入框 min-height / padding 调整 |

### 实现要点
1. **触控热区**：所有可点击元素最小 44×44px（templateBtn / lockBtn / sendBtn / attDot 全部加 mobile class）
2. **软键盘适配**：使用 `visualViewport` API 监听 resize，footer 随键盘上推
3. **发送按钮**：固定在输入框右下角，44×44px，font-size 14px
4. **iOS 防缩放**：textarea font-size: 16px（iOS 自动缩放保护）
5. **桌面端**：不变

### 验收标准
- [x] 输入框/按钮触控热区 ≥ 44px
- [x] 软键盘弹出时输入框可见
- [x] 桌面端布局不受影响

---

## 门禁检查清单

```
每次 Build 任务完成后执行：
□ npm run typecheck  — 零错误
□ npm run test       — 全绿
□ npm run lint       — 无新增 error/warning
```

## 交付物

- [ ] Issue #35 所有 DoD 勾选完成
- [ ] GH-35 分支 → PR → merge
- [ ] dev-docs/designs/phase-a-mobile-v1.md 设计文档
- [ ] docs/decision-log.md 复盘记录
