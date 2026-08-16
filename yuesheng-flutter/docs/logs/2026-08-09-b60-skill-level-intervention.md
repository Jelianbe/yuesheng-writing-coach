# B60 教学决策层（技能层级 + 介入级别）— 交付提交日志

**日期**：2026-08-09
**类型**：功能增强（教学效率/品质核心——研究落地 V2.0 §2.1/§2.2）
**前置**：`37e8bc7`（批次 59 Just-in-Time 触发增强）

---

## 背景与立项

1. **用户需求**：研究品读后要求聚焦「教学更有效率、提高教学品质」的架构建议。
2. **建议提炼**（用户全选立项）：
   - **技能层级映射**（V2.0 §2.1 Progressive Mastery）：症候 → L1-L5 技能层级，焦点选择优先「当前层级+1」以内，避免越级教学（效率最大杠杆）
   - **I/We/You 动态介入**（V2.0 §2.2 Gradual Release）：同症候按训练次数逐步撤除脚手架——0-1 次 I do 示范 → 2-3 次 We do 引导 → ≥4 次 You do 独立（品质核心）
3. **设计红线**（用户偏好）：层级是**软引导不是硬拦截**——AI 建议不受限，仅 fallback 排序优先；介入级别是**参考输入**，AI 按学员情况判断（AI 自主判断优先）

## 改动内容

### lib/services/syndrome_skill_levels.dart（新建）
- `SkillLevel` 枚举（L1 基础表达 / L2 叙事节奏 / L3 角色塑造 / L4 情节结构 / L5 风格声线）
- `kSyndromeSkillLevels`：P003-P021 全部 19 症候层级映射
- `skillLevelOf`（未知 → null 不拦截）
- `skillLevelForBeginner`（N0/N1→L1、N2→L2、N3→L3、N4→L4）
- `InterventionLevel` 枚举（I do / We do / You do）+ `interventionLevelForTrainingCount`（0-1→iDo、2-3→weDo、≥4→youDo）

### lib/services/focus_resolver.dart
- `ResolveFocusInput` 加 `studentSkillLevel`（可选，向后兼容）
- `_selectFallback` 三优先级分支加层级软优先：`_preferLevelAppropriate` 在已排序候选中优先选「层级 ≤ 当前+1」；全部越级回退原逻辑（不硬拦截）

### lib/services/chat_service.dart
- 步骤 3 提取 `beginnerLevel`（方法级）
- 步骤 6.1 focus 输入传 `studentSkillLevel`
- 步骤 6.3 训练评估块前：读 `countTrainingForSyndrome` → 注入「训练介入级别」（I do/We do/You do 组织方式）
- 步骤 6.4 结构化上下文后：注入「学员技能层级」软引导（AI 自主判断，仅提示）

### lib/services/training_input_builder.dart
- 新增 `countTrainingForSyndrome`（独立于训练评估，诊断数不足时仍可用）

### 测试
- `syndrome_skill_levels_test.dart`（新建）13 用例：#S1-S3 层级表 / #S4-S6 beginner 映射 / #S7-S9 介入阈值 / #S10-S13 fallback 层级优先
- `chat_service_skill_injection_test.dart`（新建）3 用例：#J1 N1+未训练 → L1/I do 注入 / #J2 训练 4 次 → You do / #J3 无水平 → 不注入技能层级

## 关键设计

- **软引导**：技能层级只影响 fallback 排序 + prompt 提示，不拦截 AI 建议——「AI 自主判断优先」红线
- **撤脚手架**：介入级别随训练次数自动进阶，AI 据此调整示范/引导/独立的组织方式
- **向后兼容**：`studentSkillLevel` 可选参数；无学员水平时技能层级注入自动跳过，介入级别仍生效

## 四闸验证

- `dart format --set-exit-if-changed`：全过（0 changed）
- `flutter analyze --no-pub`：0 error 0 warning（32 info 全历史存量，未新增）
- `flutter test`：全量 **842 全绿 + 4 skipped**（+16：技能层级 13 + 注入集成 3）
- 文档同步：本日志

## 提交

| Commit | 日期 | 标题 |
|--------|------|------|
| （本次） | 2026-08-09 | feat: 批次60 教学决策层（症候技能层级 L1-L5 + fallback 层级软优先 + I/We/You 介入级别随训练次数进阶）+ 本日志 |
