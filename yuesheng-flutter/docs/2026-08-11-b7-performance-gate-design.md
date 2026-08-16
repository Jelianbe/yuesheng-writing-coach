# 7.2 performance_gate 设计稿 — 介入级别加表现感知

> **状态**: ✅ 已实施（批次 16，2026-08-11）
> **日期**: 2026-08-11
> **依据**: 待办执行清单 7.2 / 模块审查包 A2（"介入级别阈值 0-1/2-3/≥4 次是否合理？"）
> **前置**: 批次 8（D3 介入级别综合 severity/relapse）已落地

---

## 一、背景与目标

### 1.1 现状

介入级别 = f(训练次数 + severity + 复发信号)（[syndrome_skill_levels.dart](file:///D:/teacher/yuesheng-flutter/lib/services/syndrome_skill_levels.dart)）：

- 基础次数分级：0-1 次 → I do（示范+引导）；2-3 次 → We do（标注+引导）；≥4 次 → You do（独立练习）
- 批次 8（D3）：`relapse` 或 `currentSeverity == L3` → 无条件回退 I do（防过早撤脚手架）

调用点：[chat_service.dart](file:///D:/teacher/yuesheng-flutter/lib/services/chat_service.dart) 步骤 6.3 介入级别注入（约 L894-931），注入前统计 `countTrainingForSyndrome`（teaching_history 中 type='training' 记录数）。

### 1.2 问题（模块审查包 A2）

- **纯次数分级的盲区**：训练 4 次但 4 次全未达标（passRate=0）→ 仍 You do（撤掉示范），学员得不到示范支持，训练空转。
- **反向盲区**：训练 1 次即连续 2 次达标、已明显掌握 → 仍 I do（重复示范），浪费一轮教学节奏、学员体验冗余。
- 现有 severity 信号（D3）只反映"当前诊断严重度"，不反映"训练表现趋势"——两者互补但不可互相替代。

### 1.3 目标

介入级别增加**表现感知**（performance gate），双向修正：
1. **延迟撤脚手架（保守，主）**：次数达标但历史表现差 → 不升档，甚至回退一档（宁可多练一轮，不虚报掌握）
2. **提前撤脚手架（正向，辅）**：次数不足但连续达标 → 提前升档（减少冗余示范）

与 D3（severity/复发，现状信号）优先级关系：**D3 > performance > 次数**。

---

## 二、设计决策

### 2.1 表现指标定义（对齐 FSM 同口径，不新增 schema）

从 teaching_history 的 `type='training'` 记录（含 `result: passed/partial/failed`）轻量统计：

| 指标 | 定义 | 说明 |
|---|---|---|
| `passRate` | passed 数 / 训练总数 | 与 training_input_builder L173 / 毕业复核同口径（partial 不计入通过） |
| `consecutivePasses` | 从最新记录倒序连续 passed 数 | 提前撤脚手架的依据 |
| `consecutiveFails` | 从最新记录倒序连续 failed 数 | 延迟/回退的依据（partial 不算 fail） |
| `totalCount` | 训练记录数 | 与 trainingCount 一致（冗余校验） |

数据不足（`totalCount == 0`）→ `performance = null` → 维持现有次数分级（不改变现状行为）。

### 2.2 修正规则

在**基础次数档位**基础上做单向调整（规则按序判断，first-match）：

**A. 延迟撤脚手架（保守，优先于提前）**

| 规则 | 触发条件 | 动作 |
|---|---|---|
| G1 强制 I do | `consecutiveFails >= 3`（连续 3 次未达标） | 无论次数/其它，降为 I do（学员明显卡住，重新给示范） |
| G2 降一档 | `passRate < 0.5` 且基础档位为 We do/You do | 降一档（We do → I do / You do → We do） |
| G3 不升档 | `consecutiveFails >= 2` 且基础档位为 You do | 保持 We do（不升 You do） |

**B. 提前撤脚手架（正向，谨慎）**

> 注：训练次数 = 训练记录数，`consecutivePasses` 不可能超过次数——故"提前"必须是**全部记录通过**（全通过才算证明掌握，避免"题目简单恰好连中"误伤）。

| 规则 | 触发条件 | 动作 |
|---|---|---|
| G4 升一档 | 基础档位为 I do 且 `trainingCount >= 1 && consecutivePasses == trainingCount`（首次训练即通过） | 升 We do（学员已看懂示范，转向引导） |
| G5 升一档 | 基础档位为 We do 且 `trainingCount >= 2 && consecutivePasses == trainingCount`（2-3 次全部通过） | 升 You do（连续稳定达标，撤示范） |

**优先级总序**：
1. D3：`relapse || currentSeverity == L3` → I do（无条件，最高）
2. performance 延迟规则（G1/G2/G3）
3. 基础次数档位
4. performance 提前规则（G4/G5）

即：**延迟修正永远优先于提前修正**；G1 强于 G2/G3；提前修正只在延迟修正未命中时生效。

### 2.3 边界与保守原则

- `performance == null`（无训练记录）→ 完全维持现状（次数分级 + D3 信号），回归零风险。
- partial 计为"未通过但未失败"：不进入 consecutiveFails，不进入 consecutivePasses。
- passRate 阈值 0.5 与连续失败 3 次/G4 连续达标 2 次等阈值，**第一阶段按保守值落地**，可后续用遥测调整（与批次 4.1 warning 级起步的观察思路一致）。
- 不新增 DB 字段/表；统计复用 teaching_history 现有记录。
- 注入消息中标注回退/提前原因（与 D3 的"回退原因说明"同款做法），帮助 AI 校准教学力度。

---

## 三、接口设计

### 3.1 统计函数（轻量，独立于 buildTrainingInputForActiveSyndrome）

新增于 [training_input_builder.dart](file:///D:/teacher/yuesheng-flutter/lib/services/training_input_builder.dart)（与 `countTrainingForSyndrome` 并列）：

```dart
/// 表现感知输入（performance_gate，7.2）
class TrainingPerformance {
  final double passRate;
  final int consecutivePasses;
  final int consecutiveFails;
  final int totalCount;
  const TrainingPerformance({...});
}

/// 统计指定症候的训练表现（无记录返回 null）
Future<TrainingPerformance?> computeTrainingPerformance(
  StudentModelRepository studentModelRepo,
  String sessionId,
  String syndromeId,
) async { ... }
```

读取方式与 `countTrainingForSyndrome` 完全一致（`getTeachingHistory` 过滤 `type=='training'` 与 `syndromeId`），**与训练次数统计合并为一次读取**（避免重复查询：`countTrainingForSyndrome` 改为内部复用同一次 history 拉取，或调用方一次拉取后分别计算——实施时取"一次拉取"方案）。

### 3.2 介入级别函数签名

[syndrome_skill_levels.dart](file:///D:/teacher/yuesheng-flutter/lib/services/syndrome_skill_levels.dart)：

```dart
InterventionLevel interventionLevelForTrainingCount(
  int trainingCount, {
  Severity? currentSeverity,
  bool? relapse,
  TrainingPerformance? performance,   // 新增（7.2），null = 无表现数据
})
```

- 函数体：D3 判断 → G1/G2/G3 → 基础次数档位 → G4/G5。
- 保持向后兼容：`performance` 缺省为 null，现有全部调用与测试行为不变（批次 8 D3 测试不受影响）。

### 3.3 调用点改动

[chat_service.dart](file:///D:/teacher/yuesheng-flutter/lib/services/chat_service.dart) 步骤 6.3 介入级别注入（约 L894-931）：

```
trainingCount + relapse + currentSeverity（现状）
  → computeTrainingPerformance(...) 一次拉取 history 得 performance
  → interventionLevelForTrainingCount(trainingCount, currentSeverity, relapse, performance)
  → 注入消息追加表现修正原因（如"连续 3 次未达标，回退 I do"）
```

try/catch 包裹，统计失败降级为 `performance=null`（延续 D3 的 SafeRun 防御风格）。

---

## 四、测试计划

### 4.1 纯函数单测（syndrome_skill_levels_test.dart，补 #G1-#G6）

| 用例 | 输入 | 期望 |
|---|---|---|
| #G1 | 训练 4 次、passRate=0、consecutiveFails=3 | I do（G1 强制） |
| #G2 | 训练 4 次、passRate=0.25、consecutiveFails=1 | We do（G2 降一档） |
| #G3 | 训练 4 次、passRate=0.6、consecutiveFails=2 | We do（G3 不升档） |
| #G4 | 训练 1 次、passRate=1.0、consecutivePasses=1（首次通过） | We do（G4 提前） |
| #G5 | 训练 2 次、passRate=1.0、consecutivePasses=2（全通过） | You do（G5 提前） |
| #G5b | 训练 3 次、passRate=1.0、consecutivePasses=3（全通过） | You do（G5 提前） |
| #G6 | performance=null 时维持次数分级（回归） | I do/We do/You do 按次数 |

补充组合：D3 L3 + performance 优 → 仍 I do（D3 优先）；G1 与 G4 同时满足 → G1 优先（连续 3 次未达标中不可能全通过，此组合天然不冲突，仅防御性断言）。

### 4.2 统计函数单测（training_input_builder_test 或新文件）

- 无训练记录 → null
- 混合结果 → passRate/consecutivePasses/consecutiveFails 计算正确（含 partial 不计入两者）

### 4.3 集成测试（chat_service 注入）

- 表现差症候 → 注入消息含回退原因 + 对应级别
- 表现优症候 → 注入消息含提前原因（若命中 G4/G5）
- 现有注入测试（#J1-J3）不回归

---

## 五、实施步骤（批次 16）

1. `training_input_builder.dart`：新增 `TrainingPerformance` + `computeTrainingPerformance`；`countTrainingForSyndrome` 改为复用同一次 history 拉取（不重复查询）
2. `syndrome_skill_levels.dart`：签名加 `performance` 参数 + G1-G5 规则实现
3. `chat_service.dart`：调用处统计 performance 并传参 + 注入消息附修正原因
4. 补测试（4.1/4.2/4.3）
5. 四闸验证（analyze 0 issues + 全量 test）
6. commit 批次 16 + 回填清单 7.2

## 六、风险与回滚

- **误伤率**：G4/G5（提前撤脚手架）是主要风险——连续 2 次达标可能恰逢"题目简单"。对策：第一阶段 G4 的 consecutivePasses 阈值保守取 2、G5 取 3；若遥测显示提前撤后出现复练，上调阈值或降级为仅 G1-G3（延迟修正）上线。
- **重复查询**：performance 与 trainingCount 若各查一次 history 会双倍 I/O——实施时合并为单次拉取（见 3.1）。
- **回滚**：performance 参数缺省 null，去掉调用处传参即可完全回退到现状行为（D3 逻辑不受影响）。
