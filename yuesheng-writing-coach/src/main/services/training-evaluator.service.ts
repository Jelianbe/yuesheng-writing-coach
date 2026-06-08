/**
 * 训练评估服务（Evaluator Agent）
 *
 * 负责：调用 LLM 评估用户改写稿，返回结构化评分结果
 * 依赖：training-evaluator-prompt-v1.md, ApiProxy
 */

import { ApiProxy } from '../api-proxy';
import { ConfigService } from './config.service';
import * as path from 'path';
import * as fs from 'fs';

/** 评估结果 */
export interface EvaluationResult {
  /** 评分 1-10 */
  score: number;
  /** 文字反馈 */
  feedback: string;
  /** 是否相比原文有改善 */
  improved: boolean;
  /** 下一步建议 */
  nextStep: string;
}

/** 评估输入 */
export interface EvaluationInput {
  challengeDescription: string;
  constraint: string;
  originalQuote: string;
  userDraft: string;
}

/** prompt 文件缓存 */
let cachedPrompt: string | null = null;

/**
 * 加载 evaluator prompt（带缓存）
 */
function loadEvaluatorPrompt(): string {
  if (cachedPrompt) return cachedPrompt;
  const promptPath = path.join(__dirname, '../../resources/prompts/training-evaluator-prompt-v1.md');
  try {
    cachedPrompt = fs.readFileSync(promptPath, 'utf-8');
  } catch {
    cachedPrompt = '你是一个写作教练。评估用户的改写是否达到了训练要求。只输出 JSON: { "score": 1-10, "feedback": "评价", "improved": true/false, "nextStep": "建议" }';
  }
  return cachedPrompt;
}

/**
 * 评估用户改写稿
 *
 * @param input - 评估输入（训练目标、约束、原文、改写稿）
 * @param configService - 配置服务（获取 API 密钥等）
 * @returns 结构化评估结果
 */
export async function evaluateTraining(
  input: EvaluationInput,
  configService: ConfigService,
): Promise<EvaluationResult> {
  const config = configService.getConfig();
  const proxy = new ApiProxy(config);

  const systemPrompt = loadEvaluatorPrompt();

  const userMessage = [
    '## 训练目标',
    input.challengeDescription,
    '',
    '## 约束条件',
    input.constraint,
    '',
    '## 用户原始文本',
    input.originalQuote,
    '',
    '## 用户改写稿',
    input.userDraft,
  ].join('\n');

  const messages = [
    { role: 'system' as const, content: systemPrompt },
    { role: 'user' as const, content: userMessage },
  ];

  let fullResponse = '';
  for await (const chunk of proxy.chatStream(messages)) {
    fullResponse += chunk;
  }

  const jsonMatch = fullResponse.match(/\{[\s\S]*\}/);
  if (!jsonMatch) {
    throw new Error('评估服务返回格式异常');
  }

  const parsed = JSON.parse(jsonMatch[0]);

  return {
    score: clampScore(parsed.score),
    feedback: parsed.feedback ?? '改写稿已收到。',
    improved: parsed.improved === true,
    nextStep: parsed.nextStep ?? '继续练习',
  };
}

/**
 * 将评分限制在 1-10 范围内
 */
function clampScore(score: unknown): number {
  const n = Number(score);
  if (Number.isNaN(n)) return 5;
  return Math.max(1, Math.min(10, Math.round(n)));
}
