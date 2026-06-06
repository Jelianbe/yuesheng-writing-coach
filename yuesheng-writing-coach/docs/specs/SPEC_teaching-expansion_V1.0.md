# 教学系统扩展：世界观构建与角色塑造

> 版本：V1.0 | 创建：2026-06-01  
> 依据：  
> - design-philosophy_V1.0.md → 第三章「降级规则」、第八章「能力图谱」  
> - worldbuilding-character-craft-foundation.md → 第二章「四大层级模型」、第三章「McKee角色理论」  
> 回退方案：若扩展导致状态机异常，回退到 types.ts 中删除新增枚举值，并恢复 teaching-state-machine.ts 的 PHASE_SUBPHASES 为原始配置

---

## 一、改造范围总览

本次改造涉及三项内容，按实施顺序排列：

| 序号 | 改造项 | 当前状态 | 目标状态 | 改造成本 |
|------|-------|---------|---------|---------|
| 1 | P1_WORLD 子阶段扩展 | 2 个子阶段 | 5 个子阶段 | 低 |
| 2 | 症候库扩充 | 7 个症候（P001-P007） | 10 个症候（P001-P010） | 低 |
| 3 | 训练任务映射补全 | 仅 T001/T003/T005/T007/T009/T011/T013 有内容 | 7+7 全部映射就位 | 极低 |

---

## 二、改造项一：P1_WORLD 子阶段扩展

### 2.1 当前结构

```
P1_WORLD → [S1_PROTAGONIST, S1_FIRST_SCENE]
```

### 2.2 目标结构

```
P1_WORLD → [S1_NATURAL_LAW, S1_PROTAGONIST, S1_SOCIAL_STRUCT, S1_FIRST_SCENE, S1_DAILY_DETAIL]
```

### 2.3 新增子阶段详解

#### S1_NATURAL_LAW「自然法则」

| 项目 | 内容 |
|------|------|
| **教学目的** | 引导用户确定世界最底层的运行规则（力量体系/能量守恒/超自然规则） |
| **对应理论** | worldbuilding-character-craft-foundation.md 2.2「四大层级模型」——第一层：自然法则 |
| **典型教学对话** | "你故事里的世界，最基本的一条规则是什么？比如，魔法有代价吗？" |
| **子阶段目标** | 用户能说出一条清晰的"这个世界与真实世界不同的根本规则" |
| **关联动作** | A004（从核心搭建） |

#### S1_SOCIAL_STRUCT「社会结构」

| 项目 | 内容 |
|------|------|
| **教学目的** | 引导用户思考力量体系如何影响社会权力分布、势力格局 |
| **对应理论** | worldbuilding-character-craft-foundation.md 2.2「四大层级模型」——第二层：社会结构 |
| **典型教学对话** | "你的力量体系让这个世界分成了哪些势力？主角一开始在哪个位置？" |
| **子阶段目标** | 用户能描述出世界观下的至少两股对立势力或阶层 |
| **关联动作** | A004（从核心搭建）、A002（回到主角） |

#### S1_DAILY_DETAIL「日常细节」

| 项目 | 内容 |
|------|------|
| **教学目的** | 引导用户通过日常细节（物价、饮食、交通、社会礼仪）让世界有"烟火气" |
| **对应理论** | worldbuilding-character-craft-foundation.md 2.3「冰山理论」——设计100%、只露10% |
| **典型教学对话** | "在这个世界里，一个普通人一顿午餐大概要花多少钱？" |
| **子阶段目标** | 用户能给出 3 个以上让世界有真实感的日常细节 |
| **关联动作** | A003（扎根现实）、A005（展示而非讲述） |

### 2.4 修改位置

| 文件 | 修改内容 |
|------|---------|
| `shared/types.ts` | TeachingSubphase 枚举增加 3 个新值 |
| `teaching-state-machine.ts` | SUBPHASE_NAMES 加 3 条映射、PHASE_SUBPHASES 的 P1_WORLD 数组扩展、calculateNextActions 加 3 条分支 |
| `teaching-state.types.ts` | 自动继承（re-export 不改） |

### 2.5 数据结构（无变化）

此次改造不涉及数据库 schema 变更。TeachingSubphase 枚举值扩展后，teaching_state 表的 current_subphase 字段自动支持新值。

### 2.6 关键决策与权衡

- **线性推进 vs 条件分支**：本次改造保持线性推进（不加入条件边）。条件分支属于后续优化的图结构增强（参见 [research/codegraph-survey_V1.0.md](../research/codegraph-survey_V1.0.md) 第四章），不在本次范围内
- **回退方案**：如果新子阶段导致现有会话的状态机卡死，可在 types.ts 中恢复枚举到旧的 2 子阶段状态

---

## 三、改造项二：症候库扩充

### 3.1 新增症候清单

#### P008：世界观说明书症（WorldbuildingManual）

| 项目 | 内容 |
|------|------|
| **核心特征** | 用户通过大段说明而非角色体验来展现世界观。主角停下不做事，世界设定却先写了 500 字 |
| **对应理论** | worldbuilding-character-craft-foundation.md 2.3「冰山理论」、2.4「展示而非告知原则」 |
| **严重度 L1** | 偶尔出现，说明段落不超过 200 字 |
| **严重度 L2** | 经常出现，说明段落 200-500 字 |
| **严重度 L3** | 每章开头必有大段说明，严重阻碍叙事节奏 |
| **识别信号** | "在这个世界里...""据悉..." "自古以来..."等说明书句式；角色行为中断超过 3 句才回到叙事 |
| **建议动作** | A005（展示而非讲述）、A003（扎根现实） |

#### P009：角色动机缺失症（MotivationDeficit）

| 项目 | 内容 |
|------|------|
| **核心特征** | 角色行为缺乏内在驱动力。角色做一件事是因为"剧情需要"而不是"角色想这么做" |
| **对应理论** | worldbuilding-character-craft-foundation.md 3.1.3「角色的两大驱动力——欲望与恐惧」 |
| **严重度 L1** | 配角偶发行为动机模糊 |
| **严重度 L2** | 核心角色行为动机不清晰，读者不理解"他为什么这么做" |
| **严重度 L3** | 所有角色的行为都由剧情推动，角色完全沦为剧情工具 |
| **识别信号** | "巧合"事件过多；角色在重大决定前没有内心挣扎；读者问"他为什么不去..." |
| **建议动作** | A002（回到主角）、A006（对话段落练习） |

#### P010：OC 平面化症（OCFlatness）

| 项目 | 内容 |
|------|------|
| **核心特征** | 角色只有外貌、职业、性格标签（"高冷""温柔"），没有成长弧光。角色从第一章到最后一章性格没有变化 |
| **对应理论** | worldbuilding-character-craft-foundation.md 3.1.2「三层次模型」、3.1.6「人物弧光三阶段公式」 |
| **严重度 L1** | 配角扁平，主角有弧光但不够明确 |
| **严重度 L2** | 主角弧光缺失，角色经历了大事但性格没变 |
| **严重度 L3** | 所有角色都像纸板人，读完记不住任何一个角色 |
| **识别信号** | 角色从头到尾用同一个语气说话；经历重大事件后没有任何性格变化；角色之间的对话可以互换 |
| **建议动作** | A006（对话段落练习）、A007（视角切换练习） |

### 3.2 修改位置

| 文件 | 修改内容 |
|------|---------|
| `shared/types.ts` | SyndromeId 枚举增加 3 个新值 |
| `syndrome-manual.md` | 增加 3 章新的症候识别标准 |
| `training-tasks.md` | 填充 T002/T004/T006/T008/T010/T012 任务内容 |
| `recommendation-engine.ts` | SYNDROME_TASK_MAP 增加 3 条映射 |
| `teaching-state.types.ts` | 自动继承（无修改） |

### 3.3 数据格式

SyndromeId 枚举扩展后，AI 诊断输出中新增症候的解析自动生效——诊断解析器（diagnosis-parser.ts）通过 `Object.values(SyndromeId)` 校验症候 ID 的有效性，枚举扩展后新值自动纳入白名单。

### 3.4 关键决策与权衡

- **为什么不新增动作（A009-A010）**：当前的 8 个动作已经能够覆盖新建候对应的教学策略（A005 show-don't-tell 恰好对应 P008 世界观说明书症）。新增动作会产生新的 IPC 和 UI 改动，增加风险。等教学实践验证后再决定是否需要新增
- **为什么先加上训练任务映射**：推荐引擎的 SYNDROME_TASK_MAP 已经预留了偶数槽位。填充映射不改变任何接口和数据流，零风险

---

## 四、改造项三：训练任务映射填充

### 4.1 当前状态

SYNDROME_TASK_MAP 中每个症候有 2 个任务槽，但偶数编号槽位（T002/T004/T006/T008/T010/T012）的内容未填充。

### 4.2 填充方案

| 症候 | 任务 1（已填） | 任务 2（本次填充） |
|------|---------------|------------------|
| P001 世界观膨胀 | T001 限定空间内描述 | T002 用角色行动展现世界观（新增） |
| P002 角色工具人化 | T003 给角色补充一个动机 | T004 写角色的内心挣扎（新增） |
| P003 情绪标签化 | T005 替换情绪词为行动 | T006 用环境烘托情绪（新增） |
| P004 信息倾泻 | T007 拆分信息段落 | T008 信息隐含在对话中（新增） |
| P005 视角漂移 | T009 保持固定视角段落练习 | T010 切换视角场景练习（新增） |
| P006 节奏凝滞 | T011 删减冗余段落 | T012 插入冲突或信息（新增） |
| P007 阅读结构单一 | T013 分析经典段落结构 | T014 模仿结构写一段（新增） |

### 4.3 修改位置

| 文件 | 修改内容 |
|------|---------|
| `recommendation-engine.ts` | SYNDROME_TASK_MAP 中各症候的 task 数组从 `[1个]` 补齐到 `[2个]` |

---

## 五、影响面分析

### 5.1 影响文件清单

| 文件 | 改造项 | 改动类型 |
|------|--------|---------|
| `src/renderer/shared/types.ts` | ①+② | 枚举扩展（TeachingSubphase + 3、SyndromeId + 3） |
| `src/main/services/teaching-state-machine.ts` | ① | 名称映射 + 子阶段序列 + 动作建议（约 30 行） |
| `src/main/services/recommendation-engine.ts` | ②+③ | SYNDROME_TASK_MAP 扩展（约 20 行） |
| `resources/prompts/syndrome-manual.md` | ② | 新增 3 章症候识别标准 |
| `resources/prompts/training-tasks.md` | ③ | 填充 6 个训练任务内容 |
| `src/main/services/__tests__/test-factories.ts` | ② | 测试工厂增加新症候数据 |
| `src/main/services/__tests__/diagnosis-parser.test.ts` | ② | 新增诊断解析测试用例 |
| `src/main/ipc/__tests__/merge-diagnosis.test.ts` | ② | 新增合并逻辑测试用例 |

### 5.2 不受影响的文件

以下文件经过逐一排查，确认不受本次改造影响：
- `src/preload/index.ts`（无 IPC 通道变更）
- `src/renderer/stores/*.store.ts`（无前端逻辑变更）
- `src/renderer/components/*.tsx`（诊断面板自动支持新增枚举值）
- `src/main/db/*.sql`（无数据库 schema 变更）
- `src/main/ipc/*.handler.ts`（无 IPC 协议变更）
- `src/main/api-proxy.ts`（无 API 调用变更）
- `resources/prompts/action-library.md`（动作库无变更）
- `resources/prompts/core-principles.md`（核心原则无变更）
- `resources/prompts/yuesheng-prompt-v3.md`（系统 Prompt 无变更——AI 会自动学习新症候）

### 5.3 测试影响

新增 SyndromeId 枚举值后，受影响的测试文件需要同步更新：

| 测试文件 | 需要更新的内容 |
|---------|--------------|
| `test-factories.ts` | `createMockDiagnosisEntry` 中 SyndromeId 的随机取值需要包含新值 |
| `diagnosis-parser.test.ts` | 新增新症候的诊断解析测试用例 |
| `merge-diagnosis.test.ts` | 新增新症候的合并测试用例 |
| `teaching-state-machine.test.ts` | 确保 P1_WORLD 的 5 个子阶段流转测试通过 |
