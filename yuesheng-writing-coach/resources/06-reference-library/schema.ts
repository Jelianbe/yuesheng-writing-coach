/**
 * 后备资料库（Reference / Knowledge Library）——条目结构 Schema
 *
 * 本文件定义资料库条目的 TypeScript 类型，供教学系统（Teaching Agent）在
 * 运行时装载与检索。资料库是「创作技法知识」的权威来源，与 01-diagnosis
 * （症候）、02-prescription（技法/能力节点）、03-teaching（教学策略）并列，
 * 作为 AI 教学时的「补充数据」被检索与调用。
 *
 * 设计原则（继承自项目纪律 R-021 / 教练哲学）：
 *  - 资料库只提供「创作知识」，不替用户写句子、不替用户做决定。
 *  - teachingTips 字段必须体现「找根因、引导、不代劳」的教练姿态。
 *  - externalRefs 只引用书名/作者与方法论框架，不编造章节/页码/原文。
 */

/** 难度档位 */
export type Difficulty = 'beginner' | 'intermediate' | 'advanced';

/** 资料库可服务的教学场景（决定检索路由） */
export type TeachingScenario =
  | 'onboarding' // 新用户引导
  | 'post-diagnosis' // 诊断后讲解根因
  | 'in-flow-coaching' // 对话内即时教练
  | 'pre-training' // 训练前铺垫
  | 'contrast-demo' // 对比展示（好/差范例）
  | 'browse' // 自主浏览/扩展阅读
  | 'review'; // 复盘/回顾

/** 外部参考资料（遵守 external-resources.json 的引用纪律） */
export interface ExternalRef {
  title: string;
  author: string;
  /** 可引用的方法论框架，不得引用具体案例/章节/页码 */
  note: string;
}

/** 示例片段：含上下文、原文摘录、为什么有效（或为什么失败）的分析 */
export interface ExampleFragment {
  context: string;
  excerpt: string;
  analysis: string;
}

/**
 * 资料库条目（知识卡）
 */
export interface ReferenceEntry {
  /** 全局唯一 ID，格式 REF-<分类>-<序号>，如 REF-C2-002 */
  id: string;
  /** 标题 */
  title: string;
  /** 一级分类 ID（C1..C7） */
  category: string;
  /** 一级分类中文名 */
  categoryLabel: string;
  /** 二级子分类（可选） */
  subcategory?: string;
  /** 一句话核心摘要 */
  summary: string;
  /** 核心要点（3-6 条） */
  corePoints: string[];
  /** 示例片段（1-3 条） */
  examples: ExampleFragment[];
  /** 教学提示：AI 教练应如何用这一条知识引导用户（体现教练哲学） */
  teachingTips: string[];
  /** 常见误区（可选，关联 C7） */
  commonMistakes?: string[];
  /** 关联诊断症候 ID（P001..P012），用于「诊断 → 资料」路由 */
  relatedSyndromes?: string[];
  /** 关联技法 ID（TQ-/TC-），用于「资料 → 练习」链路 */
  relatedTechniques?: string[];
  /** 难度档位 */
  difficulty: Difficulty;
  /** 检索关键词（供关键词/语义检索匹配） */
  retrievalKeywords: string[];
  /** 可服务的教学场景 */
  scenarios: TeachingScenario[];
  /** 外部参考（仅书名/作者/框架） */
  externalRefs?: ExternalRef[];
  /** 最后更新日期 YYYY-MM-DD */
  updatedAt: string;
}

/** 分类节点（用于 taxonomy 树与 UI 呈现） */
export interface CategoryNode {
  id: string;
  label: string;
  description: string;
  children?: CategoryNode[];
}

/** 资料库整体索引文件结构 */
export interface LibraryIndex {
  version: string;
  updatedAt: string;
  description: string;
  /** 分类树 */
  taxonomy: CategoryNode[];
  /** 症候 → 条目 ID 映射 */
  syndromeMap: Record<string, string[]>;
  /** 场景 → 条目 ID 映射 */
  scenarioMap: Record<TeachingScenario, string[]>;
  /** 关键词 → 条目 ID 倒排索引（小写） */
  keywordIndex: Record<string, string[]>;
}

/** 教学上下文：检索器据此组合应注入的参考资料 */
export interface TeachingContext {
  /** 当前诊断症候（可能为空，如纯浏览场景） */
  syndrome?: string;
  /** 学员水平 */
  studentLevel?: '新手' | '进阶' | '熟练';
  /** 项目类型（玄幻/言情/悬疑…） */
  projectType?: string;
  /** 触发场景 */
  scenario: TeachingScenario;
  /** 自由文本查询（可选，用于关键词/语义检索） */
  query?: string;
  /** 返回上限 */
  limit?: number;
}

/** 注入 Teaching Agent 的精简参考资料结构（对应 availableTechniques 的形态） */
export interface InjectableReference {
  id: string;
  title: string;
  summary: string;
  corePoints: string[];
  examples: ExampleFragment[];
  teachingTips: string[];
  difficulty: Difficulty;
}
