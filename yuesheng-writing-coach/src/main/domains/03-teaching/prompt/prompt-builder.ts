/**
 * Prompt 构建器
 * 负责：根据教学状态构建 System Prompt 注入内容、聚焦方向 Prompt、诊断摘要更新
 *
 * 职责分离：从 teaching-state-machine.ts 提取的 Prompt 层职责
 */

import * as fs from 'fs';
import * as path from 'path';
import { getPhaseName, getSubphaseName } from '../state/teaching-state-machine';
import type { TeachingState } from '../state/teaching-state.types';
import type { FocusArea } from '../../../../shared/types/index';
import type { TeachingMode, ToneType, TeachingStrategyDecision } from '../../02-prescription/strategy/service';
import type { PrioritizedProblem } from '../../02-prescription/problem-prioritizer.service';

/** 策略服务输出选项（可选传入） */
export interface StrategyPromptOptions {
  /** 教学策略决策 */
  strategyDecision?: TeachingStrategyDecision;
  /** 排序后的问题列表 */
  prioritizedProblems?: PrioritizedProblem[];
}

/** 教练话术模板的 TS 视图 */
interface CoachingTemplate {
  id: string;
  name: string;
  description: string;
  triggerConditions: {
    signals: string[];
    applicableLevels: string[];
    applicableSyndromes: string[];
  };
  steps: Array<{
    stepId: string;
    instruction: string;
  }>;
  contraindications?: string[];
  toneProfile?: string;
  challengeSize?: string;
}

/**
 * PromptBuilder 类
 *
 * 封装所有与 Prompt 构建相关的逻辑，供 IPC handler 调用
 */
export class PromptBuilder {
  /**
   * 构建 System Prompt 注入内容
   *
   * 将当前教学状态格式化为 AI 可读的文本
   *
   * @param state - 当前教学状态
   * @param getActionName - 动作 ID 到名称的映射函数
   * @param getActionGoal - 动作 ID 到目标的映射函数
   * @param getSyndromeName - 症候 ID 到名称的映射函数
   * @param options - 可选的策略服务输出（教学模式、优先级问题等）
   * @returns 格式化的 System Prompt 注入文本
   */
  buildSystemPrompt(
    state: TeachingState,
    getActionName: (id: string) => string,
    getActionGoal: (id: string) => string,
    getSyndromeName: (id: string) => string,
    options?: StrategyPromptOptions,
  ): string {
    const phaseName = getPhaseName(state.currentPhase);
    const subphaseName = getSubphaseName(state.currentSubphase);

    const completedActionsDesc = state.completedActions
      .map(id => `- ${id}（${getActionName(id)}）：${getActionGoal(id)}`)
      .join('\n');

    const nextActionsDesc = state.nextSuggestedActions
      .map(id => `- ${id}（${getActionName(id)}）`)
      .join('\n');

    const activeProblemsDesc = state.activeProblems
      .filter(p => p.status === 'active' || p.status === 'improving')
      .map(p => `- ${p.id}（${getSyndromeName(p.id)}，${p.status === 'improving' ? '改善中' : '活跃'}）`)
      .join('\n');

    const focusAreaLines = this.buildFocusAreaPrompt(state.focusArea);

    // 构建策略指令（如果提供了策略决策）
    const strategyLines = this.buildStrategySection(options);

    return [
      '【当前教学进度】',
      `你正在与用户进行【${phaseName}】阶段的教学。`,
      `当前子阶段：${subphaseName}`,
      '',
      '【已完成的教学动作】',
      completedActionsDesc || '暂无',
      '下次如果用户再次出现相同问题，可以提醒但不必重新教学。',
      '',
      '【用户当前问题】',
      activeProblemsDesc || '暂无',
      '',
      '【建议你下一步使用】',
      nextActionsDesc || '根据对话情况判断',
      '',
      ...focusAreaLines,
      ...strategyLines,
      '请根据这个进度，继续你的教练对话。',
      '不要重复已经教过的内容。',
      '聚焦在建议的教学动作上。',
    ].join('\n');
  }

  /**
   * 根据 focusArea 构建 Prompt 注入内容
   *
   * @param focusArea - 聚焦方向
   * @returns Prompt 行数组
   */
  private buildFocusAreaPrompt(focusArea: FocusArea): string[] {
    if (!focusArea || focusArea === 'general') {
      return [];
    }

    const descriptions: Record<string, string> = {
      worldbuilding: `【当前聚焦方向：世界观构建】
用户当前专注于世界观构建。
- 诊断时优先关注世界观相关症候（P001 世界观膨胀、P004 信息硬塞）
- 教学时多引用世界观构建的案例和理论
- 引导用户通过"角色体验"来展现设定，而非直接说明`,
      character: `【当前聚焦方向：角色/OC 设计】
用户当前专注于角色和 OC 设计。
- 诊断时优先关注角色相关症候（P002 角色工具人化、P009 角色动机缺失、P010 OC平面化）
- 教学时多引用角色塑造的案例和理论
- 引导用户从"压力下的选择"来刻画角色，而非标签描述`,
    };

    const desc = descriptions[focusArea];
    return desc ? [desc, ''] : [];
  }

  /**
   * 更新诊断摘要
   *
   * 从 AI 回复中提取关键信息，追加到诊断摘要中
   * 保留最近 N 轮的简洁文本
   *
   * @param currentSummary - 当前诊断摘要
   * @param newContent - 新增内容
   * @param maxRounds - 最大保留轮次，默认 3
   * @returns 更新后的诊断摘要
   */
  updateDiagnosisSummary(
    currentSummary: string,
    newContent: string,
    maxRounds: number = 3,
  ): string {
    const rounds = currentSummary ? currentSummary.split('\n---\n') : [];
    rounds.push(newContent);

    // 保留最近 N 轮
    if (rounds.length > maxRounds) {
      return rounds.slice(-maxRounds).join('\n---\n');
    }

    return rounds.join('\n---\n');
  }

  /**
   * 构建教学策略指令段落
   * 将策略服务层的决策翻译为结构化的 Prompt 指令
   *
   * @param options - 策略服务输出（可选）
   * @returns Prompt 行数组，无策略决策时返回空数组
   */
  private buildStrategySection(options?: StrategyPromptOptions): string[] {
    if (!options?.strategyDecision) {
      return [];
    }

    const { strategyDecision, prioritizedProblems } = options;
    const lines: string[] = [];

    lines.push('---');
    lines.push('【教学策略指令】');
    lines.push('');

    // 1. 症候类型入口指令（R-004~R-006，来自 Router 第二层）
    if (strategyDecision.entryInstruction) {
      lines.push(strategyDecision.entryInstruction);
      lines.push('');
    }

    // 2. 教学模式指令
    const modeInstruction = this.getModeInstruction(strategyDecision.mode);
    if (modeInstruction) {
      lines.push(modeInstruction);
      lines.push('');
    }

    // 3. 语气指令
    const toneInstruction = this.getToneInstruction(strategyDecision.tone);
    if (toneInstruction) {
      lines.push(toneInstruction);
      lines.push('');
    }

    // 4. 步骤序列（来自 Router 第三层 Parameters）
    if (strategyDecision.parameters?.stepSequence) {
      lines.push('建议执行顺序：');
      for (const step of strategyDecision.parameters.stepSequence) {
        lines.push(`- ${step.stepName}（语气：${step.toneProfile}）`);
      }
      lines.push('');
    }

    // 5. 核心模式推荐（来自 Router 第三层 Parameters）
    if (strategyDecision.parameters?.corePatterns && strategyDecision.parameters.corePatterns.length > 0) {
      lines.push(`推荐聚焦技法核心模式：${strategyDecision.parameters.corePatterns.join('、')}`);
      lines.push('');
    }

    // 6. 输出格式指令
    if (strategyDecision.format) {
      const formatInstruction = this.getFormatInstruction(strategyDecision.format);
      if (formatInstruction) {
        lines.push(formatInstruction);
        lines.push('');
      }
    }

    // 7. 最高优先级问题
    if (prioritizedProblems && prioritizedProblems.length > 0) {
      const top = prioritizedProblems[0];
      const actionLabel = top.action === 'must_fix' ? '必须先修复' : top.action === 'priority' ? '优先处理' : '可延后';
      lines.push(`**当前最高优先级问题**：${top.tierLabel} — ${top.syndromeId}（${top.name}）`);
      lines.push(`行动级别：${actionLabel}`);
      lines.push('请在本轮对话中聚焦于此问题，一次只说一个问题。');
      lines.push('');
    }

    // 8. 聚焦症候（来自 Router 第一层 FocusDecision）
    if (strategyDecision.targetSyndrome) {
      const focus = strategyDecision.targetSyndrome;
      lines.push(`**本次聚焦**：${focus.targetSyndromeName}`);
      if (focus.rationale) {
        lines.push(`原因：${focus.rationale}`);
      }
      lines.push('');
    }

    // 9. 匹配的教练话术模板（来自 Router 第三层 ParameterDecision.matchedTemplateId）
    const matchedTemplateId = strategyDecision.parameters?.matchedTemplateId;
    if (matchedTemplateId) {
      try {
        const configPath = path.resolve(process.resourcesPath ?? __dirname, '../../resources/config/coaching-templates.json');
        const raw = fs.readFileSync(configPath, 'utf-8');
        const templates: CoachingTemplate[] = JSON.parse(raw).templates;
        const template = templates.find(t => t.id === matchedTemplateId);
        if (template) {
          lines.push(`**匹配话术模板**：${template.name}`);
          lines.push(`提示：${template.description}`);
          if (template.steps && template.steps.length > 0) {
            lines.push('推荐话术步骤：');
            for (const step of template.steps) {
              lines.push(`- ${step.instruction}`);
            }
          }
          if (template.contraindications && template.contraindications.length > 0) {
            lines.push(`避免：${template.contraindications.join('；')}`);
          }
          lines.push('');
        }
      } catch (e) {
        // 文件不存在或解析失败时不注入模板内容（降级）
        if (process.env.NODE_ENV === 'development') {
          console.warn('[prompt-builder] Failed to load template:', e);
        }
      }
    }

    return lines;
  }

  /** 教学模式指令映射 */
  private getModeInstruction(mode: TeachingMode): string {
    const map: Record<TeachingMode, string> = {
      scaffolding: '请使用支架模式：给出具体示范和结构化步骤，让用户模仿。',
      guiding: '请使用引导模式：用提问引导用户自己发现答案，不给示范。',
      challenging: '请使用挑战模式：给出变形条件，要求用户在约束下创作。',
    };
    return map[mode] ?? '';
  }

  /** 语气指令映射 */
  private getToneInstruction(tone: ToneType): string {
    const map: Record<ToneType, string> = {
      encouraging: '使用鼓励的语气，多肯定用户的进步。',
      direct: '使用直接简洁的语气，直击问题核心。',
      logical: '使用逻辑化的语气，以推理和结构化方式表达。',
      resonant: '使用共鸣的语气，通过案例和情感连接来表达。',
      challenging: '使用犀利的语气，直指问题核心，不要客套。',
    };
    return map[tone] ?? '';
  }

  /** 输出格式指令映射 */
  private getFormatInstruction(
    format: 'problem→cause→evidence→solution' | 'example→feeling→demonstration',
  ): string {
    const map: Record<string, string> = {
      'problem→cause→evidence→solution': '按照"问题→原因→证据→解决方案"的结构输出。',
      'example→feeling→demonstration': '按照"案例→感受→示范"的结构输出。',
    };
    return map[format] ?? '';
  }
}
