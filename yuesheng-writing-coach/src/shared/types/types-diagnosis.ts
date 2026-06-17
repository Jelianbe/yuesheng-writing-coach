// 诊断域类型

/** 诊断严重度等级 */
export type SeverityLevel = 'L1' | 'L2' | 'L3';

/** 病症 ID（运行时常量见 constants.js → SyndromeId） */
export type SyndromeId = string;

/** 症候类型分类（V6.0新增，用于教育学规则匹配） */
export type SyndromeType = 'expressive_deficit' | 'structural_disorder' | 'motivation_deficit';

/** 教学动作 ID（运行时常量见 constants.js → ActionId） */
export type ActionId = string;

/** 触发信号（诊断引擎用，仅用于诊断解析器验证） */
export interface SyndromeSignal {
  /** 信号类型：关键词/正则/句式 */
  type: string;
  /** 匹配模式（关键词或正则表达式） */
  pattern: string;
  /** 权重分值 */
  weight: number;
  /** 是否匹配到文本前缀位置 */
  prefixMatch?: boolean;
  /** 匹配到的文本片段 */
  matchedText?: string;
}

/** 单个病症诊断结果（AI 输出格式） */
export interface SyndromeResult {
  /** 病症 ID（可能与 variant 编码在同一字符串中，如 "P001::setting_overload"） */
  id: SyndromeId;
  /** 变种标识（如 "setting_overload"），由 parser 从 id 中拆分 */
  variant?: string;
  /** 病症名称 */
  name: string;
  /** 严重度等级 */
  severity: SeverityLevel;
  /** 用户原文证据片段 */
  evidence: string[];
  /** 信号分（可选，用于排序） */
  score?: number;
  /** 建议教学动作 */
  suggestedActions: ActionId[];
  /** AI 提供的修改建议（可选，用于治疗模式） */
  rewriteSuggestion?: string;
}

/** AI 修改评估结果 */
export interface RewriteEvaluation {
  /** 改善程度 */
  improvement: '明显改善' | '略有改善' | '无明显改善';
  /** 具体分析 */
  analysis: string;
  /** 一句话建议 */
  suggestion: string;
}

/** 教学进度(RWR-P0-1 新增,按会话分组持久化)
 *  - R-021 隐性诊断: 进度不暴露症候细节,只显示分子分母
 *  - R-014 配置外置: 该结构仅持久化不参与诊断决策
 */
export interface TeachingProgress {
  /** 当前教学阶段(教学状态机枚举值,见 types-teaching.TeachingPhase) */
  currentStage: string;
  /** 已解决问题数(分子,只增不减) */
  resolvedIssues: number;
  /** 总问题数(分母,只增不减) */
  totalIssues: number;
}

/** 完整诊断条目(AI 输出格式) */
export interface DiagnosisEntry {
  /** 所属会话 ID */
  sessionId: string;
  /** 所属消息 ID */
  messageId: string;
  /** 识别到的病症列表(按严重度排序) */
  syndromes: SyndromeResult[];
  /** 合并后的建议动作列表(去重） */
  suggestedActions: ActionId[];
  /** 整体置信度（0-1） */
  confidence: number;
  /** 诊断时间戳（ISO 8601 格式） */
  timestamp: string;
  /** 下一步建议关注的病症 ID */
  nextFocus?: SyndromeId;
  /** SF-004: 节拍完整性检测结果（叙事节奏诊断用） */
  beatCheck?: Record<string, boolean>;
  /** RWR-P0-1: 教学进度(可选,旧诊断条目无此字段) */
  teachingProgress?: TeachingProgress;
}

/** 单条证据记录 */
export interface EvidenceRecord {
  evidenceId: string;
  type: 'text' | 'pattern' | 'statistical' | 'comparison';
  level: 1 | 2 | 3 | 4;
  novelId: string;
  contentJson: string;
  relatedDisease: string;
  relatedAbility: string;
  extractedBy: string;
  createdAt: string;
}

/** 诊断证据链（含关联关系） */
export interface EvidenceChain {
  diagnosisId: string;
  primaryEvidence: EvidenceRecord[];
  supportingEvidence: EvidenceRecord[];
  statistics: EvidenceRecord[];
}

/** 技法池条目（Diagnosis Agent 输出用） */
export interface TechniqueRef {
  /** 技法名 */
  name: string;
  /** 来源作品 */
  source: string;
  /** 难度等级 */
  difficulty: 'beginner' | 'intermediate';
}

/** 关键段落引用（Diagnosis Agent 输出用） */
export interface KeyPassage {
  /** 原文片段（不超过 50 字） */
  text: string;
  /** 问题描述 */
  issue: string;
  /** 关联的症候 ID（可选，用于按症候分组证据） */
  syndromeRef?: string;
}

/** 诊断 Agent 的结构化输出 */
export interface DiagnosisAnalysis {
  /** 内容类型：narrative=叙事文本（执行完整诊断），non-narrative=非叙事（跳过症候诊断） */
  contentType?: 'narrative' | 'non-narrative';
  /** 根因：一句话概括（不超过 20 字） */
  rootCause: string;
  /** 意图阶段：0=未成形/1=模糊/2=明确但不一致 */
  intentPhase: number;
  /** 关联症候编号列表（内部使用） */
  syndromeRef: string[];
  /** 可选技法池（3-5条） */
  techniquePool: TechniqueRef[];
  /** 文本中的关键段落（供教学引用） */
  keyPassages: KeyPassage[];
  /** 置信度（0-1） */
  confidence: number;
  /** SF-003: 节拍完整性检测（激励事件/中点转折/高潮/结局/开篇钩子） */
  beatCheck?: Record<string, boolean>;
}
