const fs = require('node:fs');
const path = require('node:path');

const LOG = path.resolve(__dirname, '../docs/decision-log.md');
const APPEND = `
### D-057: SkillDispatcher 集成 SkillRegistry 版本过滤(Sprint 20 A-2 桥接)
- **类型**: 架构桥接
- **决策**:
  1. SkillDispatcher 集成 SkillRegistry,新增 \`SelectOptions.promptVersion\` 可选参数
  2. 不传 version = 向后兼容(行为不变),传 version = 走 SkillRegistry 过滤
  3. 加载时自动创建默认 registry(从 skillsDir),允许 \`setRegistry()\` 注入测试桩
  4. \`setRegistry()\` 必须在 load() 之前调用,否则抛错(防止覆盖)
- **交付物**:
  1. \`src/main/domains/03-teaching/prompt/skill-dispatcher.ts\` (修改: ~60 行新增/修改)
  2. \`src/main/domains/03-teaching/prompt/__tests__/skill-dispatcher-version.test.ts\` (NEW, 10 个用例)
- **门禁**:
  - typecheck: ✅ 0 errors
  - vitest: ✅ 737/737(新增 10 个 SkillDispatcher 版本过滤测试)
  - lint: ✅ 0 errors, 251 warnings(阈值 300)
  - E2E (firefox-mobile): ✅ 33/33
- **教训**:
  1. **注入 vs 自动创建的优先级**: 若先 setRegistry() 再 load(),应保留注入的实例;自动创建仅作为缺省。设计上让 setRegistry() 在 load() 后抛错,避免运行时"静默覆盖"导致调试噩梦
  2. **"找不到元数据 → 通过"是显式选择**: SkillRegistry 是 skill 元数据的"权威源",但 SkillDispatcher 仍可能加载 registry 外的 skill(老格式/外部脚本)。保守放过可保持向后兼容,代价是契约硬要求稍弱。**契约硬约束已由 validateContract() 在启动时拦截,运行时再补一刀性价比低**
  3. **测试桩需要"完整"才能精准测试**: setRegistry 注入测试桩时,必须把 dispatcher 会查到的所有 skill id 都在桩里声明"不兼容",否则"找不到元数据 → 保守放过"会污染断言。这是测试设计而非实现 bug
  4. **selectForPhase 过滤是 AND 组合**: 现有 phase/attitude/coreSubset/conditions 不变,新增 version 是第 5 维度。这样保证旧调用方零改动,新调用方按需启用
- **依据**:
  - dev-docs/tasks/sprint-20-plan.md §A-2
  - D-056(SkillRegistry 是版本过滤的元数据源)
  - R-010 最小化范围(只改 SkillDispatcher,不动 ChatPage/状态机,A-3/A-4 后续)
- **后续**:
  - A-3: TeachingStateMachine 改订阅 OrchestratorEvent
  - A-4: ChatPage 改订阅模式
  - C-1: v5.0.0 提示词草案(契约/版本过滤层就绪,可独立迭代)
---
`;

fs.appendFileSync(LOG, APPEND, 'utf-8');
console.log('D-057 appended to', LOG);
