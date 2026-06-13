/**
 * BehaviorDerivationService — F-03 角色行为推导服务
 *
 * 根据用户对"角色三问"的回答，调用 LLM 推演合理行为预期。
 * 依赖：behavior-derivation-prompt-v1.md, ApiProxy
 */

import { ApiProxy } from '../../api-proxy';
import { ConfigService } from '../../shared/services/config.service';
import * as path from 'path';
import * as fs from 'fs';

/** 推导输入 */
export interface DerivationInput {
  characterName: string;
  sceneDescription: string;
  question1: string;
  question2: string;
  question3: string;
}

/** 推导输出 */
export interface DerivationResult {
  derivedBehavior: string;
  analysis: string;
  consistencyCheck: string;
}

/** prompt 文件缓存 */
let cachedPrompt: string | null = null;

/** 回退 prompt */
const FALLBACK_PROMPT =
  '你是一位角色分析顾问。根据角色背景和三问回答，推演合理行为。' +
  '只输出 JSON: { "derivedBehavior": "行为描述", "analysis": "解释", "consistencyCheck": "自省问题" }';

function loadDerivationPrompt(): string {
  if (cachedPrompt) return cachedPrompt;
  const promptPath = path.join(__dirname, '../../resources/prompts/behavior-derivation-prompt-v1.md');
  try {
    cachedPrompt = fs.readFileSync(promptPath, 'utf-8');
  } catch {
    cachedPrompt = FALLBACK_PROMPT;
  }
  return cachedPrompt;
}

/**
 * 推导角色行为预期
 *
 * @param input - 三问 + 场景描述
 * @param configService - 配置服务
 * @returns 行为推导结果
 */
export async function deriveBehavior(
  input: DerivationInput,
  configService: ConfigService,
): Promise<DerivationResult> {
  const config = configService.getConfig();
  const proxy = new ApiProxy(config);

  const systemPrompt = loadDerivationPrompt();

  const userMessage = [
    '## 角色名',
    input.characterName,
    '',
    '## 场景描述',
    input.sceneDescription,
    '',
    '## 三问回答',
    `1. 他的过往经历让他怎么看待这件事？`,
    input.question1,
    '',
    `2. 他当前的利益诉求是什么？`,
    input.question2,
    '',
    `3. 他的性格底色驱使他怎么做？`,
    input.question3,
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
    throw new Error('角色推导服务返回格式异常');
  }

  const parsed = JSON.parse(jsonMatch[0]);

  return {
    derivedBehavior: parsed.derivedBehavior ?? '',
    analysis: parsed.analysis ?? '',
    consistencyCheck: parsed.consistencyCheck ?? '',
  };
}
