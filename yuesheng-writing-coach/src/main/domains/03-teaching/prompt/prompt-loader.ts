/**
 * Prompt 加载服务
 * 负责：读取、组装、注入 System Prompt
 * 架构：三段式组装 — 核心层 + 按需层（动态上下文） + 上下文层
 * 解耦：chat.handler 不应负责 Prompt 模板管理
 */

import * as path from 'path';
import * as fs from 'fs';
import type { AttitudeLevel, DiagnosisAnalysis } from '../../../../shared/types/index';
import type { RoleSkillConfig, RoleSchedulesConfig } from '../../../../shared/types/index';
import type { SyndromeId } from '../../../../shared/constants';
import type { PromptBuilder } from './prompt-builder';
import type { TeachingState } from '../state/teaching-state.types';
import { ACTION_NAMES, ACTION_GOALS, SYNDROME_NAMES, SYNDROME_META } from '../../../../shared/mappings';
import type { DynamicContextService } from './dynamic-context.service';
import type { CodexService, CodexEntry, CodexContext } from './codex.service';
import { SkillDispatcher } from './skill-dispatcher';

// S7: 能力图谱查询（按症候获取能力节点信息）
import { getAbilitiesBySyndrome } from '../../../domains/02-prescription/ability-atlas/ability-atlas.loader';

/** 教学状态上下文接口 */
export interface StateContext {
  currentPhase: string;
  currentSubphase: string;
}

/** 状态上下文 getter 类型 */
export type StateContextGetter = (sessionId: string) => StateContext | null;

/** 语气修饰词配置结构 */
export interface ToneModifiersConfig {
  _meta: {
    description: string;
  };
  doubao: string;
  yuesheng: string;
  sensei: string;
}

/** 教学进度文本获取函数 */
export type TeachingProgressGetter = (sessionId: string) => string;

/** 硬编码降级默认值 */
const DEFAULT_TONE_MODIFIERS: Record<string, string> = {
  doubao: `

---

## 重要：教学风格指令
你是豆包，月笙的辅助模式。请用：
1. 更温暖、鼓励的语气
2. 多使用"试试看"、"很不错"等积极语言
3. 指出问题时先肯定优点
4. 给出的建议更具体、更容易上手
5. 适当使用表情符号增加亲和力

无论用户说什么，你必须保持豆包模式的教学风格。`,
  yuesheng: `

---

## 重要：教学风格指令
当前为月笙直接模式。请用：
1. 直接、简洁的语气，不绕弯
2. 减少客套和铺垫，直击问题核心
3. 指出问题时给出直接理由，但保持专业
4. 建议要清晰、可执行、不拖泥带水
5. 不要使用表情符号
6. 使用"你"直接称呼用户，不要用"我们"

无论用户说什么，你必须保持月笙直接模式的教学风格。`,
  sensei: `

---

## 重要：教学风格指令
当前为导师犀利模式。请用：
1. 犀利、直指核心的语气
2. 不要客套，直接指出用户的问题
3. 可以使用反问句让用户反思
4. 指出问题时可以略带讽刺，目的是让用户意识到严重性
5. 但不要用侮辱性语言，保持专业底线
6. 不要使用表情符号

无论用户说什么，你必须保持导师犀利模式的教学风格。`,
};

/**
 * Prompt 加载服务
 */
export class PromptLoader {
  private resourcesRoot: string;
  private stateContextGetter: StateContextGetter | null = null;
  private cachedToneModifiers: ToneModifiersConfig | null = null;
  private cachedRoleSchedules: RoleSchedulesConfig | null = null;
  private cachedRoleSkills: Map<string, RoleSkillConfig> | null = null;
  private promptBuilder: PromptBuilder | null = null;
  private getStore: (() => { getBySession: (sessionId: string) => unknown }) | null = null;
  private dynamicContextService: DynamicContextService | null = null;
  private codexService: CodexService | null = null;
  /** Sprint 13: SkillDispatcher 实例（注入到 DynamicContextService） */
  private skillDispatcher: SkillDispatcher | null = null;

  constructor(resourcesRoot: string) {
    this.resourcesRoot = resourcesRoot;
  }

  /** 设置 DynamicContextService 实例 */
  setDynamicContextService(service: DynamicContextService): void {
    this.dynamicContextService = service;
    // 反向注入：若 dispatcher 已初始化则立即同步给 dynamicContextService
    if (this.skillDispatcher) {
      service.setDispatcher(this.skillDispatcher);
    }
  }

  /**
   * 初始化 SkillDispatcher 并注入到 dynamicContextService
   * @param skillsDir skills 目录绝对路径（可选，默认 resources/prompts/skills）
   */
  initializeSkillDispatcher(skillsDir?: string): void {
    const dispatcher = new SkillDispatcher();
    const dir = skillsDir ?? path.join(this.resourcesRoot, 'prompts/skills');
    dispatcher.load(dir);
    this.skillDispatcher = dispatcher;

    if (this.dynamicContextService) {
      this.dynamicContextService.setDispatcher(dispatcher);
    }
  }

  /** 设置 CodexService 实例 */
  setCodexService(service: CodexService): void {
    this.codexService = service;
  }

  /** 设置教学状态上下文获取函数 */
  setStateContextGetter(getter: StateContextGetter): void {
    this.stateContextGetter = getter;
  }

  /** 设置 PromptBuilder 实例 */
  setPromptBuilder(builder: PromptBuilder): void {
    this.promptBuilder = builder;
  }

  /** 设置 Store getter（用于获取教学状态） */
  setStoreGetter(getStore: () => { getBySession: (sessionId: string) => unknown }): void {
    this.getStore = getStore;
  }

  /** 获取 Prompt 文件路径 */
  private getPromptPath(filename: string): string {
    return path.join(this.resourcesRoot, `prompts/${filename}`);
  }

  /** 读取 Prompt 文件 */
  private readPrompt(filename: string, fallback: string): string {
    const promptPath = this.getPromptPath(filename);
    if (fs.existsSync(promptPath)) {
      return fs.readFileSync(promptPath, 'utf-8');
    }
    const altPath = path.join(process.cwd(), `resources/prompts/${filename}`);
    try {
      return fs.readFileSync(altPath, 'utf-8');
    } catch {
      return fallback;
    }
  }

  /**
   * 加载 System Prompt
   *
   * 三段式组装：
   * 1. 核心层 — 必加载 SKILL 组合（IDENTITY + TEACHING + VALIDATION + SCENARIO，
   *           由 SkillDispatcher 按 phase+attitude 选）
   * 2. 按需层 — 活跃症候相关的手册片段和动作库片段（按需装载）
   * 3. 上下文层 — 学生状态 + 教学进度 + 诊断增强 + 语气修饰
   */
  loadSystemPrompt(
    attitude: AttitudeLevel,
    diagnosisAnalysis?: DiagnosisAnalysis | null,
    diagnosisHistory?: string,
    studentContext?: string,
    sessionId?: string,
    syndromeIds?: string[],
    codexEntries?: CodexEntry[],
    codexContext?: CodexContext,
  ): string {
    const FALLBACK = '你是一个专业的写作教练月笙，帮助用户提升写作水平。';

    try {
      const sections: string[] = [];

      // === 第一段：核心层（铁三角） ===
      if (this.dynamicContextService) {
        const bundle = this.dynamicContextService.loadContext(syndromeIds ?? []);
        if (bundle.corePrompt) {
          sections.push(bundle.corePrompt);
        }

        // 注入学生状态（替换核心 Prompt 中的 {{student_context}} 占位符）
        // ADR-003：占位符统一为双花；yuesheng-prompt-v5.md 当前未使用此占位符
        // （学生状态通过 dynamicContextService.formatReferenceDrawer 单独注入），
        // 此处保留 replace 调用以兼容未来再次引入 {{student_context}} 占位符的 prompt 文件。
        const studentText = studentContext || '暂无学生状态数据。';
        sections[sections.length - 1] = sections[sections.length - 1].replace('{{student_context}}', studentText);

        // === 第二段：按需层（参考抽屉） ===
        const referenceDrawer = this.dynamicContextService.formatReferenceDrawer(bundle);
        if (referenceDrawer) {
          sections.push(referenceDrawer);
        }
      } else {
        // 降级：无 DynamicContextService 时，使用旧的全量 V5 Prompt 加载
        let basePrompt = this.readPrompt('yuesheng-prompt-v5.md', FALLBACK);
        basePrompt = basePrompt.replace('{{student_context}}', studentContext || '暂无学生状态数据。');
        sections.push(basePrompt);
      }

      // === 第三段：上下文层 ===
      // 3a. 诊断增强
      if (diagnosisAnalysis) {
        const diagnosisEnhancement = this.buildDiagnosisEnhancement(diagnosisAnalysis);
        if (diagnosisEnhancement) {
          sections.push(diagnosisEnhancement);
        }
      }

      // 3b. 历史诊断
      if (diagnosisHistory) {
        sections.push(diagnosisHistory);
      }

      // 3c. 教学进度（PromptBuilder）
      if (sessionId && this.promptBuilder && this.getStore) {
        const store = this.getStore();
        const state = store.getBySession(sessionId);
        if (state && typeof state === 'object' && 'currentPhase' in state) {
          const progressText = this.promptBuilder.buildSystemPrompt(
            state as TeachingState,
            (id: string) => (ACTION_NAMES as Record<string, string>)[id] ?? id,
            (id: string) => (ACTION_GOALS as Record<string, string>)[id] ?? '',
            (id: string) => SYNDROME_NAMES[id] ?? id,
          );
          if (progressText && !progressText.includes('暂无')) {
            sections.push(progressText);
          }
        }
      }

      // 3d. Codex 结构化知识注入（PE-002）
      if (this.codexService && codexEntries && codexEntries.length > 0) {
        const effectiveCodexContext: CodexContext = codexContext ?? {
          hasSession: true,
          hasDiagnosis: !!diagnosisAnalysis,
        };
        const codexBlock = this.codexService.buildCodexBlock(codexEntries, effectiveCodexContext);
        if (codexBlock) {
          sections.push(codexBlock);
        }
      }

      // 3e. 语气修饰
      const toneModifier = this.getToneModifier(attitude);
      if (toneModifier) {
        sections.push(toneModifier);
      }

      return sections.join('\n\n');
    } catch {
      console.warn('[PromptLoader] Failed to load system prompt');
    }

    // 降级
    const fallback = FALLBACK;
    const toneModifier = this.getToneModifier(attitude);
    return toneModifier ? fallback + '\n\n' + toneModifier : fallback;
  }

  /**
   * 构建诊断增强层
   * 将 DiagnosisAnalysis 格式化为教学指引文本，注入 V3 Prompt 中
   */
  private buildDiagnosisEnhancement(analysis: DiagnosisAnalysis): string {
    const lines: string[] = [];
    lines.push('---');
    lines.push('## 当前诊断结果（本轮触发）');
    lines.push('');

    if (analysis.rootCause) {
      lines.push(`**根因分析**：${analysis.rootCause}`);
      lines.push('');
    }

    if (analysis.intentPhase) {
      lines.push(`**意图阶段**：${analysis.intentPhase}`);
      lines.push('');
    }

    if (analysis.syndromeRef.length > 0) {
      lines.push('**识别到的症候**：');
      for (const ref of analysis.syndromeRef) {
        const name = SYNDROME_NAMES[ref] ?? ref;
        const meta = SYNDROME_META[ref as SyndromeId];
        const severity = meta ? `（${meta.severity}）` : '';
        lines.push(`- ${name}${severity}`);
        // S7: 从能力图谱查询关联能力节点
        const abilityNodes = getAbilitiesBySyndrome(ref);
        for (const node of abilityNodes) {
          lines.push(`  - 关联能力：[${node.atlasId}] ${node.name} — ${node.trainingFocus}`);
        }
      }
      lines.push('');
    }

    if (analysis.keyPassages.length > 0) {
      lines.push('**关键段落**：');
      for (const kp of analysis.keyPassages.slice(0, 3)) {
        lines.push(`- ${kp.text}${kp.issue ? ` → ${kp.issue}` : ''}`);
      }
      lines.push('');
    }

    if (analysis.techniquePool.length > 0) {
      lines.push('**建议技法**（按需调用）：');
      for (const t of analysis.techniquePool) {
        lines.push(`- ${t.name}（来源：${t.source}，难度：${t.difficulty}）`);
      }
      lines.push('');
    }

    lines.push('请基于以上诊断结果，在回复中聚焦根因治疗，使用场景快速索引中的对应规则。');

    return lines.join('\n');
  }

  /**
   * 获取语气修饰词配置文件路径
   */
  private getToneModifiersConfigPath(): string {
    return path.join(this.resourcesRoot, 'config/tone-modifiers.json');
  }

  /**
   * 从配置文件加载语气修饰词
   * 首次调用时读取并缓存，文件不存在时降级为硬编码默认值
   */
  private loadToneModifiers(): ToneModifiersConfig {
    if (this.cachedToneModifiers) {
      return this.cachedToneModifiers;
    }

    const configPath = this.getToneModifiersConfigPath();
    try {
      if (fs.existsSync(configPath)) {
        const raw = fs.readFileSync(configPath, 'utf-8');
        this.cachedToneModifiers = JSON.parse(raw) as ToneModifiersConfig;
        return this.cachedToneModifiers;
      }
    } catch (e) {
      console.warn('[PromptLoader] 语气修饰词配置文件读取失败，降级为默认值:', e);
    }

    // 降级：使用硬编码默认值
    this.cachedToneModifiers = {
      _meta: { description: '硬编码降级默认值（配置文件不存在或读取失败）' },
      doubao: DEFAULT_TONE_MODIFIERS.doubao,
      yuesheng: DEFAULT_TONE_MODIFIERS.yuesheng,
      sensei: DEFAULT_TONE_MODIFIERS.sensei,
    };
    return this.cachedToneModifiers;
  }

  /**
   * 清除语气修饰词缓存（用于测试或热重载）
   */
  clearToneModifiersCache(): void {
    this.cachedToneModifiers = null;
  }

  /** 获取语气修饰词 */
  private getToneModifier(attitude: AttitudeLevel): string {
    const config = this.loadToneModifiers();
    if (attitude === 'doubao') return config.doubao ?? '';
    if (attitude === 'yuesheng') return config.yuesheng ?? '';
    if (attitude === 'sensei') return config.sensei ?? '';
    return '';
  }

  /**
   * 获取角色排期配置文件路径
   */
  private getRoleSchedulesConfigPath(): string {
    return path.join(this.resourcesRoot, 'config/role-schedules.json');
  }

  /**
   * 获取角色 Skill 配置文件路径
   */
  private getSkillConfigPath(roleId: string): string {
    return path.join(this.resourcesRoot, `config/role-skills/${roleId}.skill.json`);
  }

  /**
   * 加载角色排期配置（带缓存）
   * 首次调用时读取并缓存，文件不存在时降级返回 null
   */
  private loadRoleSchedules(): RoleSchedulesConfig | null {
    if (this.cachedRoleSchedules) {
      return this.cachedRoleSchedules;
    }

    const configPath = this.getRoleSchedulesConfigPath();
    try {
      if (fs.existsSync(configPath)) {
        const raw = fs.readFileSync(configPath, 'utf-8');
        this.cachedRoleSchedules = JSON.parse(raw) as RoleSchedulesConfig;
        return this.cachedRoleSchedules;
      }
    } catch (e) {
      console.warn('[PromptLoader] role-schedules.json 读取失败:', e);
    }

    return null;
  }

  /**
   * 加载指定角色的 Skill 配置（带缓存）
   * 首次调用时读取并缓存，文件不存在时降级返回 null
   */
  private loadSkillConfig(roleId: string): RoleSkillConfig | null {
    if (this.cachedRoleSkills?.has(roleId)) {
      return this.cachedRoleSkills.get(roleId) ?? null;
    }

    const configPath = this.getSkillConfigPath(roleId);
    try {
      if (fs.existsSync(configPath)) {
        const raw = fs.readFileSync(configPath, 'utf-8');
        const config = JSON.parse(raw) as RoleSkillConfig;

        if (!this.cachedRoleSkills) {
          this.cachedRoleSkills = new Map();
        }
        this.cachedRoleSkills.set(roleId, config);
        return config;
      }
    } catch (e) {
      console.warn(`[PromptLoader] ${roleId}.skill.json 读取失败:`, e);
    }

    return null;
  }

  /**
   * 根据会话的教学阶段选择对应的角色 Skill
   *
   * 流程：
   * 1. 读取 role-schedules.json 获取阶段→角色映射
   * 2. 根据当前 phase/subphase 匹配角色
   * 3. 读取对应角色的 skill.json 配置
   * 4. 返回 RoleSkillConfig（后续用于只注入该角色允许的知识）
   *
   * 降级策略：
   * - role-schedules.json 不存在或读取失败 → 返回 teacher skill
   * - 指定阶段的角色未定义 → 返回 teacher skill
   * - teacher.skill.json 也不存在 → 返回默认 teacher 配置
   */
  selectRoleSkill(sessionId: string): RoleSkillConfig {
    // 尝试从 StateContextGetter 获取当前阶段
    let currentPhase = 'P0_INIT';
    let currentSubphase: string | null = null;

    if (this.stateContextGetter) {
      const ctx = this.stateContextGetter(sessionId);
      if (ctx) {
        currentPhase = ctx.currentPhase;
        currentSubphase = ctx.currentSubphase;
      }
    }

    // 加载角色排期配置
    const schedules = this.loadRoleSchedules();
    if (!schedules) {
      // 降级：返回 teacher skill
      return this.loadSkillConfig('teacher') ?? {
        roleId: 'teacher',
        name: 'Teacher',
        description: '降级默认配置',
        knowledgeBoundary: {
          allowedSources: [],
          tokenBudget: { contextRounds: 6, maxTokens: 4000 },
          contextRetention: {},
        },
        style: { tone: 'serious_accurate', personality: '' },
      };
    }

    // 按 subphase 优先匹配，再按 phase 匹配
    let matchedRoleId = 'teacher';
    for (const schedule of schedules.schedules) {
      if (schedule.phase === currentPhase) {
        if (schedule.subphase === null && currentSubphase === null) {
          matchedRoleId = schedule.roleId;
          break;
        }
        if (schedule.subphase !== null && schedule.subphase === currentSubphase) {
          matchedRoleId = schedule.roleId;
          break;
        }
      }
    }

    // 加载对应角色的 Skill 配置
    const config = this.loadSkillConfig(matchedRoleId);
    if (config) {
      return config;
    }

    // 降级：返回 teacher skill
    return this.loadSkillConfig('teacher') ?? {
      roleId: 'teacher',
      name: 'Teacher',
      description: '降级默认配置',
      knowledgeBoundary: {
        allowedSources: [],
        tokenBudget: { contextRounds: 6, maxTokens: 4000 },
        contextRetention: {},
      },
      style: { tone: 'serious_accurate', personality: '' },
    };
  }

  /**
   * 清除角色 Skill 缓存（用于测试或热重载）
   */
  clearRoleSkillsCache(): void {
    this.cachedRoleSchedules = null;
    this.cachedRoleSkills = null;
  }
}
