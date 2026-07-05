/**
 * Capacitor 训练模块 — Sprint 33
 *
 * 在 Android/Capacitor 端提供训练功能的真实降级替代：
 * - submit: 用 LlmClient 评估训练提交
 * - evaluate: 用 LlmClient 评分
 * - deriveBehavior: 用 LlmClient 分析角色行为
 * - 其余方法（recommend/assign/complete/skip/history/decideReading/catalog/generateFlow）保持 noop
 *
 * 依据: dev-docs/decision-log.md D-082 未做事项 §2
 */

import { LlmClient } from '../../shared/llm/llm-client';
import { loadConfig } from './capacitor-config';

// ============================================================
// 工具函数：获取 LlmClient 实例
// ============================================================

async function getClient(): Promise<{ client: LlmClient; config: { apiKey: string; baseUrl: string; modelName: string } } | null> {
  try {
    const config = await loadConfig();
    if (!config.apiKey) {
      console.warn('[capacitor-training] API Key 未配置');
      return null;
    }
    const client = new LlmClient({
      apiKey: config.apiKey,
      baseUrl: config.baseUrl,
      modelName: config.modelName,
      temperature: config.temperature,
      maxTokens: config.maxTokens,
    });
    return { client, config: { apiKey: config.apiKey, baseUrl: config.baseUrl, modelName: config.modelName } };
  } catch (err) {
    console.error('[capacitor-training] 获取 LlmClient 失败:', err);
    return null;
  }
}

// ============================================================
// 公开 API
// ============================================================

/**
 * 提交训练评估 — 直调 LLM API
 * 评估用户的改写/练习文本，返回改进反馈和是否降级。
 */
export async function capacitorTrainingSubmit(
  params: { sessionId: string; recordId: string; text: string },
): Promise<{ recordId: string } | null> {
  const ctx = await getClient();
  if (!ctx) return null;

  try {
    const prompt = `你是一个写作教练。请评估以下训练提交：

学生改写：「${params.text}」

请从以下维度评分（1-10 分）：
1. 技巧运用：是否恰当运用了目标写作技巧
2. 自然度：改写是否自然流畅
3. 改善程度：相比原文是否有改善

以 JSON 格式返回：
{
  "score": <1-10 的整数>,
  "feedback": "<具体的反馈意见>",
  "passed": true/false
}`;

    const result = await ctx.client.chat([
      { role: 'system', content: '你是一个专业的写作教练助手。' },
      { role: 'user', content: prompt },
    ]);

    const jsonMatch = result.content.match(/\{[\s\S]*"score"[\s\S]*\}/);
    const jsonStr = jsonMatch?.[1] ?? jsonMatch?.[0] ?? result.content;
    const parsed = JSON.parse(jsonStr) as { score: number; feedback: string; passed: boolean };

    // 保存评估结果到 localStorage（供后续 evaluate 查询）
    try {
      const key = `yuesheng_training_eval_${params.sessionId}`;
      localStorage.setItem(key, JSON.stringify({ recordId: params.recordId, ...parsed }));
    } catch { /* 静默 */ }

    return { recordId: params.recordId };
  } catch (err) {
    console.error('[capacitor-training] submit failed:', err);
    return null;
  }
}

/**
 * 训练评分 — 直调 LLM API
 * 对训练提交进行详细评分和反馈。
 */
export async function capacitorTrainingEvaluate(
  params: { sessionId: string; recordId: string; syndromeId: string; text: string; trainingType: string },
): Promise<{ score: number; feedback: string; downgraded: boolean } | null> {
  const ctx = await getClient();
  if (!ctx) return null;

  try {
    const prompt = `你是一个写作教练。请对以下训练作品进行评分：

症候类型：${params.trainingType}
症候 ID：${params.syndromeId}
学生作品：「${params.text}」

请以 JSON 格式返回：
{
  "score": <1-10 的整数>,
  "feedback": "<详细的反馈意见>",
  "downgraded": true/false
}`;

    const result = await ctx.client.chat([
      { role: 'system', content: '你是一个专业的写作教练助手。' },
      { role: 'user', content: prompt },
    ]);

    const jsonMatch = result.content.match(/\{[\s\S]*"score"[\s\S]*\}/);
    const jsonStr = jsonMatch?.[1] ?? jsonMatch?.[0] ?? result.content;
    const parsed = JSON.parse(jsonStr) as { score: number; feedback: string; downgraded: boolean };

    return {
      score: typeof parsed.score === 'number' ? parsed.score : 5,
      feedback: parsed.feedback ?? '评估完成。',
      downgraded: !!parsed.downgraded,
    };
  } catch (err) {
    console.error('[capacitor-training] evaluate failed:', err);
    return null;
  }
}

/**
 * 角色行为推导 — 直调 LLM API
 * 从文本中分析角色行为特征。
 */
export async function capacitorTrainingDeriveBehavior(
  params: { sessionId: string; text: string },
): Promise<{ behaviors: string[] } | null> {
  const ctx = await getClient();
  if (!ctx) return null;

  try {
    const prompt = `你是一个写作教练分析助手。请分析以下文本中的人物行为特征：

文本：「${params.text}」

请列出这段文本中体现的人物行为特征（最多 5 条），以 JSON 数组格式返回：
{
  "behaviors": ["行为特征1", "行为特征2", ...]
}`;

    const result = await ctx.client.chat([
      { role: 'system', content: '你是一个专业的写作分析助手。' },
      { role: 'user', content: prompt },
    ]);

    const jsonMatch = result.content.match(/\{[\s\S]*"behaviors"[\s\S]*\}/);
    const jsonStr = jsonMatch?.[1] ?? jsonMatch?.[0] ?? result.content;
    const parsed = JSON.parse(jsonStr) as { behaviors: string[] };

    return {
      behaviors: Array.isArray(parsed.behaviors) ? parsed.behaviors.slice(0, 5) : [],
    };
  } catch (err) {
    console.error('[capacitor-training] deriveBehavior failed:', err);
    return null;
  }
}
