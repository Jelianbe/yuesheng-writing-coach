# T26-2.2 Plan: projects 表迁移(主进程 ProjectService → StorageAdapter)

> **目标**: 把 `project.handler.ts` 中直接调用 better-sqlite3 的同步逻辑抽离到 `src/shared/services/project.service.ts`,实现异步 + 双端共用
> **依据**: T26-2.1 模式(sessions 迁移) + Sprint 26 plan §1.2
> **R-010**: 最小化,只新建 1 个 service + 重构 1 个 handler + 新增 1 个测试 + 改 1 个 DI 配置

---

## 0. 现状

### 0.1 主进程 handler(同步 better-sqlite3)
- `src/main/ipc/project.handler.ts` — 5 个 createHandler 全部直接 `d.db.prepare(...).run/all/get(...)`
- 5 个通道:PROJECT_LIST / PROJECT_GET / PROJECT_CREATE / PROJECT_UPDATE / PROJECT_DELETE
- 字段映射:行(row) → ProjectInfo(rowToProjectInfo 函数)
- 依赖:`Database.Database`(同步 better-sqlite3)
- DI 入口:`src/main/core/app-initializer.ts` 中 `initProjectHandlers({ db })`

### 0.2 shared 端(待新建)
- `src/shared/services/project.service.ts` — 尚不存在
- 渲染层不直接调 service,通过 `project.store.ts` 走 IPC

### 0.3 表结构(021_projects.sql)
```sql
projects (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT DEFAULT NULL,
  setting_tree TEXT DEFAULT NULL,
  setting_tree_type TEXT NOT NULL DEFAULT 'main',
  created_at INTEGER NOT NULL DEFAULT (unixepoch()),  -- 整数 unix 秒
  updated_at INTEGER NOT NULL DEFAULT (unixepoch())
)
```

---

## 1. 实施步骤

### Step 1: 新建 `src/shared/services/project.service.ts`

```typescript
export class ProjectService {
  constructor(private readonly adapter: StorageAdapter) {}

  async listProjects(): Promise<ProjectInfo[]> {
    const rows = await this.adapter.query<ProjectRow>(...);
    return rows.map(rowToProjectInfo);
  }

  async getProject(projectId: string): Promise<ProjectInfo | null> { ... }

  async createProject(input: ProjectCreateInput): Promise<ProjectInfo> { ... }

  async updateProject(projectId: string, input: ProjectUpdateInput): Promise<ProjectInfo> {
    // 动态 SET 拼接(与原 handler 一致,但用 adapter.execute)
  }

  async deleteProject(projectId: string): Promise<void> {
    // result.changes === 0 → throw PROJECT_NOT_FOUND
  }
}
```

要点:
- 内部行类型 `ProjectRow` 用 snake_case(`setting_tree` / `created_at`)
- 公开返回 `ProjectInfo` 用 camelCase(`settingTree` / `createdAt`)
- `created_at`/`updated_at` 用 `Math.floor(Date.now() / 1000)`(整数 unix 秒)
- 抛错语义保持 `PROJECT_NOT_FOUND`(供 IPC handler 透传)
- `setting_tree` / `setting_tree_type` 命名映射在 rowToProjectInfo 集中处理

### Step 2: 重构 `src/main/ipc/project.handler.ts`

- import 切到 `ProjectService`(shared)
- 5 个 createHandler 全部改为 `async`
- 移除 `Database.Database` 依赖,改为 `ProjectService`
- `rowToProjectInfo` 内联逻辑删除(交给 service 层)
- `initProjectHandlers` deps 改 `{ projectService }`

### Step 3: 改 DI(`src/main/core/service-config.ts`)

```diff
+ import { ProjectService } from '../../shared/services/project.service';
  ...
  container.register<ProjectService>('projectService', (c) =>
    new ProjectService(c.get<BetterSqliteAdapter>('storageAdapter')),
  );
```

### Step 4: 改 DI 注入(`src/main/core/app-initializer.ts`)

```diff
- initProjectHandlers({ db });
+ initProjectHandlers({ projectService: c.get<ProjectService>('projectService') });
```

(具体路径依据实际 app-initializer 实现调整)

### Step 5: 单测 `src/shared/services/__tests__/project.service.test.ts`

- 使用 `BetterSqliteAdapter(:memory:)`(T26-2.1 已验证)
- 覆盖 listProjects / getProject(找到/未找到) / createProject / updateProject(部分更新) / deleteProject(成功/PROJECT_NOT_FOUND)
- ≥ 6 用例

### Step 6: 4 道门禁

```bash
npm run typecheck && npm run test && npm run lint
```

---

## 2. 范围与边界

### 在范围内
- 新建 src/shared/services/project.service.ts
- 重构 src/main/ipc/project.handler.ts(async + service 依赖)
- DI 改造: service-config.ts + app-initializer.ts
- 新增 src/shared/services/__tests__/project.service.test.ts

### 不在范围内
- ❌ 改 src/shared/api-contracts/project.contract.ts(已 OK,沿用)
- ❌ 改 src/renderer/stores/project.store.ts(沿用 IPC)
- ❌ 改 settings_tree / setting_tree_type 字段语义
- ❌ 改其他 3 张表(teaching_state / training_records / active_training)
- ❌ 移除 project.handler.ts(S26 阶段 4 才做)

---

## 3. DoD(完成标准)

- [ ] DoD-1: src/shared/services/project.service.ts 新建完成
- [ ] DoD-2: src/main/ipc/project.handler.ts 切到 ProjectService
- [ ] DoD-3: DI(service-config + app-initializer)改造完成
- [ ] DoD-4: 单测 ≥ 6 用例全部通过
- [ ] DoD-5: typecheck 0 errors
- [ ] DoD-6: lint 0 errors
- [ ] DoD-7: test 全绿(包含新单测 + 旧单测不退化)
- [ ] DoD-8: 提交干净,无 console error

---

## 4. 风险与对策

| 风险 | 影响 | 对策 |
|:-----|:-----|:-----|
| 同步→异步遗漏某 handler | IPC 调用返回 undefined | 严格 typecheck(IPC handler 强制返回 Promise) |
| settingTree null 与 undefined 边界 | 字段映射错误 | 显式 `(row.setting_tree as string \| null) ?? null` |
| 动态 SET 拼接 SQL 注入 | 安全 | 字段白名单(原 handler 已用,沿用) |
| 项目表无 messages 关联 | 误删数据 | 原 handler 注释已说明 sessions/project 外键未建立,本次沿用 |

---

## 5. 预估工作量

- Step 1: 20 分钟(service + 类型)
- Step 2: 15 分钟(handler 异步化)
- Step 3-4: 5 分钟(DI 改造)
- Step 5: 20 分钟(单测)
- Step 6: 5 分钟(门禁)

总计: ~1 小时
