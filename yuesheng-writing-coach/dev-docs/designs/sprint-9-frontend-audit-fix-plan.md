# Sprint 9 — 前端全面审计与修复

> 对 ChatView 双输入入口、左侧栏耦合、右侧栏 IPC + 标签注册、Header 子标签、AI 输出渲染、右侧栏可扩展性预留通道的完整审计与修复。
>
> Issue 链接：TBD（见 GitHub Kanban）

## 定位

Sprint 8 完成后，前端长期累积的代码债务与可扩展性瓶颈尚未清理。本 Sprint 不引入新功能，**纯粹修复**，包含 32 个待修复项 + AI 输出渲染问题 + 右侧栏可扩展性架构改造。

依据 GStack 流程执行：**Think → Plan → Build → Review → Test → Ship → Reflect**。

## 已完成前置项（Sprint 8 顺手做掉的）

| ID | 内容 | 状态 |
|:---|:-----|:----:|
| D-01 | TrainingFlow→Store 集成（`training.actions.ts` → `training:generateFlow`） | ✅ |
| D-02 | IPC handler（`training.handler.ts` + `development-path.handler.ts`） | ✅ |
| D-03 | UI 阶段进度（`StageProgressWorkspace` + `stage` 工具） | ✅ |
| D-04 | ChatView 双输入入口修复（inputArea 删除，Footer 还原为唯一入口） | ✅ |

## 一、严重问题 (S)

### S-01. `growth:getTrends` / `growth:getGlobalTrends` 双重注册

**文件**：
- `src/main/ipc/diagnosis.handler.ts:122-145`
- `src/main/ipc/growth.handler.ts:25-48`

**问题**：
`createHandler` 通过 `ipcMain.handle` 注册 IPC 处理器，但 `diagnosis.handler.ts` 与 `growth.handler.ts` 都对 `GROWTH_GET_TRENDS` 和 `GROWTH_GET_GLOBAL_TRENDS` 做了注册。`ipcMain.handle` 在第二次注册时**会抛 `Error: Attempted to register a second handler for 'growth:getTrends'`**。

**修复方案**：
1. 删除 `diagnosis.handler.ts:122-145` 的两个 handler
2. 仅保留 `growth.handler.ts` 的实现（统一职责）
3. 验证 `growthTrendService` 已通过 DI 注入到 `growth.handler`

**DoD**：
- [ ] `diagnosis.handler.ts` 中 `GROWTH_GET_TRENDS` / `GROWTH_GET_GLOBAL_TRENDS` 注册已删除
- [ ] `ipcRegistry.registerAll()` 调用顺序无冲突
- [ ] `typecheck` + `test` + `lint` 三门禁全绿

---

## 二、高优先级问题 (H)

### H-02. 4 个孤立组件

**文件**：
- `src/renderer/components/chat/MessageInput.tsx`
- `src/renderer/components/chat/InputToolbar.tsx`
- `src/renderer/components/chat/AttitudeIndicator.tsx`
- `src/renderer/components/chat/TemplateSelector.tsx`

**问题**：ChatView 的 inputArea 已删除，4 个组件成为死代码。

**修复方案**：
- `AttitudeIndicator` 移至 `Footer`（Footer 已有 `attLights` 区块，可整合）
- `TemplateSelector` 移至 `Footer` 工具区（`[模板]` 按钮触发）
- `MessageInput` + `InputToolbar` 确认无其他调用方后**删除**
- 验证 Footer 已能完整替代上述功能

**DoD**：
- [ ] 4 个组件的去留明确，每个组件有迁移或删除的 commit
- [ ] 无外部引用残留
- [ ] `typecheck` + `lint` 全绿

### H-03. ChatView 死 CSS

**文件**：`src/renderer/components/chat/ChatView.module.css`

**问题**：~50 行死 CSS（`.inputArea`、`.inputAreaToolbarRow`、`.inputAreaBody`、`.inputAreaAttitude`、`.inputAreaTextCol`）

**修复方案**：删除上述 5 个类及对应样式

**DoD**：
- [ ] ChatView.module.css 行数显著减少
- [ ] 视觉无变化（grep 确认无外部引用）

### H-04. ChatView 死 props

**文件**：
- `src/renderer/components/center/CenterPanel/index.tsx`（`handleSendMessage`）
- `src/renderer/components/chat/ChatView.tsx`（`_onSend` / `_onStop` 重命名）
- `src/renderer/App.tsx`（`handleSendMessage` 函数 + `void showOnboarding; void handleSendMessage;`）

**问题**：
- ChatView 输入区已删除，`onSend` / `onStop` 是死接口
- App.tsx 与 CenterPanel 都定义了 `handleSendMessage`，但 App.tsx 的版本被 `void` 掉

**修复方案**：
1. 移除 ChatView 的 `onSend` / `onStop` props
2. 还原 CenterPanel 中 `chatViewProps` 的 onSend/onStop
3. 删除 App.tsx 中冗余的 `handleSendMessage` 和 `void showOnboarding; void handleSendMessage;`

**DoD**：
- [ ] ChatView 签名收敛
- [ ] App.tsx 不再持有死状态
- [ ] typecheck + lint 全绿

### H-05. Footer 模式覆盖不完整

**文件**：`src/renderer/components/center/CenterPanel/index.tsx:334`

**问题**：`centerMode !== 'training'` 条件意味着 Footer 在 `chat` / `editor` / `retro` 三种模式都显示。但 `editor` / `retro` 模式不应该显示输入框。

**修复方案**：
- 改为 `centerMode === 'chat'` 显式判断
- 提取 `ChatFooter` 组件包 Footer（仅 chat 模式用）

**DoD**：
- [ ] editor / retro 模式不显示输入区
- [ ] chat 模式行为不变
- [ ] 手动验证三种模式

---

## 三、中优先级问题 (M)

### M-01. `stage` 工具默认不显示

**文件**：`src/renderer/stores/right-tools.store.ts:69`

**问题**：`openTools: ['catalog', 'progress', 'growth', 'works', 'training']` 不含 `'stage'`

**修复方案**：
- 在 `openTools` 中加入 `'stage'`
- 调整默认 `activeToolId` 为 `'catalog'`（保持当前行为）

**DoD**：
- [ ] 用户首次打开应用即看到发展路径工具

### M-02. drawer-constants 放错位置

**文件**：`src/renderer/stores/right-panel.store.ts:40`

**问题**：引用 `components_archived/layout/drawer-constants` 而非 `components/layout/drawer-constants`

**修复方案**：
- 修正 import 路径到 `components/layout/drawer-constants`
- 验证 `drawer-constants.ts` 在两个位置的内容一致性

**DoD**：
- [ ] 无 `_archived` 路径依赖
- [ ] typecheck + lint 全绿

### M-03. 两个 AppShell 共存

**文件**：
- `src/renderer/components/AppShell.tsx`（根 components 下）
- `src/renderer/components/layout/AppShell.tsx`（layout 子目录下）

**修复方案**：
- 确认 App.tsx 导入的是哪一个
- 删除/合并冗余版本
- 保留**一个**为 `AppShell.tsx`（建议保留 `components/AppShell.tsx`）

**DoD**：
- [ ] 全代码库 grep `AppShell` 仅 1 处定义
- [ ] 应用启动无变化

### M-04. CenterPanel 内联 Tailwind 类

**文件**：`src/renderer/components/center/CenterPanel/index.tsx:230`

**问题**：内联 `className="w-[26px] h-[26px] rounded..."` 违反 R-019 CSS Modules 规范

**修复方案**：
- 移到 `CenterPanel.module.css` 新增 `.collapsedBarLogo` 类

**DoD**：
- [ ] 无内联 Tailwind 类
- [ ] 视觉无变化

### M-05. SubTabs "回到目录" 无功能

**文件**：`src/renderer/components/right/RightPanel/index.tsx:107,117`

**问题**：`addBtnTitle="回到目录"` 但 `onAddBtnClick` 未传入

**修复方案**：
- 传入 `onAddBtnClick` 回调，调用 `setActiveSubTab(null)` 或返回目录态
- 或直接移除 `showAddBtn` / `addBtnTitle`（如果功能未规划）

**DoD**：
- [ ] "回到目录"按钮可点击且有行为

### M-06. `clearSubTabs` 死函数

**文件**：`src/renderer/stores/right-tools.store.ts:162`

**问题**：`clearSubTabs` 从未被调用

**修复方案**：
- 找到合适的调用点（切换会话时清空 sub-tabs）
- 或直接删除

**DoD**：
- [ ] 函数有调用方 或 已删除

### M-07. CatalogWorkspace 无法关闭 sub-tab

**文件**：`src/renderer/components/right/workspaces/CatalogWorkspace/index.tsx`

**问题**：打开技法调用 `addSubTab` 但未提供关闭入口（`removeSubTab` 从未调用）

**修复方案**：
- SubTabs 的 `onClose` 已接入 `removeSubTab`，检查 `CatalogWorkspace` 中技法项是否能正确被关闭
- 若无问题则关闭；若有路径问题则修复

**DoD**：
- [ ] 用户可关闭子标签

### M-08. `training:catalog` 通道报错

**文件**：`src/shared/constants.ts` + `src/main/ipc/training.handler.ts`

**问题**：运行时报 "Disallowed IPC channel"

**修复方案**：
- 确认 `training:catalog` 是否在 `ALLOWED_INVOKE_CHANNELS` 白名单
- 确认 `training.handler.ts` 是否已注册

**DoD**：
- [ ] 渠道可用，前端调用无报错

### M-09. App.tsx 死状态/回调

**文件**：`src/renderer/App.tsx:119-120`

**问题**：`void showOnboarding; void handleSendMessage;` 两行

**修复方案**：
- 删除 `showOnboarding` state、`handleSendMessage` callback 及对应的 `void` 行

**DoD**：
- [ ] App.tsx 行数减少
- [ ] typecheck + lint 全绿

---

## 四、低优先级问题 (L)

### L-01. `prescription:*` 缺 contract 文件

**修复方案**：在 `src/shared/api-contracts/` 下创建 `prescription.contract.ts`，与 IPC handler 对齐

### L-02. `window:*` 未纳入 IPC_CHANNELS

**修复方案**：在 `src/shared/constants.ts` 添加 `WINDOW_MINIMIZE` / `WINDOW_MAXIMIZE` / `WINDOW_CLOSE` 常量

### L-03. `teachingDecision:record` 无通道常量

**修复方案**：在 `src/shared/constants.ts` 添加 `TEACHING_DECISION_RECORD`

### L-04. ProjectInfo 类型不一致

**修复方案**：对齐 `project.store.ts` 与 `project.contract.ts` 的 `ProjectInfo` 类型

### L-05. `withIdempotency()` 死函数

**修复方案**：删除或迁移到主进程 `createHandler`（已有幂等机制）

---

## 五、AI 输出渲染问题

### R-01. AI 输出夹带 JSON 片段乱码

**文件**：
- `src/renderer/components/chat/MessageBubble.tsx`（ReactMarkdown 渲染）
- `src/renderer/components/chat/MessageList.tsx`

**问题**：AI 输出中夹带 JSON 时，渲染层无法正确切分 markdown 与 code block

**修复方案**：
1. 在 `chat.store.ts` 的 `appendToLastAssistant` 阶段引入**预处理层** `streamSanitizer.ts`：
   - 检测 ` ```json ... ``` ` 边界
   - 提取并缓存 JSON 块（不进入 ReactMarkdown 内容流）
   - 在消息 metadata 中保存 JSON 数据，由诊断卡片等消费
2. 增加 R-021 风格的边界检查（空字符串、未闭合 code block）

**DoD**：
- [ ] AI 输出夹带 JSON 时不再产生乱码
- [ ] 诊断卡片仍能正确接收 JSON 数据

### R-02. 流式追加内容被吞

**文件**：`src/renderer/stores/chat.store.ts`（`appendToLastAssistant`）

**修复方案**：
- 改用 immutable update：`messages.map(m => m.id === lastId ? { ...m, content: m.content + chunk } : m)`
- 加入 chunk ID + 序号去重
- 验证 `chat:stream:data` 事件顺序

**DoD**：
- [ ] 长输出无字符丢失
- [ ] 多次快速发送无竞态

### R-03. 流结束时 `finalContent` 与累积内容不一致

**文件**：`src/renderer/App.tsx:82-89`（`chat:stream:end` 订阅）

**修复方案**：
- 优先信任前端累积的 `content`，仅在 `error` 时使用后端 `finalContent`
- 或反之：信任后端，覆盖前端累积（需对账）

**DoD**：
- [ ] 流结束时消息内容完整

---

## 六、右侧栏可扩展性预留通道

### 现状（添加新工具需修改 4 个文件）

```
1. right-tools.store.ts → ToolId + ALL_TOOLS
2. workspaces/ → 新组件
3. RightPanel/index.tsx → WORKSPACE_MAP
4. IPC channel → constants.ts + handler + contract
```

### 改造方案：workspace 注册机制

**新增文件**：`src/renderer/stores/right-tools.registry.ts`

```typescript
// 接口定义
interface WorkspaceDescriptor {
  id: ToolId;
  component: () => Promise<{ default: React.FC }>; // 懒加载
  channels: string[];                              // 绑定的 IPC 通道
  icon: string;
  name: string;
  // ... 元数据
}

const registry = new Map<ToolId, WorkspaceDescriptor>();

export function registerWorkspace(desc: WorkspaceDescriptor): void;
export function getWorkspace(id: ToolId): WorkspaceDescriptor | undefined;
export function getAllWorkspaces(): WorkspaceDescriptor[];
export function getWorkspaceChannels(id: ToolId): string[];
```

**改造点**：
1. `RightPanel/index.tsx` 的 `WORKSPACE_MAP` 改为 `getWorkspace(activeToolId)?.component`
2. 配合 `React.lazy` + `Suspense` 实现懒加载
3. `ToolGrid` 数据源从 `ALL_TOOLS` 改为 `getAllWorkspaces()`

**DoD**：
- [ ] 新增工具**仅需注册一次**（调用 `registerWorkspace`）
- [ ] `RightPanel/index.tsx` 不再硬编码 workspace 映射
- [ ] 启动时无 workspace 加载阻塞

---

## 七、左侧栏耦合问题

### L-COUPLE-01. 跨 Store 操作右侧栏

**文件**：`src/renderer/components/left/LeftPanel/index.tsx:32,35-37,119-120`

**问题**：
```typescript
if (openTools.includes('training')) closeTool('training');
if (openTools.includes('works')) closeTool('works');
openProjectTab(id);
openTool('works');
```

违反 X-01 协议 — 组件层直接协调多 Store

**修复方案**：
- 通过 `useRightPanelStore.getState().switchTo(...)` 统一入口
- 业务耦合（关闭 training）由 right-panel.store 内部消化

**DoD**：
- [ ] LeftPanel 不再直接调用 `closeTool` / `openTool`
- [ ] 通过 `rightPanelActions` 统一入口

### L-COUPLE-02. 业务耦合

**问题**：tab 切换触发右侧栏工具的开关，是业务逻辑泄露

**修复方案**：
- 在 `right-panel.store.ts` 新增 `switchLeftTab(tab: 'chat' | 'proj')` 统一处理
- LeftPanel 仅调用此 action

**DoD**：
- [ ] tab 切换逻辑集中在 store

---

## 八、Header 子标签栏注册混乱

### HDR-01. Header 无组件化

**文件**：`src/renderer/components/center/CenterPanel/index.tsx:226-260`

**问题**：header 内联渲染，包含 collapsedBar + projectBtn + statusBadge + sessionBadge + actions

**修复方案**：
- 提取 `CenterHeader` 组件
- projectBtn 接收 `projects` + `onSelect` props
- actions 接收 `centerMode` + 回调

**DoD**：
- [ ] CenterHeader 独立组件
- [ ] 业务配置通过 props 注入

### HDR-02. "我的第一本小说" 硬编码

**修复方案**：
- 接入 `useProjectStore` 获取当前项目
- 无项目时显示"选择项目"提示

**DoD**：
- [ ] projectBtn 显示真实项目名

---

## 实施计划

### Phase A：双输入入口修复 ✅（已完成）

### Phase B：S-01 + H 系列（本次 Sprint 第一批）

- S-01 growth handler 冲突
- H-02 4 个孤立组件清理
- H-03 ChatView 死 CSS
- H-04 ChatView 死 props
- H-05 Footer 模式覆盖

### Phase C：M 系列（基础设施小修）

- M-01 ~ M-09

### Phase D：L 系列（接口统一）

- L-01 ~ L-05

### Phase E：AI 输出渲染（R-01/02/03）

- 流式管道改造
- 预处理层

### Phase F：右侧栏可扩展性架构改造

- workspace registry

### Phase G：左侧栏耦合 + Header 子标签

- X-01 协议落地
- CenterHeader 组件化

---

## DoD（整个 Sprint）

- [ ] 所有 32 项问题已解决或明确延期
- [ ] AI 输出 JSON 夹带场景无乱码
- [ ] 流式输出无内容丢失
- [ ] 右侧栏添加新工具仅需注册一次
- [ ] `npm run typecheck && npm run test && npm run lint` 三门禁全绿
- [ ] 应用启动并手动验证 3 种 mode（chat/training/retro/editor）
- [ ] R-021 边界检查通过

## 风险

- **R-AI-1**：流式管道改造可能引入新 bug，需充分测试长输出
- **R-REG-1**：registry 机制可能破坏现有 `ALL_TOOLS` 依赖方
- **R-LEFT-1**：X-01 协议重写可能影响训练模式启动

## 优先级排序

1. **S-01**（运行时报错）
2. **R-01/02/03**（用户立即可感的体验问题）
3. **H 系列**（死代码 / 死 CSS）
4. **M 系列**（功能完整性）
5. **可扩展性改造**（Phase F）
6. **左侧栏 + Header**（Phase G）
7. **L 系列**（接口统一）
