# ADR-002: 右侧栏 Workspace Registry（可扩展性预留通道）

> 状态: **提议 (Proposed)** · 2026-06-22
> 决策者: 月笙
> Sprint 9 · Phase F 前置

## 背景 (Context)

Sprint 9 前端审计识别出右侧栏有 **6 个可扩展性瓶颈**（E-01~E-06），导致新增 workspace 需改 5 个文件。

### 现状

| 文件 | 作用 | 添加新 workspace 的修改点 |
|:-----|:-----|:-------------------------|
| `right-tools.store.ts` | 1. `ToolId` union type<br>2. `ALL_TOOLS` 数组（含 name/icon） | 必须改 |
| `RightPanel/index.tsx` | 1. 静态 import 7 个 workspace<br>2. `WORKSPACE_MAP` Record | 必须改 |
| `workspaces/<NewWorkspace>.tsx` | 新建组件文件 | 新建 |
| `workspaces/<NewWorkspace>.module.css` | 配套样式 | 新建 |
| `__tests__/<NewWorkspace>.test.tsx` | 单元测试 | 新建 |

**最小 5 文件改动**（外加测试）。瓶颈点：

| 瓶颈 | 描述 |
|:-----|:------|
| **E-01** | `WORKSPACE_MAP` 是硬编码 `Record<ToolId, React.FC>` — 新增必须改 `RightPanel/index.tsx` |
| **E-02** | 无 workspace 注册/生命周期机制（mount/unmount/load） |
| **E-03** | 7 个 workspace 组件都是**静态 import** — 初始 bundle 包含所有 workspace 代码 |
| **E-04** | `ToolGrid` 工具选择弹窗与 `ALL_TOOLS` 强耦合 |
| **E-05** | `SubTabEntry` 类型仅 `{id, label}`，无元数据字段（如 `closable`, `pinned`, `metadata`） |
| **E-06** | 没有 IPC channel ↔ workspace 的声明式映射（每个 workspace 自己 import IPC handler） |

### 实际痛点

- **新增 workspace 流程**（以"读者画像"为例）：
  ```
  1. ToolId 加 'reader-profile'
  2. ALL_TOOLS 加条目
  3. 新建 components/right/workspaces/ReaderProfileWorkspace.tsx
  4. 在 RightPanel/index.tsx 加静态 import
  5. 在 WORKSPACE_MAP 加映射
  6. （如果有 IPC）readerProfileHandler.ts + preload + constants + contract
  ```
  **6+ 步骤分散在 5+ 个文件**

- **bundle 体积**：7 个 workspace 全部静态加载，初次启动加载 7 份代码
- **测试隔离**：测试 workspace 组件需要先在 store 注册 ToolId
- **重构成本**：把 "工具" 重命名 / 改图标都要改 3 个文件

## 决策驱动 (Decision Drivers)

- **可扩展性 (R-014)**：新增 workspace ≤ 1 个新文件 + 1 个注册调用
- **bundle 性能 (R-018)**：支持懒加载，初始只加载默认打开的 workspace
- **类型安全 (R-019)**：注册时类型校验，避免错配
- **最小变更 (R-021)**：不动 IPC 通道、不改 store 行为
- **可测试 (R-013)**：注册表有 clear/reset 接口用于测试隔离

## 候选方案 (Considered Options)

### 选项 A：保持现状（不重构）

**做法**：继续硬编码

**优点**：
- 零改动
- 简单直接

**缺点**：
- 添加新 workspace 永远要改 5 个文件
- 不解决 E-01~E-06
- Sprint 9 文档中 E-01~E-06 列出的所有瓶颈继续存在

**不采用** — 不解决核心问题。

### 选项 B：中央注册表 + 静态 import（最小重构）

**做法**：
- 新建 `src/renderer/registry/workspace-registry.ts`
- 提供 `registerWorkspace(reg)`、`getWorkspace(id)`、`getAllWorkspaces()`
- **保持**静态 import（RightPanel 顶部 `import './workspaces/catalog'`）
- `RightPanel` 的 `WORKSPACE_MAP` 改为 `getWorkspace(id).component`

**优点**：
- 新增 workspace 流程简化为：
  ```
  1. 新建 ReaderProfileWorkspace.tsx
  2. 在文件顶部加 registerWorkspace({...})
  3. 在 RightPanel import 一次（用于触发注册）
  ```
- 注册元数据集中化
- 仍兼容现有 7 个 workspace

**缺点**：
- 仍是 2 文件改动（1 新建 + 1 import）
- 静态 import，bundle 没优化
- 注册是命令式的（`registerWorkspace()` 在模块顶层调用）

### 选项 C：自注册 + 动态 import（**推荐 B-lite**）

**做法**：
- 新建 `src/renderer/registry/workspace-registry.ts`
- 提供 `registerWorkspace`、`getWorkspace`、`getAllWorkspaces`、`getDefaultOpenWorkspaces`
- workspace 文件**自注册**（`registerWorkspace({...})` 在文件顶层）
- 动态 import：`component: () => import('./ReaderProfileWorkspace')`
- 新建 `src/renderer/registry/workspaces-index.ts` 触发所有 workspace 的自注册
- `RightPanel` 改为 `React.lazy(() => workspaceRegistry.getWorkspace(id).component())`
- 提供 `resetForTesting()` 接口

**优点**：
- 新增 workspace 流程：
  ```
  1. 新建 ReaderProfileWorkspace.tsx（顶部自注册）
  2. 在 workspaces-index.ts 加 import './ReaderProfileWorkspace'
  ```
- **2 文件改动**（vs 现状 5 个）
- 支持懒加载（bundle 优化）
- 自注册是声明式的（workspace 自己声明元数据）
- 测试隔离：`resetForTesting()`

**缺点**：
- 自注册是副作用，需要被 import 触发（"魔法"）
- 增加少量间接性（理解成本）

### 选项 D：完整插件架构（运行时注册）

**做法**：
- workspace 可在运行时从 JSON manifest 动态加载
- 支持第三方扩展

**优点**：
- 终极灵活

**缺点**：
- 严重过度工程化（YAGNI）
- 类型安全难保证
- 风险大，超出 Sprint 9 范围

**不采用** — 违反 R-021。

## 决策 (Decision)

**采用选项 C**（自注册 + 动态 import）。

理由：
1. **新增 workspace 简化到 2 个文件**（vs 现状 5 个）
2. **支持懒加载**（bundle 性能优化 — R-018）
3. **声明式自注册**（workspace 自己声明 metadata，易理解）
4. **保留类型安全**（TypeScript 编译时校验注册元数据）
5. **测试隔离**：`resetForTesting()` 清理注册表
6. **不破坏现有结构**：`right-tools.store` 的运行时状态保持不变

## 实施细节 (Implementation Plan)

### F-1: 新建 `src/renderer/registry/workspace-registry.ts`

```ts
// src/renderer/registry/workspace-registry.ts
import type { ComponentType } from 'react';

export type WorkspaceId = string;  // 保持灵活，未来可加 union

export interface WorkspaceMeta {
  id: WorkspaceId;
  name: string;
  icon: string;
  defaultOpen?: boolean;  // 默认是否打开
}

export interface WorkspaceRegistration extends WorkspaceMeta {
  component: () => Promise<{ default: ComponentType }>;
}

const registry = new Map<WorkspaceId, WorkspaceRegistration>();

export function registerWorkspace(reg: WorkspaceRegistration): void {
  if (registry.has(reg.id)) {
    console.warn(`[WorkspaceRegistry] duplicate id: ${reg.id}`);
    return;
  }
  registry.set(reg.id, reg);
}

export function getWorkspace(id: WorkspaceId): WorkspaceRegistration | undefined {
  return registry.get(id);
}

export function getAllWorkspaces(): WorkspaceRegistration[] {
  return Array.from(registry.values());
}

export function getDefaultOpenWorkspaces(): WorkspaceRegistration[] {
  return getAllWorkspaces().filter(w => w.defaultOpen === true);
}

export function resetForTesting(): void {
  registry.clear();
}
```

### F-2: workspace 文件改为自注册

**现状**：
```tsx
// CatalogWorkspace.tsx
import React from 'react';
export const CatalogWorkspace: React.FC = () => { ... };
```

**改造后**：
```tsx
// workspaces/CatalogWorkspace.tsx
import React from 'react';
import { registerWorkspace } from '../../registry/workspace-registry';
export const CatalogWorkspace: React.FC = () => { ... };

registerWorkspace({
  id: 'catalog',
  name: '技法目录',
  icon: '✤',
  defaultOpen: true,
  component: () => import('./CatalogWorkspace'),  // 自引用动态 import
});
```

### F-3: 新建 `src/renderer/registry/workspaces-index.ts`

```ts
// 触发所有 workspace 自注册
import './workspaces/CatalogWorkspace';
import './workspaces/ProgressWorkspace';
import './workspaces/LearningLogWorkspace';
import './workspaces/WorksWorkspace';
import './workspaces/TeachingNoteWorkspace';
import './workspaces/SettingsWorkspace';
import './workspaces/StageProgressWorkspace';
```

### F-4: RightPanel 改造

```tsx
// RightPanel/index.tsx
import { getAllWorkspaces, getWorkspace, type WorkspaceId } from '../../registry/workspace-registry';
import '../../registry/workspaces-index';  // 触发注册

// 替换静态 imports + WORKSPACE_MAP
const ALL_WORKSPACES = getAllWorkspaces();
const Workspace = activeToolId ? getWorkspace(activeToolId) : null;
const LazyWorkspace = Workspace ? React.lazy(Workspace.component) : null;

// 渲染时
<Suspense fallback={<div>加载中...</div>}>
  {LazyWorkspace ? <LazyWorkspace /> : <ToolGrid />}
</Suspense>
```

### F-5: right-tools.store 改造

- 移除 `ALL_TOOLS`（改由 `getAllWorkspaces()` 替代）
- 移除 `ToolId` union（改用 `WorkspaceId = string`）
- 运行时状态（openTools, subTabs, projectTabs）**保留**

### F-6: 集成测试

- `workspace-registry.test.ts`：
  - 注册、获取、清空
  - duplicate id 警告
  - getDefaultOpenWorkspaces 过滤
  - resetForTesting 不影响其他测试

## 风险与回退 (Risks & Rollback)

| 风险 | 等级 | 缓解 |
|:-----|:----:|:-----|
| 自注册是副作用，import 顺序导致问题 | 中 | `workspaces-index.ts` 集中 import 触发；测试用 `resetForTesting()` |
| 动态 import 加载延迟 | 低 | `Suspense` fallback 解决；首次加载可接受 |
| 类型 `WorkspaceId = string` 失去 union 约束 | 中 | 注册时校验 id 非空；`getWorkspace` 返回 `T \| undefined` 强制处理 |
| ToolId 移除 union 破坏调用方 | 高 | 仍导出 `ToolId` type alias（= `WorkspaceId`），过渡期不破坏 |
| 测试 import 顺序问题 | 中 | `resetForTesting()` 在 beforeEach 显式调用 |

**回退**：单 commit 涉及 8 个文件，可分阶段 revert：
- F-1 单独 revert：注册表消失，但 workspace 文件仍可被静态 import
- F-5 单独 revert：ALL_TOOLS 回来，但 id 改用 string

## 测试策略 (Testing)

1. **workspace-registry.test.ts**：
   - `registerWorkspace` 添加条目
   - `getWorkspace` 返回正确组件
   - duplicate id 警告
   - `getDefaultOpenWorkspaces` 正确过滤
   - `resetForTesting` 清空
2. **RightPanel 集成测试**（若存在）：
   - 默认打开 7 个工具
   - 切换工具正常
3. **手动验证**：
   - 新建一个虚拟 workspace（如 `__test__`）→ 验证流程是 1 文件 + 1 import

## ADR 状态

- [x] 提议 (Proposed)
- [ ] 接受 (Accepted)
- [ ] 实施 (Implemented)
- [ ] 废弃 (Deprecated)
