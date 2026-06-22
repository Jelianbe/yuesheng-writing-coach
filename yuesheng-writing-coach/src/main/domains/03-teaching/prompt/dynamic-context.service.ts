/**
 * DynamicContextService — 动态上下文装载服务
 *
 * 职责：
 * 1. 始终装载核心 Prompt（铁三角 + 教学原则）
 * 2. 根据活跃症候按需装载症候手册片段
 * 3. 根据活跃症候按需装载动作库片段
 * 4. 将知识文件从全量拼接改为 `核心 + 按需 + 上下文` 三段式组装
 *
 * 设计依据：dynamic-context-service_V1.0.md
 * 对应发现：月笙_设计意图vs代码实现_V1.0.md → 发现10 参考抽屉实现走偏
 */

import * as path from 'path';
import * as fs from 'fs';

import { SYNDROME_NAMES, SYNDROME_TO_ACTIONS, ACTION_NAMES, ACTION_GOALS } from '../../../../shared/mappings';
import type { SyndromeId, ActionId } from '../../../../shared/constants';
import { SkillDispatcher } from './skill-dispatcher';
import type { TeachingPhase, AttitudeLevel } from './skill-metadata';

/** 从知识文件中提取的片段 */
export interface KnowledgeSnippet {
  /** 片段 ID（如 P001, A001） */
  id: string;
  /** 片段内容 */
  content: string;
}

/** 动态上下文包 */
export interface ContextBundle {
  /** 核心层 Prompt（铁三角，始终装载，~500 字） */
  corePrompt: string;
  /** 按需层：症候手册片段 */
  syndromeSnippets: KnowledgeSnippet[];
  /** 按需层：动作库片段 */
  actionSnippets: KnowledgeSnippet[];
  /** 按层：参考案例（V1 暂不实现，预留） */
  caseSnippets: KnowledgeSnippet[];
}

/**
 * 从 Markdown 文本中提取带标记的片段
 * 支持格式：<!-- TYPE:ID --> ... <!-- END:TYPE:ID -->
 */
export function extractSnippetsFromMarkdown(
  text: string,
  type: 'SYNDROME' | 'ACTION' | 'CASE',
): KnowledgeSnippet[] {
  const pattern = new RegExp(`<!--\\s*${type}:([A-Z]\\d+)\\s*-->([\\s\\S]*?)<!--\\s*END:${type}:\\1\\s*-->`, 'g');
  const snippets: KnowledgeSnippet[] = [];
  let match: RegExpExecArray | null;

  while ((match = pattern.exec(text)) !== null) {
    snippets.push({
      id: match[1],
      content: match[2].trim(),
    });
  }

  return snippets;
}

/**
 * 构建症候-动作索引（用于按需装载）
 * 给定活跃症候 ID 列表，返回所有相关的动作 ID
 */
export function getRelevantActionIds(syndromeIds: string[]): string[] {
  const actionIdSet = new Set<string>();
  for (const id of syndromeIds) {
    const actions = SYNDROME_TO_ACTIONS[id as SyndromeId];
    if (actions && actions.length > 0) {
      for (const actionId of actions) {
        actionIdSet.add(actionId);
      }
    }
  }
  return Array.from(actionIdSet);
}

/**
 * 动态上下文装载服务
 */
export class DynamicContextService {
  private resourcesRoot: string;
  /** 核心 Prompt 缓存（铁三角不变，只读一次） */
  private cachedCorePrompt: string | null = null;
  /** Sprint 13: SkillDispatcher 注入槽（运行时按 phase+attitude 选 SKILL） */
  private dispatcher: SkillDispatcher | null = null;

  /** 症候手册全文缓存（已废弃） */
  // @ts-expect-error: Kept for backward compatibility, set but not read
  private _cachedSyndromeManual: string | null = null;

  /** 动作库全文缓存（已废弃） */
  // @ts-expect-error: Kept for backward compatibility, set but not read
  private _cachedActionLibrary: string | null = null;

  /** 症候片段索引 */
  private syndromeSnippetIndex: Map<string, string> | null = null;

  /** 动作片段索引 */
  private actionSnippetIndex: Map<string, string> | null = null;

  constructor(resourcesRoot: string) {
    this.resourcesRoot = resourcesRoot;
  }

  /** 获取 Prompt 文件路径 */
  private getPromptPath(filename: string): string {
    return path.join(this.resourcesRoot, `prompts/${filename}`);
  }

  /** 读取 Prompt 文件 */
  private readPrompt(filename: string): string | null {
    const promptPath = this.getPromptPath(filename);
    if (fs.existsSync(promptPath)) {
      return fs.readFileSync(promptPath, 'utf-8');
    }
    const altPath = path.join(process.cwd(), `resources/prompts/${filename}`);
    try {
      return fs.readFileSync(altPath, 'utf-8');
    } catch {
      return null;
    }
  }

  /**
   * 装载核心 Prompt（铁三角 + 教学策略 + 验证规则）
   * Sprint 13 改造：委托给 SkillDispatcher 按 phase+attitude 选 SKILL
   * Sprint 14-prior 改造：接受 phase 参数 + A+C 方案解决 D-DEBT-11 体积膨胀
   *   - P0/P1 走 v5 降级（保持 ~800 字符）
   *   - P2+ 走 dispatcher v2（coreSubset 过滤 + tokenPriority 截断）
   * 降级路径：dispatcher 不可用时回退到 v5.md §一铁三角提取
   *
   * @param phase 教学阶段（默认 P0_INIT）
   */
  private loadCorePrompt(phase: TeachingPhase = 'P0_INIT'): string {
    if (this.cachedCorePrompt) {
      return this.cachedCorePrompt;
    }

    // 方案 C：P0/P1 走 v5 降级路径（保持 800 字符，不启用 dispatcher）
    if (phase === 'P0_INIT' || phase === 'P1_WORLD') {
      this.cachedCorePrompt = this.loadV5CoreFallback();
      return this.cachedCorePrompt;
    }

    // 方案 A：P2+ 走 dispatcher v2 + coreSubset 过滤
    if (this.dispatcher && this.dispatcher['loaded']) {
      const defaultAttitude: AttitudeLevel = 'yuesheng';
      // 体积预算：P2+ 限制 4K tokens，dispatcher 内部按 tokenPriority 截断
      const budget = 4000;
      this.cachedCorePrompt = this.dispatcher.composePrompt(
        phase,
        defaultAttitude,
        { coreSubsetOnly: true, maxTokens: budget },
      );
      return this.cachedCorePrompt;
    }

    // 降级路径：dispatcher 不可用时回退到 v5
    this.cachedCorePrompt = this.loadV5CoreFallback();
    return this.cachedCorePrompt;
  }

  /**
   * v5 降级路径：从 v5.md 提取铁三角
   * P0/P1 走此路径，体积 < 1.2K tokens
   * @internal
   */
  private loadV5CoreFallback(): string {
    const fullText = this.readPrompt('yuesheng-prompt-v5.md');
    if (!fullText) {
      return '';
    }

    const coreSnippets = extractSnippetsFromMarkdown(fullText, 'SYNDROME');
    if (coreSnippets.length > 0) {
      return coreSnippets.map(s => s.content).join('\n\n');
    }

    const ironTriangleMatch = fullText.match(/## 一、铁三角[\s\S]*?(?=## 二|## 三|$)/);
    if (ironTriangleMatch) {
      return ironTriangleMatch[0].trim();
    }

    return fullText.substring(0, 800).trim();
  }

  /** 设置 SkillDispatcher 实例（外部注入） */
  setDispatcher(dispatcher: SkillDispatcher): void {
    this.dispatcher = dispatcher;
    // dispatcher 变更后清除缓存，强制重新加载
    this.clearCache();
  }

  /**
   * 装载症候手册全文并构建索引
   */
  private loadSyndromeManual(): void {
    if (this.syndromeSnippetIndex) {
      return;
    }

    const fullText = this.readPrompt('syndrome-manual.md');
    if (!fullText) {
      this.syndromeSnippetIndex = new Map();
      return;
    }

    this._cachedSyndromeManual = fullText;
    this.syndromeSnippetIndex = new Map();

    // 尝试提取带标记的片段
    const snippets = extractSnippetsFromMarkdown(fullText, 'SYNDROME');
    if (snippets.length > 0) {
      for (const snippet of snippets) {
        this.syndromeSnippetIndex.set(snippet.id, snippet.content);
      }
      return;
    }

    // 降级：按 ## Pxxx 分割
    const lines = fullText.split('\n');
    let currentId: string | null = null;
    let currentContent: string[] = [];

    for (const line of lines) {
      const idMatch = line.match(/^###\s+(P\d{3})\s*[:：]/);
      if (idMatch) {
        if (currentId && currentContent.length > 0) {
          this.syndromeSnippetIndex.set(currentId, currentContent.join('\n').trim());
        }
        currentId = idMatch[1];
        currentContent = [line];
      } else if (currentId) {
        currentContent.push(line);
      }
    }

    if (currentId && currentContent.length > 0) {
      this.syndromeSnippetIndex.set(currentId, currentContent.join('\n').trim());
    }
  }

  /**
   * 装载动作库全文并构建索引
   */
  private loadActionLibrary(): void {
    if (this.actionSnippetIndex) {
      return;
    }

    const fullText = this.readPrompt('action-library.md');
    if (!fullText) {
      this.actionSnippetIndex = new Map();
      return;
    }

    this._cachedActionLibrary = fullText;
    this.actionSnippetIndex = new Map();

    // 尝试提取带标记的片段
    const snippets = extractSnippetsFromMarkdown(fullText, 'ACTION');
    if (snippets.length > 0) {
      for (const snippet of snippets) {
        this.actionSnippetIndex.set(snippet.id, snippet.content);
      }
      return;
    }

    // 降级：按 ### Axxx 分割
    const lines = fullText.split('\n');
    let currentId: string | null = null;
    let currentContent: string[] = [];

    for (const line of lines) {
      const idMatch = line.match(/^###\s+(A\d{3})\s*[:：]/);
      if (idMatch) {
        if (currentId && currentContent.length > 0) {
          this.actionSnippetIndex.set(currentId, currentContent.join('\n').trim());
        }
        currentId = idMatch[1];
        currentContent = [line];
      } else if (currentId) {
        currentContent.push(line);
      }
    }

    if (currentId && currentContent.length > 0) {
      this.actionSnippetIndex.set(currentId, currentContent.join('\n').trim());
    }
  }

  /**
   * 按症候 ID 装载症候手册片段
   */
  private loadSyndromeSnippets(syndromeIds: string[]): KnowledgeSnippet[] {
    this.loadSyndromeManual();

    const snippets: KnowledgeSnippet[] = [];
    for (const id of syndromeIds) {
      const content = this.syndromeSnippetIndex?.get(id);
      if (content) {
        snippets.push({ id, content });
      }
    }

    return snippets;
  }

  /**
   * 按症候 ID 装载动作库片段
   * 动作片段根据症候-动作映射自动关联
   */
  private loadActionSnippets(syndromeIds: string[]): KnowledgeSnippet[] {
    this.loadActionLibrary();

    const actionIds = getRelevantActionIds(syndromeIds);
    const snippets: KnowledgeSnippet[] = [];

    for (const actionId of actionIds) {
      const content = this.actionSnippetIndex?.get(actionId);
      if (content) {
        snippets.push({ id: actionId, content });
      } else {
        // 降级：使用映射表中的名称和目标
        const name = ACTION_NAMES[actionId as ActionId] ?? actionId;
        const goal = ACTION_GOALS[actionId as ActionId] ?? '';
        const fallback = `## ${actionId} ${name}\n**精髓**：见症候手册中对应的可选方向。\n**目标**：${goal}`;
        snippets.push({ id: actionId, content: fallback });
      }
    }

    return snippets;
  }

  /**
   * 入口：根据教学状态装载上下文
   * Sprint 14-prior 升级（解决 D-DEBT-09）：接受 phase 参数注入 dispatcher
   *
   * @param syndromeIds - 活跃症候 ID 列表（如 ['P001', 'P003']）
   * @param phase - 当前教学阶段（默认 P0_INIT）
   * @returns ContextBundle 上下文包
   */
  loadContext(syndromeIds: string[], phase: TeachingPhase = 'P0_INIT'): ContextBundle {
    const corePrompt = this.loadCorePrompt(phase);
    const syndromeSnippets = this.loadSyndromeSnippets(syndromeIds);
    const actionSnippets = this.loadActionSnippets(syndromeIds);

    return {
      corePrompt,
      syndromeSnippets,
      actionSnippets,
      caseSnippets: [], // V1 暂不实现案例
    };
  }

  /**
   * 将参考抽屉内容格式化为 Prompt 文本
   */
  formatReferenceDrawer(bundle: ContextBundle): string {
    const lines: string[] = [];

    if (bundle.syndromeSnippets.length > 0) {
      lines.push('---');
      lines.push('## 参考抽屉：症候手册');
      lines.push('');
      for (const snippet of bundle.syndromeSnippets) {
        const name = SYNDROME_NAMES[snippet.id] ?? snippet.id;
        lines.push(`### ${snippet.id} ${name}`);
        lines.push(snippet.content);
        lines.push('');
      }
    }

    if (bundle.actionSnippets.length > 0) {
      lines.push('---');
      lines.push('## 参考抽屉：教学动作');
      lines.push('');
      for (const snippet of bundle.actionSnippets) {
        const name = ACTION_NAMES[snippet.id as ActionId] ?? snippet.id;
        lines.push(`### ${snippet.id} ${name}`);
        lines.push(snippet.content);
        lines.push('');
      }
    }

    return lines.join('\n');
  }

  /**
   * 清除所有缓存（用于测试或热重载）
   */
  clearCache(): void {
    this.cachedCorePrompt = null;
    this._cachedSyndromeManual = null;
    this._cachedActionLibrary = null;
    this.syndromeSnippetIndex = null;
    this.actionSnippetIndex = null;
  }
}
