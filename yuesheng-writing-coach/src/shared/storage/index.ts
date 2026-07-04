/**
 * StorageAdapter 工厂 — Sprint 26
 *
 * 根据平台/环境选择合适的 Adapter 实现:
 *   - 'better-sqlite3': Windows / Electron(默认)
 *   - 'capacitor-sqlite': Android / Capacitor
 *   - 'memory': 测试 / 阶段 1 PoC
 *
 * 用法:
 * ```typescript
 * import { createStorageAdapter } from '@/shared/storage';
 *
 * const adapter = createStorageAdapter('memory');  // 测试
 * await adapter.initialize();
 * ```
 *
 * 依据: dev-docs/tasks/sprint-26-android-pivot.md §1.2
 * 决策: D-074
 */
import { BetterSqliteAdapter } from './adapters/better-sqlite.adapter';
import { CapacitorSqliteAdapter } from './adapters/capacitor-sqlite.adapter';
import { MemoryAdapter } from './adapters/memory.adapter';
import type { StorageAdapter } from './storage-adapter';
import type { StorageAdapterType, StorageInitConfig } from './storage-types';

export interface CreateStorageAdapterOptions extends StorageInitConfig {
  /** 显式指定 adapter 类型(若不指定,自动检测) */
  type?: StorageAdapterType;
  /** better-sqlite3 数据库实例(type='better-sqlite3' 时必填) */
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  betterSqliteDb?: any;
}

/**
 * 自动检测当前环境的 adapter 类型
 * - Capacitor 环境: 'capacitor-sqlite'
 * - Electron / Node.js: 'better-sqlite3'
 * - 测试 / PoC: 'memory'(默认 fallback)
 */
export function detectStorageAdapterType(): StorageAdapterType {
  // Capacitor 检测
  if (typeof window !== 'undefined' && (window as { Capacitor?: unknown }).Capacitor) {
    return 'capacitor-sqlite';
  }
  // 默认 Electron / Node
  return 'better-sqlite3';
}

export function createStorageAdapter(
  typeOrOptions: StorageAdapterType | CreateStorageAdapterOptions,
): StorageAdapter {
  const options: CreateStorageAdapterOptions =
    typeof typeOrOptions === 'string'
      ? { type: typeOrOptions, dbName: 'app.db', version: 1 }
      : typeOrOptions;

  const type = options.type ?? detectStorageAdapterType();

  switch (type) {
    case 'better-sqlite3':
      if (!options.betterSqliteDb) {
        throw new Error(
          'createStorageAdapter: betterSqliteDb is required for type=better-sqlite3',
        );
      }
      return new BetterSqliteAdapter({
        db: options.betterSqliteDb,
        dbName: options.dbName,
        version: options.version,
        encrypted: options.encrypted,
      });

    case 'capacitor-sqlite':
      return new CapacitorSqliteAdapter({
        dbName: options.dbName,
        version: options.version,
        encrypted: options.encrypted,
      });

    case 'memory':
      return new MemoryAdapter();

    default: {
      const _exhaustive: never = type;
      throw new Error(`Unknown adapter type: ${String(_exhaustive)}`);
    }
  }
}

export type { StorageAdapter, TransactionContext, ExecuteResult } from './storage-adapter';
export { StorageError } from './storage-adapter';
export type {
  DatabaseRow,
  QueryParam,
  StorageAdapterType,
  StorageInitConfig,
} from './storage-types';
