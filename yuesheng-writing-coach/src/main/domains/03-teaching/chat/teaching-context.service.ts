/**
 * 教学上下文服务
 *
 * 职责：准备教学上下文，包括诊断历史格式化、Codex 条目构建、最终 Prompt 组装
 * 从 chat-orchestrator.service.ts 提取，减少主文件职责
 *
 * DI 注册名：'teachingContextService'
 */

import type { DiagnosisAnalysis, DiagnosisEntry, AttitudeLevel } from '../../../../shared/types/index';
import type { CodexEntry } from '../../03-teaching/prompt/codex.service';
import type { IDiagnosisDomain } from '../../01-diagnosis';
import type { ITeachingDomain } from '../../03-teaching';
import type { IStudentDomain } from '../../02-prescription/student';
import type { IPromptDomain } from '../../03-teaching/prompt';

export interface TeachingContext {
  finalPrompt: string;
  isReflectionGate: boolean;
}

export class TeachingContextService {
  constructor(
    private diagnosisDomain: IDiagnosisDomain,
    private promptDomain: IPromptDomain,
    private studentDomain: IStudentDomain,
    private teachingDomain: ITeachingDomain,
  ) {}

  /**
   * 准备教学上下文
   * 1. 加载诊断历史并格式化
   * 2. 加载系统提示词
   * 3. 检测是否需要触发反思门控
   * 4. 组装最终 Prompt
   */
  prepare(
    diagnosisAnalysis: DiagnosisAnalysis | null,
    activeSessionId: string,
    attitude: AttitudeLevel,
    studentContext?: string,
  ): TeachingContext {
    const diagnosisHistory = this.formatDiagnosisHistory(
      this.diagnosisDomain.getRecentBySession(activeSessionId, 3),
    );

    const effectiveStudentContext = this.resolveStudentContext(studentContext);

    const systemPrompt = this.loadSystemPrompt(
      attitude,
      diagnosisAnalysis,
      diagnosisHistory,
      effectiveStudentContext,
      activeSessionId,
    );

    const { isReflectionGate, reflectionInstruction } = this.evaluateReflectionGate(
      diagnosisAnalysis,
      attitude,
    );

    const strategyInstruction = this.teachingDomain.buildStrategyInstruction(
      diagnosisAnalysis,
      attitude,
    );

    const extraParts = [reflectionInstruction, strategyInstruction].filter(Boolean);
    const finalPrompt = extraParts.length > 0
      ? `${systemPrompt}\n\n${extraParts.join('\n\n')}`
      : systemPrompt;

    return { finalPrompt, isReflectionGate };
  }

  /**
   * 构建 Codex 条目
   */
  buildCodexEntries(
    diagnosisHistory: string,
    studentContext?: string,
  ): CodexEntry[] {
    const entries: CodexEntry[] = [];

    if (diagnosisHistory && !diagnosisHistory.includes('暂无历史诊断记录')) {
      entries.push({
        id: 'diagnosis-latest',
        type: 'diagnosis_history',
        content: diagnosisHistory,
        priority: 1,
        label: '诊断历史（记忆胶囊）',
        format: 'structured',
      });
    }

    if (studentContext) {
      entries.push({
        id: 'student-profile',
        type: 'student_profile',
        content: studentContext,
        priority: 3,
        label: '学生画像',
        format: 'compact',
      });
    }

    return entries;
  }

  // ─── 私有方法 ───

  private formatDiagnosisHistory(diagnoses: DiagnosisEntry[]): string {
    return this.promptDomain.buildCapsule({ diagnoses, recentCount: 3 });
  }

  private resolveStudentContext(studentContext?: string): string | undefined {
    const effectiveStudentContext = this.studentDomain.toPromptText();
    if (!effectiveStudentContext && studentContext) {
      return studentContext;
    }
    return effectiveStudentContext || undefined;
  }

  private loadSystemPrompt(
    attitude: AttitudeLevel,
    diagnosisAnalysis: DiagnosisAnalysis | null,
    diagnosisHistory: string,
    studentContext?: string,
    activeSessionId?: string,
  ): string {
    return this.promptDomain.loadSystemPrompt(
      attitude,
      diagnosisAnalysis,
      diagnosisHistory,
      studentContext,
      activeSessionId ?? '',
      undefined,
      this.buildCodexEntries(diagnosisHistory, studentContext),
      { hasSession: true, hasDiagnosis: !!diagnosisAnalysis },
    ) ?? '你是一个专业的写作教练月笙，帮助用户提升写作水平。';
  }

  private evaluateReflectionGate(
    diagnosisAnalysis: DiagnosisAnalysis | null,
    attitude: AttitudeLevel,
  ): { isReflectionGate: boolean; reflectionInstruction: string } {
    if (!diagnosisAnalysis) {
      return { isReflectionGate: false, reflectionInstruction: '' };
    }

    const gateResult = this.teachingDomain.shouldTriggerReflection(diagnosisAnalysis);
    if (gateResult.shouldReflect && gateResult.question) {
      return {
        isReflectionGate: true,
        reflectionInstruction: this.teachingDomain.buildReflectionPrompt(gateResult.question, attitude),
      };
    }

    return { isReflectionGate: false, reflectionInstruction: '' };
  }
}
