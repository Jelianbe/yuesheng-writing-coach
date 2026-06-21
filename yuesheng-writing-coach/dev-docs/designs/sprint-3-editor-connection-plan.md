# Sprint 3 — 渲染链路：编辑器接入实现计划

## 定位
Issue #11 的实施计划。将 `ManuscriptPanel` 接入 CenterPanel 渲染管线，实现章节编辑 + 自动保存端到端闭环。

## 当前状态
- DB + IPC + Store 层已就绪
- ManuscriptPanel（多标签编辑器）代码完整但 0 处渲染
- 点击章节 → RightPanel WorksWorkspace（只读）
- CenterPanel 仅 chat/training/retro 三种视图

## 文件变更清单

### 1. `src/renderer/shared/types-training.ts`
- `CenterMode` 扩展 `'editor'`：`'chat' | 'training' | 'retro' | 'editor'`

### 2. `src/renderer/stores/training.store.ts`
- 新增 `enterEditor()` action：`set({ centerMode: 'editor' })`
- `backToChat()` 已兼容 `'editor'` → `'chat'`（无额外变更）

### 3. `src/renderer/components/center/CenterPanel/index.tsx`
- import `ManuscriptPanel`
- content 区域新增 `'editor'` 分支（在 retro/training 之后，fallback 之前）
- header 新增 editor 模式「← 返回」按钮（复用 training 已有模式）

### 4. `src/renderer/components/layout/WorkTreePanel.tsx`
- import `useTrainingStore`
- 章节点击 handler 增加：
  - `onOpenTab(ch.id, ms.title)` — 打开编辑器标签页
  - `useTrainingStore.getState().enterEditor()` — 切换 CenterPanel 视图
- 保留原有 `openTool('works')` 调用（右侧栏仍可查看）

### 5. `src/renderer/stores/training.selectors.ts`
- 无变更（`selectCenterMode` 通用，无需改动）

## 不涉及变更
- `ManuscriptPanel.tsx` — 无改动（直接 import 渲染即可）
- `chapter.store.ts` — 无改动（`openTab`/`select` 等 API 完备）
- `training.types.ts` — 无改动（`centerMode: CenterMode` 泛型自动适配）
- `centerPanel.module.css` — 无新增样式（复用既有 header/backBtn 样式）
- 测试 — 无新增测试（门禁守护既有 319 用例）

## 数据流

```
WorkTreePanel 点击章节
  │
  ├─ chapter.store.openTab(id, title)  →  openFiles[] + openTabMeta
  ├─ chapter.store.select(id)          →  currentChapter 更新
  ├─ training.store.enterEditor()      →  centerMode = 'editor'
  └─ rightPanel.openTool('works')      →  RightPanel 显示（只读参考）
                                             │
                                             ▼
CenterPanel 检测 centerMode === 'editor'
  └─ 渲染 ManuscriptPanel
       └─ useChapterStore → 读取 openFiles / currentChapter / contentCache
       └─ 编辑 → 1500ms 防抖 → chapter.store.updateContent → IPC → DB
```

## 回退路径
- 编辑器右上角「← 返回」按钮 → `training.store.backToChat()` → 回到 chat 视图
- 编辑器对 `chat.store` / `training.store` 无副作用，切换无损

## 门禁
- typecheck 0 errors
- test 319/319 pass
- lint 0 errors
