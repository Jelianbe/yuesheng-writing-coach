/**
 * EventBus 单测(Sprint 20 Issue 20-1 B-1)
 *
 * 验证:订阅/取消订阅/emit/emitAndWait/异常隔离/类型守卫
 */

import { describe, it, expect, beforeEach } from 'vitest';
import { EventBus, getGlobalEventBus, resetGlobalEventBus } from '../event-bus.service';

describe('EventBus (B-1)', () => {
  let bus: EventBus;

  beforeEach(() => {
    bus = new EventBus();
  });

  it('on() 注册订阅,emit() 触发 handler', () => {
    const received: string[] = [];
    bus.on('chat:token', (p) => { received.push(p.content); });
    bus.emit({ topic: 'chat:token', payload: { sessionId: 's1', content: 'hello' } });
    expect(received).toEqual(['hello']);
  });

  it('on() 返回的 unsubscribe 函数能取消订阅', () => {
    const received: string[] = [];
    const off = bus.on('chat:token', (p) => { received.push(p.content); });
    bus.emit({ topic: 'chat:token', payload: { sessionId: 's1', content: 'a' } });
    off();
    bus.emit({ topic: 'chat:token', payload: { sessionId: 's1', content: 'b' } });
    expect(received).toEqual(['a']);
  });

  it('同一 topic 多个订阅者都会被触发', () => {
    const a: string[] = [];
    const b: string[] = [];
    bus.on('chat:token', (p) => { a.push(p.content); });
    bus.on('chat:token', (p) => { b.push(p.content); });
    bus.emit({ topic: 'chat:token', payload: { sessionId: 's1', content: 'x' } });
    expect(a).toEqual(['x']);
    expect(b).toEqual(['x']);
  });

  it('handler 抛错不阻断其他订阅者', () => {
    const a: string[] = [];
    bus.on('chat:token', () => { throw new Error('boom'); });
    bus.on('chat:token', (p) => { a.push(p.content); });
    const origErr = console.error;
    console.error = () => {};
    try {
      bus.emit({ topic: 'chat:token', payload: { sessionId: 's1', content: 'ok' } });
    } finally {
      console.error = origErr;
    }
    expect(a).toEqual(['ok']);
  });

  it('emitAndWait 等待所有 async handler', async () => {
    const order: string[] = [];
    bus.on('training:triggered', async () => {
      await new Promise(r => setTimeout(r, 10));
      order.push('a');
    });
    bus.on('training:triggered', () => { order.push('b'); });
    await bus.emitAndWait({ topic: 'training:triggered', payload: { sessionId: 's1', syndromeId: 'P001' } });
    expect(order).toContain('a');
    expect(order).toContain('b');
  });

  it('removeAllListeners(topic) 只清空指定 topic', () => {
    let aCount = 0;
    let bCount = 0;
    bus.on('chat:token', () => { aCount++; });
    bus.on('chat:done', () => { bCount++; });
    bus.removeAllListeners('chat:token');
    bus.emit({ topic: 'chat:token', payload: { sessionId: 's1', content: 'x' } });
    bus.emit({ topic: 'chat:done', payload: { sessionId: 's1' } });
    expect(aCount).toBe(0);
    expect(bCount).toBe(1);
  });

  it('emittedLog 记录所有 emit 过的事件(测试可观测性)', () => {
    bus.emit({ topic: 'chat:token', payload: { sessionId: 's1', content: '1' } });
    bus.emit({ topic: 'chat:done', payload: { sessionId: 's1' } });
    expect(bus.emittedLog).toHaveLength(2);
    expect(bus.emittedLog[0].topic).toBe('chat:token');
  });

  it('getGlobalEventBus 单例 + resetGlobalEventBus', () => {
    const a = getGlobalEventBus();
    const b = getGlobalEventBus();
    expect(a).toBe(b);
    resetGlobalEventBus();
    const c = getGlobalEventBus();
    expect(c).not.toBe(a);
  });
});
