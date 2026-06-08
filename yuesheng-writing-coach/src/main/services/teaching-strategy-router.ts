/**
 * 教学策略路由服务（TeachingStrategyRouter）
 *
 * 职责：
 *   1. 消费 Phase 2.5 产出的 6 个配置文件
 *   2. 实现三层决策引擎：聚焦症候选择 → 教学方式选择 → 参数细化
 *   3. 输出包含教育学理论依据（theoryReference）
 *   4. 提供 backward-compatibility bridge 兼容旧接口
 *
 * 架构位置：
 *   StudentModel + DiagnosisResult + TrainingHistory
 *           ↓
 *   TeachingStrategyRouter（本服务）
 *           ↓ 决策输出
 *           teaching-state-machine.ts → prompt-builder.ts → Agent
 *
 * 设计依据：
 *   - docs/design/teaching-strategy-router_V1.0.md
 *   - docs/tasks/T-033-teaching-strategy-router.md
 *   - SPEC_adaptive-teaching_V1.0.md §4.2
 */

import * as fs from 'fs';
import * as path from 'path';

import type {
  TeachingMode,
  TeachingStrategy,
  RouterInput,
  RouterOutput,
  FocusDecision,
  ModeDecision,
  ParameterDecision,
} from '../../renderer/shared/types';

import { PERSONA_PRESETS } from '../../renderer/shared/types';

// ==============================
// 内部类型：配置 JSON 的 TS 视图
// ==============================

interface EducationTheoryFragment {
  id: string;
  condition: Record<string, unknown>;
  recommendedMode: string;
  rationale: string;
  source: string;
  priority: string;
}

interface LearningPathConfig {
  version: string;
  beginner: LevelPath;
  intermediate: LevelPath;
  advanced: LevelPath;
  syndromeOverride: {
    syndromePatternMap: Record<string, string[]>;
  };
}

interface LevelPath {
  description: string;
  phases: PhaseConfig[];
  skipPatterns: string[];
  skipReason: string;
}

interface PhaseConfig {
  phase: number;
  name: string;
  corePatterns: Array<{
    id: string;
    reason: string;
    maxDifficultyOrder: number;
  }>;
  maxTechniquesPerPattern: number;
}

interface TechniqueSelectionMatrix {
  syndromePriorityMap: Record<string, string[]>;
  defaultMaxDifficulty: Record<string, {
    maxDifficultyOrder: number;
    override?: Record<string, { maxDifficultyOrder?: number; skip?: boolean }>;
  }>;
}

interface CoachingTemplate {
  id: string;
  name: string;
  triggerConditions: {
    applicableLevels: string[];
    applicableSyndromes: string[];
  };
  steps: Array<{
    order: number;
    action: string;
    template: string;
  }>;
  contraindications: string[];
}

interface CoachingTemplatesConfig {
  strategies: CoachingTemplate[];
}

interface UserTypeMapConfig {
  types: Record<string, {
    name: string;
    teachingStyle?: string;
    applicableRules?: string[];
  }>;
  teachingStyleMap: Record<string, {
    mode: string;
    tone: string;
    challengeSize: string;
  }>;
}

interface SyndromeTypeMapConfig {
  types: Record<string, {
    name: string;
    syndromes: string[];
    recommendedEntry: string;
    rationale: string;
  }>;
}

// ==============================
// 常量映射
// ==============================

/** syndrome-type-map.json 的 recommendedEntry → TeachingStrategy 映射 */
const ENTRY_TO_STRATEGY: Record<string, TeachingStrategy> = {
  '先案例再模仿': 'case-driven',
  '先反思再练习': 'reflection-driven',
  '先提问激发再案例': 'analysis-driven',
};

/** 教育学理论规则分段：Layer 1 适用规则 (R-011 ~ R-015) */
const LAYER1_THEORY_RULE_IDS = ['R-011', 'R-012', 'R-013', 'R-014', 'R-015'];

/** 教育学理论规则分段：Layer 2 适用规则 (R-001 ~ R-006) */
const LAYER2_THEORY_RULE_IDS = ['R-001', 'R-002', 'R-003', 'R-004', 'R-005', 'R-006'];

/** user-type-map 中的 mode → TeachingMode 映射（含降级） */
const USER_TYPE_MODE_TO_TEACHING_MODE: Record<string, TeachingMode> = {
  scaffolding: 'scaffolding',
  guiding: 'guiding',
  challenging: 'challenging',
  reflective: 'guiding', // reflective 降级为 guiding
};

/** 症候类型 → 练习类型映射 */
const SYNDROME_TYPE_TO_PRACTICE: Record<string, string> = {
  expressive_deficit: 'imitation',
  structural_disorder: 'reflection',
  motivation_deficit: 'analysis',
};

/** 教学模式 → 练习类型映射（兜底） */
const MODE_TO_PRACTICE: Record<string, string> = {
  scaffolding: 'guided_practice',
  guiding: 'semi_independent',
  challenging: 'independent',
};



// ==============================
// 服务类
// ==============================

export class TeachingStrategyRouter {
  private resourcesRoot: string;

  // 已缓存的配置
  private educationTheoryFragments: EducationTheoryFragment[] | null = null;
  private learningPath: LearningPathConfig | null = null;
  private techniqueSelectionMatrix: TechniqueSelectionMatrix | null = null;
  private coachingTemplates: CoachingTemplatesConfig | null = null;
  private userTypeMap: UserTypeMapConfig | null = null;
  private syndromeTypeMap: SyndromeTypeMapConfig | null = null;

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

  private loadEducationTheoryFragments(): EducationTheoryFragment[] {
    if (this.educationTheoryFragments) return this.educationTheoryFragments;
    this.educationTheoryFragments = this.loadJson<EducationTheoryFragment[]>('education-theory-fragments.json', []);
    return this.educationTheoryFragments;
  }

  private loadLearningPathConfig(): LearningPathConfig {
    if (this.learningPath) return this.learningPath;
    this.learningPath = this.loadJson<LearningPathConfig>('learning-path.json', {
      version: '1.0',
      beginner: { description: '', phases: [], skipPatterns: [], skipReason: '' },
      intermediate: { description: '', phases: [], skipPatterns: [], skipReason: '' },
      advanced: { description: '', phases: [], skipPatterns: [], skipReason: '' },
      syndromeOverride: { syndromePatternMap: {} },
    });
    return this.learningPath;
  }

  private loadTechniqueSelectionMatrix(): TechniqueSelectionMatrix {
    if (this.techniqueSelectionMatrix) return this.techniqueSelectionMatrix;
    this.techniqueSelectionMatrix = this.loadJson<TechniqueSelectionMatrix>('technique-selection-matrix.json', {
      syndromePriorityMap: {},
      defaultMaxDifficulty: {},
    });
    return this.techniqueSelectionMatrix;
  }

  private loadCoachingTemplates(): CoachingTemplatesConfig {
    if (this.coachingTemplates) return this.coachingTemplates;
    this.coachingTemplates = this.loadJson<CoachingTemplatesConfig>('coaching-templates.json', { strategies: [] });
    return this.coachingTemplates;
  }

  private loadUserTypeMap(): UserTypeMapConfig {
    if (this.userTypeMap) return this.userTypeMap;
    this.userTypeMap = this.loadJson<UserTypeMapConfig>('user-type-map.json', {
      types: {},
      teachingStyleMap: {},
    });
    return this.userTypeMap;
  }

  private loadSyndromeTypeMap(): SyndromeTypeMapConfig {
    if (this.syndromeTypeMap) return this.syndromeTypeMap;
    this.syndromeTypeMap = this.loadJson<SyndromeTypeMapConfig>('syndrome-type-map.json', {
      types: {},
    });
    return this.syndromeTypeMap;
  }

  /** 清除配置缓存（用于测试或热重载） */
  clearCache(): void {
    this.educationTheoryFragments = null;
    this.learningPath = null;
    this.techniqueSelectionMatrix = null;
    this.coachingTemplates = null;
    this.userTypeMap = null;
    this.syndromeTypeMap = null;
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
    // Layer 1: 聚焦症候选择
    const focusDecision = this.selectFocusSyndrome(input);

    // Layer 2: 教学方式选择
    const modeDecision = this.selectTeachingMode(input, focusDecision);

    // Layer 3: 参数细化
    const parameterDecision = this.refineParameters(input, focusDecision, modeDecision);

    // 构建 backward-compatibility bridge
    const compatibleWithLegacy = this.buildLegacyBridge(input, modeDecision);

    return {
      targetSyndrome: focusDecision,
      teachingMode: modeDecision,
      parameters: parameterDecision,
      compatibleWithLegacy,
    };
  }

  // ==============================
  // Layer 1: 聚焦症候选择
  // ==============================

  private selectFocusSyndrome(input: RouterInput): FocusDecision {
    const active = input.activeSyndromes;
    if (active.length === 0) {
      return {
        targetSyndrome: '',
        targetSyndromeName: '',
        rationale: '无活跃症候，使用默认教学路径',
        theoryReference: [],
        alternativeSyndromes: [],
      };
    }

    // 如果只有一个症候，直接返回
    if (active.length === 1) {
      return {
        targetSyndrome: active[0].id,
        targetSyndromeName: active[0].name,
        rationale: '唯一活跃症候，直接聚焦',
        theoryReference: this.collectTheoryRefForSyndrome(active[0].id, input),
        alternativeSyndromes: [],
      };
    }

    // ---- 多症候选择 ----
    const theoryRef: string[] = [];

    // Step 1: 应用 R-015（影响阅读体验的症候优先）
    const r015 = this.findTheoryRule('R-015');
    const prioritySyndromeIds = this.getPrioritySyndromeIds();
    const priorityMatch = active.find((s) => prioritySyndromeIds.includes(s.id));

    if (priorityMatch && r015) {
      theoryRef.push(`R-015: ${r015.rationale}`);
    }

    // Step 2: 检查训练评分 → 选评分最低的
    const completedTraining = input.trainingHistory.filter((t) => t.completed);
    if (completedTraining.length > 0) {
      const avgScores = this.computeAvgTrainingScores(completedTraining);
      const scorable = active.filter((s) => avgScores.has(s.id));
      if (scorable.length > 0) {
        const lowest = scorable.reduce((a, b) =>
          (avgScores.get(a.id) ?? Infinity) <= (avgScores.get(b.id) ?? Infinity) ? a : b,
        );
        return {
          targetSyndrome: lowest.id,
          targetSyndromeName: lowest.name,
          rationale: `训练评分最低（${avgScores.get(lowest.id)?.toFixed(1)}/10），需要优先改进`,
          theoryReference: theoryRef,
          alternativeSyndromes: active.filter((s) => s.id !== lowest.id).map((s) => s.id),
        };
      }
    }

    // Step 3: 检查 syndromePriorityMap
    const priorityMap = this.loadTechniqueSelectionMatrix().syndromePriorityMap;
    for (const s of active) {
      if (priorityMap[s.id] && priorityMap[s.id].length > 0) {
        return {
          targetSyndrome: s.id,
          targetSyndromeName: s.name,
          rationale: `症候 ${s.id} 在技法矩阵中有优先映射关系`,
          theoryReference: theoryRef,
          alternativeSyndromes: active.filter((a) => a.id !== s.id).map((a) => a.id),
        };
      }
    }

    // Step 4: 选最高严重度
    const highest = active.reduce((a, b) =>
      (a.severity ?? 1) >= (b.severity ?? 1) ? a : b,
    );

    // Step 5: 应用 R-011 多症候聚焦规则
    if (active.length >= 2) {
      const r011 = this.findTheoryRule('R-011');
      if (r011) {
        theoryRef.push(`R-011: ${r011.rationale}`);
      }
    }

    return {
      targetSyndrome: highest.id,
      targetSyndromeName: highest.name,
      rationale: `严重度最高的症候（severity=${highest.severity}）`,
      theoryReference: theoryRef,
      alternativeSyndromes: active.filter((s) => s.id !== highest.id).map((s) => s.id),
    };
  }

  /** 收集与特定症候相关的教育理论依据 */
  private collectTheoryRefForSyndrome(_syndromeId: string, input: RouterInput): string[] {
    const refs: string[] = [];
    const rules = this.loadEducationTheoryFragments();
    for (const rule of rules) {
      if (LAYER1_THEORY_RULE_IDS.includes(rule.id)) {
        // 检查规则是否适用于当前输入
        if (this.matchesCondition(rule.condition, input)) {
          refs.push(`${rule.id}: ${rule.rationale}`);
        }
      }
    }
    return refs;
  }

  /**
   * 检查条件是否匹配输入的简化引擎
   * 只匹配教育理论 fragments 中常用的条件字段
   */
  private matchesCondition(condition: Record<string, unknown>, input: RouterInput): boolean {
    for (const [key, value] of Object.entries(condition)) {
      switch (key) {
        case 'userLevel':
          if (value !== input.userLevel) return false;
          break;
        case 'syndromeType': {
          const typeMap = this.loadSyndromeTypeMap();
          const inputType = this.getDominantSyndromeType(input.activeSyndromes.map((s) => s.id), typeMap);
          if (value !== inputType) return false;
          break;
        }
        case 'activeSyndromeCount': {
          const count = input.activeSyndromes.length;
          const cond = String(value);
          if (cond.startsWith('>=')) {
            if (count < parseInt(cond.slice(2), 10)) return false;
          } else if (cond.startsWith('<=')) {
            if (count > parseInt(cond.slice(2), 10)) return false;
          } else if (cond.startsWith('>')) {
            if (count <= parseInt(cond.slice(1), 10)) return false;
          } else if (cond.startsWith('<')) {
            if (count >= parseInt(cond.slice(1), 10)) return false;
          } else if (count !== parseInt(cond, 10)) return false;
          break;
        }
        case 'sameSyndromeCount':
          if (typeof value === 'number' && input.topSyndromeCount < value) return false;
          break;
        case 'syndromeSeverity': {
          // 检查是否有任意活跃症候达到该严重度
          const hasSeverity = input.activeSyndromes.some(
            (s) => this.severityToLabel(s.severity) === value,
          );
          if (!hasSeverity) return false;
          break;
        }
        case 'activeSyndromes': {
          if (Array.isArray(value)) {
            const ids = input.activeSyndromes.map((s) => s.id);
            const matchCount = (value as string[]).filter((v) => ids.includes(v)).length;
            if (matchCount === 0) return false;
          }
          break;
        }
        case 'trainingScore': {
          // R-008: 检查已完成训练的平均分是否达到阈值
          const completed = input.trainingHistory.filter((t) => t.completed);
          if (completed.length === 0) return false;
          const avgScore = completed.reduce((sum, t) => sum + t.score, 0) / completed.length;
          const cond = String(value);
          if (cond.startsWith('>=')) {
            if (avgScore < parseFloat(cond.slice(2))) return false;
          } else if (cond.startsWith('<=')) {
            if (avgScore > parseFloat(cond.slice(2))) return false;
          } else {
            if (avgScore < parseFloat(cond)) return false;
          }
          break;
        }
        case 'sameSyndromeRepeated': {
          // R-008: 检查是否有症候重复出现（若为 false 则要求无重复）
          const repeated = input.topSyndromeCount >= 2;
          if (value === true && !repeated) return false;
          if (value === false && repeated) return false;
          break;
        }
        case 'trainingMotivation': {
          if (value !== input.trainingMotivation) return false;
          break;
        }
        case 'trainingSkipRate': {
          const rate = input.trainingSkipRate ?? 0;
          const cond = String(value);
          if (cond.startsWith('>')) {
            // >0.5 → rate > 0.5
            if (rate <= parseFloat(cond.slice(1))) return false;
          } else if (cond.startsWith('>=')) {
            if (rate < parseFloat(cond.slice(2))) return false;
          } else if (cond.startsWith('<')) {
            if (rate >= parseFloat(cond.slice(1))) return false;
          } else if (cond.startsWith('<=')) {
            if (rate > parseFloat(cond.slice(2))) return false;
          }
          break;
        }
        case 'conflict': {
          // R-012: 症候间是否存在冲突
          const ids = input.activeSyndromes.map((s) => s.id);
          const hasConflict = ids.length >= 2;
          if (value === true && !hasConflict) return false;
          if (value === false && hasConflict) return false;
          break;
        }
        case 'syndromePriority': {
          // R-015: 检查症候是否属于高优先级
          const highPriority = ['P006', 'P004']; // 影响阅读体验的症候
          const hasPriority = input.activeSyndromes.some((s) => highPriority.includes(s.id));
          if (value === 'reading_experience_impact' && !hasPriority) return false;
          break;
        }
        default:
          // 无法识别的条件跳过
          break;
      }
    }
    return true;
  }

  /** 数字严重度转 L1/L2/L3 标签 */
  private severityToLabel(sev: number): string {
    if (sev >= 3) return 'L3';
    if (sev >= 2) return 'L2';
    return 'L1';
  }

  /** 获取应优先处理的症候 ID 列表（来自 R-015） */
  private getPrioritySyndromeIds(): string[] {
    // R-015 规则定义 P006, P004 优先
    return ['P006', 'P004'];
  }

  /** 计算训练平均分映射 */
  private computeAvgTrainingScores(
    history: Array<{ syndromeId: string; score: number }>,
  ): Map<string, number> {
    const scoreMap = new Map<string, { total: number; count: number }>();
    for (const h of history) {
      const entry = scoreMap.get(h.syndromeId) ?? { total: 0, count: 0 };
      entry.total += h.score;
      entry.count += 1;
      scoreMap.set(h.syndromeId, entry);
    }
    const avgMap = new Map<string, number>();
    for (const [id, data] of scoreMap.entries()) {
      avgMap.set(id, data.total / data.count);
    }
    return avgMap;
  }

  // ==============================
  // Layer 2: 教学方式选择
  // ==============================

  private selectTeachingMode(input: RouterInput, _focus: FocusDecision): ModeDecision {
    const syndromeTypeMap = this.loadSyndromeTypeMap();
    const userTypeMap = this.loadUserTypeMap();
    const theoryFragments = this.loadEducationTheoryFragments();

    // Step 1: 映射症候到类型
    const syndromeIds = input.activeSyndromes.map((s) => s.id);
    const dominantType = this.getDominantSyndromeType(syndromeIds, syndromeTypeMap);

    // Step 2: 获取推荐入口
    const typeConfig = dominantType ? syndromeTypeMap.types[dominantType] : null;
    const recommendedEntry = typeConfig?.recommendedEntry ?? '';
    const strategy = ENTRY_TO_STRATEGY[recommendedEntry] ?? 'case-driven';

    // Step 3: 从 userTypeMap 获取粗粒度 mode
    const styleKey = this.buildTeachingStyleKey(input);
    const styleConfig = styleKey ? userTypeMap.teachingStyleMap[styleKey] : null;
    let coarseMode: TeachingMode = 'guiding';

    if (styleConfig) {
      coarseMode = USER_TYPE_MODE_TO_TEACHING_MODE[styleConfig.mode] ?? 'guiding';
    }

    // Step 4: 匹配教育学规则细化教学模式
    const theoryRefs: string[] = [];
    const LAYER2_AND_REPEAT_RULE_IDS = [
      ...LAYER2_THEORY_RULE_IDS,
      'R-007', 'R-008', 'R-009', 'R-010',
    ];

    for (const rule of theoryFragments) {
      if (LAYER2_AND_REPEAT_RULE_IDS.includes(rule.id)) {
        if (this.matchesCondition(rule.condition, input)) {
          const refinedMode = this.refineModeFromRule(rule.recommendedMode);
          if (refinedMode) {
            coarseMode = refinedMode;
          }
          theoryRefs.push(`${rule.id}: ${rule.rationale}`);
        }
      }
    }

    // Step 5: 态度覆盖
    if (input.attitude === 'direct') {
      coarseMode = 'challenging';
    } else if (input.attitude === 'doubao') {
      coarseMode = coarseMode === 'challenging' ? 'guiding' : coarseMode;
    }

    return {
      teachingMode: coarseMode,
      strategy,
      syndromeType: dominantType ?? '',
      recommendedEntry,
      theoryReference: theoryRefs,
    };
  }

  /** 获取占主导的症候类型 */
  private getDominantSyndromeType(
    syndromeIds: string[],
    typeMap: SyndromeTypeMapConfig,
  ): string | null {
    const typeCounts = new Map<string, number>();

    for (const [typeName, typeInfo] of Object.entries(typeMap.types)) {
      const matchCount = syndromeIds.filter((id) => typeInfo.syndromes.includes(id)).length;
      if (matchCount > 0) {
        typeCounts.set(typeName, matchCount);
      }
    }

    if (typeCounts.size === 0) return null;

    // 返回匹配最多的类型
    let dominant: string | null = null;
    let maxCount = 0;
    for (const [typeName, count] of typeCounts) {
      if (count > maxCount) {
        dominant = typeName;
        maxCount = count;
      }
    }
    return dominant;
  }

  /** 构建 userTypeMap.teachingStyleMap 的查找键 */
  private buildTeachingStyleKey(input: RouterInput): string | undefined {
    const { userLevel, cognitiveStyle, topSyndromeCount } = input;

    // 尝试多个可能的 key，返回第一个匹配的
    const candidates: string[] = [];

    if (userLevel === 'beginner') {
      candidates.push('low_confidence_newbie');
      if (cognitiveStyle === 'emotional') candidates.unshift('emotional_newbie');
      // newbie_with_draft 需要有草稿历史才能匹配
      candidates.push('newbie_with_draft');
    } else if (userLevel === 'advanced') {
      if (topSyndromeCount >= 3) {
        candidates.push('experienced_syndrome_repeat');
      }
      candidates.push('high_confidence_experienced');
      if (cognitiveStyle === 'analytical') candidates.push('analytical_advanced');
    } else {
      // intermediate
      if (cognitiveStyle === 'analytical') {
        candidates.push('analytical_intermediate');
      } else if (cognitiveStyle === 'emotional') {
        candidates.push('emotional_intermediate');
      }
      candidates.push('high_confidence_experienced');
    }

    const styleMap = this.loadUserTypeMap().teachingStyleMap;
    for (const key of candidates) {
      if (styleMap[key]) return key;
    }
    return undefined;
  }

  /** 从教育理论规则的 recommendedMode 映射到 TeachingMode */
  private refineModeFromRule(recommendedMode: string): TeachingMode | null {
    const lower = recommendedMode.toLowerCase();
    // R-010 降级训练 → 降到最低教学模式（scaffolding）
    if (lower.includes('降级') || lower.includes('downgrade')) {
      return 'scaffolding';
    }
    // R-009 拆分训练+元认知 → guiding（引导用户拆解子技能）
    if (lower.includes('拆分') || lower.includes('元认知') || lower.includes('自我诊断')) {
      return 'guiding';
    }
    // R-007 微任务 → scaffolding
    if (lower.includes('微任务') || lower.includes('自主选择')) {
      return 'scaffolding';
    }
    if (lower.includes('scaffold') || lower.includes('支架') || lower.includes('案例') || lower.includes('案例驱动')) {
      return 'scaffolding';
    }
    // R-008 撤除脚手架 → challenging（不再提供案例支撑）
    if (lower.includes('撤除') || lower.includes('拆除')) {
      return 'challenging';
    }
    if (lower.includes('guiding') || lower.includes('引导') || lower.includes('分析')) {
      return 'guiding';
    }
    if (lower.includes('challeng') || lower.includes('挑战') || lower.includes('反思')) {
      return 'challenging';
    }
    return null;
  }

  // ==============================
  // Layer 3: 参数细化
  // ==============================

  private refineParameters(
    input: RouterInput,
    focus: FocusDecision,
    mode: ModeDecision,
  ): ParameterDecision {
    const learningPath = this.loadLearningPathConfig();
    const coachingTemplates = this.loadCoachingTemplates();

    // Step 1: 获取学习路径阶段
    const levelPath = learningPath[input.userLevel];
    const firstPhase = levelPath?.phases[0];
    const phaseId = firstPhase ? String(firstPhase.phase) : '1';

    // Step 2: 获取核心模式（优先 syndromeOverride）
    let corePatterns: string[] = [];
    if (focus.targetSyndrome && learningPath.syndromeOverride?.syndromePatternMap?.[focus.targetSyndrome]) {
      corePatterns = learningPath.syndromeOverride.syndromePatternMap[focus.targetSyndrome];
    } else if (firstPhase?.corePatterns) {
      corePatterns = firstPhase.corePatterns.map((p) => p.id);
    }

    // Step 3: 过滤 coaching templates
    const matchedTemplates = this.filterCoachingTemplates(
      coachingTemplates,
      input.userLevel,
      focus.targetSyndrome,
    );

    // Step 4: 构建 stepSequence
    const stepSequence = this.buildStepSequence(matchedTemplates, input, mode);

    // Step 6: 确定匹配的模板 ID
    const matchedTemplateId = matchedTemplates.length > 0 ? matchedTemplates[0].id : undefined;

    // Step 7: 确定练习类型
    const practiceType = SYNDROME_TYPE_TO_PRACTICE[mode.syndromeType]
      ?? MODE_TO_PRACTICE[mode.teachingMode]
      ?? 'guided_practice';

    return {
      phaseId,
      corePatterns,
      stepSequence,
      matchedTemplateId,
      practiceType,
    };
  }

  /** 过滤 coaching templates */
  private filterCoachingTemplates(
    config: CoachingTemplatesConfig,
    userLevel: string,
    targetSyndrome: string,
  ): CoachingTemplate[] {
    return config.strategies.filter((t) => {
      const levels = t.triggerConditions.applicableLevels;
      const syndromes = t.triggerConditions.applicableSyndromes;

      // 检查用户水平
      const levelMatch = levels.length === 0 || levels.includes(userLevel) || levels.includes('*');

      // 检查症候匹配
      const syndromeMatch = syndromes.length === 0
        || syndromes.includes('*')
        || syndromes.includes(targetSyndrome);

      return levelMatch && syndromeMatch;
    });
  }

  /** 构建步骤序列 */
  private buildStepSequence(
    templates: CoachingTemplate[],
    input: RouterInput,
    mode: ModeDecision,
  ): ParameterDecision['stepSequence'] {
    if (templates.length === 0) {
      // 无匹配模板时返回默认步骤
      return [{
        stepId: 'default-1',
        stepName: '基础教学',
        coachingTemplateRef: '__default__',
        toneProfile: this.resolveToneFromMode(mode.teachingMode, input),
      }];
    }

    // 取第一个匹配模板（按排序）
    const template = templates[0];
    const toneProfile = this.resolveToneFromMode(mode.teachingMode, input);

    return template.steps.map((step) => ({
      stepId: `${template.id}-step-${step.order}`,
      stepName: step.action,
      coachingTemplateRef: template.id,
      toneProfile,
    }));
  }

  /** 根据教学模式、认知风格、用户水平综合解析语气 */
  private resolveToneFromMode(teachingMode: TeachingMode, input: RouterInput): string {
    // 1. 优先使用 Persona 预设（PE-001 结构化替代硬编码）
    const persona = input.persona ?? (input.attitude ? PERSONA_PRESETS[input.attitude] : undefined);
    if (persona) {
      return persona.tone;
    }

    // 2. 次优先使用 user-type-map 的 teachingStyleMap
    const userTypeMap = this.loadUserTypeMap();
    const styleKey = this.computeTeachingStyleKey(input);
    if (styleKey && userTypeMap.teachingStyleMap[styleKey]?.tone) {
      return userTypeMap.teachingStyleMap[styleKey].tone;
    }

    // 3. 兜底：教学模式映射
    const modeToneMap: Record<TeachingMode, string> = {
      scaffolding: 'encouraging',
      guiding: 'direct',
      challenging: 'challenging',
    };
    return modeToneMap[teachingMode] ?? 'direct';
  }

  /**
   * 计算 user-type-map 的 teachingStyleMap key
   *
   * 组合规则：
   *   cognitiveStyle + userLevel → key
   *   analytical + beginner/beginner → 'analytical_intermediate'
   *   emotional + intermediate → 'emotional_intermediate'
   *   特殊组合检测（优先于通用组合）
   */
  private computeTeachingStyleKey(input: RouterInput): string | null {
    const { userLevel, cognitiveStyle, topSyndromeCount } = input;
    if (!cognitiveStyle) return null;

    // 特殊组合：老手+重复问题
    if (userLevel === 'advanced' && (topSyndromeCount ?? 0) >= 3) {
      return 'experienced_syndrome_repeat';
    }
    // 特殊组合：新手+已有文稿
    if (userLevel === 'intermediate' && cognitiveStyle === 'emotional') {
      return 'emotional_intermediate';
    }

    // 通用组合：cognitiveStyle_userLevel
    const key = `${cognitiveStyle}_${userLevel}`;
    const userTypeMap = this.loadUserTypeMap();
    if (userTypeMap.teachingStyleMap[key]) {
      return key;
    }

    // 放宽匹配：按认知风格降级
    const fallbacks: Record<string, string> = {
      analytical: `analytical_intermediate`,
      emotional: `emotional_newbie`,
    };
    const fallback = cognitiveStyle ? fallbacks[cognitiveStyle] : undefined;
    if (fallback && userTypeMap.teachingStyleMap[fallback]) {
      return fallback;
    }

    return null;
  }

  /** 查找指定 ID 的教育理论规则 */
  private findTheoryRule(ruleId: string): EducationTheoryFragment | undefined {
    return this.loadEducationTheoryFragments().find((r) => r.id === ruleId);
  }

  // ==============================
  // Backward Compatibility Bridge
  // ==============================

  /**
   * 构建向后兼容字段
   * 映射到 TeachingStrategyService.TeachingStrategyDecision 接口
   */
  private buildLegacyBridge(
    input: RouterInput,
    mode: ModeDecision,
  ): RouterOutput['compatibleWithLegacy'] {
    const tone = this.resolveToneFromMode(mode.teachingMode, input);

    let format: string | undefined;
    if (mode.strategy === 'case-driven') {
      format = 'example→feeling→demonstration';
    } else if (mode.strategy === 'analysis-driven') {
      format = 'problem→cause→evidence→solution';
    }
    // reflection-driven 无固定 format

    return {
      mode: mode.teachingMode,
      tone,
      format,
    };
  }
}
