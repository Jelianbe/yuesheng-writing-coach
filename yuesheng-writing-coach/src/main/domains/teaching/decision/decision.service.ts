/**
 * TeachingDecisionService — 教学决策记录层(主进程)
 *
 * 依据 spec §8.2 + §8.3:
 *   - 仅实现 record() 一个公开方法(写不读)
 *   - 读路径(getBySession/getBySyndrome)在 Phase 4+ 评估后再开放
 *   - 与 DiagnosisService / TeachingStateService 解耦,避免循环依赖
 *
 * 约束:
 *   - R-021 隐性诊断:本服务是系统内部,前端 UI 永不渲染
 *   - R-020 循环依赖:不引用 diagnosis / state-machine / store
 *   - R-014 配置外置:策略枚举引用 shared/types
 *
 * 调用方:diagnosis-processor.processAIResponse 内(diagnosisService.save 之后)
 */

import crypto from 'node:crypto';
import type Database from 'better-sqlite3';
import type {
  TeachingDecisionStudentState,
  TeachingStrategyType,
} from '../../../../shared/types/types-teaching';

export interface TeachingDecisionRecordInput {
  sessionId: string;
  syndromeId: string;
  strategyChosen: TeachingStrategyType;
  reason: string;
  studentState: TeachingDecisionStudentState;
}

export class TeachingDecisionService {
  constructor(private db: Database.Database) {}

  /**
   * 写入一条教学决策记录
   * 幂等保证:decisionId 由 crypto.randomUUID 生成,DB 冲突概率为零
   *
   * @returns 写入的 decisionId(供 Phase 4 outcome 关联)
   */
  record(input: TeachingDecisionRecordInput): { decisionId: string; decidedAt: number } {
    const decisionId = `dec_${crypto.randomUUID()}`;
    const decidedAt = Date.now();

    const stmt = this.db.prepare(`
      INSERT INTO teaching_decision_log
        (decision_id, session_id, syndrome_id, strategy_chosen, reason, student_state_json, decided_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)
    `);
    stmt.run(
      decisionId,
      input.sessionId,
      input.syndromeId,
      input.strategyChosen,
      input.reason,
      JSON.stringify(input.studentState),
      Math.floor(decidedAt / 1000),
    );

    return { decisionId, decidedAt };
  }
}
