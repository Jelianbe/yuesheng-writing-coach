import type Database from 'better-sqlite3';
import type { ServiceContainer } from './service-container';
import { ConfigService } from '../shared/services/config.service';
import { SessionService } from '../shared/services/session.service';
import { DiagnosisService } from '../domains/01-diagnosis/diagnosis.service';
import { EvidenceService } from '../domains/01-diagnosis/evidence/evidence.service';
import { TrainingRecordService } from '../domains/04-validation/training/training-record.service';
import { StudentModelService } from '../domains/02-prescription/student/student-model-service';
import { AbilityProfileService } from '../domains/02-prescription/student/ability-profile.service';
import { ProfileDataAggregator } from '../domains/02-prescription/student/profile-data-aggregator';
import { GrowthTrendService } from '../domains/02-prescription/student/growth-trend.service';
import { TeachingStrategyService } from '../domains/02-prescription/strategy/service';
import { TeachingStrategyRouter } from '../domains/02-prescription/strategy/router';
import { ProblemPrioritizer } from '../domains/02-prescription/problem-prioritizer.service';
import { DisputeTrackerService } from '../domains/03-teaching/dispute-tracker.service';
import { PromptBuilder } from '../domains/03-teaching/prompt/prompt-builder';
import { PromptLoader } from '../domains/03-teaching/prompt/prompt-loader';
import { MessageRouter } from '../domains/03-teaching/chat/message-router';
import { DynamicContextService } from '../domains/03-teaching/prompt/dynamic-context.service';
import { ReflectionGateService } from '../domains/03-teaching/reflection-gate.service';
import { CodexService } from '../domains/03-teaching/prompt/codex.service';
import { getTeachingStateContext, getStoreForPromptLoader } from '../ipc/teaching-state.handler';
import { TeachingStateService } from '../domains/03-teaching/teaching-state.service';
import { ActiveTrainingService } from '../domains/03-teaching/state/active-training.service';
import { ActiveTrainingStore } from '../domains/03-teaching/state/active-training.store';
import { TeachingNoteService } from '../domains/03-teaching/teaching-note.service';
import { ApiProxyService } from '../shared/services/api-proxy.service';
import { StrategyInstructionBuilder } from '../domains/03-teaching/strategy-instruction-builder';
import { ChatOrchestratorService, TechniquePoolService, DiagnosisOrchestratorService, TeachingContextService, StreamHandlerService } from '../domains/03-teaching/chat';
import { DiagnosisMerger } from '../domains/01-diagnosis/diagnosis-merger';
import { injectMockDiagnosisData } from '../services/mock-data-injector';
import type { IDiagnosisDomain } from '../domains/01-diagnosis';
import { processAIResponse } from '../domains/01-diagnosis/diagnosis-processor';
import { TeachingDecisionService } from '../domains/02-prescription/decision/decision.service';
import { RetroService } from '../domains/05-retro/retro.service';
import type { ITeachingDomain } from '../domains/03-teaching';
import type { IStudentDomain } from '../domains/02-prescription/student';
import type { IPromptDomain } from '../domains/03-teaching/prompt';
import type { AttitudeLevel, DiagnosisAnalysis } from '../../shared/types/index';
import type { DiagnosisEntry } from '../../shared/types/types-diagnosis';
import { getMemoryCapsuleService } from '../domains/03-teaching/prompt/memory-capsule.service';
import type { CodexEntry } from '../domains/03-teaching/prompt/codex.service';
import type { CapsuleOptions } from '../domains/03-teaching/prompt/memory-capsule.service';
import type { ReflectionQuestion } from '../domains/03-teaching/reflection-gate.service';

export function configureServices(
  container: ServiceContainer,
  db: Database.Database,
  resourcesRoot: string,
  isDevelopment: boolean,
): void {
  // ============================================================
  // Shared / Infrastructure Layer
  // ============================================================
  container.register<Database.Database>('db', () => db);
  container.register<string>('resourcesRoot', () => resourcesRoot);
  container.register<ConfigService>('configService', () => new ConfigService());
  container.register<SessionService>('sessionService', () => new SessionService(db));
  container.register<ApiProxyService>('apiProxyService', (c) =>
    new ApiProxyService(c.get<ConfigService>('configService')),
  );

  // ============================================================
  // Diagnosis Domain
  // ============================================================
  container.register<DiagnosisService>('diagnosisService', () => new DiagnosisService(db));
  container.register<EvidenceService>('evidenceService', () => new EvidenceService(db));
  container.register<DiagnosisMerger>('diagnosisMerger', (c) => {
    const teachingStateService = c.get<TeachingStateService>('teachingStateService');
    return new DiagnosisMerger(teachingStateService);
  });

  // RWR-P1-6 (B-2): 教学决策记录层
  container.register<TeachingDecisionService>('teachingDecisionService', () =>
    new TeachingDecisionService(db),
  );

  // ============================================================
  // Training Domain
  // ============================================================
  container.register<TrainingRecordService>('trainingRecordService', () => new TrainingRecordService(db));

  // ============================================================
  // Retro Domain (F-03)
  // ============================================================
  container.register<RetroService>('retroService', (c) =>
    new RetroService(c.get<TrainingRecordService>('trainingRecordService')),
  );

  // ============================================================
  // Student Domain
  // ============================================================
  container.register<ProfileDataAggregator>('profileDataAggregator', (c) =>
    new ProfileDataAggregator(
      c.get<DiagnosisService>('diagnosisService'),
      c.get<TrainingRecordService>('trainingRecordService'),
    ),
  );

  container.register<StudentModelService>('studentModelService', (c) =>
    new StudentModelService(
      db,
      c.get<ProfileDataAggregator>('profileDataAggregator'),
      resourcesRoot,
    ),
  );

  container.register<AbilityProfileService>('abilityProfileService', (c) =>
    new AbilityProfileService(
      c.get<ProfileDataAggregator>('profileDataAggregator'),
      resourcesRoot,
    ),
  );

  container.register<GrowthTrendService>('growthTrendService', (c) =>
    new GrowthTrendService(c.get<StudentModelService>('studentModelService')),
  );

  // ============================================================
  // Teaching Domain
  // ============================================================
  container.register<TeachingStrategyService>('teachingStrategyService', () => {
    const service = new TeachingStrategyService(resourcesRoot);
    const router = new TeachingStrategyRouter(resourcesRoot);
    service.setRouter(router);
    return service;
  });

  container.register<ProblemPrioritizer>('problemPrioritizer', () =>
    new ProblemPrioritizer(resourcesRoot),
  );

  container.register<DisputeTrackerService>('disputeTracker', () => new DisputeTrackerService());
  container.register<ReflectionGateService>('reflectionGate', () => new ReflectionGateService());

  container.register<StrategyInstructionBuilder>('strategyInstructionBuilder', (c) =>
    new StrategyInstructionBuilder(
      c.get<StudentModelService>('studentModelService'),
      c.get<TeachingStrategyService>('teachingStrategyService'),
      c.get<ProblemPrioritizer>('problemPrioritizer'),
    ),
  );

  container.register<TeachingStateService>('teachingStateService', () => {
    const service = new TeachingStateService();
    service.initStore(db);
    return service;
  });

  // Sprint 24 A-1/A-2: ActiveTraining 完整状态机服务
  // - 封装 ActiveTrainingStore (active_training 表)
  // - 订阅 training_triggered 事件,实现 start/advanceStep/updateDraft/evaluate/complete/abort
  container.register<ActiveTrainingService>('activeTrainingService', () => {
    const store = new ActiveTrainingStore(db);
    return new ActiveTrainingService(store);
  });

  // 教学笔记服务 (I-08)
  container.register<TeachingNoteService>('teachingNoteService', () => new TeachingNoteService());

  // ============================================================
  // Prompt Domain
  // ============================================================
  container.register<PromptBuilder>('promptBuilder', () => new PromptBuilder());

  container.register<DynamicContextService>('dynamicContextService', () =>
    new DynamicContextService(resourcesRoot),
  );

  container.register<CodexService>('codexService', () =>
    new CodexService(resourcesRoot),
  );

  container.register<PromptLoader>('promptLoader', (c) => {
    const loader = new PromptLoader(resourcesRoot);
    loader.setStateContextGetter((sessionId: string) => {
      const context = getTeachingStateContext(sessionId);
      if (!context || !context.currentPhase || !context.currentSubphase) return null;
      return { currentPhase: context.currentPhase, currentSubphase: context.currentSubphase };
    });
    loader.setPromptBuilder(c.get<PromptBuilder>('promptBuilder'));
    loader.setStoreGetter(getStoreForPromptLoader);
    loader.setDynamicContextService(c.get<DynamicContextService>('dynamicContextService'));
    loader.setCodexService(c.get<CodexService>('codexService'));
    // T14-8: 启用 SkillDispatcher v2（D-034）
    // P2+ 阶段走 dispatcher（coreSubset + 4K token 预算）
    // P0/P1 仍走 v5 降级（保持 ~800 字符）
    loader.initializeSkillDispatcher();
    return loader;
  });

  // ============================================================
  // Chat Domain
  // ============================================================
  container.register<MessageRouter>('messageRouter', () => new MessageRouter());
  container.register<StreamHandlerService>('streamHandlerService', () => new StreamHandlerService());
  container.register<TechniquePoolService>('techniquePoolService', () => new TechniquePoolService(resourcesRoot));

  container.register<DiagnosisOrchestratorService>('diagnosisOrchestratorService', (c) =>
    new DiagnosisOrchestratorService(
      c.get<TechniquePoolService>('techniquePoolService'),
      {
        save: (data) => c.get<DiagnosisService>('diagnosisService').save(data as DiagnosisEntry),
        saveAnalysis: (analysis, diagId) => c.get<DiagnosisService>('diagnosisService').saveAnalysis(analysis, diagId),
        getRecentBySession: (sessionId, limit) => c.get<DiagnosisService>('diagnosisService').getRecentBySession(sessionId, limit),
        processAIResponse: (fullResponse, sessionId, messageId) =>
          processAIResponse(fullResponse, sessionId, messageId, {
            diagnosisService: c.get<DiagnosisService>('diagnosisService'),
            evidenceService: c.get<EvidenceService>('evidenceService'),
            diagnosisMerger: c.get<DiagnosisMerger>('diagnosisMerger'),
            teachingDecisionService: c.get<TeachingDecisionService>('teachingDecisionService'),
          }),
      } as IDiagnosisDomain,
      null,
    ),
  );

  container.register<TeachingContextService>('teachingContextService', (c) =>
    new TeachingContextService(
      {
        getRecentBySession: (sessionId, limit) => c.get<DiagnosisService>('diagnosisService').getRecentBySession(sessionId, limit),
        save: () => '',
        saveAnalysis: () => {},
        processAIResponse: () => {},
      } as IDiagnosisDomain,
      {
        loadSystemPrompt: (attitude: AttitudeLevel, diagnosisAnalysis: DiagnosisAnalysis | null, diagnosisHistory?: string, studentContext?: string, sessionId?: string, _transitionPrompt?: string, _codexEntries?: unknown[], _flags?: { hasSession?: boolean; hasDiagnosis?: boolean }) =>
          c.get<PromptLoader>('promptLoader').loadSystemPrompt(attitude, diagnosisAnalysis, diagnosisHistory, studentContext, sessionId, undefined, _codexEntries as CodexEntry[], undefined),
        buildCapsule: (params: { diagnoses: unknown[]; recentCount: number }) =>
          getMemoryCapsuleService().buildCapsule(params as unknown as CapsuleOptions),
      } as IPromptDomain,
      c.get<StudentModelService>('studentModelService') as IStudentDomain,
      {
        checkMessage: () => {},
        getEffectiveAttitude: () => 'yuesheng' as AttitudeLevel,
        shouldTriggerReflection: (diagnosis: DiagnosisAnalysis) =>
          c.get<ReflectionGateService>('reflectionGate').shouldTriggerReflection(diagnosis),
        buildReflectionPrompt: (question: { question: string; syndromeId: string; syndromeName: string }, attitude: AttitudeLevel) =>
          c.get<ReflectionGateService>('reflectionGate').buildReflectionPrompt(question as ReflectionQuestion, attitude),
        buildStrategyInstruction: (diagnosis: DiagnosisAnalysis | null, attitude: AttitudeLevel) =>
          c.get<StrategyInstructionBuilder>('strategyInstructionBuilder').build(diagnosis, attitude),
      } as ITeachingDomain,
    ),
  );

  container.register<ChatOrchestratorService>('chatOrchestratorService', (c) => {
    const deps = {
      configService: c.get<ConfigService>('configService'),
      sessionService: c.get<SessionService>('sessionService'),
      messageRouter: c.get<MessageRouter>('messageRouter'),
      diagnosisDomain: {
        save: (data) => c.get<DiagnosisService>('diagnosisService').save(data as DiagnosisEntry),
        saveAnalysis: (analysis, diagId) => c.get<DiagnosisService>('diagnosisService').saveAnalysis(analysis, diagId),
        getRecentBySession: (sessionId, limit) => c.get<DiagnosisService>('diagnosisService').getRecentBySession(sessionId, limit),
        processAIResponse: (fullResponse, sessionId, messageId) =>
          processAIResponse(fullResponse, sessionId, messageId, {
            diagnosisService: c.get<DiagnosisService>('diagnosisService'),
            evidenceService: c.get<EvidenceService>('evidenceService'),
            diagnosisMerger: c.get<DiagnosisMerger>('diagnosisMerger'),
            teachingDecisionService: c.get<TeachingDecisionService>('teachingDecisionService'),
          }),
      } as IDiagnosisDomain,
      promptDomain: {
        loadSystemPrompt: (attitude: AttitudeLevel, diagnosisAnalysis: DiagnosisAnalysis | null, diagnosisHistory?: string, studentContext?: string, sessionId?: string, _transitionPrompt?: string, _codexEntries?: unknown[], _flags?: { hasSession?: boolean; hasDiagnosis?: boolean }) =>
          c.get<PromptLoader>('promptLoader').loadSystemPrompt(attitude, diagnosisAnalysis, diagnosisHistory, studentContext, sessionId, undefined, _codexEntries as CodexEntry[], undefined),
        buildCapsule: (params: { diagnoses: unknown[]; recentCount: number }) =>
          getMemoryCapsuleService().buildCapsule(params as unknown as CapsuleOptions),
      } as IPromptDomain,
      studentDomain: c.get<StudentModelService>('studentModelService') as IStudentDomain,
      teachingDomain: {
        checkMessage: (sessionId: string, message: string, isReflectionPhase: boolean) => {
          c.get<DisputeTrackerService>('disputeTracker').checkMessage(sessionId, message, isReflectionPhase);
        },
        getEffectiveAttitude: (sessionId: string, userAttitude: AttitudeLevel, isReflectionPhase: boolean) =>
          c.get<DisputeTrackerService>('disputeTracker').getEffectiveAttitude(sessionId, userAttitude, isReflectionPhase),
        shouldTriggerReflection: (diagnosis: DiagnosisAnalysis) =>
          c.get<ReflectionGateService>('reflectionGate').shouldTriggerReflection(diagnosis),
        buildReflectionPrompt: (question: { question: string; syndromeId: string; syndromeName: string }, attitude: AttitudeLevel) =>
          c.get<ReflectionGateService>('reflectionGate').buildReflectionPrompt(question as ReflectionQuestion, attitude),
        buildStrategyInstruction: (diagnosis: DiagnosisAnalysis | null, attitude: AttitudeLevel) =>
          c.get<StrategyInstructionBuilder>('strategyInstructionBuilder').build(diagnosis, attitude),
      } as ITeachingDomain,
      diagnosisOrchestrator: c.get<DiagnosisOrchestratorService>('diagnosisOrchestratorService'),
      teachingContext: c.get<TeachingContextService>('teachingContextService'),
      streamHandler: c.get<StreamHandlerService>('streamHandlerService'),
      mainWindow: null,
      db,
    };
    return new ChatOrchestratorService(deps);
  });

  // ============================================================
  // Dev Mode: Mock Data Injection
  // ============================================================
  if (isDevelopment) {
    injectMockDiagnosisData(db);
  }
}
