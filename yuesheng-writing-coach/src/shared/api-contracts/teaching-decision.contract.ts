/**
 * teaching-decision.contract.ts — 教学决策记录层 IPC 契约
 *
 * 依据 spec §8.3 Phase 1 = "写不读":
 *   - 当前仅暴露 record() 通道(主进程内部调用,非用户触发)
 *   - 读通道(getBySession/getByDecision)留待 Phase 4+ 评估是否暴露
 *   - 任何读路径必须经过审计,严禁前端 UI 直接订阅
 *
 * 约束:
 *   - R-021 隐性诊断:本契约不向 renderer 暴露数据读通道
 *   - R-014 配置外置:strategy 枚举引用 shared/types 的 TeachingStrategyType
 */

import type {
  TeachingDecisionStudentState,
  TeachingStrategyType,
} from '../types/types-teaching';

/** record 请求:写入一条决策记录(由主进程诊断流水线内部调用) */
export interface TeachingDecisionRecordRequest {
  sessionId: string;
  syndromeId: string;
  strategyChosen: TeachingStrategyType;
  reason: string;
  studentState: TeachingDecisionStudentState;
}

/** record 响应:返回写入的 decisionId(便于 Phase 4 关联 outcome) */
export interface TeachingDecisionRecordResponse {
  decisionId: string;
  decidedAt: number;
}

/**
 * 教学决策 IPC API
 *
 * 阶段:Phase 1 — 仅 record,读路径暂不开放(spec §8.3)
 * 未来扩展:Phase 4+ 可加 getBySession / getBySyndrome / getOutcomeSummary
 */
export const TeachingDecisionApi = {
  record: 'teachingDecision:record',
} as const;

/** invoke 通道(主进程调用) */
export type TeachingDecisionInvokeChannels = 'teachingDecision:record';

/** event 通道(预留,Phase 1 不推送任何事件给 renderer) */
export type TeachingDecisionEventChannels = never;

/** record 入参校验类型导出(供 validate-payload 工具复用) */
export type TeachingDecisionRecordPayload = TeachingDecisionRecordRequest;
