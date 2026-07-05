/**
 * S16 BL-02 验证：analyze() 把 options.syndromeIds 映射为 TechniqueFilter 并透传给
 * callDiagnosisAgent → techniquePool.injectIntoPrompt。
 *
 * 验证策略：mock fs.readFile 让其成功，spy techniquePool.injectIntoPrompt。
 */
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { DiagnosisOrchestratorService } from '../diagnosis-orchestrator.service';
import type { BrowserWindow } from 'electron';
import type nodeFs from 'fs';

vi.mock('fs', async () => {
  const actual = await vi.importActual<typeof nodeFs>('fs');
  return {
    ...actual,
    promises: {
      ...actual.promises,
      readFile: vi.fn().mockResolvedValue('PROMPT {{technique_pool}}'),
    },
  };
});

function makeService(techniquePool: { injectIntoPrompt: (p: string, f?: unknown) => string }) {
  const domain = {
    save: () => 1,
    saveAnalysis: () => {},
    getRecentBySession: () => [],
  };
  const win = {
    webContents: { send: vi.fn() },
  } as unknown as BrowserWindow;
  const svc = new DiagnosisOrchestratorService(
    techniquePool as never,
    domain as never,
    win,
  );
  return { svc, win };
}

describe('DiagnosisOrchestratorService.analyze (S16 BL-02)', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('无 syndromeIds 时 injectIntoPrompt 收到 undefined filter', async () => {
    const injectIntoPrompt = vi
      .fn()
      .mockImplementation((p: string) => p.replace('{{technique_pool}}', 'TECH'));
    async function* emptyStream() {
      // noop
    }
    const proxy = { chatStream: emptyStream };
    const { svc } = makeService({ injectIntoPrompt });
    await svc.analyze(proxy as never, '测试文本', 'sess-1');
    expect(injectIntoPrompt).toHaveBeenCalled();
    const secondArg = injectIntoPrompt.mock.calls[0]?.[1];
    expect(secondArg).toBeUndefined();
  });

  it('有 syndromeIds 时 injectIntoPrompt 收到 { syndromeIds: [...] }', async () => {
    const injectIntoPrompt = vi
      .fn()
      .mockImplementation((p: string) => p.replace('{{technique_pool}}', 'TECH'));
    async function* emptyStream() {
      // noop
    }
    const proxy = { chatStream: emptyStream };
    const { svc } = makeService({ injectIntoPrompt });
    await svc.analyze(
      proxy as never,
      '测试文本',
      'sess-1',
      { syndromeIds: ['P001', 'P004'] },
    );
    expect(injectIntoPrompt).toHaveBeenCalled();
    const secondArg = injectIntoPrompt.mock.calls[0]?.[1];
    expect(secondArg).toEqual({ syndromeIds: ['P001', 'P004'] });
  });

  it('空数组 syndromeIds 视为不传 filter', async () => {
    const injectIntoPrompt = vi
      .fn()
      .mockImplementation((p: string) => p.replace('{{technique_pool}}', 'TECH'));
    async function* emptyStream() {
      // noop
    }
    const proxy = { chatStream: emptyStream };
    const { svc } = makeService({ injectIntoPrompt });
    await svc.analyze(proxy as never, '测试文本', 'sess-1', { syndromeIds: [] });
    expect(injectIntoPrompt).toHaveBeenCalled();
    const secondArg = injectIntoPrompt.mock.calls[0]?.[1];
    expect(secondArg).toBeUndefined();
  });
});
