/**
 * 教学策略服务 — 决定"怎么教"
 *
 * 职责：
 *   1. 读取 teaching-strategies.json + user-type-matrix.json 配置
 *   2. 结合 StudentModel 状态，输出教学决策
 *   3. 决策逻辑从 JSON 配置读取，不在代码里硬编码
 *
 * 设计依据：
 *   - teaching-knowledge-bridge_V1.0.md §4.2 TeachingStrategyService
 *   - SPEC_adaptive-teaching_V1.0.md §4.2 决策逻辑伪代码
 *   - user-type-matrix.json（用户类型映射）
 */

import * as fs from 'fs';
import * as path from 'path';

import { ProficiencyLevel, CognitiveStyle } from './student-model.service';

/** 教学模式 */
export type TeachingMode = 'scaffolding' | 'guiding' | 'challenging';

/** 语气类型 */
export type ToneType = 'encouraging' | 'direct' | 'logical' | 'resonant';

/** 教学策略决策 */
export interface TeachingStrategyDecision {
  /** 教学模式 */
  mode: TeachingMode;
  /** 语气 */
  tone: ToneType;
  /** 输出格式偏好 */
  format?: 'problem→cause→evidence→solution' | 'example→feeling→demonstration';
}

/** 教学策略配置（从 teaching-strategies.json 加载） */
interface TeachingStrategiesConfig {
  $source: string;
  teachingModes: Record<string, {
    name: string;
    description: string;
    triggerConditions: Record<string, unknown>;
    instruction: string;
  }>;
  modeSwitchRules: Array<{
    rule: string;
    condition: string;
    targetMode: TeachingMode;
  }>;
  defaultMode: TeachingMode;
}

/** 用户类型矩阵配置（从 user-type-matrix.json 加载） */
interface UserTypeMatrixConfig {
  $source: string;
  userTypes: Record<string, {
    label: string;
    toneProfile: string;
    preferredFormat?: string;
    confidenceBoost: boolean;
  }>;
  teachingStyleMap: Record<string, {
    mode: TeachingMode;
    tone: string;
  }>;
}

/** 教学策略决策输入 */
export interface StrategyInput {
  /** 能力等级 */
  proficiency: ProficiencyLevel;
  /** 认知风格 */
  cognitiveStyle: CognitiveStyle;
  /** 症候出现次数（最频繁的一个） */
  topSyndromeCount: number;
  /** 挫折指标（0-1） */
  frustrationIndex: number;
}

/**
 * 教学策略服务
 */
export class TeachingStrategyService {
  private resourcesRoot: string;
  private config: TeachingStrategiesConfig | null = null;
  private userTypeMatrix: UserTypeMatrixConfig | null = null;

  constructor(resourcesRoot: string) {
    this.resourcesRoot = resourcesRoot;
  }

  /** 获取配置文件路径 */
  private getConfigPath(filename: string): string {
    return path.join(this.resourcesRoot, `config/${filename}`);
  }

  /** 加载教学策略配置 */
  private loadTeachingStrategiesConfig(): TeachingStrategiesConfig {
    if (this.config) return this.config;

    const configPath = this.getConfigPath('teaching-strategies.json');
    try {
      const raw = fs.readFileSync(configPath, 'utf-8');
      this.config = JSON.parse(raw) as TeachingStrategiesConfig;
      return this.config;
    } catch {
      return this.getDefaultTeachingStrategiesConfig();
    }
  }

  /** 加载用户类型矩阵配置 */
  private loadUserTypeMatrixConfig(): UserTypeMatrixConfig {
    if (this.userTypeMatrix) return this.userTypeMatrix;

    const configPath = this.getConfigPath('user-type-matrix.json');
    try {
      const raw = fs.readFileSync(configPath, 'utf-8');
      this.userTypeMatrix = JSON.parse(raw) as UserTypeMatrixConfig;
      return this.userTypeMatrix;
    } catch {
      return this.getDefaultUserTypeMatrixConfig();
    }
  }

  /** 默认教学策略配置（配置文件不存在时的降级） */
  private getDefaultTeachingStrategiesConfig(): TeachingStrategiesConfig {
    return {
      $source: 'hardcoded-fallback',
      teachingModes: {
        scaffolding: { name: '支架模式', description: '', triggerConditions: {}, instruction: '' },
        guiding: { name: '引导模式', description: '', triggerConditions: {}, instruction: '' },
        challenging: { name: '挑战模式', description: '', triggerConditions: {}, instruction: '' },
      },
      modeSwitchRules: [
        { rule: '屡犯 + 低分', condition: '', targetMode: 'scaffolding' },
        { rule: '挫折信号', condition: '', targetMode: 'scaffolding' },
        { rule: '理解期 + 中等分', condition: '', targetMode: 'guiding' },
        { rule: '创造期 + 高分', condition: '', targetMode: 'challenging' },
      ],
      defaultMode: 'guiding',
    };
  }

  /** 默认用户类型矩阵配置（配置文件不存在时的降级） */
  private getDefaultUserTypeMatrixConfig(): UserTypeMatrixConfig {
    return {
      $source: 'hardcoded-fallback',
      userTypes: {
        beginner: { label: '新手', toneProfile: 'encouraging', confidenceBoost: true },
        intermediate: { label: '进阶', toneProfile: 'direct', confidenceBoost: false },
        advanced: { label: '成熟', toneProfile: 'direct', confidenceBoost: false },
        analytical: { label: '理工型', toneProfile: 'logical', preferredFormat: 'problem→cause→evidence→solution', confidenceBoost: false },
        emotional: { label: '感性型', toneProfile: 'resonant', preferredFormat: 'example→feeling→demonstration', confidenceBoost: false },
      },
      teachingStyleMap: {},
    };
  }

  /**
   * 决定教学模式
   * 规则从 teaching-strategies.json 的 modeSwitchRules 读取
   * 决策逻辑参考：SPEC_adaptive-teaching_V1.0.md §4.2
   */
  decide(input: StrategyInput): TeachingStrategyDecision {
    const config = this.loadTeachingStrategiesConfig();
    const userTypeMatrix = this.loadUserTypeMatrixConfig();

    // === 第一步：决定教学模式（按规则优先级匹配） ===
    const mode = this.decideMode(config, input);

    // === 第二步：决定语气（根据用户类型） ===
    const tone = this.decideTone(userTypeMatrix, input);

    // === 第三步：决定输出格式 ===
    const format = this.decideFormat(userTypeMatrix, input);

    return { mode, tone, format };
  }

  /**
   * 教学模式决策
   * 按 modeSwitchRules 顺序匹配，返回第一个命中的模式
   */
  private decideMode(config: TeachingStrategiesConfig, input: StrategyInput): TeachingMode {
    for (const rule of config.modeSwitchRules) {
      // 规则 1：挫折信号 → 支架模式
      if (rule.rule === '挫折信号' && input.frustrationIndex >= 0.6) {
        return rule.targetMode;
      }
      // 规则 2：屡犯 + 低分 → 支架模式
      if (rule.rule === '屡犯 + 低分' && input.topSyndromeCount >= 3) {
        return rule.targetMode;
      }
      // 规则 3：新手 → 支架模式
      if (rule.rule === '模仿期' && input.proficiency === 'beginner') {
        return rule.targetMode;
      }
      // 规则 4：理解期 + 中等分 → 引导模式
      if (rule.rule === '理解期 + 中等分' && input.proficiency === 'intermediate') {
        return rule.targetMode;
      }
      // 规则 5：创造期 + 高分 → 挑战模式
      if (rule.rule === '创造期 + 高分' && input.proficiency === 'advanced') {
        return rule.targetMode;
      }
    }

    return config.defaultMode;
  }

  /**
   * 语气决策
   * 根据能力等级和用户类型从 user-type-matrix.json 查找
   * 优先级：proficiency（能力等级） > cognitiveStyle（认知风格）
   * 如果 proficiency 返回的是通用语气（direct），则进一步检查 cognitiveStyle
   */
  private decideTone(matrix: UserTypeMatrixConfig, input: StrategyInput): ToneType {
    // 先根据能力等级查找 toneProfile
    const userType = matrix.userTypes[input.proficiency];
    if (userType) {
      const tone = this.normalizeTone(userType.toneProfile);
      // 如果是通用语气且存在认知风格，进一步查找
      if (tone === 'direct' && input.cognitiveStyle) {
        const styleType = matrix.userTypes[input.cognitiveStyle];
        if (styleType && styleType.toneProfile !== 'direct') {
          return this.normalizeTone(styleType.toneProfile);
        }
      }
      return tone;
    }

    // 根据认知风格查找
    const styleType = matrix.userTypes[input.cognitiveStyle];
    if (styleType) {
      return this.normalizeTone(styleType.toneProfile);
    }

    return 'direct';
  }

  /**
   * 输出格式决策
   */
  private decideFormat(
    matrix: UserTypeMatrixConfig,
    input: StrategyInput,
  ): 'problem→cause→evidence→solution' | 'example→feeling→demonstration' | undefined {
    const styleType = matrix.userTypes[input.cognitiveStyle];
    if (styleType?.preferredFormat === 'problem→cause→evidence→solution') {
      return 'problem→cause→evidence→solution';
    }
    if (styleType?.preferredFormat === 'example→feeling→demonstration') {
      return 'example→feeling→demonstration';
    }
    return undefined;
  }

  private normalizeTone(raw: string): ToneType {
    if (raw === 'encouraging') return 'encouraging';
    if (raw === 'direct') return 'direct';
    if (raw === 'logical') return 'logical';
    if (raw === 'resonant') return 'resonant';
    return 'direct';
  }

  /** 清除配置缓存（用于测试或热重载） */
  clearCache(): void {
    this.config = null;
    this.userTypeMatrix = null;
  }
}
