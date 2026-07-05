/**
 * ChatHandleTurnBridge 单测 — Sprint 20 A-4
 *
 * 验证:
 * 1. startTurn 返回 streamId
 * 2. MockConversationOrchestrator 事件流被正确推送
 * 3. token / done 事件按序到达
 * 4. stopAll 终止活跃流
 * 5. webContents 为 null / destroyed 时不抛异常
 */

import { describe, it, expect, vi, beforeEach } from 'vitest';
import { ChatHandleTurnBridge } from '../chat-handle-turn.bridge';
import { MockConversationOrchestrator } from '../mock-orchestrator';
import type { WebContents } from 'electron';

const makeFakeWebContents = (): WebContents => {
  const sendFn = vi.fn();
  return {
    isDestroyed: vi.fn().mockReturnValue(false),
    send: sendFn,
  } as unknown as WebContents;
};

const collectSendEvents = (wc: WebContents) => {
  const calls = vi.mocked(wc.send).mock.calls;
  return calls.map(([channel, payload]) => ({ channel, payload: payload as { streamId: string; sessionId: string; event: unknown } }));
};

describe('ChatHandleTurnBridge (A-4)', () => {
  let orchestrator: MockConversationOrchestrator;
  let bridge: ChatHandleTurnBridge;

  beforeEach(() => {
    orchestrator = new MockConversationOrchestrator();
    bridge = new ChatHandleTurnBridge(orchestrator);
  });

  it('startTurn 返回 streamId 并推至少 1 个 chat:event', async () => {
    const wc = makeFakeWebContents();
    const { streamId } = await bridge.startTurn(wc, {
      userMessage: 'hello',
      sessionId: 'sess-1',
      phase: 'requirement',
    });
    expect(typeof streamId).toBe('string');
    expect(streamId.length).toBeGreaterThan(0);

    // 等异步消费跑完
    await new Promise(r => setTimeout(r, 50));

    const events = collectSendEvents(wc).filter(e => e.channel === 'chat:event');
    expect(events.length).toBeGreaterThan(0);
    expect(events[0].payload.streamId).toBe(streamId);
    expect(events[0].payload.sessionId).toBe('sess-1');
  });

  it('推送的 token 事件按序累积', async () => {
    const wc = makeFakeWebContents();
    await bridge.startTurn(wc, {
      userMessage: '你好',
      sessionId: 'sess-2',
      phase: 'trust_building',
    });
    await new Promise(r => setTimeout(r, 50));

    const events = collectSendEvents(wc).filter(e => e.channel === 'chat:event');
    const tokens = events
      .map(e => e.payload.event)
      .filter((e): e is { type: 'token'; content: string } =>
        typeof e === 'object' && e !== null && (e as { type?: string }).type === 'token',
      );

    // MockConversationOrchestrator 至少 yield 3 个 token
    expect(tokens.length).toBeGreaterThanOrEqual(3);
    const reconstructed = tokens.map(t => t.content).join('');
    expect(reconstructed).toBe('我看到了你的消息。');
  });

  it('done 事件为流末尾', async () => {
    const wc = makeFakeWebContents();
    await bridge.startTurn(wc, {
      userMessage: 'hi',
      sessionId: 'sess-3',
      phase: 'requirement',
    });
    await new Promise(r => setTimeout(r, 50));

    const events = collectSendEvents(wc).filter(e => e.channel === 'chat:event');
    const last = events[events.length - 1].payload.event as { type: string };
    expect(last.type).toBe('done');
  });

  it('stopAll 终止活跃流并清空 activeStreamIds', async () => {
    const wc = makeFakeWebContents();
    await bridge.startTurn(wc, { userMessage: 'a', sessionId: 's1', phase: 'requirement' });
    await bridge.startTurn(wc, { userMessage: 'b', sessionId: 's2', phase: 'requirement' });
    expect(bridge.activeStreamCount).toBe(2);

    const result = bridge.stopAll();
    expect(result.stopped).toBe(2);
    expect(bridge.activeStreamCount).toBe(0);
  });

  it('webContents 为 null 时不抛异常', async () => {
    const { streamId } = await bridge.startTurn(null, {
      userMessage: 'noop',
      sessionId: 'sess-null',
      phase: 'requirement',
    });
    expect(typeof streamId).toBe('string');
    // 等异步消费
    await new Promise(r => setTimeout(r, 50));
    expect(bridge.activeStreamCount).toBe(0);
  });

  it('webContents.isDestroyed() 为 true 时跳过 emit', async () => {
    const sendFn = vi.fn();
    const wc = {
      isDestroyed: vi.fn().mockReturnValue(true),
      send: sendFn,
    } as unknown as WebContents;
    await bridge.startTurn(wc, { userMessage: 'destroyed', sessionId: 's', phase: 'requirement' });
    await new Promise(r => setTimeout(r, 50));
    expect(sendFn).not.toHaveBeenCalled();
  });

  it('注入 orchestrator 后通过 getOrchestrator 暴露', () => {
    const bridgeWithInject = new ChatHandleTurnBridge(orchestrator);
    expect(bridgeWithInject.getOrchestrator()).toBe(orchestrator);
  });
});
