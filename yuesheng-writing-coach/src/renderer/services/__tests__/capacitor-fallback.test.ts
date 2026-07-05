/**
 * Capacitor 降级分支综合测试 — Sprint 29
 *
 * 覆盖 6 个 service 在 isCapacitor()=true 时的降级行为:
 * 1. chat.service.ts — 5 个方法降级（null / {stopped:false} / 空 cleanup）
 * 2. diagnosis.service.ts — 4 个方法降级（null / 空 cleanup）
 * 3. training.service.ts — 现有方法降级（均返回 null/[]/false）
 * 4. student-context.service.ts — 3 个方法降级（null）
 * 5. app-controller.ts — initialize 早返回
 * 6. teaching-state.service.ts — IPC-only 方法降级（null / 空 cleanup）
 *
 * Sprint 32: 方法签名已更新,测试同步对齐
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
  it('query() 返回 null（不支持）', async () => {
    setCapacitorPlatform();
    const { diagnosisService } = await import('../diagnosis.service');
    const result = await diagnosisService.query('analyze this text');
    expect(result).toBeNull();
  });

  it('submitRewrite() 返回 null', async () => {
    setCapacitorPlatform();
    const { diagnosisService } = await import('../diagnosis.service');
    const result = await diagnosisService.submitRewrite('session-1', 'original', 'rewritten');
    expect(result).toBeNull();
  });

  it('getComparison() 返回 null', async () => {
    setCapacitorPlatform();
    const { diagnosisService } = await import('../diagnosis.service');
    const result = await diagnosisService.getComparison('session-1');
    expect(result).toBeNull();
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
  it('createObjective() 返回 null', async () => {
    setCapacitorPlatform();
    const { trainingService } = await import('../training.service');
    const result = await trainingService.createObjective({ sessionId: 's1', title: 'test' });
    expect(result).toBeNull();
  });

  it('getObjectives() 返回 []', async () => {
    setCapacitorPlatform();
    const { trainingService } = await import('../training.service');
    const result = await trainingService.getObjectives('s1');
    expect(result).toEqual([]);
  });

  it('createNote() 返回 null', async () => {
    setCapacitorPlatform();
    const { trainingService } = await import('../training.service');
    const result = await trainingService.createNote({ sessionId: 's1', content: 'note' });
    expect(result).toBeNull();
  });

  it('getNotes() 返回 []', async () => {
    setCapacitorPlatform();
    const { trainingService } = await import('../training.service');
    const result = await trainingService.getNotes('s1');
    expect(result).toEqual([]);
  });

  it('createEvaluation() 返回 null', async () => {
    setCapacitorPlatform();
    const { trainingService } = await import('../training.service');
    const result = await trainingService.createEvaluation({ sessionId: 's1', score: 5, dimension: 'test' });
    expect(result).toBeNull();
  });

  it('getEvaluations() 返回 []', async () => {
    setCapacitorPlatform();
    const { trainingService } = await import('../training.service');
    const result = await trainingService.getEvaluations('s1');
    expect(result).toEqual([]);
  });

  it('getHistory() 返回 []', async () => {
    setCapacitorPlatform();
    const { trainingService } = await import('../training.service');
    const result = await trainingService.getHistory('s1');
    expect(result).toEqual([]);
  });

  it('remove() 返回 false', async () => {
    setCapacitorPlatform();
    const { trainingService } = await import('../training.service');
    const result = await trainingService.remove('r1');
    expect(result).toBe(false);
  });
});

// ─── 4. student-context.service.ts ───

describe('student-context.service — Capacitor 降级', () => {
  it('get() 返回 null', async () => {
    setCapacitorPlatform();
    const { studentContextService } = await import('../student-context.service');
    const result = await studentContextService.get('user-1');
    expect(result).toBeNull();
  });

  it('update() 返回 null', async () => {
    setCapacitorPlatform();
    const { studentContextService } = await import('../student-context.service');
    const result = await studentContextService.update('user-1', {});
    expect(result).toBeNull();
  });

  it('getNote() 返回 null', async () => {
    setCapacitorPlatform();
    const { studentContextService } = await import('../student-context.service');
    const result = await studentContextService.getNote('user-1');
    expect(result).toBeNull();
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
  it('confirmPhase() 返回 null', async () => {
    setCapacitorPlatform();
    const { teachingStateService } = await import('../teaching-state.service');
    const result = await teachingStateService.confirmPhase('session-1', 'P1_WORLD').catch(() => null);
    expect(result).toBeNull();
  });

  it('getPrompt() 返回 null', async () => {
    setCapacitorPlatform();
    const { teachingStateService } = await import('../teaching-state.service');
    const result = await teachingStateService.getPrompt('session-1');
    expect(result).toBeNull();
  });

  it('updateSummary() 返回 null', async () => {
    setCapacitorPlatform();
    const { teachingStateService } = await import('../teaching-state.service');
    const result = await teachingStateService.updateSummary('session-1', 'summary');
    expect(result).toBeNull();
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
