/**
 * 诊断结果格式化工具
 * 将 DiagnosisAnalysis 格式化为教学指引文本，用于注入 System Prompt
 */

import type { DiagnosisAnalysis } from '../../../../shared/types/index';
import type { SyndromeId } from '../../../../shared/constants';
import { SYNDROME_NAMES, SYNDROME_META } from '../../../../shared/mappings';

/**
 * 构建诊断增强层
 * 将 DiagnosisAnalysis 格式化为教学指引文本，注入 V3 Prompt 中
 */
export function formatDiagnosisEnhancement(analysis: DiagnosisAnalysis): string {
  const lines: string[] = [];
  lines.push('---');
  lines.push('## 当前诊断结果（本轮触发）');
  lines.push('');

  if (analysis.rootCause) {
    lines.push(`**根因分析**：${analysis.rootCause}`);
    lines.push('');
  }

  if (analysis.intentPhase) {
    lines.push(`**意图阶段**：${analysis.intentPhase}`);
    lines.push('');
  }

  if (analysis.syndromeRef.length > 0) {
    lines.push('**识别到的症候**：');
    for (const ref of analysis.syndromeRef) {
      const name = SYNDROME_NAMES[ref] ?? ref;
      const meta = SYNDROME_META[ref as SyndromeId];
      const severity = meta ? `（${meta.severity}）` : '';
      lines.push(`- ${name}${severity}`);
    }
    lines.push('');
  }

  if (analysis.keyPassages.length > 0) {
    lines.push('**关键段落**：');
    for (const kp of analysis.keyPassages.slice(0, 3)) {
      lines.push(`- ${kp.text}${kp.issue ? ` → ${kp.issue}` : ''}`);
    }
    lines.push('');
  }

  if (analysis.techniquePool.length > 0) {
    lines.push('**建议技法**（按需调用）：');
    for (const t of analysis.techniquePool) {
      lines.push(`- ${t.name}（来源：${t.source}，难度：${t.difficulty}）`);
    }
    lines.push('');
  }

  lines.push('请基于以上诊断结果，在回复中聚焦根因治疗，使用场景快速索引中的对应规则。');

  return lines.join('\n');
}
