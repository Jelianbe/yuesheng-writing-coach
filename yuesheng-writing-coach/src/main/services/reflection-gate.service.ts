/**
 * 反思门控服务
 * 负责：判定是否触发反思门控 + 生成反思性问题
 *
 * 设计依据：challenge-unlock-reflection_V1.0.md
 * 触发时机：诊断后发现 L2+ 症候时
 * 目标：在"诊断"和"给出建议"之间插入反思关卡，让用户先思考再接受建议
 */

import type { DiagnosisAnalysis, AttitudeLevel } from '../../renderer/shared/types';
import type { SyndromeId } from '../../shared/constants';
import { SYNDROME_META } from '../../shared/mappings';
import { severityToNumber } from '../../shared/severity-utils';

/** 反思问题结果 */
export interface ReflectionQuestion {
  /** 问题文本 */
  question: string;
  /** 触发该反思的症候 ID */
  syndromeId: SyndromeId;
  /** 症候名称 */
  syndromeName: string;
}

/** 反思门控判定结果 */
export interface ReflectionGateResult {
  /** 是否触发反思 */
  shouldReflect: boolean;
  /** 反思问题（如果触发） */
  question?: ReflectionQuestion;
}

/** 症候对应的反思问题模板 */
const REFLECTION_TEMPLATES: Partial<Record<SyndromeId, string>> = {
  P001: '你的开篇设定很宏大，但如果让读者先看到一个具体的场景或角色，再慢慢展开世界观，你觉得效果会有什么不同？',
  P002: '这个配角有自己的立场和欲望吗？如果让他做一件完全不符合"工具人"身份的事——比如反对主角——故事会怎样变化？',
  P003: '你写了角色的情绪（比如"他很紧张"）。如果删掉这个词，只用动作、神态或环境来让读者"感受到"紧张，你会怎么写？',
  P004: '这段说明性文字能不能删掉，只用一个角色的动作或对话来暗示同样的信息？读者自己发现的信息，比被告知的信息更有价值。',
  P005: '你用了全知视角（"大家都很紧张"）。如果锁定到主角一个人的眼睛和耳朵，他看不到/听不到的全部删掉，这段文字会怎样？',
  P006: '你的开篇还没有发生任何推动故事的事。如果让主角在前三段内必须做一个选择——不管多小——你会放什么选择？',
  P009: '这个角色为什么做这个决定？他内心真正的恐惧或欲望是什么？不是剧情需要他做什么，而是他自己想要什么？',
  P010: '你的角色从头到尾性格没有变化。如果给他一个经历重大事件后性格改变的转折点——他从A变成了B——那会是什么？',
};

/**
 * 反思门控服务
 */
export class ReflectionGateService {
  /**
   * 判定是否应触发反思门控
   *
   * 规则：
   * - 有症候发现时检查
   * - 只对 L2+ 症候触发（忽略纯信息型 L1）
   * - 返回最高优先级的症候对应的反思问题
   */
  shouldTriggerReflection(diagnosis: DiagnosisAnalysis | null): ReflectionGateResult {
    if (!diagnosis || diagnosis.syndromeRef.length === 0) {
      return { shouldReflect: false };
    }

    // 过滤 L2+ 症候
    const significantSyndromes = diagnosis.syndromeRef.filter((ref) => {
      const meta = SYNDROME_META[ref as SyndromeId];
      if (!meta) return false;
      return severityToNumber(meta.severity) >= severityToNumber('L2');
    });

    if (significantSyndromes.length === 0) {
      return { shouldReflect: false };
    }

    // 取最严重的症候（第一个）生成反思问题
    const topSyndrome = significantSyndromes[0];
    const meta = SYNDROME_META[topSyndrome as SyndromeId];
    if (!meta) {
      return { shouldReflect: false };
    }

    const template = REFLECTION_TEMPLATES[topSyndrome as SyndromeId];
    if (!template) {
      // 无模板时仍然触发，使用通用反思问题
      return {
        shouldReflect: true,
        question: {
          question: `你作品中"${meta.name}"这个问题，你自己觉得原因是什么？如果换一种写法，你会怎么调整？`,
          syndromeId: topSyndrome as SyndromeId,
          syndromeName: meta.name,
        },
      };
    }

    return {
      shouldReflect: true,
      question: {
        question: template,
        syndromeId: topSyndrome as SyndromeId,
        syndromeName: meta.name,
      },
    };
  }

  /**
   * 根据态度档位生成反思问题的语气调整指令
   *
   * @param attitude - 当前教学态度档位
   * @param question - 原始反思问题
   * @returns 带语气引导的反思问题
   */
  adjustReflectionTone(attitude: AttitudeLevel, question: string): string {
    switch (attitude) {
      case 'doubao':
        return `别急，我们一起想想看：${question}\n\n不着急，慢慢想就好～`;

      case 'direct':
        return `直说：${question}\n\n想清楚再回复我。`;

      case 'yuesheng':
      default:
        return `想想看：${question}`;
    }
  }

  /**
   * 构建完整的反思性 System Prompt 段落
   * 注入到 AI 对话中，让 AI 输出反思性问题
   *
   * @param question - 反思问题内容
   * @param attitude - 当前教学态度档位
   * @returns 反思门控的 Prompt 段落
   */
  buildReflectionPrompt(question: ReflectionQuestion, attitude: AttitudeLevel): string {
    const toneAdjusted = this.adjustReflectionTone(attitude, question.question);

    return `---
## 反思门控（Reflection Gate）

你已识别到用户的"${question.syndromeName}"问题。

在给出具体建议前，请先向用户提出以下反思性问题，等待用户回答后再继续。

**反思问题**：${toneAdjusted}

**要求**：
1. 不要暗示答案，让用户自己思考
2. 如果用户回答后有明显偏差，再结合回答给出具体建议
3. 如果用户回答得很好，先肯定用户的洞察，再补充进阶建议
4. 一次只说一个问题，不要一次性输出太多内容`;
  }
}
