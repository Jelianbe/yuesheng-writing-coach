/**
 * 本地降级响应
 *
 * 当 LLM API 不可用时，返回本地友好的兜底回复，避免前端空白或崩溃。
 */

import type { RewriteEvalResult } from '../../../api-proxy';

/**
 * 获取本地降级响应
 *
 * @param type - 响应类型：'eval' 返回评估降级，'stream' 返回文本降级
 * @returns 降级响应数据
 */
export function getFallbackResponse(type: 'eval' | 'stream'): RewriteEvalResult | string {
  if (type === 'eval') {
    return {
      improvement: '略有改善' as const,
      analysis: 'AI 评估暂时不可用，请稍后重试或人工判断修改效果。',
      suggestion: '建议对比原文通读一遍，确认修改是否自然。',
    };
  }
  return 'AI 暂时不可用，请稍后重试。';
}
