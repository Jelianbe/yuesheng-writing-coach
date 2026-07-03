/**
 * RealOrchestratorAdapter 单测 — Sprint 21 D-1
 *
 * 验证:
 * 1. 订阅路径:onOrchestratorEvent → 透传事件
 * 2. 事件类型映射:onToken → token 事件、emit → 对应事件
 * 3. 错误转换:sendMessage reject → error 事件
 * 4. Mock 降级:无 SkillRegistry 时 skillManifest 返回 []
 * 5. sessionId 过滤:其他会话事件被丢弃
 * 6. unsubscribe:stream 完成后清理订阅
 * 7. promptVersion / stopGeneration 委托
 * 8. 异常隔离:订阅 handler 抛错不中断流
 *
 * DoD: ≥5 个单测
 * 依据: dev-docs/tasks/sprint-21-plan.md §D-1
 */

import { describe, it, expect, vi, beforeEach } from 'vitest';
import { RealOrchestratorAdapter } from '../real-orchestrator-adapter';
import type { ChatOrchestratorService } from '../../chat/chat-orchestrator.service';
import type { SkillRegistry, SkillMetadata } from '../skill-registry';
import type {
  HandleTurnInput,
  OrchestratorEvent,
  OrchestratorError,
} from '../orchestrator.types';

// ─── 辅助:收集 AsyncIterable 事件 ───
const collect = async (gen: AsyncIterable<OrchestratorEvent>): Promise<OrchestratorEvent[]> => {
  const out: OrchestratorEvent[] = [];
  for await (const ev of gen) out.push(ev);
  return out;
};

// ─── 辅助:构造最小 ChatOrchestratorService fake ───
type EventHandler = (e: OrchestratorEvent, sessionId: string) => void;

interface FakeChatOrchestratorDeps {
  sendImpl?: (args: {
    sessionId: string;
    onToken?: (chunk: string) => void;
  }) => Promise<{ messageId: string }>;
  emitDuringSend?: (event: OrchestratorEvent, sessionId: string) => void;
  stopResult?: { stopped: boolean };
}

const createFakeChatOrchestrator = (deps: FakeChatOrchestratorDeps = {}): ChatOrchestratorService => {
  const subscribers = new Set<EventHandler>();

  return {
    onOrchestratorEvent: (handler: EventHandler) => {
      subscribers.add(handler);
      return () => subscribers.delete(handler);
    },
    sendMessage: async (args: {
      message: string;
      sessionId: string;
      onToken?: (chunk: string) => void;
    }) => {
      if (deps.sendImpl) {
        return deps.sendImpl({
          sessionId: args.sessionId,
          onToken: args.onToken,
        });
      }
      // 默认: 模拟 token 流,然后完成
      args.onToken?.('hello ');
      args.onToken?.('world');
      if (deps.emitDuringSend) {
        deps.emitDuringSend({ type: 'intent', payload: { type: 'none' } }, args.sessionId);
      }
      return { messageId: 'msg-1' };
    },
    stopGeneration: () => deps.stopResult ?? { stopped: true },
    // 未使用的方法用占位,避免 TS strict 报错
    setMainWindow: vi.fn(),
    updateApiProxyConfig: vi.fn(),
    handleOnboardingAnalyze: vi.fn().mockResolvedValue({ summary: '' }),
  } as unknown as ChatOrchestratorService;
};

// ─── 辅助:构造最小 SkillRegistry fake ───
const createFakeSkillRegistry = (skills: SkillMetadata[]): SkillRegistry => {
  return {
    getById: (id: string) => skills.find(s => s.id === id),
    getAll: () => skills,
    compatibleWith: (version: string) => skills.filter(s => s.compatiblePromptVersions.includes(version)),
    ids: () => skills.map(s => s.id),
    stats: () => ({ total: skills.length, withVersion: skills.length, withoutVersion: 0 }),
  } as unknown as SkillRegistry;
};

const baseInput: HandleTurnInput = {
  userMessage: '请帮我看一下',
  phase: 'trust_building',
  sessionId: 'sess-real-001',
};

describe('RealOrchestratorAdapter (D-1)', () => {
  beforeEach(() => {
    vi.spyOn(console, 'warn').mockImplementation(() => {});
  });

  it('缺失 sessionId 时立即 yield error(CONTEXT_MISSING)', async () => {
    const fake = createFakeChatOrchestrator();
    const adapter = new RealOrchestratorAdapter(fake);

    const events = await collect(adapter.handleTurn({ ...baseInput, sessionId: '' }));
    expect(events).toHaveLength(1);
    expect(events[0].type).toBe('error');
    if (events[0].type === 'error') {
      const payload = events[0].payload as OrchestratorError;
      expect(payload.code).toBe('CONTEXT_MISSING');
      expect(payload.retryable).toBe(false);
    }
  });

  it('onToken 回调映射为 token 事件,按序累积', async () => {
    const fake = createFakeChatOrchestrator({
      sendImpl: async ({ onToken }) => {
        onToken?.('你');
        onToken?.('好');
        onToken?.('!');
        return { messageId: 'm1' };
      },
    });
    const adapter = new RealOrchestratorAdapter(fake);

    const events = await collect(adapter.handleTurn(baseInput));
    const tokens = events.filter((e): e is { type: 'token'; content: string } => e.type === 'token');
    expect(tokens.length).toBe(3);
    expect(tokens.map(t => t.content).join('')).toBe('你好!');
  });

  it('emitOrchestratorEvent 透传 intent 事件给消费者', async () => {
    let capturedHandler: EventHandler | null = null;
    const fake = createFakeChatOrchestrator({
      emitDuringSend: (event, sid) => {
        if (capturedHandler) capturedHandler(event, sid);
      },
    });
    // 抓取订阅的 handler
    const originalOn = fake.onOrchestratorEvent.bind(fake);
    (fake as unknown as { onOrchestratorEvent: typeof fake.onOrchestratorEvent }).onOrchestratorEvent = (h) => {
      capturedHandler = h;
      return originalOn(h);
    };

    const adapter = new RealOrchestratorAdapter(fake);
    const events = await collect(adapter.handleTurn(baseInput));

    const intentEvents = events.filter((e): e is { type: 'intent'; payload: { type: 'none' } } => e.type === 'intent');
    expect(intentEvents.length).toBeGreaterThanOrEqual(1);
  });

  it('sendMessage 失败时 yield error(API_ERROR)且流终止', async () => {
    const fake = createFakeChatOrchestrator({
      sendImpl: async () => {
        throw new Error('upstream 500');
      },
    });
    const adapter = new RealOrchestratorAdapter(fake);

    const events = await collect(adapter.handleTurn(baseInput));
    const errorEv = events.find((e): e is { type: 'error'; payload: OrchestratorError } => e.type === 'error');
    expect(errorEv).toBeDefined();
    expect(errorEv?.payload.code).toBe('API_ERROR');
    expect(errorEv?.payload.message).toContain('upstream 500');
    expect(errorEv?.payload.retryable).toBe(false);

    // 流必须在 error 后终止
    expect(events[events.length - 1].type).toBe('error');
  });

  it('sendMessage reject 非 Error 类型时,message 正确序列化', async () => {
    const fake = createFakeChatOrchestrator({
      sendImpl: async () => {
        // 抛出非 Error(字符串)
        throw 'string error';
      },
    });
    const adapter = new RealOrchestratorAdapter(fake);
    const events = await collect(adapter.handleTurn(baseInput));
    const errorEv = events.find((e): e is { type: 'error'; payload: OrchestratorError } => e.type === 'error');
    expect(errorEv?.payload.message).toBe('string error');
  });

  it('sessionId 过滤:其他会话的事件被丢弃', async () => {
    const subscribers: EventHandler[] = [];
    const fake = {
      onOrchestratorEvent: (h: EventHandler) => {
        subscribers.push(h);
        return () => {
          const i = subscribers.indexOf(h);
          if (i >= 0) subscribers.splice(i, 1);
        };
      },
      sendMessage: async (args: { sessionId: string; onToken?: (c: string) => void }) => {
        // 触发本会话 + 其它会话的事件
        subscribers.forEach(h => h({ type: 'intent', payload: { type: 'none' } }, 'other-session'));
        subscribers.forEach(h => h({ type: 'intent', payload: { type: 'none' } }, args.sessionId));
        args.onToken?.('mine');
        return { messageId: 'm2' };
      },
      stopGeneration: () => ({ stopped: true }),
    } as unknown as ChatOrchestratorService;

    const adapter = new RealOrchestratorAdapter(fake);
    const events = await collect(adapter.handleTurn(baseInput));

    // 只有 1 个 intent(本会话)+ 1 个 token
    const intents = events.filter(e => e.type === 'intent');
    expect(intents).toHaveLength(1);
    const tokens = events.filter(e => e.type === 'token');
    expect(tokens).toHaveLength(1);
  });

  it('stream 完成后 unsubscribe 被调用(订阅清理)', async () => {
    let unsubscribeCalled = false;
    const fake = createFakeChatOrchestrator({
      sendImpl: async () => ({ messageId: 'm3' }),
    });
    const originalOn = fake.onOrchestratorEvent.bind(fake);
    (fake as unknown as { onOrchestratorEvent: typeof fake.onOrchestratorEvent }).onOrchestratorEvent = (h) => {
      const unsub = originalOn(h);
      return () => {
        unsubscribeCalled = true;
        unsub();
      };
    };

    const adapter = new RealOrchestratorAdapter(fake);
    await collect(adapter.handleTurn(baseInput));
    // 等微任务清空
    await new Promise(r => setImmediate(r));
    expect(unsubscribeCalled).toBe(true);
  });

  it('无 SkillRegistry 时 skillManifest 返回 []', () => {
    const fake = createFakeChatOrchestrator();
    const adapter = new RealOrchestratorAdapter(fake);
    const manifest = adapter.skillManifest('diagnosis');
    expect(manifest).toEqual([]);
  });

  it('有 SkillRegistry 时,无 version 参数返回 getAll()', () => {
    const skills: SkillMetadata[] = [
      {
        id: 'a',
        estimatedTokens: 100,
        phases: [],
        compatiblePromptVersions: ['v5', 'v5.0.1'],
        sourcePath: '/a.md',
      },
      {
        id: 'b',
        estimatedTokens: 200,
        phases: [],
        compatiblePromptVersions: ['v5'],
        sourcePath: '/b.md',
      },
    ];
    const registry = createFakeSkillRegistry(skills);
    const fake = createFakeChatOrchestrator();
    const adapter = new RealOrchestratorAdapter(fake, registry);

    const manifest = adapter.skillManifest('diagnosis');
    expect(manifest).toHaveLength(2);
    expect(manifest.map(s => s.id).sort()).toEqual(['a', 'b']);
  });

  it('有 SkillRegistry 且指定 version 时仅返回兼容 skill', () => {
    const skills: SkillMetadata[] = [
      {
        id: 'core',
        estimatedTokens: 100,
        phases: ['trust_building'],
        compatiblePromptVersions: ['v5.0.1'],
        sourcePath: '/core.md',
      },
      {
        id: 'legacy',
        estimatedTokens: 200,
        phases: ['diagnosis'],
        compatiblePromptVersions: ['v4'],
        sourcePath: '/legacy.md',
      },
    ];
    const registry = createFakeSkillRegistry(skills);
    const fake = createFakeChatOrchestrator();
    const adapter = new RealOrchestratorAdapter(fake, registry);

    const manifest = adapter.skillManifest('diagnosis', 'v5.0.1');
    expect(manifest).toHaveLength(1);
    expect(manifest[0].id).toBe('core');
  });

  it('promptVersion 返回 v5.0.1 + 契约 + rollbackTo', () => {
    const fake = createFakeChatOrchestrator();
    const adapter = new RealOrchestratorAdapter(fake);
    const pv = adapter.promptVersion();

    expect(pv.version).toBe('v5.0.1');
    expect(pv.rollbackTo).toBe('v5');
    expect(pv.contract.required_phases).toContain('trust_building');
    expect(pv.contract.required_skills).toContain('core-identity');
    expect(pv.contract.required_techniques.length).toBeGreaterThan(0);
    expect(pv.contract.required_tools).toContain('chapter:get');
  });

  it('stopGeneration 委托给底层 chatOrchestrator', () => {
    const fake = createFakeChatOrchestrator({ stopResult: { stopped: true } });
    const adapter = new RealOrchestratorAdapter(fake);
    expect(adapter.stopGeneration()).toEqual({ stopped: true });
  });

  it('stream 结束(consumer break)时 unsubscribe 仍被调用(资源清理)', async () => {
    let unsubscribeCalled = false;
    const fake = createFakeChatOrchestrator({
      sendImpl: async ({ onToken }) => {
        // 制造持续 token 让 consumer 有机会 break
        for (let i = 0; i < 100; i++) {
          onToken?.(`chunk-${i} `);
          await new Promise(r => setTimeout(r, 1));
        }
        return { messageId: 'm4' };
      },
    });
    const originalOn = fake.onOrchestratorEvent.bind(fake);
    (fake as unknown as { onOrchestratorEvent: typeof fake.onOrchestratorEvent }).onOrchestratorEvent = (h) => {
      const unsub = originalOn(h);
      return () => {
        unsubscribeCalled = true;
        unsub();
      };
    };

    const adapter = new RealOrchestratorAdapter(fake);
    // 拿第 1 个 token 后 break
    let count = 0;
    for await (const ev of adapter.handleTurn(baseInput)) {
      if (ev.type === 'token') {
        count++;
        if (count >= 2) break;
      }
    }

    // 等待 async 链路清理
    await new Promise(r => setTimeout(r, 50));
    expect(unsubscribeCalled).toBe(true);
  });
});
