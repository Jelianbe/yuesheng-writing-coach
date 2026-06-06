# 月笙写作教练 - 教学状态机技术设计文档

**版本**: V1.0  
**创建日期**: 2026-06-01  
**状态**: draft  
**关联文档**: [PRD_V1.0.md](../PRD_V1.0.md), [diagnosis-layer-design_V1.0.md](./diagnosis-layer-design_V1.0.md)

---

## 1. 设计目标

教学状态机是月笙写作教练的核心组件，解决以下问题：

| 问题 | 解决方案 |
|------|---------|
| AI 记忆缺陷 | 外部持久化存储教学状态 |
| 教学割裂 | 状态机驱动教学流程 |
| 无法按图索骥 | 记录已完成动作和当前进度 |
| 用户缺乏进度感 | UI 展示教学进度、已完成、下一步 |

**核心理念**：诊断层 = 教学状态记录器，而非文本分析器。

---

## 2. 教学阶段定义

### 2.1 大阶段流转

```
P0_INIT → P1_WORLD → P2_PRACTICE_LOOP → P4_REVIEW
                          ↑↓
                 (可反复在诊断和训练间切换)
```

| 阶段 | 说明 | 子阶段 |
|------|------|--------|
| **P0_INIT** | 初次见面，了解用户写作目标 | 无 |
| **P1_WORLD** | 世界观搭建：确定主角 + 缩小到第一个具体场景 | S1_PROTAGONIST, S1_FIRST_SCENE |
| **P2_PRACTICE_LOOP** | 诊断-训练循环：识别问题 → 推荐任务 → 练习 → 反馈 | S2_IDENTIFY, S2_TEACHING, S2_ASSIGN_TASK, S2_REVIEW_TASK |
| **P4_REVIEW** | 复盘总结 | S4_SUMMARY |

### 2.2 简化设计理由

- **P1_WORLD 不强制冲突**：冲突可以后续自然涌现
- **P2_PRACTICE_LOOP 是循环**：用户不可能一次性解决所有问题，反复迭代
- **不自动离开循环**：除非用户明确说"我想复盘"或达到一定轮次

---

## 3. 数据库设计

### 3.1 teaching_state 表

```sql
CREATE TABLE IF NOT EXISTS teaching_state (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL UNIQUE,
    current_phase TEXT NOT NULL DEFAULT 'P0_INIT',
    current_subphase TEXT,
    completed_actions TEXT DEFAULT '[]',
    completed_tasks TEXT DEFAULT '[]',
    active_problems TEXT DEFAULT '[]',
    next_suggested_actions TEXT DEFAULT '[]',
    current_task_id TEXT,
    diagnosis_summary TEXT DEFAULT '',
    last_user_confirmation TEXT,
    updated_at TEXT NOT NULL,
    FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
);
```

### 3.2 关键字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `completed_actions` | JSON 数组 | 已完成的教学动作 ID 列表 |
| `active_problems` | JSON 数组 | 当前活跃的病症问题（含状态：active/improving/resolved） |
| `diagnosis_summary` | 文本 | 诊断历史摘要（最近 3 轮简洁文本） |
| `last_user_confirmation` | ISO 时间 | 用户最后确认时间 |

---

## 4. 状态机核心逻辑

### 4.1 阶段推进规则

```typescript
function getNextPhase(current: TeachingPhase): TeachingPhase {
  switch(current) {
    case INIT: return WORLD;
    case WORLD: return PRACTICE_LOOP;
    case PRACTICE_LOOP: return PRACTICE_LOOP; // 不自动离开循环
    case REVIEW: return PRACTICE_LOOP;
    default: return PRACTICE_LOOP;
  }
}
```

### 4.2 用户确认推进

```
用户点击"我懂了"按钮
  ↓
confirmPhaseComplete() 计算新状态
  ↓
更新数据库
  ↓
推送 IPC 事件到渲染进程
  ↓
UI 自动刷新
  ↓
下一轮对话注入新状态
```

### 4.3 状态更新示例

**初始状态**：
```json
{
  "currentPhase": "P1_WORLD",
  "currentSubphase": "S1_PROTAGONIST",
  "completedActions": [],
  "nextSuggestedActions": ["A001", "A002"]
}
```

**用户确认后**：
```json
{
  "currentPhase": "P1_WORLD",
  "currentSubphase": "S1_FIRST_SCENE",
  "completedActions": ["A001", "A002"],
  "nextSuggestedActions": ["A003", "A005"]
}
```

---

## 5. System Prompt 注入格式

### 5.1 注入内容

```
【当前教学进度】
你正在与用户进行【世界观搭建】阶段的教学。
当前子阶段：确定主角

【已完成的教学动作】
- A001（缩小范围）：用户已经学会把宏大设定聚焦到第一个具体场景。
下次如果用户再次膨胀，可以提醒但不必重新教学。

【用户当前问题】
- P001（世界观膨胀，活跃）

【建议你下一步使用】
- A002（回归主角）

请根据这个进度，继续你的教练对话。
不要重复已经教过的内容。
聚焦在建议的教学动作上。
```

### 5.2 注入时机

每次调用 AI 时，将当前教学状态注入 System Prompt。

---

## 6. UI 交互设计

### 6.1 教学进度面板

```
┌─────────────────────────────────┐
│ 📚 教学进度                      │
├─────────────────────────────────┤
│                                 │
│ 当前阶段：世界观搭建              │
│ 子阶段：确定主角                 │
│                                 │
│ ─── 进度条 ───                  │
│ ████████░░░░░░░░  50%          │
│                                 │
│ 已完成：                        │
│ ✓ A001 缩小范围                 │
│                                 │
│ 建议下一步：                    │
│ → A002 回归主角                 │
│ → A001 缩小范围                 │
│                                 │
│ 当前问题：                      │
│ ● P001 (活跃)                   │
│                                 │
│ [ 我懂了，继续 → ]              │
└─────────────────────────────────┘
```

### 6.2 确认对话框

用户点击"我懂了"后弹出：

```
┌─────────────────────────────────┐
│ 确认进度推进                     │
│                                 │
│ 确认已完成当前教学步骤？确认后将 │
│ 继续下一阶段的教学。              │
│                                 │
│          [取消]  [确认，继续]    │
└─────────────────────────────────┘
```

### 6.3 触发方式

| 触发方式 | 说明 | MVP 状态 |
|---------|------|---------|
| 用户点击"我懂了"按钮 | 主要推进手段 | ✅ 实现 |
| NLP 关键词检测 | 检测"我懂了/明白了" | Phase 2 |
| AI 建议状态更新 | AI 输出 JSON 建议 | Phase 2 |

---

## 7. 技术架构

### 7.1 文件结构

```
src/
├── main/
│   ├── db/
│   │   └── 003_create_teaching_state.sql    # 数据库迁移
│   ├── services/
│   │   ├── teaching-state.types.ts          # 类型定义
│   │   ├── teaching-state-machine.ts        # 状态机核心逻辑
│   │   └── teaching-state.store.ts          # 数据库操作层
│   ├── ipc/
│   │   └── teaching-state.handler.ts        # IPC 处理器
│   └── index.ts                             # 主进程入口
└── renderer/
    ├── stores/
    │   └── teaching-state.store.ts          # 前端状态管理
    └── components/
        └── TeachingProgressPanel.tsx        # 教学进度面板
```

### 7.2 IPC 通道

| 通道 | 方向 | 用途 |
|------|------|------|
| `teachingState:get` | 渲染 → 主 | 获取教学状态 |
| `teachingState:update` | 渲染 → 主 | 更新教学状态 |
| `teachingState:confirm` | 渲染 → 主 | 用户确认完成，推进状态 |
| `teachingState:getPrompt` | 渲染 → 主 | 获取 System Prompt 注入内容 |
| `teachingState:updateSummary` | 渲染 → 主 | 更新诊断摘要 |
| `teachingState:updated` | 主 → 渲染 | 状态变更推送 |

---

## 8. 与诊断层的关系

### 8.1 诊断层 vs 教学状态机

| 维度 | 诊断层（旧） | 教学状态机（新） |
|------|------------|----------------|
| 职责 | 文本分析，识别病症 | 教学进度跟踪 |
| 数据来源 | AI 输出 | 用户确认 + 程序控制 |
| 存储 | 临时状态 | 持久化数据库 |
| 展示 | 病症列表 | 教学进度 + 已完成 + 下一步 |

### 8.2 整合方案

- **诊断面板**：继续展示 AI 识别的病症（作为辅助反馈）
- **教学进度面板**：新增，展示教学状态机数据
- **两个面板并存**：用户可以看到诊断结果和教学进度

---

## 9. 实施状态

| 步骤 | 内容 | 状态 |
|------|------|------|
| 1 | 创建 teaching_state 表 | ✅ 完成 |
| 2 | 定义 TypeScript 接口 | ✅ 完成 |
| 3 | 实现基础状态机 | ✅ 完成 |
| 4 | 创建数据库操作层 | ✅ 完成 |
| 5 | 注册 IPC 处理器 | ✅ 完成 |
| 6 | 前端教学进度面板 | ✅ 完成 |
| 7 | "我懂了"按钮 + 确认对话框 | ✅ 完成 |
| 8 | System Prompt 动态注入 | ✅ 完成 |
| 9 | 诊断摘要更新逻辑 | ✅ 完成 |
| 10 | 类型检查验证 | ✅ 完成 |

### 9.1 待完成

| 项目 | 说明 | 优先级 |
|------|------|--------|
| 安装 better-sqlite3 | 取消代码中的 TODO 注释 | P0 |
| 前端 IPC 调用集成 | TeachingProgressPanel 中的 TODO | P0 |
| 聊天界面集成 System Prompt 注入 | chat.service.ts 中调用 | P0 |
| NLP 关键词检测 | Phase 2 功能 | P1 |
| AI 状态更新建议解析 | Phase 2 功能 | P1 |

---

## 10. 风险与缓解

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| better-sqlite3 未安装 | 数据库操作不可用 | 已标记 TODO，待安装 |
| 状态机逻辑错误 | 教学流程混乱 | 单元测试覆盖 |
| 用户误点击"我懂了" | 状态超前推进 | 确认对话框防止误操作 |
| 状态与 AI 不同步 | AI 输出不符合当前进度 | System Prompt 注入确保同步 |

---

**文档版本历史**

| 版本 | 日期 | 变更内容 | 变更人 |
|------|------|---------|--------|
| V1.0 | 2026-06-01 | 初始版本 | AI 助手 |
