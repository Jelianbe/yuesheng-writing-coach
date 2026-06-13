/**
 * Prompt 工程领域入口
 *
 * 对外接口：IPromptDomain — 供 ChatOrchestrator 等外部模块使用
 * 内部实现：PromptLoader, PromptBuilder, CodexService, MemoryCapsuleService
 */

import type { AttitudeLevel, DiagnosisAnalysis } from '../../../renderer/shared/types';
import type { CodexEntry } from './codex.service';

export interface IPromptDomain {
  loadSystemPrompt(
    attitude: AttitudeLevel,
    diagnosisAnalysis: DiagnosisAnalysis | null,
    diagnosisHistory: string,
    studentContext: string | undefined,
    sessionId: string,
    _transitionPrompt?: string,
    _codexEntries?: CodexEntry[],
    _flags?: { hasSession?: boolean; hasDiagnosis?: boolean },
  ): string;
  buildCapsule(params: { diagnoses: unknown[]; recentCount: number }): string;
}

export { PromptLoader } from './prompt-loader';
export { PromptBuilder } from './prompt-builder';
export { CodexService, type CodexEntry } from './codex.service';
export { DynamicContextService } from './dynamic-context.service';
export { MemoryCapsuleService, getMemoryCapsuleService } from './memory-capsule.service';
