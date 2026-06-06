# 诊断结果持久化

> 版本：V1.0 | 创建：2026-06-01  
> 依据：  
> - design-philosophy_V1.0.md → 第五章「诊断表 + 长期能力表单」  
> - T-003 实施后，诊断结果在内存中流转后丢弃，无法被后续引用  
> 回退方案：删除 005_migration.sql 文件，恢复 diagnosis.handler.ts 到原始状态

---

## 一、改造目标

当前诊断结果在 `processDiagnosisFromAI` 中解析后直接合并到 TeachingState 并推送到前端，但**没有持久化到 SQLite**。每次重新启动应用后，历史诊断数据全部丢失。

本次改造的目标：**将每次诊断结果持久化到 SQLite，让诊断数据可被追溯和查询。**

## 二、数据模型

### 2.1 新表：diagnosis_results

```sql
CREATE TABLE IF NOT EXISTS diagnosis_results (
  id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL,
  message_id TEXT NOT NULL,
  syndromes TEXT NOT NULL,       -- JSON 数组，存储 SyndromeResult[]
  suggested_actions TEXT NOT NULL, -- JSON 数组，存储 ActionId[]
  confidence REAL NOT NULL DEFAULT 0,
  timestamp TEXT NOT NULL,
  next_focus TEXT,               -- SyndromeId | null
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
```

### 2.2 与现有表的关系

```
messages (已有)
  ↑ 通过 message_id 关联
diagnosis_results (新增)
  ↑ 通过 session_id 关联
teaching_state (已有) - 通过 active_problems 字段冗余存储当前活跃问题
```

## 三、修改位置

| 文件 | 修改类型 | 内容 |
|------|---------|------|
| `src/main/db/005_diagnosis.sqlite` | 新增 | 建表 SQL |
| `src/main/services/diagnosis.service.ts` | 新增 | CRUD 操作 |
| `src/main/ipc/diagnosis.handler.ts` | 修改 | processDiagnosisFromAI 中调用 save |
| `src/main/index.ts` | 修改 | 执行 005 迁移 + 注入 DiagnosisService |
| `src/main/services/__tests__/diagnosis.service.test.ts` | 新增 | 单元测试 |

## 四、接口定义

### DiagnosisService

```typescript
class DiagnosisService {
  constructor(db: Database.Database)

  save(diagnosis: DiagnosisEntry): void
  getBySession(sessionId: string): DiagnosisEntry[]
  getRecentBySession(sessionId: string, limit?: number): DiagnosisEntry[]
  deleteBySession(sessionId: string): void
}
```

### IPC 通道（无新增）

本次改造不新增 IPC 通道。诊断数据仍然通过已有的 `diagnosis:update` 事件推送。新增的持久化在 `processDiagnosisFromAI` 内部完成，对前端透明。

## 五、影响面分析

| 维度 | 影响 |
|------|------|
| 前端 UI | 无影响（推送机制不变） |
| 现有 IPC | 无影响 |
| 现有数据流 | `processDiagnosisFromAI` 增加一个步骤（持久化），不改变现有逻辑 |
| 存储 | 新增 diagnosis_results 表，不影响已有表 |
| 回退 | 删除 005 迁移文件 + 恢复 handler |
