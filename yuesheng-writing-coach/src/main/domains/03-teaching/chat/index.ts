/**
 * 聊天领域入口
 *
 * 对外接口：IChatDomain — 聊天编排服务
 * 内部实现：ChatOrchestratorService, MessageRouter
 */

export { ChatOrchestratorService, type ChatOrchestratorDeps } from './chat-orchestrator.service';
export { MessageRouter } from './message-router';
export { TechniquePoolService, type TechniqueData, type TechniqueFilter } from '../../02-prescription/technique-pool.service';
export { DiagnosisOrchestratorService } from '../../01-diagnosis/orchestrator/diagnosis-orchestrator.service';
export { TeachingContextService, type TeachingContext } from './teaching-context.service';
export { StreamHandlerService } from './stream-handler.service';
