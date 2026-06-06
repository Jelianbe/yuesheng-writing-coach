# 长期能力表单与用户能力画像

> 版本：V1.0 | 创建：2026-06-01  
> 依据：  
> - design-philosophy_V1.0.md → 第五章「诊断表 + 长期能力表单」  
> - ability-atlas.json → 能力↔症候↔训练的映射体系  
> - T-004 诊断结果持久化（数据基础已就绪）  
> 回退方案：删除 006 迁移文件，恢复 diagnosis.handler.ts 到 T-004 完成状态

---

## 一、目标

将 diagnosis_results 中的原始诊断数据聚合为**用户能力画像**，实现：

1. **能力评分**——每项写作能力的量化评分（0-100）
2. **弱点标签**——用户反复出现的写作问题模式
3. **训练记录**——用户完成训练任务的历史
4. **诊断趋势**——症候严重度的变化趋势

这是诊断数据从"一次性输出"升级为"持续追踪认知档案"的关键一步。

## 二、核心设计决策

### 2.1 能力画像 = 实时聚合（不缓存）

**决策**：能力画像在查询时实时从 diagnosis_results 聚合计算，不单独建表缓存。

**理由**：
- 数据一致性最好——画像永远反映最新诊断
- 实现简单——不需要维护缓存同步逻辑
- 当前数据量小（单次会话诊断记录 < 100 条），实时聚合性能足够
- 等数据量大了再考虑预计算优化

### 2.2 训练记录需要单独建表

训练完成情况无法从诊断数据推导（诊断只记录"发现了什么问题"，不记录"用户做了哪些训练"）。

## 三、数据模型

### 3.1 新增表：user_training_records

```sql
CREATE TABLE IF NOT EXISTS user_training_records (
  id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL,
  task_id TEXT NOT NULL,        -- 如 T001, T003
  syndrome_id TEXT NOT NULL,    -- 关联的症候
  status TEXT NOT NULL,         -- 'assigned' | 'completed' | 'skipped'
  assigned_at TEXT NOT NULL,
  completed_at TEXT,
  user_response TEXT,           -- 用户完成的训练内容（可选）
  ai_feedback TEXT,             -- AI 对训练的反馈（可选）
  effectiveness INTEGER         -- AI 评估的效果 1-5（可选）
);

CREATE INDEX idx_training_session ON user_training_records(session_id, assigned_at);
CREATE INDEX idx_training_task ON user_training_records(task_id);
```

### 3.2 能力画像类型（TypeScript 接口）

```typescript
interface AbilityProfile {
  sessionId: string;
  abilities: AbilityScore[];      // 8 项能力评分
  weakPoints: WeakPoint[];        // 弱点标签
  trainingStats: TrainingStats;   // 训练统计
  diagnosisTrend: DiagnosisTrend; // 诊断趋势
  computedAt: string;             // 计算时间
}

interface AbilityScore {
  abilityId: string;      // 如 ABL-001
  abilityName: string;    // 如 "结构控制"
  score: number;          // 0-100
  relatedSyndromes: string[];  // 关联的症候 ID
  severityHistory: number[];   // 最近 N 次的严重度数值
  trend: 'up' | 'down' | 'stable';
}

interface WeakPoint {
  syndromeId: string;
  syndromeName: string;
  occurrenceCount: number;   // 出现次数
  avgSeverity: number;       // 平均严重度 (1-3)
  lastOccurrence: string;    // 最后出现时间
  trend: 'improving' | 'worsening' | 'stable';
}

interface TrainingStats {
  totalAssigned: number;
  totalCompleted: number;
  completionRate: number;    // 0-1
  bySyndrome: Record<string, { assigned: number; completed: number }>;
}

interface DiagnosisTrend {
  totalDiagnoses: number;
  avgConfidence: number;
  syndromeFrequency: Record<string, number>;
}
```

## 四、评分算法

### 4.1 严重度数值映射

```
L1 → 1
L2 → 2  
L3 → 3
```

### 4.2 能力评分公式

```
对于某项能力 ABL-xxx：
  1. 找出所有相关症候 S = ability-atlas.abilities[ABL-xxx].syndromes
  2. 从最近 N 次诊断（默认 N=20）中，提取这些症候的严重度
  3. 计算平均严重度 avgSeverity = sum(severityValues) / count
  4. 评分 score = max(0, 100 - avgSeverity * 33.33)

特殊情况：
  - 如果该能力没有任何相关症候记录 → score = 100（默认满分）
  - 如果只有 1-2 次记录 → 仍然计算，但标记为"数据不足"
```

### 4.3 弱点标签判定

```
对于每个症候 P-xxx：
  1. 统计过去 N 次诊断中的出现次数
  2. 计算平均严重度
  3. 如果 出现次数 >= 3 且 平均严重度 >= 2 → 标记为弱点
  4. 趋势判断：比较最近 5 次 vs 之前 5 次的平均严重度
```

### 4.4 趋势判断

```
trend 计算：
  recent = 最近 5 次诊断的平均严重度
  previous = 之前 5 次诊断的平均严重度
  
  if recent < previous * 0.8 → 'improving' / 'up'
  if recent > previous * 1.2 → 'worsening' / 'down'
  else → 'stable'
```

## 五、修改位置

| 文件 | 修改类型 | 内容 |
|------|---------|------|
| `src/main/db/006_user_training.sqlite` | 新增 | 建表 SQL |
| `src/main/services/ability-profile.service.ts` | 新增 | 能力画像聚合计算 |
| `src/main/services/training-record.service.ts` | 新增 | 训练记录 CRUD |
| `src/main/ipc/ability-profile.handler.ts` | 新增 | IPC handler |
| `src/renderer/shared/types.ts` | 修改 | 新增 AbilityProfile 等接口 |
| `src/preload/index.ts` | 修改 | 白名单新增 ability:getProfile |
| `src/renderer/stores/ability-profile.store.ts` | 新增 | 前端状态管理 |
| `src/renderer/components/AbilityProfilePanel.tsx` | 新增 | 能力画像展示 |
| `src/main/index.ts` | 修改 | 执行 006 迁移 + 注册 handler |

## 六、IPC 接口

### 新增通道

| 通道 | 类型 | 请求 | 响应 | 说明 |
|------|------|------|------|------|
| `ability:getProfile` | invoke | `{ sessionId: string }` | `AbilityProfile` | 获取能力画像 |
| `ability:recordTraining` | invoke | `{ sessionId, taskId, status }` | `void` | 记录训练状态 |

### 事件通道（暂无）

能力画像变更暂不发事件推送。前端在切换会话或用户主动刷新时查询。

## 七、影响面分析

| 维度 | 影响 |
|------|------|
| 前端 UI | 新增 AbilityProfilePanel 组件，不影响现有组件 |
| 现有 IPC | 新增 2 个通道，不影响现有 19 个通道 |
| 现有数据流 | diagnosis.handler 保存诊断后，新增一步"触发画像更新"（异步，不阻塞） |
| 存储 | 新增 user_training_records 表，不影响已有表 |
| 性能 | 实时聚合，单次查询扫描最近 20 条诊断记录，当前规模无性能问题 |

## 八、前端展示设计（最小实现）

第一阶段只实现最基础的信息展示：

```
AbilityProfilePanel
├── 能力评分列表（8项，每项显示名称+分数+趋势箭头）
├── 弱点标签（当前活跃的弱点列表）
├── 训练统计（已完成/已分配）
└── 诊断次数（总诊断次数 + 平均置信度）
```

不实现：雷达图、成长曲线、历史对比等复杂可视化。
