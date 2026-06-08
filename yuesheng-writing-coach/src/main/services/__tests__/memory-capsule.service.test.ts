/**
 * MemoryCapsuleService 单元测试 — PE-009 记忆胶囊机制
 *
 * 测试覆盖：
 * 1. 空诊断列表
 * 2. 最近诊断摘要格式化
 * 3. 当前聚焦（最高严重度症候）
 * 4. 频率统计（反复出现的问题）
 * 5. 教学进度集成
 * 6. 完整胶囊构建
 */

import { describe, it, expect } from 'vitest';
import { MemoryCapsuleService } from '../memory-capsule.service';
import type { DiagnosisEntry, TeachingProgressDisplay } from '../../../renderer/shared/types';

describe('MemoryCapsuleService', () => {
  const service = new MemoryCapsuleService();

  const makeDiagnosis = (overrides: Partial<DiagnosisEntry> = {}): DiagnosisEntry => ({
    sessionId: 'test-session',
    messageId: 'msg-1',
    syndromes: [
      { id: 'P001', name: '世界观膨胀', severity: 'L2', evidence: ['test'], score: 0.8, suggestedActions: [] },
    ],
    suggestedActions: [],
    confidence: 0.8,
    timestamp: '2026-06-01T10:00:00.000Z',
    ...overrides,
  });

  const makeProgress = (overrides: Partial<TeachingProgressDisplay> = {}): TeachingProgressDisplay => ({
    phaseName: '世界观构建',
    subphaseName: '基础设定',
    phaseProgress: 0.6,
    completedActions: [
      { id: 'A001', name: '完成世界观问卷' },
      { id: 'A002', name: '撰写设定文档' },
    ],
    nextActions: [],
    activeProblems: [],
    ...overrides,
  });

  // ===== 1. 空诊断 =====

  it('空诊断列表返回占位文本', () => {
    const result = service.buildCapsule({ diagnoses: [] });
    expect(result).toContain('尚无历史诊断记录');
    expect(result).toContain('教学生态（记忆胶囊）');
  });

  it('空诊断列表支持自定义标题', () => {
    const result = service.buildCapsule({ diagnoses: [], title: '自定义胶囊' });
    expect(result).toContain('自定义胶囊');
    expect(result).toContain('尚无历史诊断记录');
  });

  // ===== 2. 最近诊断摘要 =====

  it('格式化最近 3 条诊断摘要', () => {
    const diagnoses = [
      makeDiagnosis({ timestamp: '2026-06-01T10:00:00.000Z' }),
      makeDiagnosis({ timestamp: '2026-06-02T10:00:00.000Z' }),
      makeDiagnosis({ timestamp: '2026-06-03T10:00:00.000Z' }),
    ];
    const result = service.buildCapsule({ diagnoses });
    expect(result).toContain('最近诊断');
    // 应包含 3 条记录
    expect(result.match(/- 2026\/6\/\d/g)?.length).toBe(3);
  });

  it('少于 3 条时显示全部', () => {
    const diagnoses = [
      makeDiagnosis({ timestamp: '2026-06-01T10:00:00.000Z' }),
    ];
    const result = service.buildCapsule({ diagnoses });
    expect(result).toContain('最近诊断');
    expect(result.match(/- 2026\/6\/\d/g)?.length).toBe(1);
  });

  it('支持自定义 recentCount', () => {
    const diagnoses = [
      makeDiagnosis({ timestamp: '2026-06-01T10:00:00.000Z' }),
      makeDiagnosis({ timestamp: '2026-06-02T10:00:00.000Z' }),
      makeDiagnosis({ timestamp: '2026-06-03T10:00:00.000Z' }),
      makeDiagnosis({ timestamp: '2026-06-04T10:00:00.000Z' }),
      makeDiagnosis({ timestamp: '2026-06-05T10:00:00.000Z' }),
    ];
    const result = service.buildCapsule({ diagnoses, recentCount: 5 });
    expect(result.match(/- 2026\/6\/\d/g)?.length).toBe(5);
  });

  it('每条诊断最多显示 3 个症候', () => {
    const diagnoses = [
      makeDiagnosis({
        syndromes: [
          { id: 'P001', name: '症候A', severity: 'L2', evidence: [], score: 0.8, suggestedActions: [] },
          { id: 'P002', name: '症候B', severity: 'L1', evidence: [], score: 0.6, suggestedActions: [] },
          { id: 'P003', name: '症候C', severity: 'L1', evidence: [], score: 0.5, suggestedActions: [] },
          { id: 'P004', name: '症候D', severity: 'L1', evidence: [], score: 0.4, suggestedActions: [] },
        ],
        timestamp: '2026-06-01T10:00:00.000Z',
      }),
    ];
    const result = service.buildCapsule({ diagnoses });
    // 症候D 不应出现（只显示前3个）
    expect(result).toContain('症候A');
    expect(result).toContain('症候B');
    expect(result).toContain('症候C');
    expect(result).not.toContain('症候D');
  });

  // ===== 3. 当前聚焦 =====

  it('最高严重度症候出现在当前聚焦', () => {
    const diagnoses = [
      makeDiagnosis({
        syndromes: [
          { id: 'P001', name: '轻微问题', severity: 'L1', evidence: [], score: 0.5, suggestedActions: [] },
          { id: 'P002', name: '严重问题', severity: 'L3', evidence: [], score: 0.9, suggestedActions: [] },
        ],
      }),
    ];
    const result = service.buildCapsule({ diagnoses });
    expect(result).toContain('当前聚焦');
    expect(result).toContain('严重问题');
    expect(result).toContain('L3');
  });

  it('仅有 L1 时不显示当前聚焦', () => {
    const diagnoses = [
      makeDiagnosis({
        syndromes: [
          { id: 'P001', name: '轻微问题', severity: 'L1', evidence: [], score: 0.5, suggestedActions: [] },
        ],
      }),
    ];
    const result = service.buildCapsule({ diagnoses });
    expect(result).not.toContain('当前聚焦');
  });

  // ===== 4. 频率统计 =====

  it('反复出现的症候标注出现次数', () => {
    const diagnoses = [
      makeDiagnosis({
        syndromes: [{ id: 'P001', name: '反复问题', severity: 'L2', evidence: [], score: 0.8, suggestedActions: [] }],
        timestamp: '2026-06-01T10:00:00.000Z',
      }),
      makeDiagnosis({
        syndromes: [{ id: 'P001', name: '反复问题', severity: 'L2', evidence: [], score: 0.8, suggestedActions: [] }],
        timestamp: '2026-06-02T10:00:00.000Z',
      }),
      makeDiagnosis({
        syndromes: [{ id: 'P001', name: '反复问题', severity: 'L2', evidence: [], score: 0.8, suggestedActions: [] }],
        timestamp: '2026-06-03T10:00:00.000Z',
      }),
    ];
    const result = service.buildCapsule({ diagnoses });
    expect(result).toContain('已出现 3 次');
  });

  it('每次出现取最高严重度', () => {
    const diagnoses = [
      makeDiagnosis({
        syndromes: [{ id: 'P001', name: '渐变问题', severity: 'L1', evidence: [], score: 0.5, suggestedActions: [] }],
        timestamp: '2026-06-01T10:00:00.000Z',
      }),
      makeDiagnosis({
        syndromes: [{ id: 'P001', name: '渐变问题', severity: 'L3', evidence: [], score: 0.9, suggestedActions: [] }],
        timestamp: '2026-06-02T10:00:00.000Z',
      }),
    ];
    const result = service.buildCapsule({ diagnoses });
    expect(result).toContain('L3');
    // 当前聚焦部分不应含 L1（虽历史行有 L1，但聚合取最高严重度 L3）
    const focusSection = result.slice(result.indexOf('### 当前聚焦'));
    expect(focusSection).toContain('L3');
    expect(focusSection).not.toContain('L1');
  });

  // ===== 5. 教学进度 =====

  it('包含教学进度信息', () => {
    const diagnoses = [makeDiagnosis()];
    const progress = makeProgress();
    const result = service.buildCapsule({ diagnoses, progress });
    expect(result).toContain('教学进度');
    expect(result).toContain('世界观构建');
    expect(result).toContain('基础设定');
    expect(result).toContain('60%');
    expect(result).toContain('完成世界观问卷');
    expect(result).toContain('撰写设定文档');
  });

  it('无已完成动作时不显示该行', () => {
    const diagnoses = [makeDiagnosis()];
    const progress = makeProgress({ completedActions: [] });
    const result = service.buildCapsule({ diagnoses, progress });
    expect(result).toContain('教学进度');
    expect(result).not.toContain('已完成：');
  });

  it('有教学进度时教学建议包含阶段提示', () => {
    const diagnoses = [makeDiagnosis()];
    const progress = makeProgress();
    const result = service.buildCapsule({ diagnoses, progress });
    expect(result).toContain('根据当前教学阶段调整指导密度');
  });

  it('无教学进度时教学建议不含阶段提示', () => {
    const diagnoses = [makeDiagnosis()];
    const result = service.buildCapsule({ diagnoses });
    expect(result).not.toContain('根据当前教学阶段调整指导密度');
  });

  // ===== 6. 完整胶囊 =====

  it('完整胶囊包含所有区块', () => {
    const diagnoses = [
      makeDiagnosis({
        syndromes: [{ id: 'P001', name: '世界观膨胀', severity: 'L2', evidence: [], score: 0.8, suggestedActions: [] }],
        timestamp: '2026-06-01T10:00:00.000Z',
      }),
      makeDiagnosis({
        syndromes: [{ id: 'P002', name: '角色扁平', severity: 'L3', evidence: [], score: 0.9, suggestedActions: [] }],
        timestamp: '2026-06-02T10:00:00.000Z',
      }),
    ];
    const progress = makeProgress();
    const result = service.buildCapsule({ diagnoses, progress });

    // 所有区块必须存在
    expect(result).toContain('教学生态（记忆胶囊）');
    expect(result).toContain('最近诊断');
    expect(result).toContain('当前聚焦');
    expect(result).toContain('教学进度');
    expect(result).toContain('教学建议');

    // 聚焦应为 L3 的角色扁平
    const focusSection = result.slice(result.indexOf('当前聚焦'), result.indexOf('教学进度'));
    expect(focusSection).toContain('角色扁平');
    expect(focusSection).toContain('L3');
    expect(focusSection).not.toContain('世界观膨胀');
  });

  // ===== 7. 便捷函数 =====

  it('buildMemoryCapsule 便捷函数正常工作', async () => {
    const { buildMemoryCapsule } = await import('../memory-capsule.service');
    const result = buildMemoryCapsule({ diagnoses: [] });
    expect(result).toContain('尚无历史诊断记录');
  });
});
