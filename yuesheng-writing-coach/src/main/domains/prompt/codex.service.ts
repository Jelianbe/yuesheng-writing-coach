/**
 * CodexService — Codex 结构化知识注入服务
 *
 * 设计依据：pro-writing-tools-report_V1.0.md → PE-002（NovelCrafter Codex 系统）
 * 核心模式：知识条目 = {trigger_condition} + {content_block} + {injection_priority}
 *
 * 职责：
 * 1. 从多个来源（诊断历史、教学状态、学生画像）收集知识条目
 * 2. 按优先级排序
 * 3. 格式化为 Codex 结构化文本块，注入 System Prompt
 *
 * 与旧 formatDiagnosisHistory() 的区别：
 * - 旧：单一文本拼接，无优先级概念
 * - Codex：多源聚合 + 优先级排序 + 结构化格式
 */

import * as path from 'path';
import * as fs from 'fs';

// ============ 类型定义 ============

/** Codex 条目类型 */
export type CodexEntryType = 'diagnosis_history' | 'teaching_progress' | 'student_profile' | 'focus_area';

/** 触发条件类型 */
export type TriggerType = 'always' | 'on_session' | 'on_diagnosis' | 'on_phase';

/** Codex 条目 */
export interface CodexEntry {
  /** 唯一标识 */
  id: string;
  /** 条目类型 */
  type: CodexEntryType;
  /** 条目内容文本 */
  content: string;
  /** 注入优先级（1=最高，5=最低，来自配置） */
  priority: number;
  /** 条目标签（来自配置） */
  label: string;
  /** 格式类型 */
  format: 'structured' | 'compact';
}

/** 条目类型配置 */
interface EntryTypeConfig {
  priority: number;
  maxEntries: number;
  trigger: { type: TriggerType; value?: string };
  format: 'structured' | 'compact';
  label: string;
}

/** Codex 配置格式 */
interface CodexConfig {
  version: string;
  updatedAt: string;
  description: string;
  entryTypes: Record<string, EntryTypeConfig>;
}

/** 收集上下文（用于决定哪些条目被激活） */
export interface CodexContext {
  /** 是否有活跃会话 */
  hasSession: boolean;
  /** 是否有诊断数据 */
  hasDiagnosis: boolean;
  /** 当前教学阶段（可选） */
  currentPhase?: string;
}

// ============ 服务类 ============

export class CodexService {
  private resourcesRoot: string;
  private cachedConfig: CodexConfig | null = null;

  constructor(resourcesRoot: string) {
    this.resourcesRoot = resourcesRoot;
  }

  /** 获取配置文件路径 */
  private getConfigPath(): string {
    return path.join(this.resourcesRoot, 'config/codex-config.json');
  }

  /** 加载配置 */
  private loadConfig(): CodexConfig {
    if (this.cachedConfig) {
      return this.cachedConfig;
    }

    const configPath = this.getConfigPath();
    try {
      if (fs.existsSync(configPath)) {
        const raw = fs.readFileSync(configPath, 'utf-8');
        this.cachedConfig = JSON.parse(raw) as CodexConfig;
        return this.cachedConfig;
      }
    } catch (e) {
      console.warn('[CodexService] 配置文件读取失败:', e);
    }

    // 降级：使用内置默认配置
    this.cachedConfig = this.getDefaultConfig();
    return this.cachedConfig;
  }

  /** 内置默认配置（文件不存在时降级） */
  private getDefaultConfig(): CodexConfig {
    return {
      version: '1.0',
      updatedAt: new Date().toISOString(),
      description: '降级默认配置',
      entryTypes: {
        diagnosis_history: { priority: 1, maxEntries: 1, trigger: { type: 'on_session' }, format: 'structured', label: '诊断历史' },
        teaching_progress: { priority: 2, maxEntries: 1, trigger: { type: 'always' }, format: 'structured', label: '教学进度' },
        student_profile: { priority: 3, maxEntries: 1, trigger: { type: 'on_session' }, format: 'compact', label: '学生画像' },
        focus_area: { priority: 4, maxEntries: 1, trigger: { type: 'on_diagnosis' }, format: 'compact', label: '聚焦方向' },
      },
    };
  }

  /** 清除配置缓存（用于测试或热重载） */
  clearCache(): void {
    this.cachedConfig = null;
  }

  /**
   * 根据上下文判断条目类型是否应该激活
   */
  private isTriggered(trigger: { type: TriggerType; value?: string }, context: CodexContext): boolean {
    switch (trigger.type) {
      case 'always':
        return true;
      case 'on_session':
        return context.hasSession;
      case 'on_diagnosis':
        return context.hasDiagnosis;
      case 'on_phase':
        return context.currentPhase !== undefined && (!trigger.value || context.currentPhase === trigger.value);
      default:
        return false;
    }
  }

  /**
   * 按优先级排序条目（高优先级在前）
   */
  private sortByPriority(entries: CodexEntry[]): CodexEntry[] {
    return [...entries].sort((a, b) => a.priority - b.priority);
  }

  /**
   * 格式化为 structured 格式
   * 适用于较长的结构化内容（诊断历史、教学进度）
   */
  private formatStructured(entry: CodexEntry): string {
    const lines: string[] = [];
    lines.push(`---`);
    lines.push(`## Codex: ${entry.label}`);
    lines.push('');
    lines.push(entry.content);
    return lines.join('\n');
  }

  /**
   * 格式化为 compact 格式
   * 适用于较短的内容（学生画像、聚焦方向）
   */
  private formatCompact(entry: CodexEntry): string {
    const lines: string[] = [];
    lines.push(`---`);
    lines.push(`${entry.label}：${entry.content}`);
    return lines.join('\n');
  }

  /**
   * 格式化单条条目
   */
  private formatEntry(entry: CodexEntry): string {
    if (entry.format === 'structured') {
      return this.formatStructured(entry);
    }
    return this.formatCompact(entry);
  }

  /**
   * 构建 Codex 注入块
   *
   * @param entries - 待注入的知识条目列表
   * @param context - 当前上下文
   * @returns 格式化的 Codex 文本块（空数组时不注入）
   */
  buildCodexBlock(
    entries: CodexEntry[],
    context: CodexContext,
  ): string {
    const config = this.loadConfig();

    // 1. 过滤：按触发条件
    const activatedEntries = entries.filter(e => {
      const typeConfig = config.entryTypes[e.type];
      if (!typeConfig) return false;
      return this.isTriggered(typeConfig.trigger, context);
    });

    if (activatedEntries.length === 0) {
      return '';
    }

    // 2. 按优先级排序
    const sorted = this.sortByPriority(activatedEntries);

    // 3. 格式化
    const parts = sorted.map(e => this.formatEntry(e));

    return parts.join('\n\n');
  }
}
