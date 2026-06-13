/**
 * 聊天领域入口
 *
 * 对外接口：IChatDomain — 聊天编排服务
 * 内部实现：ChatOrchestratorService, MessageRouter
 */

export { ChatOrchestratorService, type ChatOrchestratorDeps } from './chat-orchestrator.service';
export { MessageRouter } from './message-router';
