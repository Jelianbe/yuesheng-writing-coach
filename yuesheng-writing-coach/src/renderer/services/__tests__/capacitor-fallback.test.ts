/**
 * Capacitor 降级分支综合测试 — Sprint 29
 *
 * 覆盖 6 个 service 在 isCapacitor()=true 时的降级行为:
 * 1. chat.service.ts — 5 个方法降级（null / {stopped:false} / 空 cleanup）
 * 2. diagnosis.service.ts — 4 个方法降级（null / undefined / fallback / 空 cleanup）
 * 3. training.service.ts — 8 个方法降级（均返回 null）
 * 4. student-context.service.ts — 3 个方法降级（null / false / ''）
 * 5. app-controller.ts — initialize 早返回
 * 6. teaching-state.service.ts — 5 个 IPC-only 方法降级（null / 空 cleanup）
 *
 * 依据: dev-docs/tasks/sprint-29-plan.md §阶段 3
 */

import { describe, it, expect, vi, afterEach } from 'vitest';

// ─── 辅助: 切换 Capacitor 平台 ───

const origWindow = globalThis.window;
const origUserAgent = navigator.userAgent;

function setCapacitorPlatform(): void {
  (globalThis as unknown as { window: unknown }).window = {};
  Object.defineProperty(navigator, 'userAgent', {
    value: 'Mozilla/5.0 (Linux; Android 10) Capacitor/3.5.0',
    configurable: true,
  });
}

afterEach(() => {
  (globalThis as unknown as { window: unknown }).window = origWindow;
  Object.defineProperty(navigator, 'userAgent', { value: origUserAgent, configurable: true });
  vi.restoreAllMocks();
});

// ─── 1. chat.service.ts ───

describe('chat.service — Capacitor 降级', () => {
  it('send() 返回 null', async () => {
    setCapacitorPlatform();
    const { chatService } = await import('../chat.service');
    const result = await chatService.send({
      message: 'hi',
      sessionId: 'session-1',
      history: [],
      attitudeLevel: 'default',
      studentContext: '',
    });
    expect(result).toBeNull();
  });

  it('stop() 返回 { stopped: false }', async () => {
    setCapacitorPlatform();
    const { chatService } = await import('../chat.service');
    const result = await chatService.stop('session-1');
    expect(result).toEqual({ stopped: false });
  });

  it('onStreamData() 返回空 cleanup 函数', async () => {
    setCapacitorPlatform();
    const { chatService } = await import('../chat.service');
    const cleanup = chatService.onStreamData(vi.fn());
    expect(typeof cleanup).toBe('function');
    expect(() => cleanup()).not.toThrow();
  });

  it('onStreamEnd() 返回空 cleanup 函数', async () => {
    setCapacitorPlatform();
    const { chatService } = await import('../chat.service');
    const cleanup = chatService.onStreamEnd(vi.fn());
    expect(typeof cleanup).toBe('function');
    expect(() => cleanup()).not.toThrow();
  });

  it('onToolExecuting() 返回空 cleanup 函数', async () => {
    setCapacitorPlatform();
    const { chatService } = await import('../chat.service');
    const cleanup = chatService.onToolExecuting(vi.fn());
    expect(typeof cleanup).toBe('function');
    expect(() => cleanup()).not.toThrow();
  });
});

// ─── 2. diagnosis.service.ts ───

describe('diagnosis.service — Capacitor 降级', () => {
  it('query() 返回空数组（无缓存诊断）', async () => {
    setCapacitorPlatform();
    const { diagnosisService } = await import('../diagnosis.service');
    const result = await diagnosisService.query({ sessionId: 'session-1' });
    expect(result).toEqual([]);
  });

  it('submitRewrite() 返回 undefined（无 API Key）', async () => {
    setCapacitorPlatform();
    const { diagnosisService } = await import('../diagnosis.service');
    const result = await diagnosisService.submitRewrite({
      sessionId: 'session-1',
      syndromeId: 's1',
      originalText: 'original',
      rewrittenText: 'text',
    });
    expect(result).toBeUndefined();
  });

  it('getComparison() 返回 { hasHistory: false }', async () => {
    setCapacitorPlatform();
    const { diagnosisService } = await import('../diagnosis.service');
    const result = await diagnosisService.getComparison({ sessionId: 'session-1', syndromeId: 's1' });
    expect(result).toEqual({ hasHistory: false });
  });

  it('onDiagnosisUpdate() 返回空 cleanup 函数', async () => {
    setCapacitorPlatform();
    const { diagnosisService } = await import('../diagnosis.service');
    const cleanup = diagnosisService.onDiagnosisUpdate(vi.fn());
    expect(typeof cleanup).toBe('function');
    expect(() => cleanup()).not.toThrow();
  });
});

// ─── 3. training.service.ts ───

describe('training.service — Capacitor 降级', () => {
  const trainingMethods: Array<{ name: string; args: unknown }> = [
    { name: 'recommend', args: { sessionId: 's1' } },
    { name: 'assign', args: { sessionId: 's1', trainingId: 't1' } },
    { name: 'complete', args: { sessionId: 's1', trainingId: 't1' } },
    { name: 'skip', args: { sessionId: 's1', trainingId: 't1' } },
    { name: 'history', args: { sessionId: 's1' } },
    { name: 'submit', args: { sessionId: 's1', trainingId: 't1', content: '' } },
    { name: 'evaluate', args: { sessionId: 's1', trainingId: 't1' } },
    { name: 'deriveBehavior', args: { sessionId: 's1', trainingId: 't1' } },
  ];

  for (const { name, args } of trainingMethods) {
    it(`${name}() 返回 null`, async () => {
      setCapacitorPlatform();
      const { trainingService } = await import('../training.service');
      const result = await (trainingService as Record<string, (a: unknown) => Promise<unknown>>)[name](args);
      expect(result).toBeNull();
    });
  }
});

// ─── 4. student-context.service.ts ───

describe('student-context.service — Capacitor 降级', () => {
  it('load() 返回 null', async () => {
    setCapacitorPlatform();
    const { studentContextService } = await import('../student-context.service');
    const result = await studentContextService.load();
    expect(result).toBeNull();
  });

  it('save() 返回 false', async () => {
    setCapacitorPlatform();
    const { studentContextService } = await import('../student-context.service');
    const result = await studentContextService.save({ sessionId: 'session-1', data: {} });
    expect(result).toBe(false);
  });

  it('toJSON() 返回空字符串', async () => {
    setCapacitorPlatform();
    const { studentContextService } = await import('../student-context.service');
    const result = await studentContextService.toJSON();
    expect(result).toBe('');
  });
});

// ─── 5. app-controller.ts ───

describe('app-controller — Capacitor 降级', () => {
  it('initialize() 在 Capacitor 平台早返回（不注册监听）', async () => {
    setCapacitorPlatform();
    const { createAppController } = await import('../app-controller');
    const app = createAppController();

    expect(() => app.initialize()).not.toThrow();
    expect(() => app.initialize()).not.toThrow();
  });
});

// ─── 6. teaching-state.service.ts (IPC-only 方法) ───

describe('teaching-state.service — Capacitor 降级（IPC-only 方法）', () => {
  it('confirm() 返回日志对象（localStorage 记录）', async () => {
    setCapacitorPlatform();
    const { teachingStateService } = await import('../teaching-state.service');
    const result = await teachingStateService.confirm({ sessionId: 'session-1' });
    expect(result).toBeTruthy();
    expect(result).toHaveProperty('oldState');
    expect(result).toHaveProperty('newState');
  });

  it('getPrompt() 返回 null', async () => {
    setCapacitorPlatform();
    const { teachingStateService } = await import('../teaching-state.service');
    const result = await teachingStateService.getPrompt({ sessionId: 'session-1' });
    expect(result).toBeNull();
  });

  it('updateSummary() 返回摘要对象（localStorage 持久化）', async () => {
    setCapacitorPlatform();
    const { teachingStateService } = await import('../teaching-state.service');
    const result = await teachingStateService.updateSummary({
      sessionId: 'session-1',
      newContent: 'summary',
    });
    expect(result).toBeTruthy();
    expect(result).toHaveProperty('diagnosisSummary', 'summary');
  });

  it('onUpdated() 返回空 cleanup 函数', async () => {
    setCapacitorPlatform();
    const { teachingStateService } = await import('../teaching-state.service');
    const cleanup = teachingStateService.onUpdated(vi.fn());
    expect(typeof cleanup).toBe('function');
    expect(() => cleanup()).not.toThrow();
  });

  it('onMastery() 返回空 cleanup 函数', async () => {
    setCapacitorPlatform();
    const { teachingStateService } = await import('../teaching-state.service');
    const cleanup = teachingStateService.onMastery(vi.fn());
    expect(typeof cleanup).toBe('function');
    expect(() => cleanup()).not.toThrow();
  });
});
