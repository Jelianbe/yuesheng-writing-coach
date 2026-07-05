/**
 * 训练协调服务 — Sprint 20 B-2 降级(D-DEBT-34)
 *
 * 重要:本服务载荷包含 AI 评估/学生练习/角色行为推导等敏感数据。
 * 降级策略:调用失败时 console.error + 返回 null,不再 throw,
 * 避免 UI 白屏(R-028 防御性编码 + R-027 门禁)。
 *
 * ─── Sprint 26 阶段 3.2 (双轨化决策) ───
 *
 * training 业务(推荐/分配/评估/角色行为推导)全部在主进程 +
 * 依赖 AI 模型 + 教学状态机。shared 端**无等价 service**。因此本 service
 * **不引入 runDualTrack**,而是:
 *   - 所有方法保持 IPC-only
 *   - Capacitor 端部分方法通过 capacitor-training 实现真实降级
 *   - 后续 training 业务下沉到 shared 时再统一迁移(待 S27+)
 *
 * ─── Sprint 33 (Training Android 端激活) ───
 *
 * Capacitor 端从全部 noop 升级为部分真实实现:
 *   - submit/evaluate/deriveBehavior: 用 LlmClient 直调 LLM
 *   - recommend/assign/complete/skip/history: 保持 noop(SQLite 依赖)
 *
 * 注:active-training.service.ts 已双轨化,本 service 是历史遗留
 *   「10 通道训练协调」,待 S27+ 拆分迁移到 active-training。
 *
 * Capacitor 端已知 trade-off:
 *   - recommend/assign/complete/skip/history 降级:需 SQLite 表
 *   - ✅ submit 升级:LlmClient 评估
 *   - ✅ evaluate 升级:LlmClient 评分
 *   - ✅ deriveBehavior 升级:LlmClient 行为分析
 *
 * 依据: dev-docs/decision-log.md D-083
 */

import { serviceBridge } from './service-bridge';
import { isCapacitor } from './_dual-track';
import {
  capacitorTrainingSubmit,
  capacitorTrainingEvaluate,
  capacitorTrainingDeriveBehavior,
} from './capacitor-training';
import type {
  TrainingRecommendRequest,
  TrainingRecommendResponse,
  TrainingAssignRequest,
  TrainingAssignResponse,
  TrainingCompleteRequest,
  TrainingCompleteResponse,
  TrainingSkipRequest,
  TrainingHistoryRequest,
  TrainingHistoryResponse,
  TrainingSubmitRequest,
  TrainingSubmitResponse,
  TrainingEvaluateRequest,
  TrainingEvaluateResponse,
  TrainingDeriveBehaviorRequest,
  TrainingDeriveBehaviorResponse,
} from '../../shared/api-contracts/training.contract';

/**
 * Capacitor 端无 IPC 通道,统一降级标识
 * C4-c 方案：明确降级，不伪造数据，不静默吞
 */
function capacitorNoopTraining<T>(methodName: string, fallback: T): T {
  console.warn(`[training] ${methodName}: not supported on Capacitor (C4-c 明确降级), returning fallback`);
  return fallback;
}

/**
 * Android 端训练协调功能是否可用
 * UI 层可在渲染前调用此函数，提前显示"不支持"提示，而非等调用失败
 */
export function isTrainingSupportedOnCapacitor(): boolean {
  return !isCapacitor();
}

export const trainingService = {
  /** 获取推荐训练 — 失败时返回 null(降级) */
  async recommend(params: TrainingRecommendRequest): Promise<TrainingRecommendResponse | null> {
    if (isCapacitor()) return capacitorNoopTraining('recommend', null);
    const result = await serviceBridge.invoke<TrainingRecommendRequest, TrainingRecommendResponse>('training:recommend', params);
    if (!result) {
      console.error('[training] recommend failed');
      return null;
    }
    return result;
  },

  /** 分配训练任务 — 失败时返回 null(降级) */
  async assign(params: TrainingAssignRequest): Promise<TrainingAssignResponse | null> {
    if (isCapacitor()) return capacitorNoopTraining('assign', null);
    const result = await serviceBridge.invoke<TrainingAssignRequest, TrainingAssignResponse>('training:assign', params);
    if (!result) {
      console.error('[training] assign failed');
      return null;
    }
    return result;
  },

  /** 完成训练 — 失败时返回 null(降级) */
  async complete(params: TrainingCompleteRequest): Promise<TrainingCompleteResponse | null> {
    if (isCapacitor()) return capacitorNoopTraining('complete', null);
    const result = await serviceBridge.invoke<TrainingCompleteRequest, TrainingCompleteResponse>('training:complete', params);
    if (!result) {
      console.error('[training] complete failed');
      return null;
    }
    return result;
  },

  /** 跳过训练 — 失败时返回 null(降级,B-3 补齐) */
  async skip(params: TrainingSkipRequest): Promise<TrainingCompleteResponse | null> {
    if (isCapacitor()) return capacitorNoopTraining('skip', null);
    const result = await serviceBridge.invoke<TrainingSkipRequest, TrainingCompleteResponse>('training:skip', params);
    if (!result) {
      console.error('[training] skip failed');
      return null;
    }
    return result;
  },

  /** 查询训练历史 — 失败时返回 null(降级) */
  async history(params: TrainingHistoryRequest): Promise<TrainingHistoryResponse | null> {
    if (isCapacitor()) return capacitorNoopTraining('history', null);
    const result = await serviceBridge.invoke<TrainingHistoryRequest, TrainingHistoryResponse>('training:history', params);
    if (!result) {
      console.error('[training] history failed');
      return null;
    }
    return result;
  },

  /** 提交训练 — 失败时返回 null(降级,涉及用户练习内容 + AI 评分) */
  async submit(params: TrainingSubmitRequest): Promise<TrainingSubmitResponse | null> {
    if (isCapacitor()) return capacitorTrainingSubmit(params);
    const result = await serviceBridge.invoke<TrainingSubmitRequest, TrainingSubmitResponse>('training:submit', params);
    if (!result) {
      console.error('[training] submit failed');
      return null;
    }
    return result;
  },

  /** 评估训练 — 失败时返回 null(降级,涉及 AI 评估全文) */
  async evaluate(params: TrainingEvaluateRequest): Promise<TrainingEvaluateResponse | null> {
    if (isCapacitor()) return capacitorTrainingEvaluate(params);
    const result = await serviceBridge.invoke<TrainingEvaluateRequest, TrainingEvaluateResponse>('training:evaluate', params);
    if (!result) {
      console.error('[training] evaluate failed');
      return null;
    }
    return result;
  },

  /** 推导角色行为 — 失败时返回 null(降级,涉及角色心理分析) */
  async deriveBehavior(params: TrainingDeriveBehaviorRequest): Promise<TrainingDeriveBehaviorResponse | null> {
    if (isCapacitor()) return capacitorTrainingDeriveBehavior(params);
    const result = await serviceBridge.invoke<TrainingDeriveBehaviorRequest, TrainingDeriveBehaviorResponse>('training:deriveBehavior', params);
    if (!result) {
      console.error('[training] deriveBehavior failed');
      return null;
    }
    return result;
  },
};
