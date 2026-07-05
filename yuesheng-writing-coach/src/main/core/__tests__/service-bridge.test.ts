/**
 * ServiceBridge (main) 单测 — Sprint 29
 *
 * 覆盖:
 * 1. registerMethod / registerMethods / unregisterMethod / clearRegistry
 * 2. handleBridgeInvoke 成功 / 多参 / 异步 handler
 * 3. 白名单安全:未注册 method 拒绝 / handler 异常透传
 * 4. getRegisteredMethods / isMethodRegistered 查询
 *
 * 依据: dev-docs/tasks/sprint-29-plan.md §阶段 1
 */

import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import {
  registerMethod,
  registerMethods,
  unregisterMethod,
  clearRegistry,
  getRegisteredMethods,
  isMethodRegistered,
  handleBridgeInvoke,
  _getRegistryForTest,
} from '../service-bridge';

describe('ServiceBridge (main)', () => {
  beforeEach(() => {
    clearRegistry();
  });

  afterEach(() => {
    clearRegistry();
  });

  // ─── 注册 ───

  describe('registerMethod', () => {
    it('注册后可通过 handleBridgeInvoke 调用', async () => {
      const handler = vi.fn().mockResolvedValue('ok');
      registerMethod('test:ping', handler);

      const result = await handleBridgeInvoke({ method: 'test:ping', args: null });
      expect(result).toBe('ok');
      expect(handler).toHaveBeenCalledWith(null);
    });

    it('重复注册覆盖已有 handler', async () => {
      registerMethod('test:dup', vi.fn().mockResolvedValue('old'));
      registerMethod('test:dup', vi.fn().mockResolvedValue('new'));

      const result = await handleBridgeInvoke({ method: 'test:dup', args: null });
      expect(result).toBe('new');
    });
  });

  describe('registerMethods', () => {
    it('批量注册所有方法', async () => {
      registerMethods([
        { method: 'a:one', handler: vi.fn().mockResolvedValue(1) },
        { method: 'b:two', handler: vi.fn().mockResolvedValue(2) },
      ]);

      expect(await handleBridgeInvoke({ method: 'a:one', args: null })).toBe(1);
      expect(await handleBridgeInvoke({ method: 'b:two', args: null })).toBe(2);
    });
  });

  // ─── 调用 ───

  describe('handleBridgeInvoke', () => {
    it('多参数正确透传', async () => {
      const handler = vi.fn().mockResolvedValue('ok');
      registerMethod('test:withArgs', handler);

      await handleBridgeInvoke({ method: 'test:withArgs', args: { a: 1, b: 'x' } });
      expect(handler).toHaveBeenCalledWith({ a: 1, b: 'x' });
    });

    it('支持异步 handler', async () => {
      registerMethod('test:async', async (args) => {
        return `hello ${args as string}`;
      });

      const result = await handleBridgeInvoke({ method: 'test:async', args: 'world' });
      expect(result).toBe('hello world');
    });
  });

  // ─── 安全 ───

  describe('安全边界', () => {
    it('未注册 method 抛 MethodNotRegisteredError', async () => {
      await expect(
        handleBridgeInvoke({ method: 'never:registered', args: null }),
      ).rejects.toThrow('METHOD_NOT_REGISTERED');
    });

    it('handler 抛错时异常透传', async () => {
      registerMethod('test:fail', async () => {
        throw new Error('handler exploded');
      });

      await expect(
        handleBridgeInvoke({ method: 'test:fail', args: null }),
      ).rejects.toThrow('handler exploded');
    });

    it('空请求抛 InvalidRequestError', async () => {
      await expect(
        handleBridgeInvoke(null as unknown as never),
      ).rejects.toThrow('INVALID_REQUEST');
    });

    it('method 非字符串抛 InvalidRequestError', async () => {
      await expect(
        handleBridgeInvoke({ method: 123, args: null } as unknown as never),
      ).rejects.toThrow('INVALID_REQUEST');
    });
  });

  // ─── 管理 ───

  describe('注册管理', () => {
    it('unregisterMethod 移除后不可调用', async () => {
      registerMethod('test:temp', vi.fn().mockResolvedValue('ok'));
      expect(isMethodRegistered('test:temp')).toBe(true);

      unregisterMethod('test:temp');
      expect(isMethodRegistered('test:temp')).toBe(false);
      await expect(
        handleBridgeInvoke({ method: 'test:temp', args: null }),
      ).rejects.toThrow('METHOD_NOT_REGISTERED');
    });

    it('clearRegistry 清空后全不可用', async () => {
      registerMethods([
        { method: 'x:one', handler: vi.fn() },
        { method: 'y:two', handler: vi.fn() },
      ]);
      expect(getRegisteredMethods()).toHaveLength(2);

      clearRegistry();
      expect(getRegisteredMethods()).toHaveLength(0);
    });

    it('isMethodRegistered 正确返回状态', () => {
      expect(isMethodRegistered('not:there')).toBe(false);
      registerMethod('exists:yes', vi.fn());
      expect(isMethodRegistered('exists:yes')).toBe(true);
    });

    it('getRegisteredMethods 返回排序列表', () => {
      registerMethods([
        { method: 'z:last', handler: vi.fn() },
        { method: 'a:first', handler: vi.fn() },
      ]);
      expect(getRegisteredMethods()).toEqual(['a:first', 'z:last']);
    });

    it('_getRegistryForTest 返回注册表快照', () => {
      registerMethod('test:snap', vi.fn().mockResolvedValue('data'));
      const registry = _getRegistryForTest();
      expect(registry.has('test:snap')).toBe(true);
      // 修改快照不应影响原始注册表
      (registry as Map<string, never>).clear();
      expect(isMethodRegistered('test:snap')).toBe(true);
    });
  });
});
