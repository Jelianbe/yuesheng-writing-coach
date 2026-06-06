// 中文显示名称映射表
// 统一从 shared/mappings.ts 导入，禁止在本地重复定义
// 与后端保持单一来源，消除前后端名称不一致问题

export { ACTION_NAMES as ActionNameMap, SYNDROME_NAMES as SyndromeNameMap } from '../../shared/mappings';

// Phase/Subphase 名称映射（仅前端使用，无对应后端映射）
export const PhaseNameMap: Record<string, string> = {
  P0_INIT: '初次见面',
  P1_WORLD: '世界观搭建',
  P2_PRACTICE_LOOP: '诊断与训练',
  P4_REVIEW: '复盘总结',
};

export const SubphaseNameMap: Record<string, string> = {
  S1_NATURAL_LAW: '自然法则',
  S1_PROTAGONIST: '主角设定',
  S1_SOCIAL_STRUCT: '社会结构',
  S1_FIRST_SCENE: '第一个场景',
  S1_DAILY_DETAIL: '日常细节',
  S2_IDENTIFY: '识别问题',
  S2_TEACHING: '教学讲解',
  S2_ASSIGN_TASK: '分配任务',
  S2_REVIEW_TASK: '评审任务',
  S4_SUMMARY: '总结',
};
