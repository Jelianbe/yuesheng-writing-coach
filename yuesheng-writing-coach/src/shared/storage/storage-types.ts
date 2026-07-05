/**
 * 存储层共享类型 — Sprint 26
 *
 * 通用类型定义,被 storage-adapter.ts 及各 Adapter 实现引用。
 *
 * 依据: dev-docs/tasks/sprint-26-android-pivot.md §1.2
 * 决策: D-074
 */

/** 数据库单行(无类型约束,由泛型 T 精确化) */
export type DatabaseRow = Record<string, unknown>;

/**
 * SQL 查询参数
 * - 基础类型: string | number | null | boolean
 * - 大整数: bigint(避免精度丢失,SQLite 支持 INTEGER)
 * - Buffer: 二进制(BLOB)
 * - Date: 序列化为 ISO 字符串(由各 Adapter 决定)
 */
export type QueryParam =
  | string
  | number
  | bigint
  | boolean
  | null
  | Buffer
  | Date
  | Uint8Array;

/** 适配器类型标识(用于 createStorageAdapter 工厂) */
export type StorageAdapterType =
  | 'better-sqlite3' // Windows / Electron
  | 'capacitor-sqlite' // Android / Capacitor
  | 'memory'; // 测试用

/** 初始化配置(各 Adapter 共享字段) */
export interface StorageInitConfig {
  /** 数据库文件名(无路径,如 'app.db') */
  dbName: string;
  /** schema 版本号(用于未来 migration) */
  version: number;
  /** 是否加密(SQLCipher,本轮不实现) */
  encrypted?: boolean;
}
