import type { ApiResponse } from './base';
import { IPC_CHANNELS } from '../constants';

// ─── 请求类型(RWR-P1-9 / C-3 训练反馈回路) ───

/**
 * teachingHistory:add 请求
 * 训练完成后由渲染端发起,主进程 handler 调
 * StudentModelService.appendTeachingHistory 写入。
 * consumed/total 由渲染端 progress.store 快照传入,
 * 供主进程判断精通门控(R-010 最小化:不扩 StudentModelService)。
 */
export interface TeachingHistoryAddRequest {
  /** 当前会话 ID */
  sessionId: string;
  /**
   * 教学历史条目(timestamp 由主进程填 Date.now(),
   * 渲染端不传以避免时钟漂移)。
   */
  entry: {
    action: string;
    syndromeId: string;
    outcome: 'success' | 'partial' | 'frustrated' | 'unknown';
  };
  /** 当前会话已解决症候数(progress.store 快照) */
  consumed: number;
  /** 当前会话症候总数(progress.store 快照) */
  total: number;
}

// ─── 响应类型 ───

/**
 * teachingHistory:add 响应
 * masteryReached: 是否触发精通门控(resolvedIssues / totalIssues ≥ 0.8)
 * consumed / total: 当前会话进度快照(供渲染端做 UI 反馈)
 */
export interface TeachingHistoryAddResponse {
  /** 是否已写入 */
  added: boolean;
  /** 是否达成精通门控 */
  masteryReached: boolean;
  /** 写入后的已解决/总数 */
  consumed: number;
  total: number;
}

// ─── API 接口定义 ───

export const TeachingHistoryApi = {
  add: {
    channel: IPC_CHANNELS.TEACHING_HISTORY_ADD,
    request: {} as TeachingHistoryAddRequest,
    response: {} as ApiResponse<TeachingHistoryAddResponse>,
  },
};
