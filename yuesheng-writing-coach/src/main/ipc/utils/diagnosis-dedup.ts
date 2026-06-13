/**
 * diagnosis-dedup.ts — RP-02 双诊断管道去重
 *
 * Pipe 1 (chat.handler.runDiagnosis) 和 Pipe 2 (diagnosis.handler.processDiagnosisFromAI)
 * 都可能发送 diagnosis:update，用 Set 记录已推送的 sessionId，避免重复推送。
 */
const _diagnosisPushedInChat = new Set<string>();

export function markDiagnosisPushed(sessionId: string): void {
  _diagnosisPushedInChat.add(sessionId);
}

export function wasDiagnosisPushed(sessionId: string): boolean {
  return _diagnosisPushedInChat.has(sessionId);
}
