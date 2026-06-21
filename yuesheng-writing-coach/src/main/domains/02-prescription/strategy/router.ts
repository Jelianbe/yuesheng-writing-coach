/**
 * 教学策略路由服务（TeachingStrategyRouter）
 *
 * 职责演变说明：
 * 为满足 R-019 单文件 ≤300 行的规范，原 teaching-strategy-router.ts 已按三层架构拆分为以下子模块：
 *
 * - router.types.ts      内部类型定义
 * - router.constants.ts  常量映射
 * - router.conditions.ts 条件匹配引擎与工具函数
 * - router.layer1.ts     Layer 1：聚焦症候选择
 * - router.layer2.ts     Layer 2：教学方式选择
 * - router.layer3.ts     Layer 3：参数细化 + 后向兼容桥接
 *
 * 本文件保留为薄类，负责：配置加载（惰性缓存） + decide() 编排。
 * 所有外部导入路径保持不变。
 *
 * @see router.layer1
 * @see router.layer2
 * @see router.layer3
 */

import * as fs from 'fs';
import * as path from 'path';

import type {
  RouterInput,
  RouterOutput,
} from '../../../../shared/types/index';

import type { RouterConfigs, LearningPathConfig } from './router.types';
import { selectFocusSyndrome } from './router.layer1';
import { selectTeachingMode } from './router.layer2';
import { refineParameters, buildLegacyBridge } from './router.layer3';

// ==============================
// 类型定义
// ==============================

/** 阅读前置决策类型 */
export interface ReadingDecision {
  /** 是否需要阅读 */
  required: boolean;
  /** 是否推荐阅读 */
  recommended: boolean;
  /** 决策标签 */
  label: 'must_read' | 'recommend_read' | 'skip_read';
  /** 决策理由 */
  reason: string;
}

/** 阅读策略配置形状 */
interface ReadingStrategyConfig {
  description: string;
  decisionByAttitude: Record<string, {
    required: boolean;
    recommended: boolean;
    label: string;
    reason: string;
  }>;
}

// ==============================
// 主类
// ==============================

export class TeachingStrategyRouter {
  private resourcesRoot: string;

  // 已缓存的配置
  private _educationTheoryFragments: RouterConfigs['educationTheoryFragments'] | null = null;
  private _learningPath: RouterConfigs['learningPath'] | null = null;
  private _techniqueSelectionMatrix: RouterConfigs['techniqueSelectionMatrix'] | null = null;
  private _coachingTemplates: RouterConfigs['coachingTemplates'] | null = null;
  private _userTypeMap: RouterConfigs['userTypeMap'] | null = null;
  private _syndromeTypeMap: RouterConfigs['syndromeTypeMap'] | null = null;

  constructor(resourcesRoot: string) {
    this.resourcesRoot = resourcesRoot;
  }

  // ==============================
  // 配置加载（带缓存）
  // ==============================

  private getConfigPath(filename: string): string {
    return path.join(this.resourcesRoot, 'config', filename);
  }

  private loadJson<T>(filename: string, fallback: T): T {
    const filePath = this.getConfigPath(filename);
    try {
      const raw = fs.readFileSync(filePath, 'utf-8');
      return JSON.parse(raw) as T;
    } catch {
      console.warn(`[TeachingStrategyRouter] Failed to load ${filename}, using fallback`);
      return fallback;
    }
  }

  private loadEducationTheoryFragments(): RouterConfigs['educationTheoryFragments'] {
    if (this._educationTheoryFragments) return this._educationTheoryFragments;
    this._educationTheoryFragments = this.loadJson<RouterConfigs['educationTheoryFragments']>('education-theory-fragments.json', []);
    return this._educationTheoryFragments;
  }

  private loadLearningPathConfig(): RouterConfigs['learningPath'] {
    if (this._learningPath) return this._learningPath;
    this._learningPath = this.loadJson<RouterConfigs['learningPath']>('learning-path.json', {
      version: '1.0',
      beginner: { description: '', phases: [], skipPatterns: [], skipReason: '' },
      intermediate: { description: '', phases: [], skipPatterns: [], skipReason: '' },
      advanced: { description: '', phases: [], skipPatterns: [], skipReason: '' },
      syndromeOverride: { syndromePatternMap: {} },
    } as LearningPathConfig);
    return this._learningPath;
  }

  private loadTechniqueSelectionMatrix(): RouterConfigs['techniqueSelectionMatrix'] {
    if (this._techniqueSelectionMatrix) return this._techniqueSelectionMatrix;
    this._techniqueSelectionMatrix = this.loadJson<RouterConfigs['techniqueSelectionMatrix']>('technique-selection-matrix.json', {
      syndromePriorityMap: {},
      defaultMaxDifficulty: {},
    });
    return this._techniqueSelectionMatrix;
  }

  private loadCoachingTemplates(): RouterConfigs['coachingTemplates'] {
    if (this._coachingTemplates) return this._coachingTemplates;
    this._coachingTemplates = this.loadJson<RouterConfigs['coachingTemplates']>('coaching-templates.json', { strategies: [] });
    return this._coachingTemplates;
  }

  private loadUserTypeMap(): RouterConfigs['userTypeMap'] {
    if (this._userTypeMap) return this._userTypeMap;
    this._userTypeMap = this.loadJson<RouterConfigs['userTypeMap']>('user-type-map.json', {
      types: {},
      teachingStyleMap: {},
    });
    return this._userTypeMap;
  }

  private loadSyndromeTypeMap(): RouterConfigs['syndromeTypeMap'] {
    if (this._syndromeTypeMap) return this._syndromeTypeMap;
    this._syndromeTypeMap = this.loadJson<RouterConfigs['syndromeTypeMap']>('syndrome-type-map.json', {
      types: {},
    });
    return this._syndromeTypeMap;
  }

  /** 获取全部配置的快照（供 extracted functions 使用） */
  private getConfigs(): RouterConfigs {
    return {
      educationTheoryFragments: this.loadEducationTheoryFragments(),
      learningPath: this.loadLearningPathConfig(),
      techniqueSelectionMatrix: this.loadTechniqueSelectionMatrix(),
      coachingTemplates: this.loadCoachingTemplates(),
      userTypeMap: this.loadUserTypeMap(),
      syndromeTypeMap: this.loadSyndromeTypeMap(),
    };
  }

  /** 清除配置缓存（用于测试或热重载） */
  clearCache(): void {
    this._educationTheoryFragments = null;
    this._learningPath = null;
    this._techniqueSelectionMatrix = null;
    this._coachingTemplates = null;
    this._userTypeMap = null;
    this._syndromeTypeMap = null;
  }

  /**
   * 阅读前置决策 — B-02
   *
   * 在 assign 训练前判断是否需要先执行阅读分析步骤。
   * 判断依据：态度档位（doubao→must read, yuesheng→recommend, sensei→skip）
   *
   * @param attitude - 当前教学态度档位
   * @returns 阅读决策
   */
  decideReading(attitude: string): ReadingDecision {
    const config = this.loadJson<ReadingStrategyConfig>('teaching-strategies.json', {
      description: '',
      decisionByAttitude: {},
    });
    const rule = config.decisionByAttitude[attitude];
    if (!rule) {
      // 未知档位默认不阅读
      return { required: false, recommended: false, label: 'skip_read', reason: `未知档位 ${attitude}，跳过阅读` };
    }
    return {
      required: rule.required,
      recommended: rule.recommended,
      label: rule.label as ReadingDecision['label'],
      reason: rule.reason,
    };
  }

  // ==============================
  // 主入口
  // ==============================

  /**
   * 执行三层决策
   *
   * @param input - Router 输入
   * @returns Router 输出（含 backward-compatibility bridge）
   */
  decide(input: RouterInput): RouterOutput {
    const configs = this.getConfigs();

    const focusDecision = selectFocusSyndrome(input, configs);
    const modeDecision = selectTeachingMode(input, focusDecision, configs);
    const parameterDecision = refineParameters(input, focusDecision, modeDecision, configs);
    const compatibleWithLegacy = buildLegacyBridge(input, modeDecision, configs.userTypeMap);

    return {
      targetSyndrome: focusDecision,
      teachingMode: modeDecision,
      parameters: parameterDecision,
      compatibleWithLegacy,
    };
  }
}
