/**
 * 能力图谱 Loader
 *
 * 职责：读取 ability-atlas.json + ability-node-prototypes.json + syndrome-action-map.json，
 * 提供类型化查询接口，供 DiagnosisService、TeachingStrategyRouter、TrainingRecommendationService 使用。
 *
 * 设计原则：
 * - 惰性加载：首次使用时读取 JSON，加载后缓存
 * - 类型安全：所有返回数据通过 TypeScript 接口约束
 * - 无外部依赖：Loader 独立，不引入循环依赖
 */

import * as fs from 'fs';
import * as path from 'path';

import type {
  AbilityAtlasJson,
  AbilityNodePrototypesJson,
  SyndromeActionMapJson,
  AtlasAbilityNode,
  AtlasTrainingTask,
  AbilityNodePrototype,
  SyndromeActionMapping,
  AbilityNodeInfo,
  SyndromeDetail,
} from './ability-atlas.types';

// ==============================
// 常量：JSON 文件路径
// ==============================

const ATLAS_JSON_PATH = path.resolve(__dirname, '../../../../../resources/knowledge-graph/ability-atlas.json');
const PROTOTYPES_JSON_PATH = path.resolve(__dirname, '../../../../../resources/02-prescription/ability-nodes/ability-node-prototypes.json');
const ACTION_MAP_JSON_PATH = path.resolve(__dirname, '../../../../../resources/01-diagnosis/syndromes/syndrome-action-map.json');

// ==============================
// 内部状态
// ==============================

let atlasData: AbilityAtlasJson | null = null;
let prototypesData: AbilityNodePrototypesJson | null = null;
let actionMapData: SyndromeActionMapJson | null = null;
let loaded = false;

// ==============================
// 缓存查询结果
// ==============================

let cachedAbilitiesBySyndrome: Map<string, AbilityNodeInfo[]> | null = null;
let cachedTasksByAbility: Map<string, AtlasTrainingTask[]> | null = null;
let cachedDependencyGraph: Map<string, string[]> | null = null;
let cachedAbilityNodeMapping: Map<string, string> | null = null;

// ==============================
// 内部方法
// ==============================

function loadJson<T>(filePath: string, label: string): T {
  try {
    const raw = fs.readFileSync(filePath, 'utf-8');
    return JSON.parse(raw) as T;
  } catch (err) {
    console.warn(`[AbilityAtlasLoader] Failed to load ${label} at ${filePath}:`, err);
    return {} as T;
  }
}

function ensureLoaded(): void {
  if (loaded) return;

  atlasData = loadJson<AbilityAtlasJson>(ATLAS_JSON_PATH, 'ability-atlas.json');
  prototypesData = loadJson<AbilityNodePrototypesJson>(PROTOTYPES_JSON_PATH, 'ability-node-prototypes.json');
  actionMapData = loadJson<SyndromeActionMapJson>(ACTION_MAP_JSON_PATH, 'syndrome-action-map.json');

  // 如果主数据文件无效，标记加载但后续查询都为空
  if (!atlasData || !atlasData.abilities) {
    console.warn('[AbilityAtlasLoader] ability-atlas.json is empty or invalid');
    atlasData = { _meta: {} as AbilityAtlasJson['_meta'], abilities: [], syndromes: [], training_tasks: [], queries: { description: '', paths: [] } };
  }
  if (!prototypesData || !prototypesData.nodes) {
    prototypesData = { version: '', description: '', nodes: [] };
  }
  if (!actionMapData || !actionMapData.mappings) {
    actionMapData = { version: '', updatedAt: '', description: '', mappings: [] };
  }

  loaded = true;
  buildCaches();
}

function buildCaches(): void {
  const abMap = new Map<string, AtlasAbilityNode>(atlasData!.abilities.map(a => [a.id, a]));
  const prototypes = prototypesData!.nodes ?? [];

  // 建立 ABL-XXX → AB-XXX 映射
  const mapping = new Map<string, string>();
  const nameToAbl = new Map<string, string>();
  for (const abl of atlasData!.abilities) {
    nameToAbl.set(abl.name, abl.id);
  }
  for (const proto of prototypes) {
    // 通过名称匹配：从原型节点名称找到对应的 ABL 节点
    for (const [name, ablId] of nameToAbl) {
      if (proto.name.includes(name) || name.includes(proto.name)) {
        mapping.set(ablId, proto.id);
        break;
      }
    }
  }

  cachedAbilityNodeMapping = mapping;

  // 建立症候 → 能力节点 缓存
  const bySyndrome = new Map<string, AbilityNodeInfo[]>();
  for (const syndrome of atlasData!.syndromes) {
    const nodes = syndrome.related_abilities
      .map(id => abMap.get(id))
      .filter((n): n is AtlasAbilityNode => !!n)
      .map(n => toAbilityNodeInfo(n, mapping, prototypes));
    bySyndrome.set(syndrome.id, nodes);
  }
  cachedAbilitiesBySyndrome = bySyndrome;

  // 建立能力 → 训练任务 缓存
  const byAbility = new Map<string, AtlasTrainingTask[]>();
  const tasksByAbilityId = new Map<string, AtlasTrainingTask[]>();
  for (const task of atlasData!.training_tasks) {
    for (const ablId of task.related_abilities) {
      const list = tasksByAbilityId.get(ablId) ?? [];
      list.push(task);
      tasksByAbilityId.set(ablId, list);
    }
  }
  for (const ablId of abMap.keys()) {
    byAbility.set(ablId, tasksByAbilityId.get(ablId) ?? []);
  }
  cachedTasksByAbility = byAbility;

  // 建立依赖拓扑
  const graph = new Map<string, string[]>();
  for (const ability of atlasData!.abilities) {
    graph.set(ability.id, ability.prerequisites);
  }
  cachedDependencyGraph = graph;
}

function toAbilityNodeInfo(
  node: AtlasAbilityNode,
  mapping: Map<string, string>,
  prototypes: AbilityNodePrototype[],
): AbilityNodeInfo {
  const protoId = mapping.get(node.id);
  const proto = protoId ? prototypes.find(p => p.id === protoId) : undefined;
  return {
    atlasId: node.id,
    prototypeId: proto?.id,
    name: node.name,
    description: node.description,
    category: node.category,
    level: node.level,
    trainingFocus: node.training_focus,
    syndromes: node.syndromes,
    prerequisites: node.prerequisites,
    actions: node.actions,
    trainingTasks: node.primary_tasks,
  };
}

function getActionMapping(syndromeId: string): SyndromeActionMapping | undefined {
  return actionMapData!.mappings.find(m => m.syndromeId === syndromeId);
}

// ==============================
// 公开 API
// ==============================

/**
 * 按症候 ID 查询相关能力节点
 */
export function getAbilitiesBySyndrome(syndromeId: string): AbilityNodeInfo[] {
  ensureLoaded();
  return cachedAbilitiesBySyndrome!.get(syndromeId) ?? [];
}

/**
 * 按能力节点 ID 查询训练任务
 */
export function getTrainingTasksByAbility(abilityId: string): AtlasTrainingTask[] {
  ensureLoaded();
  return cachedTasksByAbility!.get(abilityId) ?? [];
}

/**
 * 按能力节点 ID 查询前置依赖
 */
export function getPrerequisites(abilityId: string): string[] {
  ensureLoaded();
  return cachedDependencyGraph!.get(abilityId) ?? [];
}

/**
 * 按症候 ID 查询症候详情（含能力节点信息和动作映射）
 */
export function getSyndromeDetail(syndromeId: string): SyndromeDetail | undefined {
  ensureLoaded();
  const syndrome = atlasData!.syndromes.find(s => s.id === syndromeId);
  if (!syndrome) return undefined;

  const actionMapping = getActionMapping(syndromeId);

  return {
    id: syndrome.id,
    name: syndrome.name,
    description: syndrome.description,
    severity: {
      L1: syndrome.severity_L1,
      L2: syndrome.severity_L2,
      L3: syndrome.severity_L3,
    },
    relatedAbilities: getAbilitiesBySyndrome(syndromeId),
    trainingTasks: syndrome.training_tasks,
    primaryAction: syndrome.primary_action,
    actionMapping: actionMapping ? {
      type: actionMapping.type,
      triggerSignal: actionMapping.triggerSignal,
      triggerTemplate: actionMapping.triggerTemplate,
      coachingQuestion: actionMapping.coachingQuestion,
    } : undefined,
  };
}

/**
 * 获取能力依赖拓扑（有向图：能力 ID → [前置能力 ID]）
 */
export function getDependencyGraph(): Map<string, string[]> {
  ensureLoaded();
  return new Map(cachedDependencyGraph!);
}

/**
 * 获取能力节点 ID → 教学节点 ID 映射（ABL-XXX → AB-XXX）
 */
export function getAbilityNodeMapping(): Map<string, string> {
  ensureLoaded();
  return new Map(cachedAbilityNodeMapping!);
}

/**
 * 获取所有能力节点信息
 */
export function getAllAbilityNodes(): AbilityNodeInfo[] {
  ensureLoaded();
  return atlasData!.abilities.map(n => toAbilityNodeInfo(n, cachedAbilityNodeMapping!, prototypesData!.nodes ?? []));
}

/**
 * 获取所有症候简略信息
 */
export function getAllSyndromes(): Array<{ id: string; name: string; relatedAbilities: string[] }> {
  ensureLoaded();
  return atlasData!.syndromes.map(s => ({
    id: s.id,
    name: s.name,
    relatedAbilities: s.related_abilities,
  }));
}

/**
 * 获取症候→教学动作映射
 * 返回所有映射（供 TeachingStrategyRouter 使用）
 */
export function getAllActionMappings(): SyndromeActionMapping[] {
  ensureLoaded();
  return [...actionMapData!.mappings];
}

/**
 * 按症候 ID 查询教学动作映射
 */
export function getActionMappingBySyndrome(syndromeId: string): SyndromeActionMapping | undefined {
  ensureLoaded();
  return getActionMapping(syndromeId);
}

/**
 * 重新加载所有 JSON 数据（外部文件变动时调用）
 */
export function reload(): void {
  loaded = false;
  atlasData = null;
  prototypesData = null;
  actionMapData = null;
  cachedAbilitiesBySyndrome = null;
  cachedTasksByAbility = null;
  cachedDependencyGraph = null;
  cachedAbilityNodeMapping = null;
  ensureLoaded();
}

/** 检查 Loader 是否已就绪 */
export function isLoaded(): boolean {
  return loaded;
}
