/**
 * test-data — 共享测试数据
 */

/** 应用 4 个子页配置(从 AppsPage 的 GRID_ITEMS 同步) */
export const SUB_PAGES = [
  { label: '成长报告', route: 'growth-report' },
  { label: '训练计划', route: 'training-plan' },
  { label: '技法库', route: 'technique-library' },
  { label: '素材库', route: 'material-library' },
] as const;

export const ROOT_TABS = ['书架', '对话', '应用'] as const;
export type RootTab = typeof ROOT_TABS[number];
