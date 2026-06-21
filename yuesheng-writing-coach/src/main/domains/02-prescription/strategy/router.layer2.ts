/**
 * 教学策略路由 — Layer 2：教学方式选择
 */

import type { RouterInput, FocusDecision, ModeDecision, TeachingMode } from '../../../../shared/types/index';
import type { RouterConfigs, UserTypeMapConfig } from './router.types';
import { ENTRY_TO_STRATEGY, USER_TYPE_MODE_TO_TEACHING_MODE, LAYER2_THEORY_RULE_IDS } from './router.constants';
import { matchesCondition, getDominantSyndromeType } from './router.conditions';

/**
 * Layer 2：教学方式选择
 */
export function selectTeachingMode(input: RouterInput, _focus: FocusDecision, configs: RouterConfigs): ModeDecision {
  const syndromeTypeMap = configs.syndromeTypeMap;
  const userTypeMap = configs.userTypeMap;
  const theoryFragments = configs.educationTheoryFragments;

  // Step 1: 映射症候到类型
  const syndromeIds = input.activeSyndromes.map((s) => s.id);
  const dominantType = getDominantSyndromeType(syndromeIds, syndromeTypeMap);

  // Step 2: 获取推荐入口
  const typeConfig = dominantType ? syndromeTypeMap.types[dominantType] : null;
  const recommendedEntry = typeConfig?.recommendedEntry ?? '';
  const strategy = ENTRY_TO_STRATEGY[recommendedEntry] ?? 'case-driven';

  // Step 3: 从 userTypeMap 获取粗粒度 mode
  const styleKey = buildTeachingStyleKey(input, userTypeMap);
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
      if (matchesCondition(rule.condition, input, configs)) {
        const refinedMode = refineModeFromRule(rule.recommendedMode);
        if (refinedMode) {
          coarseMode = refinedMode;
        }
        theoryRefs.push(`${rule.id}: ${rule.rationale}`);
      }
    }
  }

  // Step 5: 态度覆盖
  if (input.attitude === 'sensei') {
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

/** 构建 userTypeMap.teachingStyleMap 的查找键 */
export function buildTeachingStyleKey(input: RouterInput, userTypeMap: UserTypeMapConfig): string | undefined {
  const { userLevel, cognitiveStyle, topSyndromeCount } = input;

  const candidates: string[] = [];

  if (userLevel === 'beginner') {
    candidates.push('low_confidence_newbie');
    if (cognitiveStyle === 'emotional') candidates.unshift('emotional_newbie');
    candidates.push('newbie_with_draft');
  } else if (userLevel === 'advanced') {
    if (topSyndromeCount >= 3) {
      candidates.push('experienced_syndrome_repeat');
    }
    candidates.push('high_confidence_experienced');
    if (cognitiveStyle === 'analytical') candidates.push('analytical_advanced');
  } else {
    if (cognitiveStyle === 'analytical') {
      candidates.push('analytical_intermediate');
    } else if (cognitiveStyle === 'emotional') {
      candidates.push('emotional_intermediate');
    }
    candidates.push('high_confidence_experienced');
  }

  const styleMap = userTypeMap.teachingStyleMap;
  for (const key of candidates) {
    if (styleMap[key]) return key;
  }
  return undefined;
}

/** 从教育理论规则的 recommendedMode 映射到 TeachingMode */
export function refineModeFromRule(recommendedMode: string): TeachingMode | null {
  const lower = recommendedMode.toLowerCase();
  if (lower.includes('降级') || lower.includes('downgrade')) {
    return 'scaffolding';
  }
  if (lower.includes('拆分') || lower.includes('元认知') || lower.includes('自我诊断')) {
    return 'guiding';
  }
  if (lower.includes('微任务') || lower.includes('自主选择')) {
    return 'scaffolding';
  }
  if (lower.includes('scaffold') || lower.includes('支架') || lower.includes('案例') || lower.includes('案例驱动')) {
    return 'scaffolding';
  }
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
