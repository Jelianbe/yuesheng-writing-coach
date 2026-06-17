import { BrowserWindow } from 'electron';
import { ServiceContainer } from './service-container';
import { initConfigHandlers, registerConfigHandlers } from '../ipc/config.handler';
import { initSessionHandlers, registerSessionHandlers } from '../ipc/session.handler';
import { initEvidenceHandlers, registerEvidenceHandlers } from '../ipc/evidence.handler';
import { initAbilityProfileHandlers, registerAbilityProfileHandlers } from '../ipc/ability-profile.handler';
import { initTrainingHandlers, registerTrainingHandlers } from '../ipc/training.handler';
import { initDiagnosisHandlers, registerDiagnosisHandlers } from '../ipc/diagnosis.handler';
import { initChatHandlers, registerChatHandlers } from '../ipc/chat.handler';
import { registerTeachingStateHandlers } from '../ipc/teaching-state.handler';
import { initTeachingStateHandler } from '../ipc/teaching-state.handler';
import { initManuscriptHandlers, registerManuscriptHandlers } from '../ipc/manuscript.handler';
import { initProjectHandlers, registerProjectHandlers } from '../ipc/project.handler';
import { initWindowHandlers } from '../ipc/window.handler';
import type { ConfigService } from '../shared/services/config.service';
import type { SessionService } from '../shared/services/session.service';
import type { DiagnosisService } from '../domains/diagnosis/diagnosis.service';
import type { EvidenceService } from '../domains/diagnosis/evidence/evidence.service';
import type { TrainingRecordService } from '../domains/training/training-record.service';
import type { StudentModelService } from '../domains/student/student-model-service';
import type { AbilityProfileService } from '../domains/student/ability-profile.service';
import type { GrowthTrendService } from '../domains/student/growth-trend.service';
import type { ChatOrchestratorService } from '../domains/chat/chat-orchestrator.service';
import type { DiagnosisMerger } from '../domains/diagnosis/diagnosis-merger';
import type { TeachingStateService } from '../domains/teaching/teaching-state.service';
import type { TeachingStrategyService } from '../domains/teaching/strategy/service';

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
    chatOrchestrator.setMainWindow(this.mainWindow);
    initChatHandlers(chatOrchestrator);
    registerChatHandlers();

    // Manuscript (V2 SOLO — 直接使用 db 实例)
    initManuscriptHandlers({ db: this.container.get<any>('db') });
    registerManuscriptHandlers();

    // Project (RWR-P0-4 — 直接使用 db 实例)
    initProjectHandlers({ db: this.container.get<any>('db') });
    registerProjectHandlers();

    // Window Controls (最小化/最大化/关闭)
    initWindowHandlers();
  }
}
