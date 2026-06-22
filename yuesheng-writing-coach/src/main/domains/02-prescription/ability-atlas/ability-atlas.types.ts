/**
 * 能力图谱 — 类型定义
 *
 * 对应 resources/knowledge-graph/ability-atlas.json
 * 和 resources/02-prescription/ability-nodes/ability-node-prototypes.json 的结构
 */

// ==============================
// ability-atlas.json 类型
// ==============================

/** 能力节点 */
export interface AtlasAbilityNode {
  id: string;                // ABL-001 ~ ABL-008
  name: string;
  description: string;
  category: string;          // '叙事能力' | '角色能力' | '世界观能力' | '语言能力' | '学习能力'
  syndromes: string[];       // 关联症候 ID 列表
  primary_tasks: string[];   // 训练任务 ID 列表
  actions: string[];         // 教学动作 ID 列表
  prerequisites: string[];   // 前置能力 ID 列表
  level: number;             // 1/2/3
  training_focus: string;
}

/** 症候节点 */
export interface AtlasSyndrome {
  id: string;                // P001 ~ P010
  name: string;
  description: string;
  related_abilities: string[];
  severity_L1: string;
  severity_L2: string;
  severity_L3: string;
  training_tasks: string[];
  primary_action: string;
}

/** 训练任务元数据 */
export interface AtlasTrainingTask {
  id: string;                // T001 ~ T020
  type: string;
  syndrome: string;
  related_abilities: string[];
  difficulty: number;        // 1/2/3
}

/** 图谱查询路径 */
export interface AtlasQueryPath {
  name: string;
  from: string;
  path: string;
}

/** 能力图谱 JSON 根结构 */
export interface AbilityAtlasJson {
  _meta: {
    title: string;
    version: string;
    updated: string;
    purpose: string;
    based_on: string[];
  };
  abilities: AtlasAbilityNode[];
  syndromes: AtlasSyndrome[];
  training_tasks: AtlasTrainingTask[];
  queries: {
    description: string;
    paths: AtlasQueryPath[];
  };
}

// ==============================
// ability-node-prototypes.json 类型
// ==============================

/** 能力节点原型（教学原子） */
export interface AbilityNodePrototype {
  id: string;                 // AB-001 ~ AB-005
  name: string;
  definition: string;
  positive_manifestation: string;
  negative_manifestation: string;
  related_syndromes: string[];
  teaching_approaches: {
    primary: string;
    alternative: string;
    case_source: string;
  };
  related_techniques: string[];
}

/** 能力节点原型 JSON 根结构 */
export interface AbilityNodePrototypesJson {
  version: string;
  description: string;
  nodes: AbilityNodePrototype[];
}

// ==============================
// syndrome-action-map.json 类型
// ==============================

/** 症候→教学动作映射 */
export interface SyndromeActionMapping {
  syndromeId: string;
  syndromeName: string;
  type: string;               // 'motivation_deficit' | 'expressive_deficit' | 'structural_disorder'
  discoverable: boolean | string;
  primaryAction: string;
  actionName: string;
  triggerSignal: string;
  triggerTemplate: string;
  coachingQuestion: string;
}

export interface SyndromeActionMapJson {
  version: string;
  updatedAt: string;
  description: string;
  mappings: SyndromeActionMapping[];
}

// ==============================
// Loader 公共查询接口
// ==============================

/** 能力节点信息（合并 ABL + AB 数据） */
export interface AbilityNodeInfo {
  /** 图谱节点 ID（ABL-XXX） */
  atlasId: string;
  /** 教学节点 ID（AB-XXX，可能为空） */
  prototypeId?: string;
  /** 能力名称 */
  name: string;
  /** 能力描述 */
  description: string;
  /** 分类 */
  category: string;
  /** 等级（1/2/3） */
  level: number;
  /** 训练重点 */
  trainingFocus: string;
  /** 关联症候 */
  syndromes: string[];
  /** 前置能力 */
  prerequisites: string[];
  /** 教学动作 */
  actions: string[];
  /** 训练任务 ID */
  trainingTasks: string[];
}

/** 症候详情（含能力节点信息） */
export interface SyndromeDetail {
  id: string;
  name: string;
  description: string;
  severity: {
    L1: string;
    L2: string;
    L3: string;
  };
  relatedAbilities: AbilityNodeInfo[];
  trainingTasks: string[];
  primaryAction: string;
  /** 教学动作映射（来自 syndrome-action-map.json） */
  actionMapping?: {
    type: string;
    triggerSignal: string;
    triggerTemplate: string;
    coachingQuestion: string;
  };
}
