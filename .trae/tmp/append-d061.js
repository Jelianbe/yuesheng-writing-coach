// 追加 D-061 到 decision-log.md
const fs = require('fs');
const path = 'd:/ai-teacher/yuesheng-writing-coach/docs/decision-log.md';

const D061 = `

### D-061: typedInvoke 强错误降级 — B-3 收尾(Sprint 20 / D-DEBT-34)
- **类型**: 架构决策(防御性编码收尾)
- **背景**:
  - B-2(D-060)完成 P0 高敏感数据降级(11 处)+ 2 处反模式
  - 剩余 13 处强错误:session.service 8 处、teaching-state.service 4 处(除 getPrompt)、training.skip 1 处
  - 这 13 处是低/中风险,但**仍违反 R-027 防御性编码基线**,应在 Sprint 20 收尾统一对齐
- **决策**:
  - session.service 8 处降级:
    - list() → \[\]  / create() → null / delete() → false / rename() → false
    - getMessagesPaged() → { messages: \[\], hasMore: false }
    - listWithMeta() → \[\] / updateTitle() → false / searchMessages() → \[\]
  - teaching-state.service 4 处降级(get/update/confirm/updateSummary 全部 → null)
    - **签名变化**:update()/updateSummary() 原返回 \`Promise<TeachingState>\`(throw 强保证),改为 \`Promise<TeachingState | null>\`
    - 审计显示 renderer 端**无消费者**,签名变化是**纯收紧**
  - training.service.skip() 降级为 null
- **改动清单**:
  1. \`src/renderer/services/session.service.ts\`(8 处 throw → console.error + fallback)
  2. \`src/renderer/services/teaching-state.service.ts\`(4 处 throw → console.error + null,签名收紧)
  3. \`src/renderer/services/training.service.ts\`(skip 1 处 throw → console.error + null)
  4. \`src/renderer/services/__tests__/typedinvoke-degradation.test.ts\`(新增 13 个 B-3 降级测试)
- **降级后状态**:
  - **全 53 处 typedInvoke 调用点全部对齐降级模式**
  - 0 处强错误 throw(全部改为 console.error + fallback)
  - 0 处反模式载荷
- **门禁**:
  - typecheck: ✅ 0 errors
  - vitest: ✅ 777/777(764 + 13 新增)
  - lint: ✅ 0 errors, 255 warnings(降 2)
- **教训**:
  1. **签名收紧是主动债务**:teaching-state.update() 从 \`Promise<TeachingState>\` 改为 \`Promise<TeachingState | null>\`,调用方必须处理 null。即使当前无消费者,也提前暴露未来调用方的判断负担,优于"未来 throw" 隐藏债务
  2. **B-3 收尾"防御性基线"价值**: 8 + 4 + 1 = 13 处降级,虽然当前无消费者,但**统一模式让代码风格一致**,后续新消费者不会误以为 throw 是合法失败模式
  3. **审计驱动收尾**: B-2 报告明确列出"剩余 P1 项",B-3 按图索骥完成,避免技术债务滚雪球
- **依据**:
  - dev-docs/audits/typedinvoke-audit-s20.md §5 修复清单 P0/P1
  - D-060(B-2 P0 修复)
  - R-027 防御性编码门禁
  - R-028 错误隔离原则
- **全 53 处 typedInvoke 降级全景**:
  | 服务 | 调用点 | 降级模式 | 状态 |
  |------|--------|----------|------|
  | student-context | 3 | null/false/'' | ✅ B-2 |
  | diagnosis | 3 | null/undefined/{hasHistory:false} | ✅ B-2 |
  | training | 9 | null(全部) | ✅ B-2(8)+B-3(1) |
  | teaching-state | 5 | null(全部) | ✅ B-2(1)+B-3(4) |
  | chat | 2 | null/{stopped:false} | ✅ B-2 |
  | session | 9 | \[\]/null/false | ✅ B-3(8)+ 原有 isNewUser(1) |
  | useOrchestrator | 1 | null + warn | ✅ A-4 |
  | store 直接调用 | 21 | try/catch + null/[]/false | ✅ 既有 |
- **后续**:
  - Sprint 21: C-2 载荷脱敏字段白名单(主进程侧)
  - Sprint 21: typedInvoke v2 — 强类型 API 客户端(skill registry 风格)
`;

fs.appendFileSync(path, D061, { encoding: 'utf8' });
console.log('[append-decision-log] D-061 appended, total lines now:', fs.readFileSync(path, 'utf8').split('\n').length);
