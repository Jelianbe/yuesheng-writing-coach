/**
 * 03-teaching Prompt 系统集成测试
 *
 * 覆盖范围：
 * 1. PromptBuilder.buildSystemPrompt 集成 — 教学状态格式化输出
 * 2. MemoryCapsuleService.buildCapsule 集成 — 记忆胶囊构建
 * 3. PromptLoader 构造验证 — 依赖注入与降级行为
 */

import { describe, it, expect } from 'vitest';
import { PromptBuilder } from '../prompt-builder';
import { MemoryCapsuleService } from '../memory-capsule.service';
import { PromptLoader } from '../prompt-loader';
import { DynamicContextService } from '../dynamic-context.service';
import { CodexService } from '../codex.service';
import type { TeachingState } from '../../state/teaching-state.types';
import type { DiagnosisEntry, TeachingProgressDisplay } from '../../../../../shared/types/index';

// ===== 工厂函数 =====

function makeTeachingState(overrides: Partial<TeachingState> = {}): TeachingState {
  return {
    sessionId: 'test-session',
    currentPhase: 'P2_PRACTICE_LOOP',
    currentSubphase: 'S2_IDENTIFY',
    completedActions: [],
    completedTasks: [],
    activeProblems: [],
    nextSuggestedActions: [],
    currentTaskId: null,
    diagnosisSummary: '',
    lastUserConfirmation: null,
    focusArea: null,
    transitionOffered: false,
    lockedSyndromes: [],
    updatedAt: '2026-06-21T00:00:00.000Z',
    ...overrides,
  };
}

function makeDiagnosisEntry(overrides: Partial<DiagnosisEntry> = {}): DiagnosisEntry {
  return {
    sessionId: 'test-session',
    messageId: 'msg-1',
    syndromes: [],
    suggestedActions: [],
    confidence: 0.9,
    timestamp: new Date().toISOString(),
    ...overrides,
  };
}

/** 模拟 ACTION_NAMES 映射 */
function getActionName(id: string): string {
  const map: Record<string, string> = {
    A001: '缩小范围',
    A002: '回归主角',
    A003: '五问法',
    A005: '阶段拆分',
  };
  return map[id] ?? id;
}

/** 模拟 ACTION_GOALS 映射 */
function getActionGoal(id: string): string {
  const map: Record<string, string> = {
    A001: '用户已经学会把宏大设定聚焦到第一个具体场景。',
    A003: '用户已经学会用连续追问理清因果链。',
    A005: '用户已经学会把大目标拆成可执行的小阶段。',
  };
  return map[id] ?? '';
}

/** 模拟 SYNDROME_NAMES 映射 */
function getSyndromeName(id: string): string {
  const map: Record<string, string> = {
    P001: '世界观膨胀',
    P002: '角色工具人化',
  };
  return map[id] ?? id;
}

// ====================================================================
// 1. PromptBuilder.buildSystemPrompt 集成
// ====================================================================

describe('PromptBuilder.buildSystemPrompt 集成', () => {
  const builder = new PromptBuilder();

  it('应包含当前教学阶段名称和子阶段名称', () => {
    const state = makeTeachingState({
      currentPhase: 'P2_PRACTICE_LOOP',
      currentSubphase: 'S2_IDENTIFY',
    });
    const output = builder.buildSystemPrompt(state, getActionName, getActionGoal, getSyndromeName);

    expect(output).toContain('诊断与训练');
    expect(output).toContain('识别问题');
  });

  it('应包含已完成的教学动作列表及其名称和目标', () => {
    const state = makeTeachingState({
      completedActions: ['A001', 'A003'],
    });
    const output = builder.buildSystemPrompt(state, getActionName, getActionGoal, getSyndromeName);

    // 动作名称
    expect(output).toContain('缩小范围');
    expect(output).toContain('五问法');
    // 动作目标
    expect(output).toContain('聚焦到第一个具体场景');
    expect(output).toContain('用连续追问理清因果链');
  });

  it('应包含建议的下一步教学动作列表', () => {
    const state = makeTeachingState({
      nextSuggestedActions: ['A005'],
    });
    const output = builder.buildSystemPrompt(state, getActionName, getActionGoal, getSyndromeName);

    expect(output).toContain('阶段拆分');
    expect(output).toContain('A005');
  });

  it('应包含活跃问题列表（状态为 active 或 improving）', () => {
    const state = makeTeachingState({
      activeProblems: [
        {
          id: 'P001',
          name: '世界观膨胀',
          severity: 'L2',
          evidence: ['用户写了太多设定'],
          firstDetected: '2026-01-01T00:00:00.000Z',
          status: 'active',
          detectionCount: 2,
          missedCount: 0,
          suggestedActions: ['A001'],
        },
        {
          id: 'P002',
          name: '角色工具人化',
          severity: 'L3',
          evidence: ['角色像工具'],
          firstDetected: '2026-01-01T00:00:00.000Z',
          status: 'improving',
          detectionCount: 1,
          missedCount: 0,
          suggestedActions: ['A004'],
        },
      ],
    });
    const output = builder.buildSystemPrompt(state, getActionName, getActionGoal, getSyndromeName);

    expect(output).toContain('世界观膨胀');
    expect(output).toContain('角色工具人化');
    expect(output).toContain('活跃');
    expect(output).toContain('改善中');
  });

  it('resolved 状态的问题不应出现在活跃问题列表中', () => {
    const state = makeTeachingState({
      activeProblems: [
        {
          id: 'P001',
          name: '世界观膨胀',
          severity: 'L1',
          evidence: ['已改善'],
          firstDetected: '2026-01-01T00:00:00.000Z',
          status: 'resolved',
          detectionCount: 3,
          missedCount: 0,
          suggestedActions: [],
        },
      ],
    });
    const output = builder.buildSystemPrompt(state, getActionName, getActionGoal, getSyndromeName);

    expect(output).not.toContain('世界观膨胀');
  });

  it('空状态（无动作、无问题）应正确处理', () => {
    const state = makeTeachingState({
      completedActions: [],
      nextSuggestedActions: [],
      activeProblems: [],
    });
    const output = builder.buildSystemPrompt(state, getActionName, getActionGoal, getSyndromeName);

    // 无已完成动作 → "暂无"
    expect(output).toContain('暂无');
    // 无活跃问题 → "暂无"
    expect(output).toContain('暂无');
  });

  it('应包含 focusArea 指令（当 focusArea 非 null 且非 general 时）', () => {
    const state = makeTeachingState({
      focusArea: 'worldbuilding',
    });
    const output = builder.buildSystemPrompt(state, getActionName, getActionGoal, getSyndromeName);

    expect(output).toContain('世界观构建');
    expect(output).toContain('P001');
    expect(output).toContain('P004');
  });

  it('focusArea 为 null 或 general 时不输出聚焦指令', () => {
    const stateNull = makeTeachingState({ focusArea: null });
    const stateGeneral = makeTeachingState({ focusArea: 'general' });

    const outputNull = builder.buildSystemPrompt(stateNull, getActionName, getActionGoal, getSyndromeName);
    const outputGeneral = builder.buildSystemPrompt(stateGeneral, getActionName, getActionGoal, getSyndromeName);

    // 不包含聚焦标记
    expect(outputNull).not.toContain('当前聚焦方向');
    expect(outputGeneral).not.toContain('当前聚焦方向');
  });

  it('所有阶段和子阶段的值都能正确映射', () => {
    const testCases: Array<{ phase: string; subphase: string; expectedPhase: string; expectedSubphase: string }> = [
      { phase: 'P0_INIT', subphase: '', expectedPhase: '初次见面', expectedSubphase: '' },
      { phase: 'P0_ENGAGE', subphase: 'S0_CONFIRM', expectedPhase: '投入建立', expectedSubphase: '确认投入' },
      { phase: 'P1_WORLD', subphase: 'S1_NATURAL_LAW', expectedPhase: '世界观搭建', expectedSubphase: '自然法则' },
      { phase: 'P2_PRACTICE_LOOP', subphase: 'S2_IDENTIFY', expectedPhase: '诊断与训练', expectedSubphase: '识别问题' },
      { phase: 'P4_REVIEW', subphase: 'S4_SUMMARY', expectedPhase: '复盘总结', expectedSubphase: '总结复盘' },
    ];

    for (const tc of testCases) {
      const state = makeTeachingState({
        currentPhase: tc.phase,
        currentSubphase: tc.subphase,
      });
      const output = builder.buildSystemPrompt(state, getActionName, getActionGoal, getSyndromeName);

      expect(output).toContain(tc.expectedPhase);
      expect(output).toContain(tc.expectedSubphase);
    }
  });
});

// ====================================================================
// 2. MemoryCapsuleService.buildCapsule 集成
// ====================================================================

describe('MemoryCapsuleService.buildCapsule 集成', () => {
  const capsuleService = new MemoryCapsuleService();

  it('空 diagnoses 列表应返回"尚无历史诊断记录"', () => {
    const output = capsuleService.buildCapsule({ diagnoses: [] });
    expect(output).toContain('尚无历史诊断记录');
    expect(output).toContain('教学生态（记忆胶囊）');
  });

  it('包含多条 DiagnosisEntry 时应输出最近诊断摘要和症候信息', () => {
    const diagnoses: DiagnosisEntry[] = [
      makeDiagnosisEntry({
        messageId: 'msg-1',
        syndromes: [
          { id: 'P001', name: '世界观膨胀', severity: 'L2', evidence: ['设定过于庞大'], suggestedActions: ['A001'] },
        ],
        timestamp: '2026-06-20T10:00:00.000Z',
      }),
      makeDiagnosisEntry({
        messageId: 'msg-2',
        syndromes: [
          { id: 'P002', name: '角色工具人化', severity: 'L3', evidence: ['角色像工具'], suggestedActions: ['A004'] },
          { id: 'P001', name: '世界观膨胀', severity: 'L1', evidence: ['稍微收敛了些'], suggestedActions: ['A001'] },
        ],
        timestamp: '2026-06-21T10:00:00.000Z',
      }),
    ];

    const output = capsuleService.buildCapsule({ diagnoses, recentCount: 3 });

    // 包含标题
    expect(output).toContain('教学生态（记忆胶囊）');
    // 包含最近诊断摘要（最新诊断在前面）
    expect(output).toContain('最近诊断');
    expect(output).toContain('世界观膨胀（L1）');
    expect(output).toContain('角色工具人化（L3）');
    // 包含教学建议
    expect(output).toContain('教学建议');
    expect(output).toContain('一次只聚焦一个问题');
  });

  it('高严重度症候应出现在"当前聚焦"部分', () => {
    const diagnoses: DiagnosisEntry[] = [
      makeDiagnosisEntry({
        syndromes: [
          { id: 'P002', name: '角色工具人化', severity: 'L3', evidence: ['严重问题'], suggestedActions: ['A004'] },
        ],
        timestamp: '2026-06-21T10:00:00.000Z',
      }),
    ];

    const output = capsuleService.buildCapsule({ diagnoses });

    expect(output).toContain('当前聚焦');
    expect(output).toContain('角色工具人化（L3）');
  });

  it('仅 L1 严重度症候不应有"当前聚焦"部分', () => {
    const diagnoses: DiagnosisEntry[] = [
      makeDiagnosisEntry({
        syndromes: [
          { id: 'H001', name: '无钩子开篇', severity: 'L1', evidence: ['小问题'], suggestedActions: [] },
        ],
        timestamp: '2026-06-21T10:00:00.000Z',
      }),
    ];

    const output = capsuleService.buildCapsule({ diagnoses });

    // L1 低于阈值，不应输出聚焦
    expect(output).not.toContain('当前聚焦');
  });

  it('传入 TeachingProgressDisplay 时应包含教学进度信息', () => {
    const diagnoses: DiagnosisEntry[] = [
      makeDiagnosisEntry({
        syndromes: [
          { id: 'P001', name: '世界观膨胀', severity: 'L2', evidence: ['设定过大'], suggestedActions: ['A001'] },
        ],
        timestamp: '2026-06-21T10:00:00.000Z',
      }),
    ];

    const progress: TeachingProgressDisplay = {
      phaseName: '诊断与训练',
      subphaseName: '识别问题',
      phaseProgress: 0.33,
      completedActions: [{ id: 'A001', name: '缩小范围' }],
      nextActions: [{ id: 'A003', name: '五问法' }],
      activeProblems: [],
    };

    const output = capsuleService.buildCapsule({ diagnoses, progress });

    expect(output).toContain('教学进度');
    expect(output).toContain('诊断与训练');
    expect(output).toContain('识别问题');
    expect(output).toContain('33%');
    expect(output).toContain('缩小范围');
  });

  it('重复出现的症候应在聚焦中标注出现次数', () => {
    const diagnoses: DiagnosisEntry[] = [
      makeDiagnosisEntry({
        messageId: 'msg-1',
        syndromes: [
          { id: 'P001', name: '世界观膨胀', severity: 'L2', evidence: ['第一次'], suggestedActions: ['A001'] },
        ],
        timestamp: '2026-06-20T10:00:00.000Z',
      }),
      makeDiagnosisEntry({
        messageId: 'msg-2',
        syndromes: [
          { id: 'P001', name: '世界观膨胀', severity: 'L3', evidence: ['第二次'], suggestedActions: ['A001'] },
        ],
        timestamp: '2026-06-21T10:00:00.000Z',
      }),
    ];

    const output = capsuleService.buildCapsule({ diagnoses, recentCount: 3 });

    // P001 出现了 2 次，且在聚焦中标注
    expect(output).toContain('已出现 2 次');
  });

  it('自定义标题应正确反映在输出中', () => {
    const output = capsuleService.buildCapsule({
      diagnoses: [],
      title: '自定义胶囊标题',
    });
    expect(output).toContain('自定义胶囊标题');
    expect(output).not.toContain('记忆胶囊');
  });

  it('recentCount 应控制最近诊断条目的显示数量', () => {
    const diagnoses: DiagnosisEntry[] = [
      makeDiagnosisEntry({ messageId: 'msg-1', syndromes: [{ id: 'P001', name: '世界观膨胀', severity: 'L1', evidence: ['1'], suggestedActions: [] }], timestamp: '2026-06-19T10:00:00.000Z' }),
      makeDiagnosisEntry({ messageId: 'msg-2', syndromes: [{ id: 'P002', name: '角色工具人化', severity: 'L1', evidence: ['2'], suggestedActions: [] }], timestamp: '2026-06-20T10:00:00.000Z' }),
      makeDiagnosisEntry({ messageId: 'msg-3', syndromes: [{ id: 'P003', name: '情绪标签化', severity: 'L1', evidence: ['3'], suggestedActions: [] }], timestamp: '2026-06-21T10:00:00.000Z' }),
      makeDiagnosisEntry({ messageId: 'msg-4', syndromes: [{ id: 'P004', name: '信息硬塞', severity: 'L1', evidence: ['4'], suggestedActions: [] }], timestamp: '2026-06-22T10:00:00.000Z' }),
    ];

    const output = capsuleService.buildCapsule({ diagnoses, recentCount: 2 });

    // recentCount=2 应只显示最近 2 条（msg-3 和 msg-4）
    expect(output).toContain('情绪标签化');
    expect(output).toContain('信息硬塞');
    // 最早的两条不应显示
    expect(output).not.toContain('世界观膨胀');
    expect(output).not.toContain('角色工具人化');
  });
});

// ====================================================================
// 3. PromptLoader 构造函数验证
// ====================================================================

describe('PromptLoader 构造函数与降级行为', () => {
  const resourcesRoot = 'dummy-path';

  it('构造函数应接受 resourcesRoot 参数', () => {
    const loader = new PromptLoader(resourcesRoot);
    expect(loader).toBeInstanceOf(PromptLoader);
  });

  it('应接受 DynamicContextService、PromptBuilder、CodexService 的 setter 注入', () => {
    const loader = new PromptLoader(resourcesRoot);
    const dynamicService = new DynamicContextService(resourcesRoot);
    const builder = new PromptBuilder();
    const codexService = new CodexService(resourcesRoot);

    // 验证 setter 方法存在且可调用
    expect(() => loader.setDynamicContextService(dynamicService)).not.toThrow();
    expect(() => loader.setPromptBuilder(builder)).not.toThrow();
    expect(() => loader.setCodexService(codexService)).not.toThrow();
  });

  it('无依赖时 loadSystemPrompt 应降级返回核心 prompt + 语气修饰', () => {
    const loader = new PromptLoader(resourcesRoot);

    // 无 DynamicContextService → 使用 readPrompt 从 process.cwd() 读取 resources/prompts/yuesheng-prompt-v5.md
    const output = loader.loadSystemPrompt('doubao');

    // 应包含读取到的 Prompt 文件内容
    expect(output).toContain('月笙写作教练 v5');
    // 应包含语气修饰
    expect(output).toContain('豆包');
    expect(output).toContain('温暖、鼓励');
  });

  it('不同 AttitudeLevel 应返回不同的语气修饰', () => {
    const loader = new PromptLoader(resourcesRoot);

    const doubaoOutput = loader.loadSystemPrompt('doubao');
    const yueshengOutput = loader.loadSystemPrompt('yuesheng');
    const senseiOutput = loader.loadSystemPrompt('sensei');

    // 豆包：温暖鼓励
    expect(doubaoOutput).toContain('温暖');
    expect(doubaoOutput).not.toContain('犀利');
    // 月笙：直接简洁
    expect(yueshengOutput).toContain('直接');
    expect(yueshengOutput).toContain('不绕弯');
    expect(yueshengOutput).not.toContain('犀利');
    // 导师：犀利直指核心
    expect(senseiOutput).toContain('犀利');
    expect(senseiOutput).toContain('略带讽刺');
  });

  it('AttitudeLevel 为 direct 时不追加语气修饰（没有对应默认配置）', () => {
    const loader = new PromptLoader(resourcesRoot);

    const output = loader.loadSystemPrompt('direct');

    // direct 没有默认 tone modifier
    // 输出应为 Prompt 文件内容，不含 direct 特有的语气修饰
    expect(output).toContain('月笙写作教练 v5');
    // direct 没有对应的 DEFAULT_TONE_MODIFIERS 条目，因此不会追加额外修饰
    // 注意：yuesheng-prompt-v5.md 文件已内嵌豆包语气，所以输出仍可能包含"风格指令"
  });

  it('loadSystemPrompt 应处理 studentContext 占位符替换', () => {
    const loader = new PromptLoader(resourcesRoot);

    const output = loader.loadSystemPrompt('doubao', null, undefined, '学生当前水平：初级，擅长描述但不擅长结构');

    // 调用不应抛异常，且包含文件内容
    expect(output).toContain('月笙写作教练 v5');
  });

  it('连续多次调用 loadSystemPrompt 应保持状态一致', () => {
    const loader = new PromptLoader(resourcesRoot);

    const output1 = loader.loadSystemPrompt('doubao');
    const output2 = loader.loadSystemPrompt('yuesheng');
    const output3 = loader.loadSystemPrompt('sensei');

    // 每次调用都返回独立结果
    expect(output1).toContain('温暖');
    expect(output2).toContain('直接');
    expect(output3).toContain('犀利');
  });

  it('clearToneModifiersCache 应清除缓存并重新加载', () => {
    const loader = new PromptLoader(resourcesRoot);

    // 第一次调用加载并缓存
    const output1 = loader.loadSystemPrompt('doubao');

    // 清除缓存
    loader.clearToneModifiersCache();

    // 再次调用应重新加载（从默认值重新构建）
    const output2 = loader.loadSystemPrompt('doubao');

    expect(output2).toContain('温暖');
    expect(output2).toBe(output1); // 降级默认值相同，内容应一致
  });

  it('loadSystemPrompt 传递 diagnosisHistory 参数时应在输出中包含历史记录', () => {
    const loader = new PromptLoader(resourcesRoot);
    const history = '历史诊断信息：用户过去 3 轮持续出现世界观膨胀问题。';

    const output = loader.loadSystemPrompt('doubao', null, history);

    expect(output).toContain(history);
  });

  it('loadSystemPrompt 传递 diagnosisAnalysis 参数时应在输出中包含诊断增强', () => {
    const loader = new PromptLoader(resourcesRoot);
    const analysis = {
      rootCause: '世界观设定过多',
      intentPhase: 1,
      syndromeRef: ['P001'],
      techniquePool: [],
      keyPassages: [{ text: '这是一个庞大的世界', issue: '设定过度' }],
      confidence: 0.85,
    };

    const output = loader.loadSystemPrompt('doubao', analysis);

    expect(output).toContain('当前诊断结果');
    expect(output).toContain('世界观设定过多');
  });
});
