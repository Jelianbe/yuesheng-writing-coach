# ADR-004: X-02 训练稿写回编辑器协议

> 状态: **提议 (Proposed)** · 2026-06-22
> 决策者: 月笙
> 关联: [ADR-003](003-ai-readwrite-pipeline.md)
> 前置: Sprint 9 全面审计（识别 X-02 缺 ADR）

## 背景 (Context)

Sprint 9 全面审计发现 **X-02 协议**（AI 训练稿写回编辑器）已在代码中实施，但**没有正式 ADR** 记录其设计意图。导致：

1. 新人不知道"应用"/"忽略"两步确认的设计动机
2. 现有实现有 **3 处技术债**未被显式记录（动态导入 / 无备份 / 跨章节污染）
3. ADR-003 总览引用了 X-02，但 X-02 自身无文档

**本 ADR 目标**：
- 正式记录 X-02 当前实现的 3 段式协议
- 明确 3 处技术债
- 为后续改进（Sprint 11+）提供基线

## 现状 (Current State)

### X-02 流程图

```
[TrainingWorkshop "发送到编辑器" 按钮]
  ↓
CenterPanel.handleSendToEditor()              [CenterPanel/index.tsx:163]
  ↓
training.store.sendToEditor()                 [training.store.ts:120]
  │
  │ ⚠️ 技术债 #1：使用动态 import 绕过循环依赖
  │   void import('./chapter.store').then(({ useChapterStore }) => {
  │     useChapterStore.setState({ pendingRewrite: activeTraining.userDraft });
  │   });
  ↓
chapter.store.pendingRewrite = userDraft       [chapter.store.ts:125]
  ↓ (Zustand 订阅触发 ManuscriptPanel 重渲染)
[ManuscriptPanel 横幅]
  ↓ 检测 currentChapter && pendingRewrite
  ├─ [应用] → chapter.store.applyRewrite(id, content)  [chapter.store.ts:210]
  │            ↓
  │            IPC: CHAPTER_UPDATE_CONTENT
  │            ↓
  │            UPDATE chapters SET content = ?        [manuscript.handler.ts:131]
  │            ↓
  │            ⚠️ 技术债 #2：落库前无 contentCache[id] 备份
  │            ↓
  │            setState({ contentCache: { ...s.contentCache, [id]: content },
  │                        pendingRewrite: null })
  │
  └─ [忽略] → chapter.store.clearRewrite()
              ↓
              setState({ pendingRewrite: null })
```

### 3 段式协议（已实施）

| 段 | 职责 | 状态 |
|:---|:-----|:-----|
| **暂存 (Stash)** | `sendToEditor` 把 `userDraft` 写入 `chapter.store.pendingRewrite` | ✅ 已实现 |
| **确认 (Confirm)** | ManuscriptPanel 显示横幅，"应用" / "忽略" 二选一 | ✅ 已实现 |
| **落库 (Persist)** | `applyRewrite` 走 IPC 持久化到 SQLite | ✅ 已实现 |

### 关键代码

[training.store.ts:120-127](file:///d:/ai-teacher/yuesheng-writing-coach/src/renderer/stores/training.store.ts#L120-L127)
```ts
sendToEditor: () => {
  const { activeTraining } = get();
  if (!activeTraining?.userDraft) return;
  void import('./chapter.store').then(({ useChapterStore }) => {
    useChapterStore.setState({ pendingRewrite: activeTraining.userDraft });
  });
},
```

[chapter.store.ts:210-225](file:///d:/ai-teacher/yuesheng-writing-coach/src/renderer/stores/chapter.store.ts#L210-L225)
```ts
applyRewrite: async (id: string, content: string) => {
  try {
    const invoke = getInvoke();
    const res = await invoke(IPC_CHANNELS.CHAPTER_UPDATE_CONTENT, { id, content }) as { success: boolean; error?: string };
    if (res.success) {
      set((s) => ({
        contentCache: { ...s.contentCache, [id]: content },
        pendingRewrite: null,
      }));
      return true;
    }
    return false;
  } catch {
    return false;
  }
},
```

[ManuscriptPanel.tsx:220-228](file:///d:/ai-teacher/yuesheng-writing-coach/src/renderer/components/manuscript/ManuscriptPanel.tsx#L220-L228)
```tsx
{currentChapter && pendingRewrite && (
  <div className={styles.rewriteBanner}>
    <span>训练改写结果待应用</span>
    <button onClick={() => { void useChapterStore.getState().applyRewrite(currentChapter.id, pendingRewrite); }}>
      应用
    </button>
    <button onClick={() => useChapterStore.getState().clearRewrite()}>
      忽略
    </button>
  </div>
)}
```

## 决策驱动 (Decision Drivers)

- **不静默覆盖 (R-005)**：AI 写回必须有用户确认
- **回退机制 (R-006)**：写回失败可恢复
- **无循环依赖 (R-020)**：禁止动态 import 绕过
- **状态一致性 (R-007)**：UI 显示与存储保持一致

## 候选方案 (Considered Options)

### X-02 是否已"足够好"？

#### 选项 A：接受现状，仅文档化（**推荐**）

**理由**：
- 3 段式协议已正确实施（暂存 → 确认 → 落库）
- 失败时 `pendingRewrite` 保留（try/catch + 不清空）
- 用户体验：横幅 + "应用/忽略" 是**最简明确**的确认 UI
- 主要技术债都是"可改进"而非"阻塞"级别

#### 选项 B：立即重构 3 处技术债

**理由**：
- 一次性解决所有问题
- 不留技术债

**不采用理由**（R-021 最小变更）：
- 跨章节污染需要 schema 升级（chapterId 关联）
- 备份机制需要新 store state + UI（"撤销"按钮）
- 动态 import 修复需要重新设计 training.store 与 chapter.store 的依赖

**结论**：技术债用后续 Sprint 11 卡片独立处理。

## 决策 (Decision)

**采用选项 A**：接受 X-02 当前实现，仅文档化协议。

**显式登记 3 处技术债**（不在本 ADR 修复）：

### 技术债 #1：动态 import 绕过循环依赖（R-020 违反）

- **位置**：[training.store.ts:124](file:///d:/ai-teacher/yuesheng-writing-coach/src/renderer/stores/training.store.ts#L124)
- **症状**：`void import('./chapter.store')` 延迟导入
- **违反规则**：R-020 明确禁止"延迟导入绕过循环依赖"
- **后续修复方向**：Sprint 11 拆分 `chapter.store` 的"数据"与"X-02 协议"两部分；或反向 `chapter.store` 依赖 `training.store`
- **风险等级**：低（功能正确，但维护风险 + 阻碍 unit test）

### 技术债 #2：落库前无备份（R-006 部分违反）

- **位置**：[chapter.store.ts:210-225](file:///d:/ai-teacher/yuesheng-writing-coach/src/renderer/stores/chapter.store.ts#L210-L225) 与 [manuscript.handler.ts:131-139](file:///d:/ai-teacher/yuesheng-writing-coach/src/main/ipc/manuscript.handler.ts#L131-L139)
- **症状**：用户点"应用"后，原 `contentCache[id]` 直接被 `content` 覆盖，无法撤销
- **违反规则**：R-006 要求"每次改动前有明确的回退路径"
- **后续修复方向**：
  - 应用前把 `contentCache[id]` 备份到 `lastContentBeforeRewrite`
  - UI 加"撤销"按钮（10 秒内可撤销）
  - 或在 SQLite 层做"版本表"（每次修改前插一条快照）
- **风险等级**：中（用户实际可能后悔，需要降级路径）

### 技术债 #3：跨章节污染（设计盲点）

- **位置**：[chapter.store.ts:32](file:///d:/ai-teacher/yuesheng-writing-coach/src/renderer/stores/chapter.store.ts#L32) — `pendingRewrite: string | null;`（无 chapterId 关联）
- **症状**：
  - 章节 A 训练 → 暂存 pendingRewrite
  - 用户切换到章节 B → 横幅仍显示 "应用" 按钮（传 `currentChapter.id` = B）
  - 用户点应用 → **A 的草稿写入 B 的章节**！
- **违反规则**：R-007 双向绑定 / R-021 最小化但不能缺关键防御
- **后续修复方向**：
  - 升级 `pendingRewrite` 为 `pendingRewrite: { chapterId: string; content: string } | null`
  - ManuscriptPanel 检查 `pendingRewrite.chapterId === currentChapter.id` 才显示横幅
  - 切换章节时若 pendingRewrite.chapterId !== newId，提示用户处理遗留草稿
- **风险等级**：中（数据污染风险，影响用户对 AI 系统的信任）

## 实施细节 (Implementation Plan)

### 本 ADR 不实施任何代码改动

**仅作为后续 Sprint 卡片的基线**。Sprint 11 推荐卡片：

#### 卡 1：消除动态 import（修技术债 #1）

| 子任务 | 改动文件 | 风险 |
|:-------|:---------|:-----|
| 1.1 检查 `training.store` 与 `chapter.store` 实际循环依赖 | - | 低 |
| 1.2 重新设计：把 `sendToEditor` 的逻辑迁到 `chapter.store` | `chapter.store.ts` `training.store.ts` | 中 |
| 1.3 改为直接 `useChapterStore.setState` | - | 低 |
| 1.4 单测：验证 `sendToEditor` 同步生效 | `__tests__/` | 低 |

#### 卡 2：落库前备份（修技术债 #2）

| 子任务 | 改动文件 | 风险 |
|:-------|:---------|:-----|
| 2.1 `chapter.store` 加 `lastContentBeforeRewrite` | `chapter.store.ts` | 低 |
| 2.2 `applyRewrite` 备份后落库 | 同上 | 中 |
| 2.3 ManuscriptPanel 加"撤销"按钮（10 秒倒计时） | `ManuscriptPanel.tsx` | 中 |
| 2.4 单测 + 集成测试 | `__tests__/` | 低 |

#### 卡 3：跨章节污染防护（修技术债 #3）

| 子任务 | 改动文件 | 风险 |
|:-------|:---------|:-----|
| 3.1 类型升级：`pendingRewrite: { chapterId, content } \| null` | `chapter.store.ts` | 中（破坏性变更） |
| 3.2 `sendToEditor` 写入 chapterId | `training.store.ts` | 低 |
| 3.3 ManuscriptPanel 横幅加 chapterId 校验 | `ManuscriptPanel.tsx` | 中 |
| 3.4 切换章节时检测遗留草稿并提示 | `chapter.store.ts` `CenterPanel` | 中 |
| 3.5 单测 + 集成测试 | `__tests__/` | 低 |

## 风险与回退 (Risks & Rollback)

| 风险 | 等级 | 缓解 |
|:-----|:----:|:-----|
| 本 ADR 决策（接受现状）被未来需求挑战 | 低 | 本 ADR 不实施代码，回退 = 改文档 |
| 3 处技术债在某天引发真实数据问题 | 中 | 3 张 Sprint 11 卡片独立可中断，单 commit 可 revert |
| 卡 1/2/3 同时做导致变更过大 | 中 | 按顺序执行，每张卡片独立 commit + 集成测试 |

## 测试策略 (Testing)

本 ADR 自身**不需要测试**（纯文档）。

### 现有 X-02 测试覆盖

| 测试文件 | 覆盖 |
|:---------|:-----|
| `chapter.store.test.ts`（如有） | `applyRewrite` 成功/失败路径 |
| `ManuscriptPanel.test.tsx`（如有） | 横幅显示条件 |

### Sprint 11 新增测试（每张卡片必做）

- 卡 1：动态 import 移除后，`sendToEditor` 同步生效（无 Promise 包装）
- 卡 2：备份机制 + 撤销按钮的 10 秒倒计时
- 卡 3：跨章节污染场景（A 草稿不能写入 B）

## ADR 状态

- [x] 提议 (Proposed)
- [ ] 接受 (Accepted)
- [ ] 实施 (Implemented)
- [ ] 废弃 (Deprecated)

## 附录 A：X-02 调用方矩阵

| 调用方 | 调用什么 | 风险 |
|:-------|:---------|:-----|
| [CenterPanel/index.tsx:163](file:///d:/ai-teacher/yuesheng-writing-coach/src/renderer/components/center/CenterPanel/index.tsx#L163) | `training.store.sendToEditor()` | 无（同步即可） |
| [TrainingWorkshop.tsx:50](file:///d:/ai-teacher/yuesheng-writing-coach/src/renderer/components/training/TrainingWorkshop.tsx#L50) | 通过 props 传递 `onSendToEditor` | 无 |
| [EvaluationStepContent.tsx:84](file:///d:/ai-teacher/yuesheng-writing-coach/src/renderer/components/training/EvaluationStepContent.tsx#L84) | 通过 props 传递 `onSendToEditor` | 无 |
| [ManuscriptPanel.tsx:220-228](file:///d:/ai-teacher/yuesheng-writing-coach/src/renderer/components/manuscript/ManuscriptPanel.tsx#L220-L228) | 消费 `pendingRewrite` | 跨章节污染风险 |

## 附录 B：X-02 与 ADR-001/002/003 的关系

```
ADR-001 (Stream Pipeline)
  └─ AI 输出流式处理（写前的文本到达）

ADR-002 (Workspace Registry)
  └─ UI 组件可扩展性（X-02 的 UI 消费方）

ADR-003 (AI 读写总览)
  └─ 读链路 + 写链路整体图
      └─ 写链路 · 路径 B：X-02 训练稿写回编辑器

ADR-004 (本 ADR · X-02 协议)
  └─ 写链路 · 路径 B 的具体协议
      └─ 3 段式（暂存 → 确认 → 落库）
      └─ 3 处技术债（待 Sprint 11 修复）
```
