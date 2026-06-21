/**
 * diagnosis-dedup.ts — RP-02 双诊断管道去重
 *
 * Pipe 1 (chat.handler.runDiagnosis) 和 Pipe 2 (diagnosis.handler.processDiagnosisFromAI)
 * 都可能发送 diagnosis:updated，用 Set 记录已推送的 sessionId，避免重复推送。
 *
 * 清理策略：Set 上限 100 条，超过时清理最旧的一半 (FIFO)。
 * 会话删除时主动调用 clearSession() 释放条目。
 */
const MAX_DEDUP_ENTRIES = 100;
const _diagnosisPushedInChat = new Set<string>();

export function markDiagnosisPushed(sessionId: string): void {
  // 达到上限时清理最旧的 50 条
  if (_diagnosisPushedInChat.size >= MAX_DEDUP_ENTRIES) {
    const entries = [..._diagnosisPushedInChat];
    const toRemove = entries.slice(0, Math.floor(MAX_DEDUP_ENTRIES / 2));
    for (const id of toRemove) {
      _diagnosisPushedInChat.delete(id);
    }
  }
  _diagnosisPushedInChat.add(sessionId);
}

export function wasDiagnosisPushed(sessionId: string): boolean {
  return _diagnosisPushedInChat.has(sessionId);
}

/** 会话删除时主动清理，避免内存泄漏 */
export function clearDiagnosisPushed(sessionId: string): void {
  _diagnosisPushedInChat.delete(sessionId);
}
