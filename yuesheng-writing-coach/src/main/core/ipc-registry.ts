import type { BrowserWindow } from 'electron';
import type Database from 'better-sqlite3';
import type { ServiceContainer } from './service-container';
import { mountBridgeEndpoint } from './bridge-endpoint';
import { initConfigHandlers, registerConfigHandlers } from '../ipc/config.handler';
import { initSessionHandlers, registerSessionHandlers } from '../ipc/session.handler';
import { initEvidenceHandlers, registerEvidenceHandlers } from '../ipc/evidence.handler';
import { initAbilityProfileHandlers, registerAbilityProfileHandlers } from '../ipc/ability-profile.handler';
import { initTrainingHandlers, registerTrainingHandlers } from '../ipc/training.handler';
import { initDevelopmentPathHandlers, registerDevelopmentPathHandlers } from '../ipc/development-path.handler';
import { initGrowthHandlers, registerGrowthHandlers } from '../ipc/growth.handler';
import { initTeachingNoteHandlers, registerTeachingNoteHandlers } from '../ipc/teaching-note.handler';
import { initDiagnosisHandlers, registerDiagnosisHandlers } from '../ipc/diagnosis.handler';
import { initChatHandlers, registerChatHandlers } from '../ipc/chat.handler';
import type { TeachingNoteService } from '../domains/03-teaching/teaching-note.service';
import { initTeachingStateHandler, registerTeachingStateHandlers } from '../ipc/teaching-state.handler';
import { initManuscriptHandlers, registerManuscriptHandlers } from '../ipc/manuscript.handler';
import { initProjectHandlers, registerProjectHandlers } from '../ipc/project.handler';
import { initWindowHandlers } from '../ipc/window.handler';
import { initRetroHandlers, registerRetroHandlers } from '../ipc/retro.handler';
// Sprint 38: 训练计划
import { initTrainingPlanHandlers } from '../ipc/training-plan.handler';
import { TrainingPlanService } from '../domains/04-validation/training-plan/training-plan.service';
// Sprint 40: 写作进度追踪
import { initProgressHandlers } from '../ipc/progress.handler';
// Sprint 24 A-3 / A-4: ActiveTraining 状态机 IPC handler
import {
  initActiveTrainingHandlers,
  registerActiveTrainingHandlers,
  setupActiveTrainingPush,
} from '../ipc/active-training.handler';
import type { ConfigService } from '../shared/services/config.service';
import type { SessionService } from '../../shared/services/session.service';
import type { DiagnosisService } from '../domains/01-diagnosis/diagnosis.service';
import type { EvidenceService } from '../domains/01-diagnosis/evidence/evidence.service';
import type { TrainingRecordService } from '../domains/04-validation/training/training-record.service';
import type { StudentModelService } from '../domains/02-prescription/student/student-model-service';
import type { AbilityProfileService } from '../domains/02-prescription/student/ability-profile.service';
import type { GrowthTrendService } from '../domains/02-prescription/student/growth-trend.service';
import type { ChatOrchestratorService } from '../domains/03-teaching/chat/chat-orchestrator.service';
import type { DiagnosisOrchestratorService } from '../domains/01-diagnosis/orchestrator/diagnosis-orchestrator.service';
import type { DiagnosisMerger } from '../domains/01-diagnosis/diagnosis-merger';
import type { TeachingStateService } from '../domains/03-teaching/teaching-state.service';
import type { TeachingStrategyService } from '../domains/02-prescription/strategy/service';
import type { RetroService } from '../domains/05-retro/retro.service';
// Sprint 24 A-3: ActiveTraining 状态机服务
import type { ActiveTrainingService } from '../domains/03-teaching/state/active-training.service';

export class IpcRegistry {
  constructor(
    private container: ServiceContainer,
    private mainWindow: BrowserWindow | null,
  ) {}

  registerAll(): void {
    const configService = this.container.get<ConfigService>('configService');
    const sessionService = this.container.get<SessionService>('sessionService');
    const diagnosisService = this.container.get<DiagnosisService>('diagnosisService');
    const evidenceService = this.container.get<EvidenceService>('evidenceService');
    const trainingRecordService = this.container.get<TrainingRecordService>('trainingRecordService');
    const studentModelService = this.container.get<StudentModelService>('studentModelService');
    const abilityProfileService = this.container.get<AbilityProfileService>('abilityProfileService');
    const growthTrendService = this.container.get<GrowthTrendService>('growthTrendService');
    const diagnosisMerger = this.container.get<DiagnosisMerger>('diagnosisMerger');
    const teachingStateService = this.container.get<TeachingStateService>('teachingStateService');
    const teachingStrategyService = this.container.get<TeachingStrategyService>('teachingStrategyService');

    // Config
    initConfigHandlers({ configService });
    registerConfigHandlers();

    // Session
    initSessionHandlers({ sessionService });
    registerSessionHandlers();

    // Evidence
    initEvidenceHandlers({ evidenceService });
    registerEvidenceHandlers();

    // Ability Profile
    initAbilityProfileHandlers({ abilityProfileService });
    registerAbilityProfileHandlers();

    // Training (inject teachingStateService for severity downgrade, teachingStrategyService for B-02)
    initTrainingHandlers({
      configService,
      trainingRecordService,
      studentModelService,
      teachingStateService,
      teachingStrategyService,
    });
    registerTrainingHandlers();

    // Development Path (S8: 七阶段发展路径 + MasteryGate)
    initDevelopmentPathHandlers({ studentModelService });
    registerDevelopmentPathHandlers();

    // Growth Trends (学习日志工具)
    initGrowthHandlers({ growthTrendService });
    registerGrowthHandlers();

    // Teaching Note (教学笔记工具 I-08)
    const teachingNoteService = this.container.get<TeachingNoteService>('teachingNoteService');
    initTeachingNoteHandlers({ teachingNoteService });
    registerTeachingNoteHandlers();

    // Teaching State — 通过 DI 注入 TeachingStateService
    initTeachingStateHandler(teachingStateService);
    registerTeachingStateHandlers();

    // Diagnosis — DI managed, no callback bridge needed
    initDiagnosisHandlers({
      configService,
      diagnosisService,
      evidenceService,
      sessionService,
      growthTrendService,
      teachingStateService,
      diagnosisMerger,
      mainWindow: this.mainWindow,
    });
    registerDiagnosisHandlers();

    // Chat
    const chatOrchestrator = this.container.get<ChatOrchestratorService>('chatOrchestratorService');
    const diagnosisOrchestrator = this.container.get<DiagnosisOrchestratorService>('diagnosisOrchestratorService');
    chatOrchestrator.setMainWindow(this.mainWindow);
    diagnosisOrchestrator.setMainWindow(this.mainWindow);
    initChatHandlers(chatOrchestrator);
    registerChatHandlers();

    // Manuscript (V2 SOLO — 直接使用 db 实例)
    initManuscriptHandlers({ db: this.container.get<Database.Database>('db') });
    registerManuscriptHandlers();

    // Project (RWR-P0-4 + Sprint 26 T26-2.2 — 切到 ProjectService 异步版)
    initProjectHandlers({ projectService: this.container.get('projectService') });
    registerProjectHandlers();

    // Retro (F-03 复盘总结)
    initRetroHandlers({
      retroService: this.container.get<RetroService>('retroService'),
    });
    registerRetroHandlers();

    // Window Controls (最小化/最大化/关闭)
    initWindowHandlers();

    // Sprint 24 A-3: ActiveTraining 草稿持久化 — DI 注入状态机服务
    const activeTrainingService = this.container.get<ActiveTrainingService>('activeTrainingService');
    initActiveTrainingHandlers(activeTrainingService);
    registerActiveTrainingHandlers();

    // Sprint 24 A-4: 桥接状态变更到 renderer(渲染层订阅模式)
    setupActiveTrainingPush(this.mainWindow);

    // Sprint 38: 训练计划 — 直接使用 db 实例
    const trainingPlanService = new TrainingPlanService(this.container.get<Database.Database>('db'));
    initTrainingPlanHandlers(trainingPlanService);

    // Sprint 40: 写作进度追踪 — 直接使用 db 实例
    initProgressHandlers({ db: this.container.get<Database.Database>('db') });

    // Sprint 26 阶段 3.5 方案 4a: 挂载单端点 bridge:invoke
    // 必须在所有 service 注册完成后挂载,否则 method 查不到
    mountBridgeEndpoint();
  }
}
