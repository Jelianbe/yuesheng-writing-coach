# 聚焦方向与过渡邀请机制

> 版本：V1.0 | 创建：2026-06-01  
> 依据：  
> - design-philosophy_V1.0.md → 用户主权原则、降级规则  
> - 用户场景：专精世界观/OC 的用户需要被邀请进入故事创作，而非强制转换  
> 回退方案：删除 focusArea 和 transitionOffered 字段，恢复状态机到 T-004 完成状态

---

## 一、目标

让用户能在进入系统时选择"聚焦方向"（世界观/角色/综合），并在完成专精领域后收到一次性的"过渡邀请"反问，优雅地引导用户探索相邻创作领域。

核心原则：**邀请，不强制。问一次，不重复。**

## 二、数据模型变更

### 2.1 TeachingState 新增字段

```typescript
interface TeachingState {
  // ... 已有字段 ...
  
  /** 当前聚焦方向 */
  focusArea: 'worldbuilding' | 'character' | 'general' | null;
  
  /** 是否已提供过过渡邀请（防止重复） */
  transitionOffered: boolean;
}
```

### 2.2 默认值

```typescript
focusArea: null,        // 初次进入未选择
transitionOffered: false,
```

## 三、聚焦方向：P0_INIT 阶段的选择

### 3.1 流程

```
P0_INIT（初次见面）
  │
  ├── AI 自我介绍后，询问：
  │   "你最近主要想练什么？"
  │   A. 搭建世界观
  │   B. 设计角色/OC
  │   C. 综合提升（写完整故事）
  │
  ├── 用户选择 A → focusArea = 'worldbuilding'
  ├── 用户选择 B → focusArea = 'character'
  └── 用户选择 C → focusArea = 'general'
```

### 3.2 对后续流程的影响

| focusArea | P1_WORLD 子阶段 | P2_PRACTICE_LOOP 诊断策略 |
|-----------|---------------|------------------------|
| worldbuilding | 完整 5 个子阶段 | 优先诊断 P001/P004/P008 |
| character | 只走 S1_PROTAGONIST（确定主角），然后进入 P2 | 优先诊断 P002/P009/P010 |
| general | 完整 5 个子阶段 | 诊断全部症候 |
| null | 完整 5 个子阶段（向后兼容） | 诊断全部症候 |

## 四、过渡邀请：完成专精后的反问引导

### 4.1 触发条件

```
同时满足：
  1. focusArea !== 'general'（专精模式才触发）
  2. transitionOffered === false（没问过）
  3. 用户完成了当前 focusArea 的核心教学
     - worldbuilding: P1_WORLD 全部 5 个子阶段完成
     - character: P2_PRACTICE_LOOP 中角色相关症候的训练已完成至少 2 个
```

### 4.2 反问话术

```typescript
const TRANSITION_PROMPTS: Record<string, string> = {
  worldbuilding: `你的世界已经很有质感了——自然法则清晰、社会结构有张力、日常细节让人能"住"进去。

我很好奇：这样一个世界里，会发生什么样的故事？有个什么样的主角，会在这片土地上留下痕迹？

（不用急着回答，只是突然想到。如果你还想继续深挖世界观，我完全陪你。）`,

  character: `你的 OC 已经立住了——有欲望、有矛盾、有让人记住的记忆点。

我忍不住想：这么好的角色，难道就让他/她呆在设定集里吗？在一个什么样的世界里，他/她会被迫做出最难的选择？

（不用急着回答。如果你还想继续打磨角色，我完全陪你。）`,
};
```

### 4.3 用户回应路由

```
用户收到过渡邀请后的可能回应：
  │
  ├── "想试试" / "好" / 开始写故事 → 
  │   focusArea = 'general'
  │   transitionOffered = true
  │   进入故事创作引导
  │
  ├── "先不" / "还想继续练" / 回到原话题 →
  │   transitionOffered = true（标记为已邀请，不再重复）
  │   保持当前 focusArea
  │
  └── 其他回应 →
      AI 正常回应，不强制转换
```

## 五、Prompt 注入策略

### 5.1 System Prompt 中增加 focusArea 感知

在 `buildSystemPromptWithState` 生成的 Prompt 中，增加一段 focusArea 描述：

```
【当前聚焦方向】
用户当前专注于：{worldbuilding/character/general}

{worldbuilding 时注入：}
- 诊断时优先关注世界观相关症候（P001 世界观膨胀、P004 信息硬塞、P008 世界观说明书）
- 教学时多引用世界观构建的案例和理论
- 引导用户通过"角色体验"来展现设定，而非直接说明

{character 时注入：}
- 诊断时优先关注角色相关症候（P002 角色工具人化、P009 角色动机缺失、P010 OC平面化）
- 教学时多引用角色塑造的案例和理论
- 引导用户从"压力下的选择"来刻画角色，而非标签描述

{general 时注入：}
- 诊断全部症候，不设优先级
- 平衡世界观、角色、结构三方面的教学
```

## 六、推荐引擎过滤

### 6.1 recommendation-engine.ts 修改

`recommendation-engine.ts` 的 `recommend` 方法增加 `focusArea` 参数：

```typescript
recommend(diagnosis: DiagnosisEntry, focusArea?: string): string[] {
  const baseRecommendations = /* 原有逻辑 */;
  
  if (!focusArea || focusArea === 'general') {
    return baseRecommendations;
  }
  
  // 按 focusArea 排序：相关症候的训练优先
  const prioritySyndromes = FOCUS_AREA_SYNDROMES[focusArea] || [];
  return baseRecommendations.sort((a, b) => {
    const aPriority = prioritySyndromes.includes(getSyndromeForTask(a)) ? 1 : 0;
    const bPriority = prioritySyndromes.includes(getSyndromeForTask(b)) ? 1 : 0;
    return bPriority - aPriority;
  });
}
```

## 七、修改文件清单

| 文件 | 修改类型 | 内容 |
|------|---------|------|
| `src/renderer/shared/types.ts` | 修改 | TeachingState 增加 focusArea + transitionOffered |
| `src/main/services/teaching-state-machine.ts` | 修改 | 方向选择逻辑、过渡邀请判断、Prompt 注入 |
| `src/main/services/recommendation-engine.ts` | 修改 | 推荐排序按 focusArea 过滤 |
| `src/main/services/teaching-state.store.ts` | 修改 | update 方法支持新字段 |
| `resources/prompts/yuesheng-prompt-v3.md` | 修改 | 增加 focusArea 感知策略说明 |
| `src/main/db/003_create_teaching_state.sql` | 修改 | 增加 focus_area、transition_offered 字段 |

## 八、影响面分析

| 维度 | 影响 |
|------|------|
| 前端 UI | 无影响（方向选择在聊天对话中完成，无新组件） |
| 现有 IPC | 无影响 |
| 数据库 | teaching_state 表增加 2 个字段，需迁移 |
| 现有流程 | general 模式完全保持现有行为，向后兼容 |
| 专精模式 | worldbuilding/character 模式下 AI 行为有针对性变化 |
