/**
 * 发展路径 IPC 处理器
 *
 * 负责：
 * 1. prescription:getStageProgress — 获取当前阶段进度（需 sessionId）
 * 2. prescription:getAllStages — 获取所有发展路径阶段
 * 3. prescription:getStageById — 按 ID 查询阶段信息
 *
 * 依赖：StudentModelService（用于获取症候掌握度数据）
 */

import { IPC_CHANNELS } from '../../shared/constants';
import { createHandler } from './utils/create-handler';
import { validatePayload } from './utils/validate-payload';
import {
  getAllStages,
  getStageById,
  getCurrentStage,
} from '../domains/02-prescription/development-path/development-path.service';
import type { UserMasteryData } from '../../shared/types/index';
import type { StudentModelService } from '../domains/02-prescription/student/student-model-service';
import type { SyndromeAggregation } from '../domains/02-prescription/student/student-model-service.types';

/** 症候严重度 → 掌握度评分映射（临时替代方案，后续应由训练评估数据替代） */
function severityToMasteryScore(severity: string): number {
  switch (severity) {
    case 'L3': return 3;  // 严重 → 低掌握度
    case 'L2': return 6;  // 中等 → 中掌握度
    case 'L1': return 9;  // 轻微 → 高掌握度
    default: return 5;    // 未知 → 默认中等
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
  /**
   * prescription:getStageProgress — 获取用户当前阶段进度
   *
   * 从 StudentModelService 获取症候画像，转换为掌握度数据后计算阶段进度。
   */
  createHandler(IPC_CHANNELS.PRESCRIPTION_GET_STAGE_PROGRESS, async (_event, args) => {
    const validation = validatePayload<{ sessionId: string }>(args, {
      required: ['sessionId'],
      types: { sessionId: 'string' },
    });
    if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    if (!deps) throw new Error('DevelopmentPathHandler deps not initialized');

    const profile = deps.studentModelService.getSyndromeProfile(validation.data.sessionId);
    if (!profile || Object.keys(profile).length === 0) {
      // 无诊断数据 → 返回第一阶段（eye 自动通过后为 pen）
      const progress = getCurrentStage([]);
      return progress;
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

    const progress = getCurrentStage(masteryData);
    return progress;
  });

  /**
   * prescription:getAllStages — 获取全部发展阶段（只读）
   *
   * 返回 ApiResponse<DevelopmentStageInfo[]> 包装后的数据。
   * handler 只返回裸数据,createHandler 会包成 { success, data }。
   */
  createHandler(IPC_CHANNELS.PRESCRIPTION_GET_ALL_STAGES, async () => {
    return getAllStages();
  });

  /**
   * prescription:getStageById — 按 ID 查询阶段信息
   */
  createHandler(IPC_CHANNELS.PRESCRIPTION_GET_STAGE_BY_ID, async (_event, args) => {
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
