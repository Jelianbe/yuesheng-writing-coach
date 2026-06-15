// 执行分析类型

/** 执行模式（从文本中提取） */
export interface ExecutionPattern {
  /** 主角起点修为/地位 */
  protagonistStartingLevel: string;
  /** 危机类型 */
  crisisType: string;
  /** 叙事模式 */
  narrativePattern: string;
  /** 金手指类型 */
  advantageType?: string;
  /** 日常/经济/阶层描写密度 0-1 */
  dailyLifeDensity: number;
  /** 与意图的匹配度（规则引擎计算） */
  intentConsistencyScore: number;
  /** 检测到的矛盾点 */
  mismatches: ConsistencyGap[];
}

/** 一致性检测规则匹配结果 */
export interface ConsistencyGap {
  /** 规则 ID */
  ruleId: string;
  /** 意图描述 */
  intent: string;
  /** 实际操作 */
  execution: string;
  /** 矛盾说明 */
  gap: string;
  /** 严重程度 1-5 */
  severity: number;
  /** 关联症候 */
  relatedSyndrome?: string;
}

/** 意图阶段枚举 */
export type IntentPhase = 'unknown' | 'incubating' | 'emerging' | 'established';

/** 作者阶段（面对诊断时的认知状态） */
export type AuthorStage = 'defensive' | 'accepting' | 'patching' | 'attributing';
