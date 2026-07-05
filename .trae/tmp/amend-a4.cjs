// 修正 A-4 commit message 中的 \n 字面字符
const { execSync } = require('child_process');
const fs = require('fs');

const cwd = 'd:/ai-teacher/yuesheng-writing-coach';
const tmp = 'd:/ai-teacher/.trae/tmp/COMMIT_EDITMSG';

const msg = `feat(conversation): A-4 ChatPage 订阅模式 — IPC 事件流推送 (Sprint 20)

引入 chat:handleTurn(invoke)+ chat:event(推送)双通道,
让 ChatPage 真正订阅 OrchestratorEvent 流,替代直接调 chat:send。

交付物:
- ChatHandleTurnBridge(主进程)包装 MockConversationOrchestrator,
  异步消费 handleTurn 事件流并推送给 webContents
- useOrchestrator Hook(renderer)单例订阅,按 streamId 过滤本轮 turn
- ChatPage 改造: token 累积到 ai 消息, done/error/phase 全部分发
- 7 个桥接单测(streamId/done/stopAll/null/destroyed)

门禁: typecheck 0 errors / vitest 749/749 / lint 0 errors

决策: D-059(IPC 边界用 unknown 避免跨域引用,真实 orchestrator 适配器
推迟到 S21,Edit 工具假成功教训)

依据: dev-docs/tasks/sprint-20-plan.md §A-4, D-058`;

fs.writeFileSync(tmp, msg, 'utf8');
try {
  execSync(`git commit --amend -F "${tmp}"`, { cwd, stdio: 'inherit' });
  console.log('[amend] OK');
} catch (e) {
  console.error('[amend] FAILED:', e.message);
  process.exit(1);
} finally {
  fs.unlinkSync(tmp);
}
