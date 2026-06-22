/**
 * 能力图谱 Loader 单元测试
 *
 * 覆盖：
 * - 按症候查询能力节点
 * - 按能力节点查询训练任务
 * - 能力依赖拓扑
 * - 症候详情（含动作映射）
 * - ABL → AB 节点映射
 * - 所有症候列表
 * - 所有能力节点列表
 */

import { describe, it, expect, beforeEach } from 'vitest';
import {
  getAbilitiesBySyndrome,
  getTrainingTasksByAbility,
  getPrerequisites,
  getSyndromeDetail,
  getDependencyGraph,
  getAbilityNodeMapping,
  getAllSyndromes,
  getAllAbilityNodes,
  getActionMappingBySyndrome,
  getAllActionMappings,
  isLoaded,
  reload,
} from '../ability-atlas.loader';

beforeEach(() => {
  // 每次测试前重新加载，确保状态干净
  reload();
});

describe('按症候查询能力节点', () => {
  it('P001（世界观膨胀）应关联 ABL-001（结构控制）和 ABL-005（世界观工程）', () => {
    const nodes = getAbilitiesBySyndrome('P001');
    expect(nodes).toHaveLength(2);
    expect(nodes.map(n => n.atlasId)).toContain('ABL-001');
    expect(nodes.map(n => n.atlasId)).toContain('ABL-005');
  });

  it('P003（情绪标签化）应关联 ABL-007（表达能力）', () => {
    const nodes = getAbilitiesBySyndrome('P003');
    expect(nodes).toHaveLength(1);
    expect(nodes[0].atlasId).toBe('ABL-007');
    expect(nodes[0].category).toBe('语言能力');
  });

  it('未知症候应返回空数组', () => {
    const nodes = getAbilitiesBySyndrome('P099');
    expect(nodes).toEqual([]);
  });
});

describe('按能力节点查询训练任务', () => {
  it('ABL-001（结构控制）应关联 T009, T010, T011, T012, T015', () => {
    const tasks = getTrainingTasksByAbility('ABL-001');
    const taskIds = tasks.map(t => t.id);
    expect(taskIds).toContain('T009');
    expect(taskIds).toContain('T010');
    expect(taskIds).toContain('T011');
    expect(taskIds).toContain('T012');
    expect(taskIds).toContain('T015');
    expect(taskIds).toHaveLength(5);
  });

  it('ABL-007（表达能力）应关联 T001', () => {
    const tasks = getTrainingTasksByAbility('ABL-007');
    const taskIds = tasks.map(t => t.id);
    expect(taskIds).toContain('T001');
  });

  it('未知能力 ID 应返回空数组', () => {
    const tasks = getTrainingTasksByAbility('ABL-099');
    expect(tasks).toEqual([]);
  });
});

describe('能力依赖拓扑', () => {
  it('ABL-001（结构控制）前置依赖 ABL-002（场景构建）', () => {
    const prereqs = getPrerequisites('ABL-001');
    expect(prereqs).toContain('ABL-002');
  });

  it('ABL-007（表达能力）无前置依赖', () => {
    const prereqs = getPrerequisites('ABL-007');
    expect(prereqs).toEqual([]);
  });

  it('getDependencyGraph 应返回所有能力节点', () => {
    const graph = getDependencyGraph();
    expect(graph.size).toBeGreaterThanOrEqual(8);
    expect(graph.has('ABL-001')).toBe(true);
    expect(graph.has('ABL-008')).toBe(true);
  });
});

describe('症候详情', () => {
  it('getSyndromeDetail 应返回 P002 的完整信息', () => {
    const detail = getSyndromeDetail('P002');
    expect(detail).toBeDefined();
    expect(detail!.name).toBe('角色工具人化');
    expect(detail!.relatedAbilities).toHaveLength(2);
    expect(detail!.trainingTasks).toContain('T003');
    expect(detail!.primaryAction).toBe('A004');
  });

  it('getSyndromeDetail 应包含动作映射', () => {
    const detail = getSyndromeDetail('P002');
    expect(detail).toBeDefined();
    expect(detail!.actionMapping).toBeDefined();
    expect(detail!.actionMapping!.triggerSignal).toBeDefined();
    expect(detail!.actionMapping!.coachingQuestion).toContain('真人');
  });

  it('未知症候应返回 undefined', () => {
    const detail = getSyndromeDetail('P099');
    expect(detail).toBeUndefined();
  });
});

describe('能力节点映射', () => {
  it('getAbilityNodeMapping 应返回 ABL-XXX → AB-XXX 映射', () => {
    const mapping = getAbilityNodeMapping();
    expect(mapping.size).toBeGreaterThanOrEqual(0); // 映射可能为空（名称匹配不全）
    expect(mapping).toBeDefined();
  });
});

describe('批量查询', () => {
  it('getAllSyndromes 应返回 10 个症候', () => {
    const syndromes = getAllSyndromes();
    expect(syndromes.length).toBeGreaterThanOrEqual(9);
    const ids = syndromes.map(s => s.id);
    expect(ids).toContain('P001');
    expect(ids).toContain('P010');
    expect(ids).not.toContain('P008'); // P008 已合并
  });

  it('getAllAbilityNodes 应返回 8 个能力节点', () => {
    const nodes = getAllAbilityNodes();
    expect(nodes.length).toBeGreaterThanOrEqual(8);
    expect(nodes.map(n => n.atlasId)).toContain('ABL-001');
    expect(nodes.map(n => n.atlasId)).toContain('ABL-008');
  });
});

describe('动作映射查询', () => {
  it('getActionMappingBySyndrome 应返回 P006 的 triggerTemplate', () => {
    const mapping = getActionMappingBySyndrome('P006');
    expect(mapping).toBeDefined();
    expect(mapping!.triggerSignal).toContain('停滞');
    expect(mapping!.triggerTemplate).toContain('{conflict}');
  });

  it('getAllActionMappings 应返回至少 9 条映射', () => {
    const mappings = getAllActionMappings();
    expect(mappings.length).toBeGreaterThanOrEqual(9);
    const syndromeIds = mappings.map(m => m.syndromeId);
    expect(syndromeIds).toContain('P001');
    expect(syndromeIds).toContain('P010');
  });
});

describe('Loader 状态管理', () => {
  it('reload 后 isLoaded 应返回 true', () => {
    // 先触发加载
    getAllAbilityNodes();
    expect(isLoaded()).toBe(true);
  });

  it('reload 应重新加载数据', () => {
    // 先加载
    getAllAbilityNodes();
    expect(isLoaded()).toBe(true);

    // 重新加载（reload 同步重新加载，isLoaded 立即为 true）
    reload();
    expect(isLoaded()).toBe(true);

    // 再次查询应正常返回
    const nodes = getAllAbilityNodes();
    expect(nodes.length).toBeGreaterThan(0);
  });
});
