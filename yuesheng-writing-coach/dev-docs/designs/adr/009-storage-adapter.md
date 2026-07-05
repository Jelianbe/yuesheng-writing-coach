# ADR-009: StorageAdapter 抽象层接口设计

> **状态**: Accepted
> **日期**: 2026-07-04
> **关联**: Sprint 26 Issue #44 / dev-docs/tasks/sprint-26-plan.md §1.1.2
> **决策者**: AI 架构师（用户确认）

## 背景

Sprint 26 战略转向：Electron → Capacitor Android 双端复用（D-074）。

**当前问题**：
- 业务 services 直接调用 better-sqlite3 同步方法
- 27 个 IPC 通道桥接 main ↔ renderer
- 平台耦合：services 与 Electron 主进程绑定

**目标**：
- 双端共用业务 services
- 移除 IPC 层（WebView 内部直接 import）
- StorageAdapter 抽象层 + 2 个 adapter 实现

## 评估

### 方案 A: StorageAdapter 接口 + 2 个 adapter（推荐）

**优点**：
- 接口稳定：双端共用
- 平台解耦：services 不依赖具体存储实现
- 异步统一：async/await 双端一致
- 易测试：mock adapter 即可单测 services

**缺点**：
- 接口设计成本：需考虑双端差异
- 性能开销：async 适配（同步→异步）

### 方案 B: 平台特定 service 文件（if-else 分支）

**优点**：
- 简单直接
- 性能无开销

**缺点**：
- 业务逻辑分叉
- 平台差异在 service 内部，难维护
- 测试需双套

### 方案 C: 完全共享 better-sqlite3（要求 WebView 支持）

**缺点**：
- WebView 不支持 better-sqlite3（需 Node.js）
- 不可行

## 决策

**采用方案 A**（StorageAdapter 接口 + 2 个 adapter）。

## 接口设计

### 文件位置
- `src/shared/storage/StorageAdapter.ts`（接口）
- `src/shared/storage/types.ts`（类型定义）
- `src/main/storage/BetterSqliteAdapter.ts`（Windows/Electron 实现）
- `src/main/storage/CapacitorSqliteAdapter.ts`（Android 实现）
- `src/main/storage/index.ts`（工厂函数）

### 核心接口

```typescript
/**
 * StorageAdapter — 跨端统一的存储接口
 * 
 * 设计原则：
 * - 异步（async/await）— 双端一致
 * - SQL 预处理（防注入）
 * - 事务支持
 * - 错误统一抛出（不返回 null 隐藏错误）
 * - 不暴露平台特定 API
 */
export interface StorageAdapter {
  // 连接管理
  init(config: StorageConfig): Promise<void>;
  close(): Promise<void>;
  
  // 基础查询
  query<T = unknown>(sql: string, params?: unknown[]): Promise<QueryResult<T>>;
  queryOne<T = unknown>(sql: string, params?: unknown[]): Promise<T | null>;
  execute(sql: string, params?: unknown[]): Promise<ExecuteResult>;
  
  // 事务
  transaction<T>(fn: (tx: Transaction) => Promise<T>): Promise<T>;
  
  // Schema
  migrate(migrations: Migration[]): Promise<void>;
  
  // 健康检查
  isHealthy(): Promise<boolean>;
}

export interface QueryResult<T> {
  rows: T[];
  rowsAffected: number;
  lastInsertId?: number;
}

export interface ExecuteResult {
  rowsAffected: number;
  lastInsertId?: number;
}

export interface Transaction {
  query<T = unknown>(sql: string, params?: unknown[]): Promise<QueryResult<T>>;
  execute(sql: string, params?: unknown[]): Promise<ExecuteResult>;
}

export interface Migration {
  version: number;
  name: string;
  up: string;  // SQL
  down?: string; // SQL（可选）
}

export interface StorageConfig {
  databaseName: string;
  // 平台特定配置
  betterSqlite?: { dbPath: string };
  capacitorSqlite?: { encrypted?: boolean };
}
```

### 关键约束

1. **异步统一**：所有方法返回 Promise，即使底层是同步（BetterSqliteAdapter 内部用 `Promise.resolve()` 包装）
2. **错误处理**：底层错误直接抛出（不吞），service 层 try/catch
3. **SQL 预处理**：所有参数化查询（禁止字符串拼接）
4. **事务边界**：由 service 层控制，adapter 仅提供 `transaction()` 方法
5. **平台特定字段**：仅在 StorageConfig 中存在，接口本身无平台差异

### 两个 adapter 实现策略

#### BetterSqliteAdapter（Windows/Electron）
- 内部用 `better-sqlite3` 同步 API
- `init()` 打开数据库 + 应用 migrations
- 所有方法 `async` 包装（`return Promise.resolve(result)`）
- 事务：`better-sqlite3` 的 `db.transaction()` + `await` 适配
- 性能：单次操作 < 5ms

#### CapacitorSqliteAdapter（Android）
- 内部用 `@capacitor-community/sqlite` 异步 API
- `init()` 连接 + 加密（如启用）
- 所有方法原生 async
- 事务：Capacitor 的 `beginTransaction/commitTransaction/rollbackTransaction`
- 性能：WebView 桥接，< 50ms

### 工厂函数

```typescript
// src/main/storage/index.ts
export function createStorageAdapter(platform: 'electron' | 'capacitor'): StorageAdapter {
  if (platform === 'electron') {
    return new BetterSqliteAdapter();
  } else {
    return new CapacitorSqliteAdapter();
  }
}
```

### 与 service 集成

```typescript
// service 改造前（同步）
class SessionService {
  getById(id: string): Session | null {
    return this.db.prepare('SELECT * FROM sessions WHERE id = ?').get(id) as Session | null;
  }
}

// service 改造后（异步）
class SessionService {
  constructor(private storage: StorageAdapter) {}
  
  async getById(id: string): Promise<Session | null> {
    const row = await this.storage.queryOne<Session>(
      'SELECT * FROM sessions WHERE id = ?',
      [id]
    );
    return row;
  }
}
```

## 风险与对策

| 风险 | 对策 |
|:-----|:-----|
| 同步→异步遗漏 | TypeScript strict mode + 全量 typecheck 验证所有 caller |
| WebView 桥接性能 | 监控 P99 延迟，超 50ms 加批处理 |
| 事务边界错误 | service 层单测覆盖事务场景 |
| Platform config 漂移 | factory 函数在 main 进程入口处一次性确定 |

## 备选方案

- **方案 D**: 直接暴露 better-sqlite3 给 renderer（WebView 不可行）
- **方案 E**: 使用 IndexedDB + SQL.js（Capacitor 兼容但性能差）
- **方案 F**: Room (Android 原生 SQLite) + 后端 (Node.js) 双栈（架构重，不推荐）

## 关联

- Sprint 26 plan: dev-docs/tasks/sprint-26-plan.md §1.1.2
- Issue #44 Sprint 26 容器
- D-074 Sprint 26 战略转向
- ADR-010 IPC 移除策略（待写）
- D-070 Sprint 24 Reflect（services 现状）
