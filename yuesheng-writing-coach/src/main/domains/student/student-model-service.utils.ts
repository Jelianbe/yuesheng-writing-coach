/**
 * 学生模型服务 — 纯函数工具
 *
 * 包含可独立测试的计算逻辑，无 DB / 服务依赖。
 */

import {
  ANALYTICAL_KEYWORDS,
  EMOTIONAL_KEYWORDS,
  RECENCY_WINDOW,
  RECENCY_WEIGHT,
  HISTORY_WEIGHT,
  TIER_1_WEIGHT,
  TIER_3_WEIGHT,
  ANALYTICAL_THRESHOLD,
  EMOTIONAL_THRESHOLD,
  MIN_MESSAGES_FOR_STYLE,
  MIN_STYLE_CONFIDENCE_SCALE,
} from './student-model-service.types';
import type { CognitiveStyle } from './student-model-service.types';

/**
 * 跨会话一致性检测
 *
 * 按 session 分组计算每个会话的主导风格，
 * 如果所有 session 风格一致则返回加分。
 */
export function computeCrossSessionConsistency(
  rows: { content: string; session_id: string | null }[],
): number {
  const sessionStyles: Array<'analytical' | 'emotional'>[] = [];
  let currentSession: { analytical: number; emotional: number } | null = null;
  let currentSessionId: string | null = null;

  for (const row of rows) {
    if (!row.session_id) continue;
    if (row.session_id !== currentSessionId) {
      if (currentSession) {
        sessionStyles.push(
          currentSession.analytical > currentSession.emotional
            ? ['analytical']
            : ['emotional'],
        );
      }
      currentSession = { analytical: 0, emotional: 0 };
      currentSessionId = row.session_id;
    }
    if (currentSession) {
      for (const group of ANALYTICAL_KEYWORDS) {
        for (const kw of group.words) {
          if (row.content.includes(kw)) currentSession.analytical++;
        }
      }
      for (const group of EMOTIONAL_KEYWORDS) {
        for (const kw of group.words) {
          if (row.content.includes(kw)) currentSession.emotional++;
        }
      }
    }
  }
  // 最后一个 session
  if (currentSession) {
    sessionStyles.push(
      currentSession.analytical > currentSession.emotional
        ? ['analytical']
        : ['emotional'],
    );
  }

  // 检查所有 session 风格一致
  const uniqueStyles = new Set(sessionStyles.flat());
  if (uniqueStyles.size === 1 && uniqueStyles.has('analytical')) {
    return 0.1;
  }
  if (uniqueStyles.size === 1 && uniqueStyles.has('emotional')) {
    return 0.1;
  }
  return 0;
}

/**
 * 从消息列表计算认知风格（纯函数，无 DB 依赖）
 *
 * @param messages - 用户消息文本数组（按时间正序）
 * @param consistencyBonus - 跨会话一致性加分（由调用方传入）
 */
export function computeCognitiveStyleFromMessages(
  messages: string[],
  consistencyBonus: number = 0,
): { style: CognitiveStyle; confidence: number } {
  const msgCount = messages.length;

  // 0 条 → 数据不足
  if (msgCount === 0) {
    return { style: 'mixed', confidence: 0 };
  }

  // === 关键词统计（分层加权 + 时效加权） ===

  let analyticalScore = 0;
  let emotionalScore = 0;
  let totalMatchCount = 0;

  for (let i = 0; i < msgCount; i++) {
    const content = messages[i];
    // 时效权重：最近 RECENCY_WINDOW 条 ×1.5，其余 ×0.5
    const timeWeight = i >= msgCount - RECENCY_WINDOW ? RECENCY_WEIGHT : HISTORY_WEIGHT;

    for (const group of ANALYTICAL_KEYWORDS) {
      const tierWeight = group.tier === 1 ? TIER_1_WEIGHT : group.tier === 3 ? TIER_3_WEIGHT : 1;
      for (const kw of group.words) {
        if (content.includes(kw)) {
          analyticalScore += tierWeight * timeWeight;
          totalMatchCount++;
        }
      }
    }

    for (const group of EMOTIONAL_KEYWORDS) {
      const tierWeight = group.tier === 1 ? TIER_1_WEIGHT : group.tier === 3 ? TIER_3_WEIGHT : 1;
      for (const kw of group.words) {
        if (content.includes(kw)) {
          emotionalScore += tierWeight * timeWeight;
          totalMatchCount++;
        }
      }
    }
  }

  // 无匹配关键词 → mixed
  if (totalMatchCount === 0) {
    return { style: 'mixed', confidence: 0 };
  }

  // === 风格判定 ===

  const totalScore = analyticalScore + emotionalScore;
  const analyticalRatio = analyticalScore / totalScore;

  let style: CognitiveStyle;
  let baseConfidence: number;

  if (analyticalRatio >= ANALYTICAL_THRESHOLD) {
    style = 'analytical';
    baseConfidence = analyticalRatio;
  } else if (analyticalRatio <= EMOTIONAL_THRESHOLD) {
    style = 'emotional';
    baseConfidence = 1 - analyticalRatio;
  } else {
    style = 'mixed';
    baseConfidence = 0.5;
  }

  // === 置信度精算 ===

  // 消息数调整：消息越多越可信，上限 1.0
  const dataMultiplier = Math.min(1, msgCount / 10);
  // 入场诊断缩放：消息不足时降低置信度
  const entryScale = msgCount < MIN_MESSAGES_FOR_STYLE
    ? MIN_STYLE_CONFIDENCE_SCALE
    : Math.min(1, msgCount / 5);

  const rawConfidence = baseConfidence * dataMultiplier + consistencyBonus;
  const finalConfidence = Math.min(1, rawConfidence * entryScale);

  return { style, confidence: Math.round(finalConfidence * 100) / 100 };
}
