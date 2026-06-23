/**
 * 蒸馏素材 — 类型定义
 *
 * 对应 resources/distillation-index.json
 * Sprint 15 T15-A：461 条素材（批次 001 避雷/教学 + 批次 002 困境/习惯 + 批次 003 PL/SC/DG）
 */

// ==============================
// 单条素材
// ==============================

/** 蒸馏素材条目 */
export interface DistillationEntry {
  /** 新格式 ID：DST-001-001 ~ DST-003-061 */
  id: string;
  /** 旧格式 ID：B-001 / J-001 / K-001 / X-001 / PL-01 / SC-01 / DG-01 */
  legacyId: string;
  /** 批次号 */
  batch: '001' | '002' | '003';
  /** 批次标签 */
  batchLabel: string;
  /** 章节分类（避雷/教学/困境/习惯/情节/场景/对话） */
  category: string;
  /** 来源平台 */
  platform: string;
  /** 摘要（≤20 字） */
  summary: string;
  /** 完整内容 */
  content: string;
  /** 症候标签 */
  syndromes: {
    /** 主症候（P001 / P001_pos / null / 辅助标签"心态""对话"） */
    primary: string | null;
    /** 次症候列表 */
    secondary: string[];
  };
  /** 教学动作 */
  teachingAction: string | null;
  /** 关键词标签 */
  keywordTags: string[];
  /** 标注方式 */
  taggedBy: 'human' | 'heuristic';
  /** 原始 MD 文件路径 */
  sourceFile: string;
}

// ==============================
// 索引根结构
// ==============================

/** 蒸馏素材索引 JSON 根结构 */
export interface DistillationIndexJson {
  version: string;
  generatedAt: string;
  description: string;
  sources: {
    batch001: string;
    batch002: string;
    batch003: string;
    tags: string;
  };
  statistics: {
    total: number;
    batch001: number;
    batch002: number;
    batch003: number;
    taggedByHuman: number;
    taggedByHeuristic: number;
  };
  entries: DistillationEntry[];
}

// ==============================
// 查询选项
// ==============================

/** 搜索选项 */
export interface DistillationSearchOptions {
  /** 关键词搜索（content + summary + teachingAction） */
  query?: string;
  /** 按症候过滤（匹配 primary + secondary） */
  syndromeId?: string;
  /** 按批次过滤 */
  batch?: '001' | '002' | '003';
  /** 按标签过滤 */
  taggedBy?: 'human' | 'heuristic';
  /** 限制返回条数 */
  limit?: number;
}

/** 统计信息 */
export interface DistillationStatistics {
  total: number;
  byBatch: Record<string, number>;
  byTag: Record<string, number>;
  bySyndromePrimary: Record<string, number>;
}
