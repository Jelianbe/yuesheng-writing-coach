# C-1 Plan: ChatPage 事件响应链路打通

> 依据: Sprint 33 计划 + D-085 评估报告
> 涉及 Issue: [#49](https://github.com/Jelianbe/yuesheng-writing-coach/issues/49)
> 来源: ChatPage.tsx L304-L308 的 `console.log` 占位

## 当前问题

ChatPage 订阅 `chat:event` 后,对 `phase_transition` / `diagnosis_extracted` / `training_triggered` / `intent` 四种事件:

```typescript
if (event.type === 'phase_transition' || ...) {
  console.log('[ChatPage] orchestrator event:', event.type, event.payload);
}
```

不做任何 UI 反馈。用户与 AI 对话时,诊断发生/阶段转换/训练触发都不可见。

## 方案: 系统消息注入 + 内联 UI

### 核心思路

不创建新页面/弹窗,而是在 **消息列表中以系统消息(SystemMessage)形式注入事件反馈**。
这种模式与聊天应用的"系统通知"一致,侵入最小、改动最少。

### 已有可复用资产

| 资产 | 路径 | 状态 |
|:-----|:-----|:-----|
| `FlowPanel` 组件 | `src/renderer/components/training/FlowPanel.tsx` | 完整可用,需外部触发显示 |
| `diag.store.setCurrentDiagnosis()` | `src/renderer/stores/diag.store.ts` | 可用 |
| `teaching-state.store` 系列 action | `src/renderer/stores/teaching-state.store.ts` | 可用 |
| 事件类型定义 | `src/renderer/hooks/useOrchestrator.ts` | 已定义 `OrchestratorEvent` |

### 修改清单

#### 1. ChatPage.tsx 事件处理器

替换 L304-L308 的 `console.log`:

```typescript
// diagnosis_extracted: 注入系统消息 + 诊断摘要
if (event.type === 'diagnosis_extracted') {
  const payload = event.payload as { syndromes: SyndromeResult[]; summary: string };
  const sysMsg: ChatMessage = {
    id: `sys_diag_${Date.now()}`,
    role: 'system',
    contentType: 'diagnosis',
    content: payload.summary || `诊断: 发现 ${payload.syndromes?.length ?? 0} 个症候`,
    metadata: payload,
    timestamp: Date.now(),
  };
  setLocalMessages(prev => [...prev, sysMsg]);
  diagStore.setCurrentDiagnosis(payload);
  return;
}

// phase_transition: 注入系统消息 + 更新副标题
if (event.type === 'phase_transition') {
  const payload = event.payload as { phase: string; transition: string; summary?: string };
  const phaseLabel = PHASE_LABELS[payload.phase as keyof typeof PHASE_LABELS] ?? payload.phase;
  const sysMsg: ChatMessage = {
    id: `sys_phase_${Date.now()}`,
    role: 'system',
    contentType: 'phase',
    content: payload.summary ?? `📋 进入${phaseLabel}`,
    timestamp: Date.now(),
  };
  setLocalMessages(prev => [...prev, sysMsg]);
  setSubtitle(phaseLabel);
  // 可选: 更新 teaching-state store
  return;
}

// training_triggered: 注入带操作按钮的系统消息
if (event.type === 'training_triggered') {
  const payload = event.payload as { trainingSessionId: string; syndromeId: string; tasks: string[] };
  const sysMsg: ChatMessage = {
    id: `sys_train_${Date.now()}`,
    role: 'system',
    contentType: 'training_trigger',
    content: '💪 AI 建议进行专项训练,是否开始？',
    metadata: payload,
    timestamp: Date.now(),
  };
  setLocalMessages(prev => [...prev, sysMsg]);
  // 保存训练会话信息,等待用户点击开始
  pendingTrainingRef.current = payload;
  return;
}
```

#### 2. MessageBubble 组件

新增 `role === 'system'` 分支渲染系统消息:

| `contentType` | 渲染方式 |
|:-------------|:---------|
| `'phase'` | 浅灰色居中横幅,显示阶段名称和摘要 |
| `'diagnosis'` | 浅灰色卡片,左上角「诊断」标签 + 摘要文字 + 症候数量 |
| `'training_trigger'` | 浅灰色卡片 + 「开始训练」按钮 |

#### 3. 新增 state: `subtitle` / `pendingTrainingRef`

- `subtitle`: Navbar 副标题显示当前阶段(默认"教学对话")
- `pendingTrainingRef`: 保存待触发的训练会话,供按钮点击时使用

#### 4. 训练入口激活

当用户点击训练按钮:
- 调用 `activeTrainingService.create(sessionId, phase)`
- 成功后设置 `showTraining = true`
- FlowPanel 已通过 `showTraining && <FlowPanel sessionId={sid} />` 渲染

### 新增 ChatMessage 类型

```typescript
// ChatMessage 需要扩展 role 以支持 system:
type ChatMessageRole = 'user' | 'assistant' | 'system';
// 可选扩展 contentType:
type SystemContentType = 'phase' | 'diagnosis' | 'training_trigger' | undefined;
```

### 改动范围

| 文件 | 改动说明 | 预估行数 |
|:-----|:---------|:--------:|
| `src/renderer/pages/ChatPage.tsx` | 事件处理器 + system message 渲染 + 训练入口 | ~60 行 |
| `src/renderer/shared/types.ts` | 扩展 `ChatMessage` 类型 | ~5 行 |
| `src/renderer/hooks/useOrchestrator.ts` | (无改动,事件类型已定义) | 0 |

### 不做的事

- ❌ 不创建诊断详情页面(后续 Sprint)
- ❌ 不创建阶段转换动画(后续 Sprint)
- ❌ 不修改 FlowPanel 组件逻辑
- ❌ 不修改 orchestrator 事件发射逻辑

### 验收 DoD

- [ ] 发送消息后,AI 回复过程中若触发 `diagnosis_extracted` → 消息列表中出现诊断系统消息
- [ ] 发送消息后,若触发 `phase_transition` → 消息列表中出现阶段转换系统消息,Navbar 副标题更新
- [ ] 发送消息后,若触发 `training_triggered` → 消息列表中出现带「开始训练」按钮的系统消息
- [ ] 点击「开始训练」按钮 → 显示 FlowPanel 训练流
- [ ] 所有事件处理器有 try/catch 保护,异常不阻塞聊天
- [ ] typecheck: 0 error / test: 全绿 / lint: 0 warning
