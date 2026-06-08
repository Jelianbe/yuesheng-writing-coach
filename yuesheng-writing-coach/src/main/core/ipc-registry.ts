import { BrowserWindow } from 'electron';
import { ServiceContainer } from './service-container';
import { initConfigHandlers, registerConfigHandlers } from '../ipc/config.handler';
import { initSessionHandlers, registerSessionHandlers } from '../ipc/session.handler';
import { initEvidenceHandlers, registerEvidenceHandlers } from '../ipc/evidence.handler';
import { initAbilityProfileHandlers, registerAbilityProfileHandlers } from '../ipc/ability-profile.handler';
import { initTrainingHandlers, registerTrainingHandlers } from '../ipc/training.handler';
import { initDiagnosisHandlers, registerDiagnosisHandlers } from '../ipc/diagnosis.handler';
import { initChatHandlers, registerChatHandlers } from '../ipc/chat.handler';
import { registerTeachingStateHandlers, registerDiagnosisMerger, getTeachingStateContext } from '../ipc/teaching-state.handler';
import { initManuscriptHandlers, registerManuscriptHandlers } from '../ipc/manuscript.handler';
import type { ConfigService } from '../services/config.service';
import type { SessionService } from '../services/session.service';
import type { DiagnosisService } from '../services/diagnosis.service';
import type { EvidenceService } from '../services/evidence.service';
import type { TrainingRecordService } from '../services/training-record.service';
import type { StudentModelService } from '../services/student-model.service';
import type { AbilityProfileService } from '../services/ability-profile.service';
import type { GrowthTrendService } from '../services/growth-trend.service';
import type { PromptLoader } from '../services/prompt-loader';
import type { MessageRouter } from '../services/message-router';
import type { TeachingStrategyService } from '../services/teaching-strategy.service';
import type { ProblemPrioritizer } from '../services/problem-prioritizer.service';
import type { DisputeTrackerService } from '../services/dispute-tracker.service';
import type { ReflectionGateService } from '../services/reflection-gate.service';
import type { DiagnosisMerger } from '../services/diagnosis-merger';

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
    const teachingStrategyService = this.container.get<TeachingStrategyService>('teachingStrategyService');
    const problemPrioritizer = this.container.get<ProblemPrioritizer>('problemPrioritizer');
    const disputeTracker = this.container.get<DisputeTrackerService>('disputeTracker');
    const reflectionGate = this.container.get<ReflectionGateService>('reflectionGate');
    const promptLoader = this.container.get<PromptLoader>('promptLoader');
    const messageRouter = this.container.get<MessageRouter>('messageRouter');

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

    // Training
    initTrainingHandlers({ configService, trainingRecordService, studentModelService });
    registerTrainingHandlers();

    // Teaching State (uses internal setters, no deps interface)
    registerTeachingStateHandlers();

    // Diagnosis - create merger via teaching-state.handler
    let diagnosisMerger!: DiagnosisMerger;
    registerDiagnosisMerger((m) => { diagnosisMerger = m; });

    initDiagnosisHandlers({
      configService,
      diagnosisService,
      evidenceService,
      sessionService,
      growthTrendService,
      getTeachingStateBySession: (sessionId: string) => {
        const context = getTeachingStateContext(sessionId);
        if (!context) return null;
        return { activeProblems: context.activeProblems };
      },
      diagnosisMerger,
      mainWindow: this.mainWindow,
    });
    registerDiagnosisHandlers();

    // Chat
    initChatHandlers({
      configService,
      sessionService,
      diagnosisService,
      promptLoader,
      messageRouter,
      studentModelService,
      teachingStrategyService,
      problemPrioritizer,
      disputeTracker,
      reflectionGate,
      mainWindow: this.mainWindow,
    });
    registerChatHandlers();

    // Manuscript (V2 SOLO — 直接使用 db 实例)
    initManuscriptHandlers({ db: this.container.get<any>('db') });
    registerManuscriptHandlers();
  }
}
