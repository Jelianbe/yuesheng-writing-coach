/**
 * 共享映射中心
 * 依据：E-03 消除多文件重复映射定义
 * 使用方式：所有模块从此文件导入，禁止在本地重复定义
 */

import type { SyndromeId, ActionId, TeachingSubphase } from './constants';

/** 症候名称映射（兼容 P008 遗留引用，保持宽松键类型） */
export const SYNDROME_NAMES: Record<string, string> = {
  P001: '世界观膨胀',
  P002: '角色工具人化',
  P003: '情绪标签化',
  P004: '信息硬塞',
  P005: '视角漂移',
  P006: '节奏停滞',
  P007: '阅读结构单一',
  P008: '世界观说明书（已合并到 P004）',
  P009: '角色动机缺失',
  P010: 'OC平面化',
  // 诊断维度标记
  H001: '无钩子开篇',
  H002: '身份未锚定',
  E001: '情绪曲线问题',
  I001: '凡人逆袭矛盾',
  I002: '天赋碾压矛盾',
  I003: '世界观自相矛盾',
  I004: '主角定位矛盾',
  I005: '节奏-张力矛盾',
  I006: '设定-执行断裂',
};

/** 症候元数据（含严重度） */
export interface SyndromeMeta {
  name: string;
  severity: 'L1' | 'L2' | 'L3';
}

export const SYNDROME_META: Partial<Record<SyndromeId, SyndromeMeta>> = {
  P001: { name: '世界观膨胀', severity: 'L1' },
  P002: { name: '角色工具人化', severity: 'L3' },
  P003: { name: '情绪标签化', severity: 'L2' },
  P004: { name: '信息硬塞', severity: 'L2' },
  P005: { name: '视角漂移', severity: 'L1' },
  P006: { name: '节奏停滞', severity: 'L2' },
  P007: { name: '阅读结构单一', severity: 'L1' },
  P009: { name: '角色动机缺失', severity: 'L2' },
  P010: { name: 'OC平面化', severity: 'L2' },
  // 诊断维度标记（信息提示级，不触发教学动作）
  H001: { name: '无钩子开篇', severity: 'L1' },
  H002: { name: '身份未锚定', severity: 'L1' },
  E001: { name: '情绪曲线问题', severity: 'L1' },
  I001: { name: '凡人逆袭矛盾', severity: 'L1' },
  I002: { name: '天赋碾压矛盾', severity: 'L1' },
  I003: { name: '世界观自相矛盾', severity: 'L1' },
  I004: { name: '主角定位矛盾', severity: 'L1' },
  I005: { name: '节奏-张力矛盾', severity: 'L1' },
  I006: { name: '设定-执行断裂', severity: 'L1' },
};

/** 动作名称映射 */
export const ACTION_NAMES: Partial<Record<ActionId, string>> = {
  A001: '缩小范围',
  A002: '回归主角',
  A003: '五问法',
  A004: '现实锚点',
  A005: '阶段拆分',
  A006: '对比展示',
  A007: '翻转拆解',
  A008: '阅读作业',
  A009: '信心确认',
  A010: '边界校准',
  A011: '跨语境迁移',
};

/** 动作目标映射 */
export const ACTION_GOALS: Partial<Record<ActionId, string>> = {
  A001: '用户已经学会把宏大设定聚焦到第一个具体场景。',
  A002: '用户已经学会从上帝视角回到角色眼睛。',
  A003: '用户已经学会用连续追问理清因果链。',
  A004: '用户已经学会把角色放回具体生活场景，写出真实感。',
  A005: '用户已经学会把大目标拆成可执行的小阶段。',
  A006: '用户已经学会用事实对比替代辩论。',
  A007: '用户已经学会打破固定视角。',
  A008: '用户已经学会通过阅读任务提升写作技巧。',
  A009: '用户已经学会确认自己的直觉，区分真正的冗余和必要的留白。',
  A010: '用户已经学会在情绪表达中精准校准，理解克制比激烈更有力。',
  A011: '用户已经学会用现代/日常类比激活陌生设定的共情通道。',
};

/** 能力名称映射 */
export const ABILITY_NAMES: Record<string, string> = {
  // 能力代码不是 SyndromeId/ActionId 类型的联合，保持宽松键类型
  'ABL-001': '世界观构建',
  'ABL-002': '角色塑造',
  'ABL-003': '情绪表达',
  'ABL-004': '信息控制',
  'ABL-005': '视角管理',
  'ABL-006': '节奏控制',
  'ABL-007': '阅读分析',
};

/**
 * 病症→动作映射
 * 依据：action-library.md / syndrome-manual.md / teaching-state-machine.ts 统一
 * key: 病症 ID (P001~P010), value: 动作 ID 数组 (A001~A011)
 */
export const SYNDROME_TO_ACTIONS: Readonly<Partial<Record<SyndromeId, string[]>>> = {
  P001: ['A001', 'A005'],       // 世界观膨胀 → 缩小范围, 阶段拆分
  P002: ['A004', 'A003'],       // 角色工具人化 → 现实锚点, 五问法
  P003: ['A004'],                // 情绪标签化 → 现实锚点
  P004: ['A002', 'A001'],       // 信息硬塞 → 回归主角, 缩小范围
  P005: ['A002', 'A007'],       // 视角漂移 → 回归主角, 翻转拆解
  P006: ['A003', 'A005'],       // 节奏停滞 → 五问法, 阶段拆分
  P007: ['A008'],                // 阅读结构单一 → 阅读作业
  P009: ['A002'],                // 角色动机缺失 → 回归主角
  P010: ['A006'],                // OC平面化 → 对比展示
};

/**
 * 子阶段→动作映射
 * 依据：teaching-state-machine.ts calculateNextActions 函数提取
 * key: 子阶段 ID, value: 动作 ID 数组
 */
export const SUBPHASE_TO_ACTIONS: Partial<Record<TeachingSubphase, string[]>> = {
  S1_NATURAL_LAW: ['A004'],
  S1_PROTAGONIST: ['A001', 'A002'],
  S1_SOCIAL_STRUCT: ['A004', 'A002'],
  S1_FIRST_SCENE: ['A003', 'A005'],
  S1_DAILY_DETAIL: ['A003', 'A005'],
  S2_IDENTIFY: [],
  S2_REFLECTION: [],
  S2_TEACHING: [],
  S2_ASSIGN_TASK: [],
  S2_REVIEW_TASK: [],
  S4_SUMMARY: [],
};

/**
 * 病症→能力映射
 * 依据：syndrome-ability-map.ts 迁移
 * key: 病症 ID (P001~P010), value: 能力代码数组
 */
export const SYNDROME_TO_ABILITIES: Readonly<Partial<Record<SyndromeId, string[]>>> = {
  P001: ['WORLD'],
  P002: ['CHAR'],
  P003: ['OBS', 'EMO'],
  P004: ['WORLD', 'STYLE'],
  P005: ['STYLE'],
  P006: ['PLOT'],
  P007: ['STYLE'],
  P009: ['CHAR'],
  P010: ['CHAR'],
};

/**
 * 获取病症对应的能力列表
 * @param syndromeId - 病症 ID
 * @returns 能力代码数组
 */
export function getAbilitiesForSyndrome(syndromeId: string): string[] {
  return SYNDROME_TO_ABILITIES[syndromeId as SyndromeId] ?? [];
}

/**
 * 获取子阶段对应的动作列表
 * @param subphase - 子阶段 ID
 * @returns 动作 ID 数组
 */
export function getActionsForSubphase(subphase: string): string[] {
  return SUBPHASE_TO_ACTIONS[subphase as TeachingSubphase] ?? [];
}

/**
 * 获取病症对应的动作列表
 * @param syndromeId - 病症 ID
 * @returns 动作 ID 数组
 */
export function getActionsForSyndrome(syndromeId: string): string[] {
  return SYNDROME_TO_ACTIONS[syndromeId as SyndromeId] ?? [];
}
