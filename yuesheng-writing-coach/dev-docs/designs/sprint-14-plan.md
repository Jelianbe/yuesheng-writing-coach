# Sprint 14 实施计划 — 方向 C 核心升级

> **目标**: 完成 Issue #20 列出的方向 C 核心升级：attitude 实质过滤 + 运行时 conditions + 依赖图校验
> **范围**: Sprint 13 简化版的完整升级
> **前置**: Sprint 14-prior 完成（D-DEBT-09/11 解决）✓
> **依据**: dev-docs/designs/sprint-14-dispatcher-upgrade.md

---

## 一、目标

| ID | 任务 | 优先级 |
|----|------|--------|
| T14-2 | 扩展 SkillMetadata（depends / version / conditions） | P0 |
| T14-3 | 依赖图校验器（启动时 fail-fast） | P0 |
| T14-4 | Attitude 实质过滤（sensei 档删鼓励话术） | P1 |
| T14-5 | 运行时 conditions（evidence 质量 / DP 触发） | P1 |
| T14-6 | token 优先级 + 截断集成（已有 maxTokens 增强） | P1 |
| T14-7 | E2E 集成测试 | P2 |

## 二、不做

- 不改变 SKILL 文件内容（只扩展 metadata）
- 不实现灰度发布（推迟到 Sprint 15）
- 不重写 dispatcher 整体架构（只增强）

## 三、YAML metadata 完整 schema（Sprint 14 最终版）

```yaml
---
id: TEACHING.feedback
version: 1.0
estimatedTokens: 800
depends: [core-identity, validation-rules]
loadWhen:
  phases: [P2_PRACTICE_LOOP, P3_TRAINING, P4_REVIEW]
  attitudes: [doubao, yuesheng]
  conditions:
    - evidence.quality IN ['low', 'medium']
    - NOT user.safetyWord
tokenPriority: 8
isCoreSubset: false
parentId: null
---

# SKILL content
```

## 四、任务分解

### T14-2: 扩展 SkillMetadata

**Files**:
- 修改: `src/main/domains/03-teaching/prompt/skill-metadata.ts`
- 测试: `src/main/domains/03-teaching/prompt/__tests__/skill-metadata.test.ts`

**Step 1**: 扩展接口
```typescript
export interface SkillLoadWhen {
  phases: TeachingPhase[];
  attitudes: AttitudeLevel[];
  conditions?: LoadCondition[];  // 新增
}

export interface SkillMetadata {
  id: string;
  estimatedTokens: number;
  loadWhen: SkillLoadWhen;
  tokenPriority?: number;
  isCoreSubset?: boolean;
  parentId?: string | null;
  // 新增字段
  version?: string;             // 语义化版本
  depends?: string[];           // 依赖的其他 SKILL id
}

export type LoadCondition =
  | { type: 'evidence.quality'; op: 'IN' | 'NOT_IN'; values: string[] }
  | { type: 'user.safetyWord'; op: 'IS' | 'IS_NOT'; value: boolean }
  | { type: 'user.dominantSyndrome'; op: 'EQ' | 'NEQ'; syndromeId: string };
```

**Step 2**: 解析 depends / version 字段
- `parseOptionalYamlString(yaml, 'version')` 默认 `'1.0'`
- `parseOptionalYamlArray(yaml, 'depends')` 默认 `[]`

**Step 3**: 写测试
- depends 字段解析
- version 字段解析
- 默认值正确

**Step 4**: commit `feat(prompt): extend SkillMetadata with version/depends/conditions`

### T14-3: 依赖图校验器

**Files**:
- 新增: `src/main/domains/03-teaching/prompt/skill-graph.ts`
- 测试: `src/main/domains/03-teaching/prompt/__tests__/skill-graph.test.ts`
- 修改: `src/main/domains/03-teaching/prompt/skill-dispatcher.ts` (集成校验)

**Step 1**: 实现 `SkillGraph`
```typescript
export class SkillGraph {
  static validate(skills: Skill[]): {
    valid: boolean;
    errors: string[];
    cycles: string[][];
    missingDeps: string[];
  };
}
```

**Step 2**: 算法
- 拓扑排序检测循环依赖
- 索引所有 skills，校验 depends 是否存在
- 启动时调用 fail-fast

**Step 3**: SkillDispatcher 集成
- `load()` 后立即调用 `SkillGraph.validate()`
- 有错误时 throw with structured message

**Step 4**: 写测试
- 循环依赖检测
- 缺失依赖检测
- 合法依赖图通过

**Step 5**: commit `feat(prompt): SkillGraph dependency validator with fail-fast`

### T14-4: Attitude 实质过滤

**Files**:
- 修改: `src/main/domains/03-teaching/prompt/skill-dispatcher.ts`
- 新增: `src/main/domains/03-teaching/prompt/attitude-filter.ts`
- 测试: `src/main/domains/03-teaching/prompt/__tests__/attitude-filter.test.ts`

**Step 1**: 实现 attitude filter
```typescript
export class AttitudeFilter {
  static apply(content: string, attitude: AttitudeLevel): string;
}
```

**Step 2**: 过滤规则
| Attitude | 行为 |
|----------|------|
| doubao | 不过滤（默认态度） |
| yuesheng | 轻微优化（保留鼓励但不过度） |
| sensei | 删"加油""棒""继续努力"等鼓励词，保留技术性反馈 |

**Step 3**: 规则表外置
- `resources/config/attitude-filter.json`
- 按 R-014 配置外置

**Step 4**: SkillDispatcher 集成
- `selectForPhase` 后调用 `AttitudeFilter.apply()`
- 过滤仅作用于 `body`，不影响 metadata

**Step 5**: 写测试
- doubao 档：内容不变
- sensei 档：删除鼓励话术
- 配置文件缺失时降级为不过滤

**Step 6**: commit `feat(prompt): attitude filter with externalized rules (R-014)`

### T14-5: 运行时 conditions 触发

**Files**:
- 修改: `src/main/domains/03-teaching/prompt/skill-dispatcher.ts`
- 新增: `src/main/domains/03-teaching/prompt/condition-evaluator.ts`
- 测试: `src/main/domains/03-teaching/prompt/__tests__/condition-evaluator.test.ts`

**Step 1**: 实现 condition evaluator
```typescript
export interface RuntimeContext {
  evidenceQuality?: 'low' | 'medium' | 'high';
  safetyWord?: boolean;
  dominantSyndrome?: string;
}

export class ConditionEvaluator {
  static evaluate(conditions: LoadCondition[], ctx: RuntimeContext): boolean;
}
```

**Step 2**: 评估算法
- 所有 conditions 用 AND 连接（all must pass）
- 缺失的 context 字段视为 `undefined`（fail）
- 不支持的 condition type 抛 warning 但不阻塞

**Step 3**: SkillDispatcher 集成
- `selectForPhase(phase, attitude, options, runtimeCtx?)` 接受 ctx
- 默认 ctx 为 `{}`（无条件约束）

**Step 4**: 写测试
- evidence.quality 评估
- user.safetyWord 评估
- 多条件 AND

**Step 5**: commit `feat(prompt): runtime conditions evaluator (evidence/safety/syndrome)`

### T14-6: token 优先级 + 截断集成

**Files**:
- 修改: `src/main/domains/03-teaching/prompt/skill-dispatcher.ts`
- 测试: 增强 `skill-dispatcher.test.ts`

**Step 1**: 增强 truncateByPriority
- 同优先级时按 estimatedTokens 升序优先（小优先）
- 总 token 估算前先按 priority 排序

**Step 2**: 集成 truncation.ts
- 把已有的 truncation 工具接入 dispatcher 流程
- 截断前先做 phase + attitude 过滤

**Step 3**: 写测试
- 同优先级时小优先
- truncation 集成

**Step 4**: commit `feat(prompt): dispatcher priority-based truncation with size tiebreak`

### T14-7: E2E 集成测试

**Files**:
- 新增: `src/main/domains/03-teaching/prompt/__tests__/sprint-14-e2e.test.ts`

**Step 1**: 端到端场景
1. P0 + doubao → v5 降级
2. P2 + sensei → dispatcher 核心子集 + 删鼓励话术
3. P3 + safety word → 跳过有 conditions 的 SKILL
4. 循环依赖配置 → 启动失败

**Step 2**: 验收断言
- 每个场景的 prompt 体积 < 预算
- sensei 档不含鼓励词
- 安全词触发时不加载有 `user.safetyWord` 约束的 SKILL

**Step 3**: commit `test(prompt): sprint-14 E2E integration`

## 五、门禁

```bash
npm run typecheck  # 零错误
npm run test       # 全绿（含新增 E2E）
npm run lint       # 零 error
```

## 六、提交策略

| Commit | 内容 | 关联 |
|--------|------|------|
| 1 | docs(plan): sprint-14 plan | Issue #20 |
| 2 | feat(prompt): extend SkillMetadata version/depends/conditions | T14-2 |
| 3 | test(prompt): metadata extended fields | T14-2 |
| 4 | feat(prompt): SkillGraph validator with fail-fast | T14-3 |
| 5 | test(prompt): graph cycle + missing deps | T14-3 |
| 6 | feat(prompt): attitude filter + externalized rules | T14-4 |
| 7 | test(prompt): attitude filter doubao/sensei | T14-4 |
| 8 | feat(prompt): runtime conditions evaluator | T14-5 |
| 9 | test(prompt): condition evaluator AND/IN/EQ | T14-5 |
| 10 | feat(prompt): priority truncation with size tiebreak | T14-6 |
| 11 | test(prompt): sprint-14 E2E | T14-7 |
| 12 | docs(decision): D-032 sprint-14 reflect | D-032 |

## 七、DoD

- [ ] SkillMetadata 支持 version / depends / conditions
- [ ] SkillGraph 启动时 fail-fast 检测循环 + 缺失依赖
- [ ] attitude filter 三档（doubao/yuesheng/sensei）实质过滤
- [ ] 过滤规则外置为 `resources/config/attitude-filter.json`
- [ ] runtime conditions 评估 evidence.quality / user.safetyWord / user.dominantSyndrome
- [ ] dispatcher 集成 truncation + size tiebreak
- [ ] E2E 测试覆盖 4 个核心场景
- [ ] typecheck zero / test all green / lint 0 errors
- [ ] D-032 决策日志已添加
- [ ] PR 关联 Issue #20

## 八、风险

| 风险 | 等级 | 缓解 |
|------|------|------|
| 完整 schema 破坏现有 SKILL 文件 | 中 | 字段全部 optional，旧 SKILL 仍能加载 |
| 依赖图算法性能问题 | 低 | 启动时一次性校验，8 个 SKILL 规模可忽略 |
| attitude filter 误删内容 | 中 | sensei 档仅删"加油/棒/继续努力"等明确鼓励词，不动技术反馈 |
| conditions 评估误跳过关键 SKILL | 中 | 缺失 context 视为 fail，但 warning 不阻塞 |
| truncation 与 priority 冲突 | 低 | 先按 priority 排序再 truncation |

## 九、依据

- `dev-docs/designs/sprint-14-dispatcher-upgrade.md` §一/§三/§四/§五
- `docs/decision-log.md` D-030 + D-031
- Issue #20（方向 C 草案）
- R-014 配置外置规范（attitude filter 规则外置）
- R-018 变更溯源 / R-019 代码规范 / R-027 四道门禁
