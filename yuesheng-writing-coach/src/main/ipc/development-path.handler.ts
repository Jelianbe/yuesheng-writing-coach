/**
 * 发展路径 — Sprint 26 阶段 3.5 方案 4a bridge 注册
 *
 * 原 IPC handler 已废弃,改为 registerMethod 走单端点 bridge:invoke。
 * 调用方:`serviceBridge.invoke('prescription:getStageProgress' | 'prescription:getAllStages' | 'prescription:getStageById', ...)`
 *
 * 注: 3.4 评估标记 getAllStages/getStageById 为删除候选(纯直调),先迁 bridge 作为过渡收口,
 *     后续批次 4 统一删除。getStageProgress 因有 StudentModelService 数据转换,短期保留。
 */

import { validatePayload } from './utils/validate-payload';
import { registerMethod } from '../core/service-bridge';
import {
  getAllStages,
  getStageById,
  getCurrentStage,
} from '../domains/02-prescription/development-path/development-path.service';
import type { UserMasteryData } from '../../shared/types/index';
import type { StudentModelService } from '../domains/02-prescription/student/student-model-service';
import type { SyndromeAggregation } from '../domains/02-prescription/student/student-model-service.types';

function severityToMasteryScore(severity: string): number {
  switch (severity) {
    case 'L3': return 3;
    case 'L2': return 6;
    case 'L1': return 9;
    default: return 5;
  }
}

export interface DevelopmentPathHandlerDeps {
  studentModelService: StudentModelService;
}

let deps: DevelopmentPathHandlerDeps | null = null;

export function initDevelopmentPathHandlers(d: DevelopmentPathHandlerDeps): void {
  deps = d;
}

export function registerDevelopmentPathHandlers(): void {
  registerMethod('prescription:getStageProgress', async (args) => {
    const validation = validatePayload<{ sessionId: string }>(args, {
      required: ['sessionId'],
      types: { sessionId: 'string' },
    });
    if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    if (!deps) throw new Error('DevelopmentPathHandler deps not initialized');

    const profile = deps.studentModelService.getSyndromeProfile(validation.data.sessionId);
    if (!profile || Object.keys(profile).length === 0) {
      return getCurrentStage([]);
    }

    const masteryData: UserMasteryData[] = Object.entries(profile).map(
      ([syndromeId, agg]: [string, SyndromeAggregation]) => ({
        syndromeId,
        averageScore: severityToMasteryScore(agg.latestSeverity),
        trainingCount: agg.occurrenceCount,
        lastScore: severityToMasteryScore(
          agg.severityHistory[agg.severityHistory.length - 1] ?? agg.latestSeverity
        ),
      }),
    );

    return getCurrentStage(masteryData);
  });

  registerMethod('prescription:getAllStages', async (_args) => {
    return getAllStages();
  });

  registerMethod('prescription:getStageById', async (args) => {
    const validation = validatePayload<{ stageId: string }>(args, {
      required: ['stageId'],
      types: { stageId: 'string' },
    });
    if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);

    const stage = getStageById(validation.data.stageId);
    if (!stage) {
      throw new Error(`Stage not found: ${validation.data.stageId}`);
    }
    return stage;
  });
}
