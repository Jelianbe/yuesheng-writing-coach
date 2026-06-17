import type Database from 'better-sqlite3';
import { ServiceContainer } from './service-container';
import { ConfigService } from '../shared/services/config.service';
import { SessionService } from '../shared/services/session.service';
import { DiagnosisService } from '../domains/diagnosis/diagnosis.service';
import { EvidenceService } from '../domains/diagnosis/evidence/evidence.service';
import { TrainingRecordService } from '../domains/training/training-record.service';
import { StudentModelService } from '../domains/student/student-model-service';
import { AbilityProfileService } from '../domains/student/ability-profile.service';
import { ProfileDataAggregator } from '../domains/student/profile-data-aggregator';
import { GrowthTrendService } from '../domains/student/growth-trend.service';
import { TeachingStrategyService } from '../domains/teaching/strategy/service';
import { TeachingStrategyRouter } from '../domains/teaching/strategy/router';
import { ProblemPrioritizer } from '../domains/teaching/problem-prioritizer.service';
import { DisputeTrackerService } from '../domains/teaching/dispute-tracker.service';
import { PromptBuilder } from '../domains/prompt/prompt-builder';
import { PromptLoader } from '../domains/prompt/prompt-loader';
import { MessageRouter } from '../domains/chat/message-router';
import { DynamicContextService } from '../domains/prompt/dynamic-context.service';
import { ReflectionGateService } from '../domains/teaching/reflection-gate.service';
import { CodexService } from '../domains/prompt/codex.service';
import { getTeachingStateContext, getStoreForPromptLoader } from '../ipc/teaching-state.handler';
import { TeachingStateService } from '../domains/teaching/teaching-state.service';
import { ApiProxyService } from '../shared/services/api-proxy.service';
import { StrategyInstructionBuilder } from '../domains/teaching/strategy-instruction-builder';
import { ChatOrchestratorService } from '../domains/chat/chat-orchestrator.service';
import { DiagnosisMerger } from '../domains/diagnosis/diagnosis-merger';
import { injectMockDiagnosisData } from '../services/mock-data-injector';
import type { IDiagnosisDomain } from '../domains/diagnosis';
import { processAIResponse } from '../domains/diagnosis/diagnosis-processor';
import { TeachingDecisionService } from '../domains/teaching/decision/decision.service';
import type { ITeachingDomain } from '../domains/teaching';
import type { IStudentDomain } from '../domains/student';
import type { IPromptDomain } from '../domains/prompt';
import type { AttitudeLevel, DiagnosisAnalysis } from '../../shared/types/index';
import type { DiagnosisEntry } from '../../shared/types/types-diagnosis';
import { getMemoryCapsuleService } from '../domains/prompt/memory-capsule.service';

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
    return loader;
  });

  // ============================================================
  // Chat Domain
  // ============================================================
  container.register<MessageRouter>('messageRouter', () => new MessageRouter());

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
          c.get<PromptLoader>('promptLoader').loadSystemPrompt(attitude, diagnosisAnalysis, diagnosisHistory, studentContext, sessionId, undefined, _codexEntries as any, undefined),
        buildCapsule: (params: { diagnoses: unknown[]; recentCount: number }) =>
          getMemoryCapsuleService().buildCapsule(params as any),
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
          c.get<ReflectionGateService>('reflectionGate').buildReflectionPrompt(question as any, attitude),
        buildStrategyInstruction: (diagnosis: DiagnosisAnalysis | null, attitude: AttitudeLevel) =>
          c.get<StrategyInstructionBuilder>('strategyInstructionBuilder').build(diagnosis, attitude),
      } as ITeachingDomain,
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
