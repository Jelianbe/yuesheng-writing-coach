import type Database from 'better-sqlite3';
import { ServiceContainer } from './service-container';
import { ConfigService } from '../services/config.service';
import { SessionService } from '../services/session.service';
import { DiagnosisService } from '../services/diagnosis.service';
import { EvidenceService } from '../services/evidence.service';
import { TrainingRecordService } from '../services/training-record.service';
import { StudentModelService } from '../services/student-model.service';
import { AbilityProfileService } from '../services/ability-profile.service';
import { GrowthTrendService } from '../services/growth-trend.service';
import { TeachingStrategyService } from '../services/teaching-strategy.service';
import { TeachingStrategyRouter } from '../services/teaching-strategy-router';
import { ProblemPrioritizer } from '../services/problem-prioritizer.service';
import { DisputeTrackerService } from '../services/dispute-tracker.service';
import { PromptBuilder } from '../services/prompt-builder';
import { PromptLoader } from '../services/prompt-loader';
import { MessageRouter } from '../services/message-router';
import { DynamicContextService } from '../services/dynamic-context.service';
import { ReflectionGateService } from '../services/reflection-gate.service';
import { CodexService } from '../services/codex.service';
import { initStore, getTeachingStateContext, getStoreForPromptLoader } from '../ipc/teaching-state.handler';
import { injectMockDiagnosisData } from '../services/mock-data-injector';

export function configureServices(
  container: ServiceContainer,
  db: Database.Database,
  resourcesRoot: string,
  isDevelopment: boolean,
): void {
  // Register database
  container.register<Database.Database>('db', () => db);
  container.register<string>('resourcesRoot', () => resourcesRoot);

  // Core services
  container.register<ConfigService>('configService', () => new ConfigService());
  container.register<SessionService>('sessionService', () => new SessionService(db));
  container.register<DiagnosisService>('diagnosisService', () => new DiagnosisService(db));
  container.register<EvidenceService>('evidenceService', () => new EvidenceService(db));
  container.register<TrainingRecordService>('trainingRecordService', () => new TrainingRecordService(db));

  // Student model depends on diagnosisService, trainingRecordService
  container.register<StudentModelService>('studentModelService', (c) =>
    new StudentModelService(
      db,
      c.get<DiagnosisService>('diagnosisService'),
      c.get<TrainingRecordService>('trainingRecordService'),
      resourcesRoot,
    ),
  );

  // Ability profile
  container.register<AbilityProfileService>('abilityProfileService', (c) =>
    new AbilityProfileService(
      db,
      c.get<DiagnosisService>('diagnosisService'),
      c.get<TrainingRecordService>('trainingRecordService'),
      resourcesRoot,
    ),
  );

  // Growth trend
  container.register<GrowthTrendService>('growthTrendService', (c) =>
    new GrowthTrendService(c.get<StudentModelService>('studentModelService')),
  );

  // Strategy services
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

  // Prompt infrastructure
  container.register<PromptBuilder>('promptBuilder', () => new PromptBuilder());

  // Dynamic context service
  container.register<DynamicContextService>('dynamicContextService', () =>
    new DynamicContextService(resourcesRoot),
  );

  // Codex 结构化知识注入服务
  container.register<CodexService>('codexService', () =>
    new CodexService(resourcesRoot),
  );

  // PromptLoader with setters
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

  container.register<MessageRouter>('messageRouter', () => new MessageRouter());

  // Initialize teaching store
  initStore(db);

  // Dev mode mock data
  if (isDevelopment) {
    injectMockDiagnosisData(db);
  }
}
