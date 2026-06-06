/**
 * 诊断数据 Fixture 生成器
 * 提供各种预定义的诊断测试数据
 */

import type { DiagnosisEntry, SyndromeResult, DiagnosisAnalysis } from '../../renderer/shared/types';

/** 单个症候工厂 */
export function createSyndrome(overrides: Partial<SyndromeResult> = {}): SyndromeResult {
  return {
    id: 'P004',
    name: '信息硬塞',
    severity: 'L2',
    evidence: ['他资质平平，只是一个普通的散修，修为筑基中期。'],
    score: 0.75,
    suggestedActions: [],
    ...overrides,
  };
}

/** 完整诊断条目工厂 */
export function createDiagnosisEntry(overrides: Partial<DiagnosisEntry> = {}): DiagnosisEntry {
  return {
    sessionId: 'test-session-001',
    messageId: 'test-msg-001',
    syndromes: [
      createSyndrome({
        id: 'P004',
        name: '信息硬塞',
        severity: 'L2',
        evidence: ['他资质平平，只是一个普通的散修，修为筑基中期。'],
        score: 0.75,
      }),
      createSyndrome({
        id: 'P002',
        name: '角色工具化',
        severity: 'L3',
        evidence: ['在修真界，散修是最底层的存在，没有资源，没有背景，没有人指导。'],
        score: 0.82,
      }),
    ],
    suggestedActions: [],
    confidence: 0.85,
    timestamp: new Date().toISOString(),
    ...overrides,
  };
}

/** 诊断 Agent 分析结果工厂 */
export function createDiagnosisAnalysis(overrides: Partial<DiagnosisAnalysis> = {}): DiagnosisAnalysis {
  return {
    rootCause: '信息硬塞+角色工具化',
    intentPhase: 2,
    syndromeRef: ['P004', 'P002'],
    techniquePool: [
      { name: '日常行为释放设定', source: '诡秘之主', difficulty: 'beginner' },
      { name: '行动代替情绪', source: '夜的命名术', difficulty: 'beginner' },
    ],
    keyPassages: [
      { text: '他资质平平，只是一个普通的散修，修为筑基中期。', issue: '直接旁白交代设定' },
      { text: '在修真界，散修是最底层的存在...', issue: '角色工具化，旁白解释' },
    ],
    confidence: 0.85,
    ...overrides,
  };
}

/** 修改评估结果工厂 */
export function createRewriteEvaluation(overrides: any = {}) {
  return {
    improvement: '明显改善' as const,
    analysis: '你的修改用动作替代了旁白说明，读者能自己感受到主角的处境。',
    suggestion: '继续——下一步是加一个环境细节，氛围会更完整。',
    ...overrides,
  };
}

/** 教学状态工厂 */
export function createTeachingState(overrides: any = {}) {
  return {
    sessionId: 'test-session-001',
    currentPhase: 'P2_PRACTICE_LOOP',
    currentSubphase: 'S2_IDENTIFY',
    completedActions: [],
    completedTasks: [],
    activeProblems: [{
      id: 'P004',
      name: '信息硬塞',
      severity: 'L2' as const,
      evidence: ['他资质平平'],
      score: 0.75,
      firstDetected: new Date().toISOString(),
      status: 'active' as const,
      suggestedActions: [],
    }],
    nextSuggestedActions: [],
    currentTaskId: null,
    diagnosisSummary: '',
    lastUserConfirmation: null,
    focusArea: null,
    transitionOffered: false,
    updatedAt: new Date().toISOString(),
    ...overrides,
  };
}

/** 会话数据工厂 */
export function createSession(overrides: any = {}) {
  const now = new Date().toISOString();
  return {
    id: `session-${Date.now()}`,
    title: '测试会话',
    createdAt: now,
    updatedAt: now,
    messages: [],
    ...overrides,
  };
}
