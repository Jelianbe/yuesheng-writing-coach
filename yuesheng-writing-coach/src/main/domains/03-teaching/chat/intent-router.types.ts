/**
 * Intent Router 类型定义
 *
 * 定义 5 种用户意图及其路由结果类型
 *
 * @see intent-router-v1.md 设计文档
 */

/** 用户意图类型 */
export type IntentType = 'diagnose' | 'learn' | 'train' | 'review' | 'general_chat';

/** 路由结果 */
export interface RouteResult {
  intent: IntentType;
  /** 置信度 (0-1)，keyword 命中为 1.0，LLM 分类为模型返回的置信度 */
  confidence: number;
  /** 分类来源 */
  source: 'keyword' | 'llm';
}

/** 关键词规则映射 */
export interface KeywordRule {
  keywords: string[];
  intent: IntentType;
}

/** LLM 分类响应格式 */
export interface LLMClassification {
  intent: IntentType;
  confidence: number;
}
