/**
 * 测试数据工厂
 *
 * 用途：从真实枚举类型生成测试数据，避免测试中硬编码字符串字面量
 * 来源：R-014 配置外置规范 - 防止测试数据与技术实现产生隐式映射绑定
 * 更新日期：2026-06-01
 */

import { SyndromeId, ActionId } from '../../../shared/constants';
import {
  SeverityLevel,
  SyndromeResult,
  DiagnosisEntry,
} from '../../../renderer/shared/types';

/** 所有有效病症 ID 列表（从枚举动态生成） */
export const ALL_SYNDROME_IDS: SyndromeId[] = Object.values(SyndromeId);

/** 所有有效动作 ID 列表（从枚举动态生成） */
export const ALL_ACTION_IDS: ActionId[] = Object.values(ActionId);

/** 所有有效严重度等级 */
export const ALL_SEVERITIES: SeverityLevel[] = ['L1', 'L2', 'L3'];

/** 病症 ID → 中文名称映射（仅用于测试可读性，非业务逻辑） */
const SYNDROME_NAMES: Record<string, string> = {
  [SyndromeId.WorldviewBloat]: '世界观膨胀',
  [SyndromeId.CharacterTool]: '人物工具化',
  [SyndromeId.EmotionLabeling]: '情绪标签化',
  [SyndromeId.InfoDumping]: '信息倾泻',
  [SyndromeId.PerspectiveDrift]: '视角漂移',
  [SyndromeId.PacingStagnation]: '节奏凝滞',
  [SyndromeId.ReadingStructureSingle]: '阅读结构单一',
  [SyndromeId.MotivationDeficit]: '角色动机缺失',
  [SyndromeId.OCPlanarization]: 'OC平面化',
};

/** 动作 ID → 动作名称映射（仅用于测试可读性） */
const ACTION_NAMES: Record<string, string> = {
  [ActionId.NarrowScope]: '缩小切入点',
  [ActionId.ReturnToProtagonist]: '回到主角',
  [ActionId.FiveQuestions]: '五问法',
  [ActionId.GroundInReality]: '现实锚点',
  [ActionId.StageSplit]: '阶段拆分',
  [ActionId.ContrastShow]: '对比展示',
  [ActionId.FlipPerspective]: '翻转拆解',
  [ActionId.ReadingAssignment]: '阅读作业',
  [ActionId.ConfidenceConfirm]: '信心确认',
  [ActionId.BoundaryCalibration]: '边界校准',
  [ActionId.CrossContextTransfer]: '跨语境迁移',
  [ActionId.IntentCalibration]: '意图校准',
};

/** 随机选取数组中的一个元素 */
function pick<T>(arr: T[]): T {
  return arr[Math.floor(Math.random() * arr.length)];
}

/** 构建单个病症结果 */
export function buildSyndromeResult(overrides?: Partial<SyndromeResult>): SyndromeResult {
  const id = overrides?.id ?? pick(ALL_SYNDROME_IDS);
  return {
    id,
    name: SYNDROME_NAMES[id] ?? '未知病症',
    severity: overrides?.severity ?? pick(ALL_SEVERITIES),
    evidence: overrides?.evidence ?? [],
    score: overrides?.score ?? undefined,
    suggestedActions: overrides?.suggestedActions ?? [],
  };
}

/** 构建诊断条目 */
export function buildDiagnosisEntry(overrides?: Partial<DiagnosisEntry>): DiagnosisEntry {
  return {
    sessionId: 'test-session-001',
    messageId: 'test-msg-001',
    syndromes: [],
    suggestedActions: [],
    confidence: 0.85,
    timestamp: new Date().toISOString(),
    ...overrides,
  };
}

/** 构建包含单个病症的 AI 回复字符串（模拟 AI 输出） */
export function buildAIResponseWithDiagnosis(
  text: string,
  syndromes: Array<{
    id: SyndromeId;
    severity?: SeverityLevel;
    evidence?: string[];
    score?: number;
    suggestedActions?: ActionId[];
  }>,
  actions: ActionId[],
  confidence?: number,
): string {
  const syndromeJson = syndromes.map((s) => ({
    id: s.id,
    name: SYNDROME_NAMES[s.id] ?? '未知',
    severity: s.severity ?? 'L2',
    evidence: s.evidence ?? [],
    score: s.score,
    suggestedActions: s.suggestedActions ?? [],
  }));

  const diag = {
    syndromes: syndromeJson,
    actions,
    confidence: confidence ?? 0.85,
  };

  return `${text}\n\n---DIAGNOSIS_START---\n${JSON.stringify(diag, null, 2)}\n---DIAGNOSIS_END---`;
}

/** 构建纯文本 AI 回复（不含诊断表） */
export function buildPlainAIResponse(text: string): string {
  return text;
}
