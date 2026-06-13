/**
 * 教学策略路由 — Layer 3：参数细化 + 后向兼容桥接
 */

import type { RouterInput, FocusDecision, ModeDecision, ParameterDecision, TeachingMode } from '../../renderer/shared/types';
import { RouterOutput, PERSONA_PRESETS } from '../../renderer/shared/types';
import type { RouterConfigs, CoachingTemplatesConfig, UserTypeMapConfig, CoachingTemplate } from './teaching-strategy-router.types';
import type { PhaseConfig } from './teaching-strategy-router.types';
import { SYNDROME_TYPE_TO_PRACTICE, MODE_TO_PRACTICE } from './teaching-strategy-router.constants';

/**
 * Layer 3：参数细化
 */
export function refineParameters(
  input: RouterInput,
  focus: FocusDecision,
  mode: ModeDecision,
  configs: RouterConfigs,
): ParameterDecision {
  const learningPath = configs.learningPath;
  const coachingTemplates = configs.coachingTemplates;

  const levelPath = learningPath[input.userLevel as keyof typeof learningPath];
  const typedLevelPath = levelPath && typeof levelPath === 'object' && 'phases' in levelPath
    ? (levelPath as { description: string; phases: PhaseConfig[]; skipPatterns: string[]; skipReason: string })
    : undefined;
  const firstPhase = typedLevelPath?.phases[0];
  const phaseId = firstPhase ? String(firstPhase.phase) : '1';

  let corePatterns: string[] = [];
  if (focus.targetSyndrome && learningPath.syndromeOverride?.syndromePatternMap?.[focus.targetSyndrome]) {
    corePatterns = learningPath.syndromeOverride.syndromePatternMap[focus.targetSyndrome];
  } else if (firstPhase?.corePatterns) {
    corePatterns = firstPhase.corePatterns.map((p) => p.id);
  }

  const matchedTemplates = filterCoachingTemplates(
    coachingTemplates,
    input.userLevel,
    focus.targetSyndrome,
  );

  const stepSequence = buildStepSequence(matchedTemplates, input, mode, configs.userTypeMap);
  const matchedTemplateId = matchedTemplates.length > 0 ? matchedTemplates[0].id : undefined;

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
export function filterCoachingTemplates(
  config: CoachingTemplatesConfig,
  userLevel: string,
  targetSyndrome: string,
): CoachingTemplate[] {
  return config.strategies.filter((t) => {
    const levels = t.triggerConditions.applicableLevels;
    const syndromes = t.triggerConditions.applicableSyndromes;

    const levelMatch = levels.length === 0 || levels.includes(userLevel) || levels.includes('*');
    const syndromeMatch = syndromes.length === 0
      || syndromes.includes('*')
      || syndromes.includes(targetSyndrome);

    return levelMatch && syndromeMatch;
  });
}

/** 构建步骤序列 */
export function buildStepSequence(
  templates: CoachingTemplate[],
  input: RouterInput,
  mode: ModeDecision,
  userTypeMap: UserTypeMapConfig,
): ParameterDecision['stepSequence'] {
  if (templates.length === 0) {
    return [{
      stepId: 'default-1',
      stepName: '基础教学',
      coachingTemplateRef: '__default__',
      toneProfile: resolveToneFromMode(mode.teachingMode, input, userTypeMap),
    }];
  }

  const template = templates[0];
  const toneProfile = resolveToneFromMode(mode.teachingMode, input, userTypeMap);

  return template.steps.map((step) => ({
    stepId: `${template.id}-step-${step.order}`,
    stepName: step.action,
    coachingTemplateRef: template.id,
    toneProfile,
  }));
}

/** 根据教学模式、认知风格、用户水平综合解析语气 */
export function resolveToneFromMode(
  teachingMode: TeachingMode,
  input: RouterInput,
  userTypeMap: UserTypeMapConfig,
): string {
  const persona = input.persona ?? (input.attitude ? PERSONA_PRESETS[input.attitude] : undefined);
  if (persona) {
    return persona.tone;
  }

  const styleKey = input.cognitiveStyle ? computeTeachingStyleKey(input, userTypeMap) : null;
  if (styleKey && userTypeMap.teachingStyleMap[styleKey]?.tone) {
    return userTypeMap.teachingStyleMap[styleKey].tone;
  }

  const modeToneMap: Record<TeachingMode, string> = {
    scaffolding: 'encouraging',
    guiding: 'direct',
    challenging: 'challenging',
  };
  return modeToneMap[teachingMode] ?? 'direct';
}

/** 计算 user-type-map 的 teachingStyleMap key */
export function computeTeachingStyleKey(input: RouterInput, userTypeMap?: UserTypeMapConfig): string | null {
  const { userLevel, cognitiveStyle, topSyndromeCount } = input;
  if (!cognitiveStyle) return null;

  if (userLevel === 'advanced' && (topSyndromeCount ?? 0) >= 3) {
    return 'experienced_syndrome_repeat';
  }
  if (userLevel === 'intermediate' && cognitiveStyle === 'emotional') {
    return 'emotional_intermediate';
  }

  const key = `${cognitiveStyle}_${userLevel}`;

  if (userTypeMap?.teachingStyleMap[key]) {
    return key;
  }

  const fallbacks: Record<string, string> = {
    analytical: `analytical_intermediate`,
    emotional: `emotional_newbie`,
  };
  const fallback = cognitiveStyle ? fallbacks[cognitiveStyle] : undefined;
  if (fallback && userTypeMap?.teachingStyleMap[fallback]) {
    return fallback;
  }

  return null;
}

/** 构建向后兼容字段 */
export function buildLegacyBridge(
  input: RouterInput,
  mode: ModeDecision,
  userTypeMap: UserTypeMapConfig,
): RouterOutput['compatibleWithLegacy'] {
  const tone = resolveToneFromMode(mode.teachingMode, input, userTypeMap);

  let format: string | undefined;
  if (mode.strategy === 'case-driven') {
    format = 'example→feeling→demonstration';
  } else if (mode.strategy === 'analysis-driven') {
    format = 'problem→cause→evidence→solution';
  }

  return {
    mode: mode.teachingMode,
    tone,
    format,
  };
}
