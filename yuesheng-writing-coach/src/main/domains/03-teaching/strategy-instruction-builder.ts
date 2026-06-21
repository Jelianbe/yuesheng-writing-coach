/**
 * 教学策略指令构建器（纯函数）
 *
 * 从 chat.handler.ts 中提取的 buildStrategyInstruction 纯函数。
 * 整合 Router 三层决策输出，构建完整的教学策略指令块。
 * 无副作用、无模块级变量、无外部状态依赖（所有依赖通过参数注入）。
 *
 * DI 注册名：'strategyInstructionBuilder'
 */

import type { AttitudeLevel, DiagnosisAnalysis } from '../../../shared/types/index';
import type { StudentModelService } from '../02-prescription/student/student-model-service';
import type { TeachingStrategyService } from '../02-prescription/strategy/service';
import type { ProblemPrioritizer } from '../02-prescription/problem-prioritizer.service';
import { SYNDROME_META, SYNDROME_NAMES } from '../../../shared/mappings';
import type { SyndromeId } from '../../../shared/constants';

export class StrategyInstructionBuilder {
  constructor(
    private studentModelService: StudentModelService,
    private teachingStrategyService: TeachingStrategyService,
    private problemPrioritizer: ProblemPrioritizer,
  ) {}

  /**
   * 构建教学策略指令
   */
  build(
    diagnosisAnalysis: DiagnosisAnalysis | null,
    attitude: AttitudeLevel,
  ): string | null {
    const proficiency = this.studentModelService.inferProficiency();
    const cognitiveStyle = this.studentModelService.inferCognitiveStyle();

    const strategyInput = {
      proficiency: proficiency.level,
      cognitiveStyle: cognitiveStyle.style,
      topSyndromeCount: diagnosisAnalysis?.syndromeRef.length ?? 0,
      frustrationIndex: 0,
      attitude,
    };

    const decision = this.teachingStrategyService.decide(strategyInput);

    let instruction = '---\n## 教学策略指令\n\n';

    // 1. 症候类型入口指令（R-004~R-006）
    if (decision.entryInstruction) {
      instruction += `${decision.entryInstruction}\n\n`;
    }

    // 2. 教学模式
    const modeInstructions: Record<string, string> = {
      scaffolding: '请使用支架模式：给出具体示范和结构化步骤，让用户模仿',
      guiding: '请使用引导模式：用提问引导用户自己发现答案，不给示范',
      challenging: '请使用挑战模式：给出变形条件，要求用户在约束下创作',
    };
    instruction += `- 教学模式：${modeInstructions[decision.mode] ?? decision.mode}\n`;

    // 3. 语气
    const toneInstructions: Record<string, string> = {
      encouraging: '使用鼓励的语气，多肯定用户的进步',
      direct: '使用直接简洁的语气，直击问题核心',
      logical: '使用逻辑化的语气，以推理和结构化方式表达',
      resonant: '使用共鸣的语气，通过案例和情感连接来表达',
    };
    instruction += `- 语气：${toneInstructions[decision.tone] ?? decision.tone}\n`;

    // 4. 步骤序列
    if (decision.parameters?.stepSequence && decision.parameters.stepSequence.length > 0) {
      instruction += '- 建议步骤：' + decision.parameters.stepSequence.map(s => s.stepName).join(' → ') + '\n';
    }

    // 5. 核心模式推荐
    if (decision.parameters?.corePatterns && decision.parameters.corePatterns.length > 0) {
      instruction += `- 核心技法模式：${decision.parameters.corePatterns.join('、')}\n`;
    }

    // 6. 输出格式
    const formatInstructions: Record<string, string> = {
      'problem→cause→evidence→solution': '按照"问题→原因→证据→解决方案"的结构输出',
      'example→feeling→demonstration': '按照"案例→感受→示范"的结构输出',
    };
    if (decision.format && formatInstructions[decision.format]) {
      instruction += `- 输出格式：${formatInstructions[decision.format]}\n`;
    }

    // 7. 最高优先级问题 + 聚焦症候
    let hasPrioritizedInfo = false;
    if (diagnosisAnalysis && diagnosisAnalysis.syndromeRef.length > 0) {
      const syndromesForPrioritization = diagnosisAnalysis.syndromeRef.map(ref => ({
        id: ref,
        name: SYNDROME_NAMES[ref] ?? ref,
        occurrenceCount: 1,
        severityHistory: [SYNDROME_META[ref as SyndromeId]?.severity ?? 'L1'],
      }));

      const prioritized = this.problemPrioritizer.prioritize(syndromesForPrioritization);
      if (prioritized.length > 0) {
        const top = prioritized[0];
        hasPrioritizedInfo = true;
        instruction += `\n**当前最高优先级问题**：${top.tierLabel} — ${top.syndromeId}（${top.name}）\n`;
        instruction += `行动级别：${top.action === 'must_fix' ? '必须先修复' : top.action === 'priority' ? '优先处理' : '可延后'}\n`;
      }
    }

    // 8. Router 聚焦症候
    if (decision.targetSyndrome) {
      const focus = decision.targetSyndrome;
      if (!hasPrioritizedInfo) {
        instruction += `\n**本次聚焦**：${focus.targetSyndromeName}\n`;
      }
      if (focus.rationale) {
        instruction += `原因：${focus.rationale}\n`;
      }
    }

    instruction += '\n- 核心原则：一次只说一个问题，聚焦当前最高优先级问题。';

    return instruction;
  }
}
