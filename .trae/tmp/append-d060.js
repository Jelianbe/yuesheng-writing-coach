// 追加 D-060 到 decision-log.md
const fs = require('fs');
const path = 'd:/ai-teacher/yuesheng-writing-coach/docs/decision-log.md';

const D060 = `

---

## 2026-07-03

### D-060: typedInvoke 强错误 → 降级统一规范(Sprint 20 B-2 / D-DEBT-34)
- **类型**: 架构决策(防御性编码 / 审计修复)
- **背景**:
  - Sprint 20 A-1~A-4 完成后,审计全部 typedInvoke 调用点发现:**53 处调用点中 31 处为强错误模式**(\`if (!result.success) throw new Error(...)\`)
  - 高度敏感数据集中在 4 个 service:
    - \`student-context.service.ts\`(3)— 认知/心理画像
    - \`teaching-state.service.ts\` getPrompt(1)— prompt 全文
    - \`diagnosis.service.ts\`(3)— 诊断细节
    - \`training.service.ts\` submit/evaluate/deriveBehavior(3)— AI 评分细节
  - 强错误模式违反 R-027 防御性编码 + R-028 错误隔离原则,会强制 UI 层 try/catch,白屏风险高
- **决策**:
  - **降级统一模式**:\`if (!result.success) { console.error('[domain] method failed:', result.error); return fallback; }\`
  - **fallback 形状**: 服务签名推断(\`Promise<T | null>\` / \`Promise<boolean>\` / \`Promise<''>\`)
  - **chat.service 反模式修复**:
    - \`send()\` 标 \`@deprecated\`,已被 A-4 useOrchestrator.handleTurn 取代
    - \`stop()\` sessionId 从 \`''\` 修正为可传参数(载荷规范)
- **改动清单**(5 个 service + 1 个测试):
  1. \`src/renderer/services/student-context.service.ts\`(3 处降级)
  2. \`src/renderer/services/diagnosis.service.ts\`(3 处降级)
  3. \`src/renderer/services/training.service.ts\`(8 处降级,7 处 throw → console.error + null,1 处 skip 保留 throw)
  4. \`src/renderer/services/teaching-state.service.ts\`(getPrompt 1 处降级)
  5. \`src/renderer/services/chat.service.ts\`(send/stop 反模式修复 + send 标 @deprecated)
  6. \`src/renderer/services/__tests__/typedinvoke-degradation.test.ts\`(NEW,15 个用例)
- **审计报告**:\`dev-docs/audits/typedinvoke-audit-s20.md\`
  - 53 处调用点逐项标注 **走 bus / 脱敏 / 降级** 三维标签 + 风险评级
  - 风险分布:高 12 / 中 21 / 低 20
  - 本 Sprint 修复 12 处高/中风险
- **门禁**:
  - typecheck: ✅ 0 errors
  - vitest: ✅ 764/764(749 原有 + 15 新增降级测试)
  - lint: ✅ 0 errors, 257 warnings(无新增)
- **教训**:
  1. **强错误违反 R-028**:\`throw new Error()\` 把 IPC 错误直接抛到 UI 层,UI 必须 try/catch。降级模式(\`console.error + return null\`)让 UI 不依赖异常处理,符合防御性编码
  2. **Service 层降级是必须不是可选项**: 用户在白屏风险 vs 错误日志详细度之间的选择,前者优先(白屏意味着完全不可用,日志可以后看)
  3. **反模式必须显式标 @deprecated**: chatService.send 仍被 chat.store.sendMessage 重试逻辑使用,不能直接删,但应明示"已被 A-4 取代",避免后续误用
  4. **载荷 null/空字符串 vs 类型正确**: chat.stop() 传 sessionId='' 是早期 API 设计的妥协,本审计修正为可传参数,载荷语义更清晰
  5. **降级测试用 mock typedInvoke**: 通过 \`vi.mock('../ipc-client')\` 注入失败响应,验证 service 不 throw,比 E2E 更轻量更可靠
- **依据**:
  - dev-docs/audits/typedinvoke-audit-s20.md
  - dev-docs/tasks/sprint-20-plan.md §B-2
  - D-059(A-4 ChatPage 订阅模式)
  - R-027 AI 代码质量门禁(防御性编码要求)
  - R-028 防御性编码(错误隔离原则)
  - R-018 变更溯源(本决策追溯到 plan §B-2)
- **未做事项**(明示):
  - **走 bus 改造**: 53 处全是 request/response,EventBus 主要在主进程侧 emit 事件给 renderer(已在 chat:event 实现,见 A-4)
  - **载荷脱敏**: 涉及主进程侧字段白名单审计,需独立 Sprint(候选 Sprint 21 C-2)
  - **降级 UI 可视化**: loading / error placeholder 统一化,推迟到 Sprint 21+ UI 规范
- **后续**:
  - Sprint 21 C-2: 载荷脱敏字段白名单(主进程侧)
  - Sprint 21: session.service 剩余 8 处强错误降级(scanMessages/getMessagesPaged 等)
  - Sprint 22: typedInvoke v2 — 强类型 API 客户端(skill registry 风格)
`;

fs.appendFileSync(path, D060, { encoding: 'utf8' });
console.log('[append-decision-log] D-060 appended, total lines now:', fs.readFileSync(path, 'utf8').split('\n').length);
