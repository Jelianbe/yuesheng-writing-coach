/**
 * Payload Sanitizer — IPC 载荷脱敏服务 (Sprint 21 E-1)
 *
 * 职责:
 * - 读取 resources/config/payload-sanitize-whitelist.json
 * - 在 IPC handler returnValue 前对 payload 应用白名单动作
 * - 支持 5 种动作: redact / truncate / hash / mask / omit
 *
 * 5 动作语义:
 * - redact:  替换为 '[REDACTED]'
 * - truncate: 截断到 maxChars(默认 80),附加 '...'
 * - hash:    SHA-256 哈希(取前 8 位 hex,无碰撞风险可控)
 * - mask:    保留首尾 1 字符,中间替换为 '*'(最少 2 字符)
 * - omit:    从对象中删除字段
 *
 * 异常隔离:
 * - 任何错误(配置缺失/字段类型异常/JSON 解析失败)→ 返回原 payload(不阻塞主流程)
 * - 命中计数埋点: 内部 hitCount + byAction,调用方可通过 stats() 查询
 *
 * 性能:
 * - 配置加载在构造时完成(单次 IO),后续 sanitize() 同步处理
 * - 字段路径用 '.' 分隔,支持 'evidence.feedback' 嵌套访问
 *
 * 依据: dev-docs/tasks/sprint-21-plan.md §E-1
 */

import * as fs from 'node:fs';
import * as path from 'node:path';
import * as crypto from 'node:crypto';

export type SanitizeAction = 'redact' | 'truncate' | 'hash' | 'mask' | 'omit' | 'truncate-nested';

/** 字段级动作规则(支持嵌套路径) */
export type FieldRule = SanitizeAction | { action: SanitizeAction; maxChars?: number };

/** 单 service 配置 */
export interface ServiceSanitizeConfig {
  enabled: boolean;
  fields: Record<string, FieldRule>;
}

/** 白名单整体结构 */
export interface SanitizeWhitelist {
  version: string;
  truncate?: { defaultMaxChars?: number };
  services: Record<string, ServiceSanitizeConfig>;
}

/** 命中统计 */
export interface SanitizeStats {
  total: number;
  byAction: Record<SanitizeAction, number>;
  errors: number;
}

const REDACTED = '[REDACTED]';
const DEFAULT_TRUNCATE_MAX = 80;

const ZERO_STATS: SanitizeStats = {
  total: 0,
  byAction: { redact: 0, truncate: 0, hash: 0, mask: 0, omit: 0, 'truncate-nested': 0 },
  errors: 0,
};

/** 简易配置加载(JSON.parse,失败抛错) */
function loadWhitelist(configPath: string): SanitizeWhitelist {
  const raw = fs.readFileSync(configPath, 'utf-8');
  const parsed = JSON.parse(raw) as SanitizeWhitelist;
  if (!parsed.services || typeof parsed.services !== 'object') {
    throw new Error('[PayloadSanitizer] Invalid whitelist: services not found');
  }
  return parsed;
}

/**
 * 解析字段规则(支持 string 简写或对象形式)
 */
function normalizeRule(rule: FieldRule): { action: SanitizeAction; maxChars?: number } {
  if (typeof rule === 'string') {
    return { action: rule };
  }
  return { action: rule.action, maxChars: rule.maxChars };
}

/** 按路径读取嵌套字段(点分隔) */
function getByPath(obj: unknown, path: string): unknown {
  if (obj === null || obj === undefined) return undefined;
  const parts = path.split('.');
  let cur: unknown = obj;
  for (const p of parts) {
    if (cur === null || cur === undefined || typeof cur !== 'object') return undefined;
    cur = (cur as Record<string, unknown>)[p];
  }
  return cur;
}

/** 按路径写入嵌套字段(返回新对象,不修改原对象) */
function setByPath(obj: unknown, path: string, value: unknown): unknown {
  if (obj === null || obj === undefined) obj = {};
  const parts = path.split('.');
  if (parts.length === 0) return obj;

  // 浅克隆路径上每一层
  const root = Array.isArray(obj) ? [...obj] : { ...(obj as Record<string, unknown>) };
  let cur: Record<string, unknown> = root as Record<string, unknown>;
  for (let i = 0; i < parts.length - 1; i++) {
    const key = parts[i];
    const next = cur[key];
    if (next === null || next === undefined || typeof next !== 'object') {
      cur[key] = {};
    } else {
      cur[key] = Array.isArray(next) ? [...next] : { ...(next as Record<string, unknown>) };
    }
    cur = cur[key] as Record<string, unknown>;
  }
  cur[parts[parts.length - 1]] = value;
  return root;
}

/** 移除路径上的字段(返回新对象) */
function unsetByPath(obj: unknown, path: string): unknown {
  if (obj === null || obj === undefined) return obj;
  const parts = path.split('.');
  if (parts.length === 0) return obj;
  const root = Array.isArray(obj) ? [...obj] : { ...(obj as Record<string, unknown>) };
  let cur: Record<string, unknown> = root as Record<string, unknown>;
  for (let i = 0; i < parts.length - 1; i++) {
    const key = parts[i];
    const next = cur[key];
    if (next === null || next === undefined || typeof next !== 'object') return root;
    cur[key] = Array.isArray(next) ? [...next] : { ...(next as Record<string, unknown>) };
    cur = cur[key] as Record<string, unknown>;
  }
  delete cur[parts[parts.length - 1]];
  return root;
}

/** 截断字符串(非字符串原样返回) */
function truncateString(value: unknown, maxChars: number): string {
  if (typeof value !== 'string') return String(REDACTED);
  if (value.length <= maxChars) return value;
  return value.slice(0, maxChars) + '...';
}

/** SHA-256 哈希(取前 8 位) */
function hashValue(value: unknown): string {
  if (value === null || value === undefined) return REDACTED;
  const str = typeof value === 'string' ? value : JSON.stringify(value);
  return crypto.createHash('sha256').update(str).digest('hex').slice(0, 8);
}

/** 掩码(保留首尾 1 字符) */
function maskValue(value: unknown): string {
  if (typeof value !== 'string') return REDACTED;
  if (value.length <= 2) return '*'.repeat(value.length);
  return value[0] + '*'.repeat(Math.max(value.length - 2, 1)) + value[value.length - 1];
}

/** 截断嵌套数组字段(支持 2 种路径格式,与 contract.sensitiveFields 约定一致)
 *  - 'X' 单层:obj 本身是数组,对每个元素的 X 字段 truncate
 *  - 'X.Y' 双层:obj.X 是数组,对每个元素的 Y 字段 truncate
 *  注:ActiveProblem.evidence 是 string[],不是嵌套对象。
 *  truncate-nested 动作对每个元素 → 子字段是 string[] 时,truncate 每个字符串
 */
function truncateNestedByPath(obj: unknown, fieldPath: string, maxChars: number): unknown {
  const parts = fieldPath.split('.');
  if (parts.length === 0) return obj;

  let arr: unknown;
  let childKey: string;
  let parentPath: string | null = null;

  if (parts.length === 1) {
    // 单层:obj 本身是数组
    if (!Array.isArray(obj)) return obj;
    arr = obj;
    childKey = parts[0];
  } else {
    // 双层:obj.X 是数组
    parentPath = parts.slice(0, -1).join('.');
    childKey = parts[parts.length - 1];
    arr = getByPath(obj, parentPath);
    if (!Array.isArray(arr)) return obj;
  }

  const newArr = (arr as unknown[]).map((item: unknown) => {
    if (item === null || item === undefined || typeof item !== 'object') return item;
    const out: Record<string, unknown> = { ...(item as Record<string, unknown>) };
    if (Array.isArray(out[childKey])) {
      out[childKey] = (out[childKey] as unknown[]).map((ev: unknown) =>
        typeof ev === 'string' ? truncateString(ev, maxChars) : ev,
      );
    }
    return out;
  });

  if (parentPath === null) {
    return newArr;
  }
  return setByPath(obj, parentPath, newArr);
}

/**
 * Payload Sanitizer 服务
 */
export class PayloadSanitizer {
  private readonly whitelist: SanitizeWhitelist;
  private readonly defaultMaxChars: number;
  private hitCount: number = 0;
  private errorCount: number = 0;
  private readonly hitsByAction: Record<SanitizeAction, number> = {
    redact: 0,
    truncate: 0,
    hash: 0,
    mask: 0,
    omit: 0,
    'truncate-nested': 0,
  };

  constructor(configPath: string) {
    try {
      this.whitelist = loadWhitelist(configPath);
      this.defaultMaxChars = this.whitelist.truncate?.defaultMaxChars ?? DEFAULT_TRUNCATE_MAX;
    } catch (e) {
      console.warn('[PayloadSanitizer] failed to load whitelist, using empty:', e);
      this.whitelist = { version: '0', services: {} };
      this.defaultMaxChars = DEFAULT_TRUNCATE_MAX;
    }
  }

  /**
   * 对 payload 应用脱敏
   * - 返回新对象(不修改原 payload)
   * - 任何内部错误 → 返回原 payload(降级不阻塞)
   * - 未知 service 或 disabled service → 返回原 payload
   */
  sanitize(service: string, payload: unknown): unknown {
    try {
      const config = this.whitelist.services[service];
      if (!config || !config.enabled) {
        return payload;
      }

      let out = payload;
      for (const [fieldPath, rule] of Object.entries(config.fields)) {
        const { action, maxChars } = normalizeRule(rule);
        const effMax = maxChars ?? this.defaultMaxChars;

        // truncate-nested: 支持 'X' 和 'X.Y' 两种路径
        // 'X' 单层: payload 本身是数组(诊断 DIAGNOSIS_QUERY 返回 activeProblems[])
        // 'X.Y' 双层: payload.X 是数组(教学状态 TEACHING_STATE_GET 返回 fullState.activeProblems)
        if (action === 'truncate-nested') {
          const parts = fieldPath.split('.');
          if (parts.length === 0) continue;
          if (parts.length === 1) {
            if (!Array.isArray(out)) continue;
            out = this.applyAction(out, fieldPath, action, undefined, effMax);
            this.hitCount++;
            this.hitsByAction[action]++;
            continue;
          }
          const parentPath = parts.slice(0, -1).join('.');
          const arr = getByPath(out, parentPath);
          if (!Array.isArray(arr)) continue;
          out = this.applyAction(out, fieldPath, action, undefined, effMax);
          this.hitCount++;
          this.hitsByAction[action]++;
          continue;
        }

        const value = getByPath(out, fieldPath);
        if (value === undefined) continue;

        out = this.applyAction(out, fieldPath, action, value, effMax);
        this.hitCount++;
        this.hitsByAction[action]++;
      }
      return out;
    } catch (e) {
      this.errorCount++;
      console.warn(`[PayloadSanitizer] sanitize(${service}) failed:`, e);
      return payload; // 降级:返回原 payload
    }
  }

  private applyAction(
    obj: unknown,
    fieldPath: string,
    action: SanitizeAction,
    value: unknown,
    maxChars: number,
  ): unknown {
    switch (action) {
      case 'redact':
        return setByPath(obj, fieldPath, REDACTED);
      case 'truncate':
        return setByPath(obj, fieldPath, truncateString(value, maxChars));
      case 'hash':
        return setByPath(obj, fieldPath, hashValue(value));
      case 'mask':
        return setByPath(obj, fieldPath, maskValue(value));
      case 'omit':
        return unsetByPath(obj, fieldPath);
      case 'truncate-nested':
        return truncateNestedByPath(obj, fieldPath, maxChars);
    }
  }

  /** 命中统计(调试 + 监控) */
  stats(): SanitizeStats {
    return {
      total: this.hitCount,
      byAction: { ...this.hitsByAction },
      errors: this.errorCount,
    };
  }

  /** 重置统计(测试用) */
  resetStats(): void {
    this.hitCount = 0;
    this.errorCount = 0;
    Object.assign(this.hitsByAction, ZERO_STATS.byAction);
  }

  /** 是否已加载白名单(测试用) */
  hasWhitelist(): boolean {
    return Object.keys(this.whitelist.services).length > 0;
  }

  /** 默认 config 路径解析 */
  static defaultConfigPath(): string {
    return path.join(process.cwd(), 'resources', 'config', 'payload-sanitize-whitelist.json');
  }
}
