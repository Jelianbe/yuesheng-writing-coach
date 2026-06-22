# Sprint 14-prior 实施计划 — 清除方向 C 启动债务

> **目的**: 解决 D-DEBT-2026-06-23-09 和 D-DEBT-2026-06-23-11，使方向 C（Issue #20）满足启动前提
> **范围**: 仅清 2 个债务，不实现方向 C 的核心升级
> **依据**: dev-docs/designs/sprint-14-dispatcher-upgrade.md + Issue #20

---

## 一、目标

| ID | 描述 | 状态 |
|----|------|------|
| D-DEBT-2026-06-23-09 | dynamic-context 不感知教学状态机 phase | 解决 |
| D-DEBT-2026-06-23-11 | dispatcher 启用导致体积膨胀 25 倍 | 解决 |

## 二、不做

- 不实现 attitude 实质过滤（方向 C 核心）
- 不实现 conditions 触发
- 不实现依赖图校验
- 不改 prompt 内容
- 不改测试基线（仅新增）

## 三、A+C 组合方案（解决 D-DEBT-11）

### 方案 A：SKILL 子集加载

| SKILL | 拆分策略 | 体积 |
|-------|---------|------|
| `core-identity.md` (1500 tokens) | 拆为 2 个子集 | - |
| └─ `core-iron-triangle.md` | 铁三角 + 回复控制 | ~600 tokens |
| └─ `core-product-identity.md` | 产品身份 + 底线清单 | ~900 tokens |

### 方案 C：渐进式启用

| Phase | 加载策略 | 体积目标 |
|-------|---------|---------|
| P0_INIT | v5 降级路径（铁三角 ~800 字符） | < 1.2K tokens |
| P1_WORLD | v5 降级路径 | < 1.2K tokens |
| P2_PRACTICE_LOOP | dispatcher v2 加载 core-iron-triangle + teaching-strategy | < 3K tokens |
| P3_TRAINING | dispatcher v2 + 训练策略 | < 4K tokens |
| P4_REVIEW | dispatcher v2 + 验证规则 | < 4K tokens |

**关键点**：
- dispatcher **只在 P2+ 启用**，P0/P1 走 v5 降级
- dispatcher 启用时只加载核心子集，不堆 4 个 always SKILL

## 四、任务分解

### T14-0: 解决 D-DEBT-11（dispatcher 体积优化）

**Files**:
- 新增: `resources/prompts/skills/core-iron-triangle.md`
- 新增: `resources/prompts/skills/core-product-identity.md`
- 修改: `resources/prompts/skills/core-identity.md`（转为聚合入口或废弃）
- 修改: `src/main/domains/03-teaching/prompt/skill-metadata.ts`
- 修改: `src/main/domains/03-teaching/prompt/skill-dispatcher.ts`
- 修改: `src/main/domains/03-teaching/prompt/dynamic-context.service.ts`
- 测试: `src/main/domains/03-teaching/prompt/__tests__/skill-dispatcher.test.ts`

**Step 1**: 拆分 core-identity.md
- 提取 §一铁三角 + §2.0 回复控制 → `core-iron-triangle.md`
- 提取 §2.6 产品身份 + 底线清单 → `core-product-identity.md`
- 保留 `core-identity.md` 作为两个子集的聚合引用（向后兼容）

**Step 2**: SkillMetadata 扩展
```typescript
export interface SkillMetadata {
  id: string;
  estimatedTokens: number;
  loadWhen: SkillLoadWhen;
  tokenPriority?: number;      // 截断优先级（10 最高）
  isCoreSubset?: boolean;      // 标记是否核心子集
  parentId?: string;           // 子集归属（如 core-iron-triangle → core-identity）
}
```

**Step 3**: SkillDispatcher 增强
- `selectForPhase(phase, attitude)` 支持 `isCoreSubset` 过滤
- P0/P1 调用时 dispatcher 仍然可选（opt-in），不强制启用
- P2+ 走 dispatcher 时只加载 `isCoreSubset: true` 的子集

**Step 4**: dynamic-context 集成
- 接受可选的 `phase: TeachingPhase` 参数
- P0/P1 走 v5 降级（保持现状 ~800 字符）
- P2+ 走 dispatcher v2（核心子集 ~3K tokens）
- 体积目标：P0/P1 < 1.2K，P2+ < 4K

**Step 5**: 写测试
- dispatcher 子集加载测试
- 体积估算测试（assert P0 < 1.2K，P2 < 4K）
- 验证 v5 降级路径未被破坏

**Step 6**: commit `feat(prompt): split core-identity + phase-aware dispatcher load`

### T14-1: 解决 D-DEBT-09（教学状态机 phase 注入）

**Files**:
- 修改: `src/main/domains/03-teaching/prompt/dynamic-context.service.ts`
- 修改: `src/main/domains/03-teaching/prompt/prompt-loader.ts`
- 修改: `src/main/domains/03-teaching/prompt/prompt-builder.ts`（如有）
- 修改: `src/main/ipc/chat.handler.ts`（注入 phase）
- 测试: `src/main/domains/03-teaching/prompt/__tests__/dynamic-context.test.ts`

**Step 1**: 调研教学状态机 API
- 查找 `TeachingStateMachine` 或 `teachingStateService` 的 phase 查询方法
- 确认返回类型（`'P0_INIT'` / `'P1_WORLD'` 等）
- 如不存在则延后此任务，先记录阻塞

**Step 2**: dynamic-context 接受 phase 参数
- `loadCorePrompt(phase?: TeachingPhase)` 
- 默认 `P0_INIT`
- 内部传给 dispatcher

**Step 3**: chat.handler 注入 phase
- 调用 `loadSystemPrompt` 之前查询当前 phase
- 把 phase 传下去

**Step 4**: 写测试
- mock phase → 验证 dynamic-context 收到正确 phase
- 默认 P0 → 验证 v5 降级

**Step 5**: commit `feat(prompt): inject teaching state machine phase into dynamic-context`

## 五、门禁

```bash
npm run typecheck  # 零错误
npm run test       # 全绿（含新测试）
npm run lint       # 零 error
```

## 六、提交策略

| Commit | 内容 | 关联 |
|--------|------|------|
| 1 | docs(plan): add sprint-14-prior plan | Issue #20 |
| 2 | refactor(prompt): split core-identity into iron-triangle + product-identity | D-DEBT-11 |
| 3 | feat(prompt): add isCoreSubset / tokenPriority to SkillMetadata | D-DEBT-11 |
| 4 | feat(prompt): dispatcher selectForPhase supports core subset | D-DEBT-11 |
| 5 | test(prompt): dispatcher subset + volume budget | D-DEBT-11 |
| 6 | feat(prompt): dynamic-context phase-aware load | D-DEBT-09 |
| 7 | refactor(prompt): chat.handler inject phase from state machine | D-DEBT-09 |
| 8 | test(prompt): dynamic-context phase injection | D-DEBT-09 |
| 9 | docs(decision): add D-031 Sprint 14-prior reflect | D-031 |

## 七、DoD

- [ ] core-identity 拆分为 2 个核心子集
- [ ] dispatcher 支持 `isCoreSubset` 过滤
- [ ] P0/P1 体积 < 1.2K tokens（保持 v5 降级）
- [ ] P2+ 体积 < 4K tokens（dispatcher 核心子集）
- [ ] dynamic-context 接受 phase 参数
- [ ] chat.handler 注入教学状态机 phase
- [ ] typecheck zero / test all green / lint 0 errors
- [ ] D-031 决策日志已添加
- [ ] Issue #20 启动前提两项已勾选

## 八、风险

| 风险 | 等级 | 缓解 |
|------|------|------|
| 拆分 core-identity 破坏现有测试 | 中 | 保留 core-identity.md 作为聚合引用 |
| 教学状态机 API 不存在 | 中 | 调研后阻塞则 T14-1 拆为 T14-1a（注入空 phase 占位） + T14-1b（真实注入） |
| dispatcher 启用导致 P2+ 体积超预算 | 中 | 单元测试 assert 体积上限 |

## 九、依据

- `dev-docs/designs/sprint-14-dispatcher-upgrade.md` §一/§二/§三/§四
- `dev-docs/designs/sprint-13-skill-dispatcher-design.md`
- `docs/decision-log.md` D-029 + D-030
- Issue #20（方向 C 草案）
- R-018 变更溯源 / R-019 代码规范 / R-027 四道门禁
