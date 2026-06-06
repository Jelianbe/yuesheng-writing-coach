---
id: T-003
status: completed
follows: T-002
precedes: T-004
started: 2026-06-01
completed: 2026-06-01
---

# T-003: 世界观构建与角色塑造教学扩展

## 目标

基于设计哲学和公开教学理论，扩展月笙的症候库和教学流程，深化网文世界观构建和角色/OC塑造方向的教学能力。

## 设计哲学依据

- **设计哲学文档**: [design-philosophy_V1.0.md](../design/design-philosophy_V1.0.md)
  - 第三章「降级规则」——将宏观理论拆解为可教学动作
  - 第八章「能力图谱」——症候、训练、能力的映射体系
- **理论基础文档**: [worldbuilding-character-craft-foundation.md](../research/worldbuilding-character-craft-foundation.md)
  - 第二章「四大层级模型」——世界观构建的4个层次
  - 第三章「McKee角色理论」——角色三层次模型、欲望驱动、人物弧光
- **技术规格**: [SPEC_teaching-expansion_V1.0.md](../specs/SPEC_teaching-expansion_V1.0.md)

## 涉及文件

| 文件 | 改动类型 |
|------|---------|
| `src/renderer/shared/types.ts` | 枚举扩展（TeachingSubphase + 3、SyndromeId + 3） |
| `src/main/services/teaching-state-machine.ts` | 名称映射 + 子阶段序列 + 动作建议 |
| `src/main/services/recommendation-engine.ts` | SYNDROME_TASK_MAP 扩展 |
| `resources/prompts/syndrome-manual.md` | 新增 3 章症候识别标准 |
| `resources/prompts/training-tasks.md` | 填充 6 个训练任务内容 |
| `src/main/services/__tests__/test-factories.ts` | 测试工厂增加新症候数据 |
| `src/main/services/__tests__/diagnosis-parser.test.ts` | 新增诊断解析测试用例 |
| `src/main/ipc/__tests__/merge-diagnosis.test.ts` | 新增合并逻辑测试用例 |

## 实施步骤

### 步骤 1：扩展 P1_WORLD 子阶段
- TeachingSubphase 枚举增加 `S1_NATURAL_LAW`, `S1_SOCIAL_STRUCT`, `S1_DAILY_DETAIL`
- SUBPHASE_NAMES 增加 3 条名称映射
- PHASE_SUBPHASES 的 P1_WORLD 数组扩展为 5 个子阶段
- calculateNextActions 增加 3 条子阶段动作建议
- 测试：teaching-state-machine.test.ts 验证新子阶段流转

### 步骤 2：扩充症候库
- SyndromeId 枚举增加 `WorldbuildingManual(P008)`, `MotivationDeficit(P009)`, `OCFlatness(P010)`
- syndrome-manual.md 增加 3 章症候识别标准
- recommendation-engine.ts SYNDROME_TASK_MAP 增加 P008→T015/T016、P009→T017/T018、P010→T019/T020 映射
- 测试工厂增加新症候数据
- 测试：diagnosis-parser.test.ts 验证新症候解析
- 测试：merge-diagnosis.test.ts 验证新症候合并

### 步骤 3：填充训练任务映射
- recommendation-engine.ts 中补齐 7 个症候的偶数编号槽位
- training-tasks.md 填充 6 个训练任务内容

## DoD（验收标准）

- [ ] P1_WORLD 子阶段从 2 个扩展到 5 个，状态机流转正常，无异常抛错
- [ ] 3 个新增症候能被诊断解析器正确解析、验证和合并
- [ ] 训练任务映射完整（P001-P010 全部有对应训练任务）
- [ ] 85+ 测试全部通过
- [ ] 类型检查零错误
- [ ] 不破坏现有 IPC 通道和前端 UI 行为

## 执行记录

### 变更溯源
- **设计哲学依据**: design-philosophy_V1.0.md 第三章、第八章
- **研究基础**: worldbuilding-character-craft-foundation.md 第二章、第三章
- **技术规格**: SPEC_teaching-expansion_V1.0.md

### 变更日志
| 日期 | 文件 | 变更内容 |
|------|------|---------|
| 2026-06-01 | — | 任务创建（待执行） |
