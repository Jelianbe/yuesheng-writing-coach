# Sprint 20 计划 — 会话层解耦 + 接口调度优化 + 提示词 v5.0.0

> 创建日期: 2026-07-03
> 锁定原则: 激进双轨(A 轨 + B 轨同步) / 提示词 v5.0.0 独立迭代(R-025 治理)
> 依据: D-052(Phase B 候选) / D-053(契约审计教训) / 用户原始诉求"建立信任联系"前置流程

---

## 目标(Sprint Goal)

把会话提示词、技能调度、状态机消费三层从"直接耦合"改造为"事件驱动 + Orchestrator 包装",并独立迭代 v5.0.0 提示词,让"建立信任联系"等前置流程的调整不再牵动整个项目进程。

---

## A 轨: 会话层解耦 (ConversationOrchestrator)

### A-1: 定义 Orchestrator 服务接口

**目标**: 在 ChatPage 与底层 AI 调用之间插入中间层,封装"读 prompt → 加载 skill → 发请求 → 解析流"全流程。

**接口草案**(放在 `src/main/domains/01-conversation/orchestrator/`):

```typescript
interface ConversationOrchestrator {
  // 输入:用户消息 + 上下文
  handleTurn(input: {
    userMessage: string;
    phase: ConversationPhase;
    activeProblem?: ActiveProblem;
    activeTraining?: ActiveTrainingSession;
  }): AsyncIterable<OrchestratorEvent>;

  // 元数据
  promptVersion(): string;     // R-025 治理入口
  skillManifest(phase): SkillRef[];
}

type OrchestratorEvent =
  | { type: 'token'; content: string }
  | { type: 'intent'; payload: IntentPayload }
  | { type: 'phase_transition'; from: Phase; to: Phase }
  | { type: 'training_triggered'; sessionId: string }
  | { type: 'diagnosis_extracted'; syndrome: SyndromeEvidence }
  | { type: 'error'; code: string; message: string };
```

**DoD**: 接口定义文件 + 类型导出 + 1 个 mock 实现。

### A-2: 封装 SkillDispatcher

**当前状态**: SkillDispatcher 在 `src/renderer/services/` 直接读 `resources/prompts/skills/`。

**改造**: 把 SkillDispatcher 抽到主进程(`src/main/domains/01-conversation/skill-loader.ts`),Orchestrator 通过 `skillManifest(phase)` 调用。renderer 不再直接访问 skill 文件。

**DoD**:
- renderer 无 `import` skill 文件路径
- preload 暴露 `skill:manifest` IPC 通道
- 4 个 always-required skills 仍可加载

### A-3: 教学状态机消费迁移

**当前状态**: `TeachingStateMachine` 直接解析 AI 流,决定 phase 切换、训练触发、问题关闭。

**改造**: 状态机改订阅 OrchestratorEvent:
- `intent:clarify` → phase:enter('requirement')
- `intent:train` → training_triggered
- `phase_transition` → 同步本地 phase
- `diagnosis_extracted` → 入库

**DoD**:
- TeachingStateMachine 无 `stream.parse()` 调用
- 至少 1 个状态机分支走事件驱动
- 现有 FiveStepFlow E2E 仍全绿

### A-4: ChatPage 入口改为订阅模式

**改造**: ChatPage 不再 `await typedInvoke('chat:sendMessage', ...)`,改 `for await (const ev of orchestrator.handleTurn(...))`,逐事件分发到 UI / 状态机。

**DoD**: ChatPage 不直接调 `chat:sendMessage`,无 raw stream 消费。

---

## B 轨: 接口调度优化 (event-bus)

### B-1: 落地 event-bus.service.ts

**目标**: 主进程侧中央事件总线,所有 IPC event 通道走 bus,不直连。

**实现**: `src/main/core/event-bus.service.ts`

```typescript
class EventBus {
  emit(event: DomainEvent): void;
  on<T>(topic: T, handler: (payload: ...) => void): Unsubscribe;
  // IPC 桥接:ipcMain.handle('event:subscribe', ...)
}
```

**DoD**:
- bus 落地 + 单测覆盖并发/异常路径
- 至少 2 个旧 IPC event 频道(`chat:stream` / `diagnosis:result`)改走 bus
- preload 暴露 `event:subscribe` / `event:publish` 通道

### B-2: typedInvoke 全量审计 (D-DEBT-34)

**当前状态**: 全仓 ~40+ `typedInvoke` 调用点,部分已走 bus,部分仍是直连。

**审计内容**:
- 列出所有 typedInvoke 调用点(file:line)
- 标注是否走 bus / 是否需要脱敏
- 标注是否可降级(success=false 容错)
- 输出 `dev-docs/audits/typedinvoke-audit-s20.md`

**DoD**: 审计报告 + 至少 5 个 typedInvoke 调用点的脱敏/降级修复。

### B-3: chat/diagnosis/training 频道收口

**目标**: 三个核心业务域的 IPC 频道全部走 bus:

| 旧频道 | 收口方式 |
|--------|----------|
| `chat:sendMessage` | request-response 保留,response 内嵌 OrchestratorEvent 列表 |
| `chat:stream` | event-bus publish(`chat.token`, `chat.intent`, ...) |
| `diagnosis:parse` | request-response 保留 |
| `diagnosis:result` | event-bus publish |
| `training:start` | request-response 保留 |
| `training:step` | event-bus publish |

**DoD**: 3 域全部完成收口 + 消费者迁移 + 旧频道标注 `@deprecated`。

---

## C 轨: 提示词 v5.0.0 (R-025 独立迭代)

### C-1: v5.0.0 草案

**目标**: 拆出"明确用户需求 + 建立信任联系"作为 phase 0,后续 phases 同步调整。

**变更点**(相对 v4.0.0):
1. **新增 phase 0**: 信任建立
   - 不直接进入诊断
   - 询问用户写作背景 / 目标 / 痛点
   - 展示教练定位(不替写、不替决定)
2. **phase 1 重构**: 明确需求
   - 区分"我有问题想问"和"我需要评估"
   - 评估场景才进诊断
3. **phase 2-4 简化**: 移除隐式 prompt 副作用,所有"提问"都显式化

**DoD**:
- `resources/prompts/yuesheng-prompt-v5.0.0.md` 草案
- 变更对照表(v4 → v5 diff)
- R-025 元数据(version / changelog / rollback_to)

### C-2: A/B 实验设计 (R-012 假设驱动)

**假设**: v5.0.0 的"信任建立"前置会提升训练启动率。

**验证方案**:
- 对照组:v4.0.0 默认加载
- 实验组:特征开关切到 v5.0.0
- 度量:30 天窗口内,完成 phase 1(明确需求)→ 进入 phase 2(诊断)的转化率
- 显著性:α=0.05, power=0.8, MDE=10%

**DoD**: 实验设计文档 + feature flag 实现 + 埋点 schema。

### C-3: 灰度切换 + 回滚 (R-006 + R-025)

**实现**: 配置层加 `promptVersion: 'v4.0.0' | 'v5.0.0'`,可热切换。

**回滚通道**: Orchestrator.promptVersion() 内部读 config,回滚只需改 config 即可,不重启。

**DoD**:
- 切换功能 + 单测
- 模拟故障演练:故意把 v5.0.0 改成 broken prompt,验证 30s 内回滚到 v4.0.0

---

## Sprint 20 DoD (R-004 至少 3 条)

- [ ] **A 轨**: Orchestrator 接口 + mock 实现 + ChatPage 订阅模式迁移
- [ ] **B 轨**: event-bus 落地 + 至少 2 个旧频道改走 bus + typedInvoke 审计报告
- [ ] **C 轨**: v5.0.0 提示词草案 + R-025 元数据 + feature flag 实现
- [ ] **门禁(R-027)**: typecheck 0 errors / vitest 全绿(新增 Orchestrator 单测 ≥5 个) / lint 0 errors / E2E 全绿(新增订阅模式路径测试)
- [ ] **变更溯源(R-018)**: D-054 决策记录 + ADR(架构决策记录):为何选事件驱动而非回调

---

## 范围边界 (R-010 最小化)

**不在本 Sprint 范围**:
- 教学状态机完整重写(只迁移 1 个分支作为示范)
- 跨项目 v5.0.0 灰度(只做架构 + 实验设计,真实验推到 Sprint 21)
- prompt 内容润色 / 文案优化(只做架构,内容由产品迭代)
- 旧 IPC 频道完整移除(只标注 @deprecated,Sprint 21 清理)

---

## 工作量评估

| 轨道 | 预估工时 | 风险 |
|------|----------|------|
| A-1 接口设计 | 0.5 天 | 低 |
| A-2 skill 封装 | 1 天 | 中(测试覆盖) |
| A-3 状态机迁移 | 2 天 | 中(回归风险) |
| A-4 ChatPage 订阅 | 1 天 | 中(流式兼容性) |
| B-1 event-bus | 1 天 | 低 |
| B-2 typedInvoke 审计 | 1 天 | 低 |
| B-3 频道收口 | 1.5 天 | 中(消费者迁移) |
| C-1 v5.0.0 草案 | 0.5 天 | 低 |
| C-2 A/B 设计 | 0.5 天 | 低 |
| C-3 灰度 + 回滚 | 0.5 天 | 低 |
| **合计** | **~9.5 天(2-3 周)** | |

**Sprint 周期建议**: 2 周半(5 个工作日 buffer for 回归 + 反馈迭代)

---

## 依赖与风险

| 风险 | 概率 | 影响 | 缓解 |
|------|------|------|------|
| 状态机迁移导致 FiveStepFlow E2E 大面积红 | 中 | 高 | A-3 先做 1 个分支试点,稳定后再推全量 |
| event-bus 与现有 IPC event 冲突 | 中 | 中 | B-1 先做兼容层,旧频道双发(直接 + bus) |
| v5.0.0 破坏现有用户会话 | 低 | 高 | C-3 回滚通道 + 灰度 5% 起步 |
| typedInvoke 审计发现大面债务 | 高 | 中 | 不在 Sprint 20 全部修,只做高优 5 个 |

---

## 依据 / 追溯 (R-018)

- **D-052**: Phase B event-bus 候选(Sprint 19 决策日志)
- **D-053**: Issue 19-3 契约断链教训 → 推动 S20 解耦
- **R-010**: 最小化范围,明确不做项
- **R-012**: 假设驱动开发,v5.0.0 必走 A/B
- **R-018**: 变更溯源,本计划是 S20 的设计哲学
- **R-025**: 提示词治理,v5.0.0 必须有 changelog + rollback_to
- **R-027**: AI 代码质量门禁,所有改动走 4 道门禁

---

## 下一步

如计划批准:
1. 创建 Sprint 20 Kanban 看板(8 个 issue: A1-A4 / B1-B3 / C1)
2. 开 Issue 20-1:Orchestrator 接口定义
3. 启动 GStack Think → Plan → Build 流程
