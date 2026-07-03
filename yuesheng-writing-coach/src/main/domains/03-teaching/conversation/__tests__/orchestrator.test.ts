/**
 * MockConversationOrchestrator 单测
 *
 * 验证事件流的正确性 / 顺序 / 完整性
 * A-1 DoD 要求 ≥5 个单测
 */

import { describe, it, expect } from 'vitest';
import { MockConversationOrchestrator } from '../mock-orchestrator';
import type { OrchestratorEvent } from '../orchestrator.types';

const collect = async (gen: AsyncIterable<OrchestratorEvent>): Promise<OrchestratorEvent[]> => {
  const out: OrchestratorEvent[] = [];
  for await (const ev of gen) out.push(ev);
  return out;
};

describe('MockConversationOrchestrator (A-1)', () => {
  const sessionId = 'test-session-001';

  it('缺失 sessionId 时立即返回 error 事件', async () => {
    const orch = new MockConversationOrchestrator();
    const events = await collect(orch.handleTurn({
      userMessage: 'hi',
      phase: 'trust_building',
      sessionId: '',
    }));
    expect(events).toHaveLength(1);
    expect(events[0].type).toBe('error');
    if (events[0].type === 'error') {
      expect(events[0].payload.code).toBe('CONTEXT_MISSING');
    }
  });

  it('trust_building 阶段先发 phase_transition 再发 token', async () => {
    const orch = new MockConversationOrchestrator();
    const events = await collect(orch.handleTurn({
      userMessage: '你好',
      phase: 'trust_building',
      sessionId,
    }));
    const types = events.map(e => e.type);
    expect(types[0]).toBe('phase_transition');
    expect(types).toContain('token');
    expect(types[types.length - 1]).toBe('done');
  });

  it('用户消息含"诊断"关键词时触发 diagnosis_extracted 事件', async () => {
    const orch = new MockConversationOrchestrator();
    const events = await collect(orch.handleTurn({
      userMessage: '请帮我诊断一下这段文字',
      phase: 'diagnosis',
      sessionId,
    }));
    const diagnoses = events.filter(e => e.type === 'diagnosis_extracted');
    expect(diagnoses).toHaveLength(1);
    if (diagnoses[0].type === 'diagnosis_extracted') {
      expect(diagnoses[0].payload.syndromeId).toBe('P003');
      expect(diagnoses[0].payload.severity).toBe('L2');
    }
  });

  it('用户消息含"训练"关键词时触发 training_triggered 事件', async () => {
    const orch = new MockConversationOrchestrator();
    const events = await collect(orch.handleTurn({
      userMessage: '我想开始训练',
      phase: 'training',
      sessionId,
    }));
    const triggered = events.filter(e => e.type === 'training_triggered');
    expect(triggered).toHaveLength(1);
    if (triggered[0].type === 'training_triggered') {
      expect(triggered[0].payload.sessionId).toBe(sessionId);
      expect(triggered[0].payload.syndromeId).toBe('P003');
      expect(triggered[0].payload.reason).toBe('user_request');
    }
  });

  it('stopGeneration() 后 handleTurn 立即返回 error', async () => {
    const orch = new MockConversationOrchestrator();
    orch.stopGeneration();
    const events = await collect(orch.handleTurn({
      userMessage: 'hi',
      phase: 'diagnosis',
      sessionId,
    }));
    const errors = events.filter(e => e.type === 'error');
    expect(errors.length).toBeGreaterThan(0);
  });

  it('promptVersion() 返回 R-025 元数据(v5.0.0-mock)', () => {
    const orch = new MockConversationOrchestrator();
    const v = orch.promptVersion();
    expect(v.version).toBe('v5.0.0-mock');
    expect(v.changelog).toContain('A-1');
  });

  it('skillManifest(phase) 至少返回 1 个 skill', () => {
    const orch = new MockConversationOrchestrator();
    const phases = ['trust_building', 'requirement', 'diagnosis', 'training', 'reflection'] as const;
    for (const p of phases) {
      const skills = orch.skillManifest(p);
      expect(skills.length).toBeGreaterThan(0);
    }
  });

  it('事件流以 done 结尾(无 error 时)', async () => {
    const orch = new MockConversationOrchestrator();
    const events = await collect(orch.handleTurn({
      userMessage: 'hello',
      phase: 'requirement',
      sessionId,
    }));
    expect(events[events.length - 1].type).toBe('done');
  });
});
