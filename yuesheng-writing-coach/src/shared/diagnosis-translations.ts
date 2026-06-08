/**
 * 诊断翻译层
 * 负责：将内部诊断结果（P001/L2 等内部术语）翻译为用户可理解的自然语言
 *
 * 设计依据：diagnosis-translation-layer_V1.0.md
 * 核心原则：不向用户输出 Layer 1 的诊断结果（评分、病症编号、诊断报告）
 */

import type { SeverityLevel } from '../renderer/shared/types';

/** 用户可见的症候诊断 */
export interface UserFacingDiagnosis {
  /** 用户友好的症候名（正面表述） */
  name: string;
  /** 教练语言的描述 */
  description: string;
  /** 严重度等级（仅用颜色表示，不显示文字） */
  severityLevel: 'mild' | 'moderate' | 'severe';
}

/** 翻译映射表 */
interface TranslationEntry {
  /** 正面表述名称 */
  name: string;
  /** 不同严重度对应的教练语言描述 */
  description: {
    L1?: string;
    L2?: string;
    L3?: string;
    default: string;
  };
}

/** P001~P010 的教练语言翻译映射 */
const DIAGNOSIS_TRANSLATIONS: Record<string, TranslationEntry> = {
  P001: {
    name: '你的故事设定很丰富',
    description: {
      L1: '开场可以试着先展示主角的日常',
      L2: '但主角的出场还不太清晰',
      L3: '建议先聚焦第一个场景，设定可以后续逐步展开',
      default: '建议先从场景入手',
    },
  },
  P002: {
    name: '角色互动自然',
    description: {
      L1: '个别角色的语气还可以更鲜明',
      L2: '但角色之间的谈话还需要更多个性',
      L3: '角色像工具人，需要赋予独立动机',
      default: '试着让每个角色说话的方式不一样',
    },
  },
  P003: {
    name: '情绪描写真实',
    description: {
      L1: '部分场景可以用动作代替直接描述',
      L2: '有些情绪可以直接用行为展现',
      L3: '建议用行动替代情绪词',
      default: '试试用行动来表达感受',
    },
  },
  P004: {
    name: '故事信息量丰富',
    description: {
      L1: '开头可以再放慢一点节奏',
      L2: '开场信息稍多，可以让角色带出设定',
      L3: '建议把设定融入角色行为而非直接说明',
      default: '试着把设定融入情节',
    },
  },
  P005: {
    name: '人物形象鲜明',
    description: {
      L1: '可以再丰富一下角色的背景',
      L2: '视角可以更集中到主角身上',
      L3: '建议锁定单一视角，删除全知部分',
      default: '让角色的行为更有说服力',
    },
  },
  P006: {
    name: '故事框架完整',
    description: {
      L1: '开篇可以增加一个推动事件',
      L2: '让主角在前三段做个选择来推动故事',
      L3: '故事缺乏推动力，建议制造一个主动选择',
      default: '给故事一个推动力',
    },
  },
  P007: {
    name: '涉猎广泛',
    description: {
      L1: '可以尝试从传统文学中吸收技巧',
      L2: '建议阅读传统文学作品学习开场技巧',
      default: '试着从传统文学中吸收叙事技巧',
    },
  },
  P009: {
    name: '角色很有潜力',
    description: {
      L1: '可以再多展现角色的内心',
      L2: '角色的动机还不太清晰',
      L3: '角色的核心动机需要明确',
      default: '让读者理解角色为什么这么做',
    },
  },
  P010: {
    name: '想象力丰富',
    description: {
      L1: '可以注意场景之间的过渡',
      L2: '转折需要更自然的铺垫',
      L3: '角色需要经历一次真正的改变',
      default: '让变化更符合逻辑',
    },
  },
};

/** 严重度映射 */
const SEVERITY_MAP: Record<string, 'mild' | 'moderate' | 'severe'> = {
  L1: 'mild',
  L2: 'moderate',
  L3: 'severe',
};

/** 变种正向表述翻译 */
const VARIANT_TRANSLATIONS: Record<string, string> = {
  setting_overload: '设定超载型',
  info_in_dialogue: '对话塞设定型',
  setting_interrupt: '设定打断型',
  info_delivery: '信息传递型',
  plot_device: '剧情道具型',
  exposition_dump: '说明文型',
  dialogue_explain: '对话解释型',
};

/** 获取变种的用户友好标签 */
export function getVariantLabel(variant: string): string {
  return VARIANT_TRANSLATIONS[variant] ?? variant;
}

/**
 * 将内部症候诊断翻译为用户可理解的自然语言
 *
 * @param id - 内部症候 ID（如 P001）
 * @param severity - 严重度等级
 * @returns 用户可见的诊断描述
 */
export function diagnosisToUserFacing(
  id: string,
  severity: SeverityLevel,
): UserFacingDiagnosis {
  const translation = DIAGNOSIS_TRANSLATIONS[id];

  if (!translation) {
    return {
      name: id,
      description: '',
      severityLevel: SEVERITY_MAP[severity] ?? 'mild',
    };
  }

  return {
    name: translation.name,
    description: translation.description[severity] ?? translation.description.default,
    severityLevel: SEVERITY_MAP[severity] ?? 'mild',
  };
}

/**
 * 批量翻译诊断列表
 *
 * @param syndromes - 内部症候列表
 * @returns 用户可见的诊断列表
 */
export function syndromesToUserFacing(
  syndromes: Array<{ id: string; name: string; severity: SeverityLevel }>,
): UserFacingDiagnosis[] {
  return syndromes.map(s => diagnosisToUserFacing(s.id, s.severity));
}
