/**
 * Attitude Filter — 态度档位实质过滤
 *
 * 职责：
 * 1. 根据 attitude 档位过滤 SKILL 内容
 * 2. 规则外置到 resources/config/attitude-filter.json（R-014）
 * 3. 配置文件缺失时降级为不过滤
 *
 * 设计依据：Sprint 14 方向 C 草案 §五（T14-4）
 *
 * 档位行为：
 * - doubao:  不过滤（默认态度）
 * - yuesheng: 轻度优化（去除过度修饰）
 * - sensei: 严格（删除鼓励话术，保留技术反馈）
 */

import * as fs from 'fs';
import type { AttitudeLevel } from './skill-metadata';

/** 单个过滤规则 */
export interface FilterRule {
  /** 要删除的 regex 模式列表（直接删除匹配内容） */
  removePatterns: string[];
  /** 要替换的 regex 模式列表（pattern → replacement） */
  replacePatterns: Array<{ pattern: string; replacement: string }>;
}

/** 过滤规则配置（从 JSON 加载） */
export interface AttitudeFilterConfig {
  version: string;
  rules: Record<AttitudeLevel, FilterRule>;
  minContentLength: { default: number };
}

/** 默认降级配置（如果 JSON 加载失败） */
const DEFAULT_CONFIG: AttitudeFilterConfig = {
  version: '1.0',
  rules: {
    doubao: { removePatterns: [], replacePatterns: [] },
    yuesheng: { removePatterns: [], replacePatterns: [] },
    sensei: { removePatterns: [], replacePatterns: [] },
  },
  minContentLength: { default: 50 },
};

/**
 * AttitudeFilter 类
 * 加载外置规则 + 应用过滤
 */
export class AttitudeFilter {
  private config: AttitudeFilterConfig;

  constructor(configPath?: string) {
    this.config = this.loadConfig(configPath);
  }

  /**
   * 加载配置文件
   * 失败时降级为默认（不过滤）
   */
  private loadConfig(configPath?: string): AttitudeFilterConfig {
    if (!configPath) {
      return DEFAULT_CONFIG;
    }
    try {
      const raw = fs.readFileSync(configPath, 'utf-8');
      const parsed = JSON.parse(raw) as AttitudeFilterConfig;
      // 验证必要字段
      if (!parsed.rules || !parsed.rules.sensei) {
        console.warn('[AttitudeFilter] Invalid config, using DEFAULT');
        return DEFAULT_CONFIG;
      }
      return parsed;
    } catch (err) {
      console.warn(`[AttitudeFilter] Failed to load ${configPath}, using DEFAULT: ${err instanceof Error ? err.message : String(err)}`);
      return DEFAULT_CONFIG;
    }
  }

  /**
   * 应用过滤到内容
   * @param content 原始内容
   * @param attitude 态度档位
   * @returns 过滤后内容
   */
  apply(content: string, attitude: AttitudeLevel): string {
    const rule = this.config.rules[attitude];
    if (!rule) {
      return content;
    }

    let result = content;

    // 1. 删除匹配 removePatterns 的内容
    for (const pattern of rule.removePatterns) {
      try {
        const regex = new RegExp(pattern, 'g');
        result = result.replace(regex, '');
      } catch (err) {
        console.warn(`[AttitudeFilter] Invalid removePattern "${pattern}": ${err instanceof Error ? err.message : String(err)}`);
      }
    }

    // 2. 应用 replacePatterns
    for (const { pattern, replacement } of rule.replacePatterns) {
      try {
        const regex = new RegExp(pattern, 'g');
        result = result.replace(regex, replacement);
      } catch (err) {
        console.warn(`[AttitudeFilter] Invalid replacePattern "${pattern}": ${err instanceof Error ? err.message : String(err)}`);
      }
    }

    // 3. 清理连续空行 / 行尾空格
    result = result
      .split('\n')
      .map(line => line.replace(/[ \t]+$/, ''))
      .filter((line, idx, arr) => {
        // 移除连续空行
        if (line.trim() === '' && idx > 0 && arr[idx - 1].trim() === '') {
          return false;
        }
        return true;
      })
      .join('\n')
      .trim();

    // 4. 长度下限保护：过滤后内容太短，返回原内容（避免误删）
    const minLen = this.config.minContentLength?.default ?? 50;
    if (result.length < minLen && content.length > result.length) {
      return content;
    }

    return result;
  }

  /** 获取当前配置（测试用） */
  getConfig(): AttitudeFilterConfig {
    return this.config;
  }
}
