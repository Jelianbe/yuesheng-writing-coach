// 诊断表解析器
// 负责：解析 AI 回复中的诊断表 JSON
// 设计原则：
//   1. 容错优先：AI 未输出或格式错误时降级处理
//   2. 安全性：不信任 AI 输出，验证字段类型
//   3. 可调试：详细日志记录解析过程

import { SyndromeId, ActionId } from '../../../shared/constants';
import { DiagnosisEntry, SyndromeResult, SeverityLevel } from '../../../shared/types/index';

/** 诊断表标记 */
const DIAGNOSIS_START = '---DIAGNOSIS_START---';
const DIAGNOSIS_END = '---DIAGNOSIS_END---';

/**
 * validSeverities
 *
 * 用途：定义允许的严重度等级，用于过滤 AI 输出的非法值域
 * 来源：SeverityLevel 类型定义（shared/types.ts）
 *    L1 = 轻度问题（轻微提示/建议性质）
 *    L2 = 中度问题（需要关注和针对性训练）
 *    L3 = 重度问题（核心瓶颈，需优先解决）
 * 边界：
 *   - 应该往里加：教学体系中的标准严重度等级
 *   - 不应该往里加：AI 随意输出的非标准等级（如 L4, L5, high, low）
 * 上限：3 级，教学体系固定分级，不应扩展
 * 更新日期：2026-06-01
 * 维护者：月笙项目规则 R-014
 */
const VALID_SEVERITIES: SeverityLevel[] = ['L1', 'L2', 'L3'];

/**
 * 解析 AI 回复中的诊断表
 * 
 * AI 回复格式：
 * 你的问题在于...
 * 
 * ---DIAGNOSIS_START---
 * {
 *   "syndromes": [...],
 *   "actions": ["A001"],
 *   "confidence": 0.85
 * }
 * ---DIAGNOSIS_END---
 * 
 * @param fullResponse - AI 完整回复（含诊断表）
 * @param sessionId - 会话 ID
 * @param messageId - 消息 ID
 * @returns 纯净回复 + 诊断表对象
 */
export function parseDiagnosisFromAIResponse(
  fullResponse: string,
  sessionId: string,
  messageId: string,
): { cleanResponse: string; diagnosis: DiagnosisEntry | null } {
  // 查找诊断表标记
  const startIndex = fullResponse.indexOf(DIAGNOSIS_START);
  const endIndex = fullResponse.indexOf(DIAGNOSIS_END);

  // 未找到完整标记，返回原始回复
  if (startIndex === -1 || endIndex === -1) {
    console.warn('[DiagnosisParser] No diagnosis markers found, returning original response');
    return { cleanResponse: fullResponse, diagnosis: null };
  }

  // 截取 JSON 部分
  const jsonStr = fullResponse.substring(
    startIndex + DIAGNOSIS_START.length,
    endIndex
  ).trim();

  // 移除诊断表标记，得到纯净回复
  const cleanResponse = fullResponse
    .substring(0, startIndex)
    .concat(fullResponse.substring(endIndex + DIAGNOSIS_END.length))
    .trim();

  try {
    const parsed = JSON.parse(jsonStr);
    const diagnosis = validateAndBuildDiagnosis(parsed, sessionId, messageId);
    return { cleanResponse, diagnosis };
  } catch (error) {
    console.warn('[DiagnosisParser] Failed to parse diagnosis JSON:', error);
    return { cleanResponse, diagnosis: null };
  }
}

/**
 * 验证并构建诊断对象
 * 不信任 AI 输出，验证字段类型和值域
 */
function validateAndBuildDiagnosis(
  parsed: unknown,
  sessionId: string,
  messageId: string,
): DiagnosisEntry | null {
  if (!parsed || typeof parsed !== 'object') {
    console.warn('[DiagnosisParser] Invalid diagnosis format: not an object');
    return null;
  }

  const obj = parsed as Record<string, unknown>;

  // 验证 syndromes 数组
  const syndromes = validateSyndromes(obj.syndromes);
  
  // 验证 actions 数组
  const actions = validateActions(obj.actions);

  // 验证 confidence
  const confidence = typeof obj.confidence === 'number'
    ? Math.max(0, Math.min(1, obj.confidence))
    : 0;

  return {
    sessionId,
    messageId,
    syndromes,
    suggestedActions: actions,
    confidence,
    timestamp: new Date().toISOString(),
    nextFocus: validateNextFocus(obj.nextFocus),
    beatCheck: validateBeatCheck(obj.beatCheck),
  };
}

/**
 * 验证 beatCheck（SF-004: 节拍完整性检测）
 * 接受 Record<string, boolean>，只保留布尔值字段
 */
function validateBeatCheck(value: unknown): Record<string, boolean> | undefined {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return undefined;
  const obj = value as Record<string, unknown>;
  const result: Record<string, boolean> = {};
  let hasValid = false;
  for (const [key, val] of Object.entries(obj)) {
    if (typeof val === 'boolean') {
      result[key] = val;
      hasValid = true;
    }
  }
  return hasValid ? result : undefined;
}

/**
 * 验证病症数组
 */
function validateSyndromes(value: unknown): SyndromeResult[] {
  if (!Array.isArray(value)) return [];

  const validSyndromes: SyndromeResult[] = [];
  const validIds = new Set<string>(Object.values(SyndromeId));
  const validSeverities: SeverityLevel[] = VALID_SEVERITIES;

  for (const item of value) {
    if (!item || typeof item !== 'object') continue;
    const s = item as Record<string, unknown>;

    // 提取 syndrome ID（可能含 variant，如 "P001::setting_overload"）
    let rawId = '';
    let variant: string | undefined;
    if (typeof s.id === 'string') {
      const sepIndex = s.id.indexOf('::');
      if (sepIndex !== -1) {
        rawId = s.id.substring(0, sepIndex);
        variant = s.id.substring(sepIndex + 2);
      } else {
        rawId = s.id;
      }
    }

    // 验证 id
    if (!rawId || !validIds.has(rawId)) continue;
    // P008 已合并到 P004，视为非法 ID，跳过
    if (rawId === 'P008') continue;

    // 验证 severity
    if (!s.severity || !validSeverities.includes(s.severity as SeverityLevel)) continue;

    validSyndromes.push({
      id: rawId as SyndromeId,
      variant,
      name: typeof s.name === 'string' ? s.name : '',
      severity: s.severity as SeverityLevel,
      evidence: Array.isArray(s.evidence) ? s.evidence.filter((e): e is string => typeof e === 'string') : [],
      score: typeof s.score === 'number' ? s.score : undefined,
      suggestedActions: validateActions(s.suggestedActions),
    });
  }

  return validSyndromes;
}

/**
 * 验证动作数组
 */
function validateActions(value: unknown): ActionId[] {
  if (!Array.isArray(value)) return [];

  const validActions: ActionId[] = [];
  const validIds = new Set<string>(Object.values(ActionId));

  for (const item of value) {
    if (typeof item === 'string' && validIds.has(item)) {
      validActions.push(item as ActionId);
    }
  }

  return validActions;
}

/**
 * 验证 nextFocus
 */
function validateNextFocus(value: unknown): SyndromeId | undefined {
  if (typeof value !== 'string') return undefined;
  const validIds = new Set<string>(Object.values(SyndromeId));
  return validIds.has(value) ? value as SyndromeId : undefined;
}
