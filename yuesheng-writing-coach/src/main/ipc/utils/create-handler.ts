/**
 * 统一 IPC handler 工厂函数
 *
 * 功能：
 * - 自动包裹 try-catch
 * - 标准化返回值格式 { success, data, error }
 * - 统一错误序列化
 * - **幂等键支持**（IDEM-1）：若请求包含 `idempotencyKey`，在 TTL 内自动去重
 *
 * 使用方式：
 *   createHandler('channel:name', async (event, args) => {
 *     const result = await service.method(args);
 *     return result;
 *   });
 *
 * handler 只需返回纯数据，不需要手动包裹 apiSuccess/apiError。
 * 验证失败时 throw new Error() 即可。
 *
 * 幂等用法（前端）：
 *   await invoke('channel:set', { ..., idempotencyKey: 'uuid-or-tx-id' });
 *   同一 key 在 5 秒内的重复请求自动返回缓存结果。
 */

import type { IpcMainInvokeEvent } from 'electron';
import { ipcMain } from 'electron';

/** 幂等缓存条目 */
interface IdempotencyEntry {
  result: HandlerResult<unknown>;
  timestamp: number;
}

type HandlerFn<TReq, TRes> = (event: IpcMainInvokeEvent, request: TReq) => Promise<TRes> | TRes;

interface HandlerResult<T> {
  success: boolean;
  data?: T;
  error?: string;
}

// ── 幂等缓存（IDEM-1） ──

const IDEMPOTENCY_CACHE = new Map<string, IdempotencyEntry>();
const IDEMPOTENCY_TTL = 5_000;       // 5 秒 TTL
const IDEMPOTENCY_MAX_SIZE = 200;    // 最大缓存条目数

/** 从请求中提取 idempotencyKey（若存在） */
function extractIdempotencyKey(request: unknown): string | null {
  if (request && typeof request === 'object' && !Array.isArray(request)) {
    const val = (request as Record<string, unknown>).idempotencyKey;
    return typeof val === 'string' && val.length > 0 ? val : null;
  }
  return null;
}

/** 清理过期缓存 */
function purgeExpiredEntries(): void {
  const now = Date.now();
  for (const [key, entry] of IDEMPOTENCY_CACHE) {
    if (now - entry.timestamp > IDEMPOTENCY_TTL) {
      IDEMPOTENCY_CACHE.delete(key);
    }
  }
}

/** 写入幂等缓存，超限时淘汰最旧的 10% */
function setIdempotencyCache(key: string, result: HandlerResult<unknown>): void {
  // 惰性清理过期条目
  if (IDEMPOTENCY_CACHE.size >= IDEMPOTENCY_MAX_SIZE) {
    purgeExpiredEntries();
  }
  // 仍然超过上限则强制淘汰
  if (IDEMPOTENCY_CACHE.size >= IDEMPOTENCY_MAX_SIZE) {
    const keysToDelete: string[] = [];
    const iter = IDEMPOTENCY_CACHE.keys();
    for (let i = 0; i < Math.ceil(IDEMPOTENCY_MAX_SIZE * 0.1); i++) {
      const k = iter.next().value;
      if (k !== undefined) keysToDelete.push(k);
    }
    for (const k of keysToDelete) IDEMPOTENCY_CACHE.delete(k);
  }
  IDEMPOTENCY_CACHE.set(key, { result, timestamp: Date.now() });
}

// ── createHandler ──

/**
 * 统一 IPC handler 工厂函数
 * - 自动包裹 try-catch
 * - 标准化返回值格式 { success, data, error }
 * - 幂等键支持：请求携带 idempotencyKey 则在 TTL 内去重
 */
export function createHandler<TReq = unknown, TRes = unknown>(
  channel: string,
  handler: HandlerFn<TReq, TRes>,
): void {
  ipcMain.handle(channel, async (event, request: TReq): Promise<HandlerResult<TRes>> => {
    // 幂等键检查（IDEM-1）
    const idempotencyKey = extractIdempotencyKey(request);
    if (idempotencyKey) {
      const cached = IDEMPOTENCY_CACHE.get(idempotencyKey);
      if (cached && Date.now() - cached.timestamp < IDEMPOTENCY_TTL) {
        return cached.result as HandlerResult<TRes>;
      }
    }

    try {
      const data = await handler(event, request);
      const result: HandlerResult<TRes> = { success: true, data };

      // 缓存幂等结果
      if (idempotencyKey) {
        setIdempotencyCache(idempotencyKey, result);
      }

      return result;
    } catch (error) {
      const isDev = process.env.NODE_ENV === 'development';
      const message = error instanceof Error ? error.message : String(error);
      if (isDev) {
        console.error(`[IPC] ${channel} error:`, error);
      } else {
        console.error(`[IPC] ${channel} error: ${message}`);
      }
      return { success: false, error: message };
    }
  });
}
