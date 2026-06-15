/**
 * 诊断处理器 — 领域层
 *
 * 负责：解析 AI 回复中的诊断表 → 持久化 → 创建证据 → 合并到 TeachingState
 * 不包含 IPC 推送逻辑（由调用方负责）
 */

import { parseDiagnosisFromAIResponse } from './diagnosis-parser';
import type { DiagnosisService } from './diagnosis.service';
import type { EvidenceService } from './evidence/evidence.service';
import type { DiagnosisMerger } from './diagnosis-merger';
import type { DiagnosisEntry } from '../../../shared/types/types-diagnosis';
import { getAbilitiesForSyndrome } from '../../../shared/mappings';

export interface DiagnosisProcessorDeps {
  diagnosisService: DiagnosisService;
  evidenceService: EvidenceService;
  diagnosisMerger: DiagnosisMerger;
}

/**
 * 处理 AI 回复中的诊断数据
 * 核心领域逻辑：解析 → 持久化 → 创建证据 → 合并到教学状态
 * 不包含 IPC 推送，由调用方按需添加
 *
 * @returns 包含诊断 ID 和诊断对象的对象（持久化成功后），失败时返回 undefined
 */
export function processAIResponse(
  fullResponse: string,
  sessionId: string,
  messageId: string,
  deps: DiagnosisProcessorDeps,
): { diagnosisId: string; diagnosis: DiagnosisEntry } | undefined {
  const { cleanResponse: _cleanResponse, diagnosis } = parseDiagnosisFromAIResponse(
    fullResponse,
    sessionId,
    messageId,
  );

  if (!diagnosis) {
    console.warn('[DiagnosisProcessor] No diagnosis table in AI response');
    return undefined;
  }

  // 1. 持久化诊断结果
  let diagnosisId = '';
  try {
    diagnosisId = deps.diagnosisService.save(diagnosis);
  } catch (err) {
    console.error('[DiagnosisProcessor] Failed to persist diagnosis:', err);
    return undefined;
  }

  // 2. 创建 Evidence 记录并关联到诊断
  try {
    const now = new Date().toISOString();
    let evidenceIdx = 0;

    for (const syndrome of diagnosis.syndromes) {
      const abilities = getAbilitiesForSyndrome(syndrome.id);

      for (const evText of syndrome.evidence) {
        const evidenceId = `EVD-${Date.now().toString(36)}-${evidenceIdx++}`;
        const record = {
          evidenceId,
          type: 'text' as const,
          level: 1 as const,
          novelId: diagnosis.sessionId,
          contentJson: JSON.stringify({ text: evText }),
          relatedDisease: syndrome.id,
          relatedAbility: abilities[0] ?? '',
          extractedBy: 'diagnosis-parser',
          createdAt: now,
        };
        deps.evidenceService.save(record);
        deps.evidenceService.linkToDiagnosis(
          diagnosisId,
          evidenceId,
          evidenceIdx === 1 ? 'primary' : 'supporting',
        );
      }
    }
  } catch (err) {
    console.error('[DiagnosisProcessor] Failed to create evidence:', err);
  }

  // 3. 合并到 TeachingState
  try {
    deps.diagnosisMerger.merge(diagnosis);
  } catch (err) {
    console.error('[DiagnosisProcessor] Failed to merge diagnosis:', err);
  }

  return { diagnosisId, diagnosis };
}
