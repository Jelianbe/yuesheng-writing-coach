/**
 * 共享映射中心
 * 依据：E-03 消除多文件重复映射定义
 * 使用方式：所有模块从此文件导入，禁止在本地重复定义
 */
import type { SyndromeId, ActionId, TeachingSubphase } from './constants';
/** 症候名称映射（兼容 P008 遗留引用，保持宽松键类型） */
export declare const SYNDROME_NAMES: Record<string, string>;
/** 症候元数据（含严重度） */
export interface SyndromeMeta {
    name: string;
    severity: 'L1' | 'L2' | 'L3';
}
export declare const SYNDROME_META: Partial<Record<SyndromeId, SyndromeMeta>>;
/** 动作名称映射 */
export declare const ACTION_NAMES: Partial<Record<ActionId, string>>;
/** 动作目标映射 */
export declare const ACTION_GOALS: Partial<Record<ActionId, string>>;
/** 能力名称映射 */
export declare const ABILITY_NAMES: Record<string, string>;
/**
 * 病症→动作映射
 * 依据：action-library.md / syndrome-manual.md / teaching-state-machine.ts 统一
 * key: 病症 ID (P001~P010), value: 动作 ID 数组 (A001~A011)
 */
export declare const SYNDROME_TO_ACTIONS: Readonly<Partial<Record<SyndromeId, string[]>>>;
/**
 * 子阶段→动作映射
 * 依据：teaching-state-machine.ts calculateNextActions 函数提取
 * key: 子阶段 ID, value: 动作 ID 数组
 */
export declare const SUBPHASE_TO_ACTIONS: Partial<Record<TeachingSubphase, string[]>>;
/**
 * 病症→能力映射
 * 依据：syndrome-ability-map.ts 迁移
 * key: 病症 ID (P001~P010), value: 能力代码数组
 */
export declare const SYNDROME_TO_ABILITIES: Readonly<Partial<Record<SyndromeId, string[]>>>;
/**
 * 获取病症对应的能力列表
 * @param syndromeId - 病症 ID
 * @returns 能力代码数组
 */
export declare function getAbilitiesForSyndrome(syndromeId: string): string[];
/**
 * 获取子阶段对应的动作列表
 * @param subphase - 子阶段 ID
 * @returns 动作 ID 数组
 */
export declare function getActionsForSubphase(subphase: string): string[];
/**
 * 获取病症对应的动作列表
 * @param syndromeId - 病症 ID
 * @returns 动作 ID 数组
 */
export declare function getActionsForSyndrome(syndromeId: string): string[];
