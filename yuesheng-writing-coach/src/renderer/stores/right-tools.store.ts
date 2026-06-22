/**
 * right-tools.store.ts — 右侧栏工具管理（V6.2 Shell 版）
 *
 * 跟踪 6 个工具的打开/关闭/激活状态，
 * 以及每个工具的子标签（sub-tab）管理。
 */

import { create } from 'zustand';

export type ToolId = 'catalog' | 'progress' | 'growth' | 'works' | 'training' | 'stage' | '__settings__';

export interface ToolMeta {
  id: ToolId;
  name: string;
  icon: string;
}

export const ALL_TOOLS: ToolMeta[] = [
  { id: 'catalog',   name: '技法目录', icon: '✤' },
  { id: 'progress',  name: '教学进度', icon: '◐' },
  { id: 'growth',    name: '学习日志', icon: '✎' },
  { id: 'works',     name: '作品',     icon: '☰' },
  { id: 'training',  name: '教学笔记', icon: '✤' },
  { id: 'stage',     name: '发展路径', icon: '◈' },
  { id: '__settings__',  name: '设置',     icon: '⚙' },
];

/** 子标签条目 */
export interface SubTabEntry {
  id: string;     // 唯一标识（如 coreId / projectId）
  label: string;  // 显示名称
}

interface RightToolsState {
  openTools: ToolId[];
  activeToolId: ToolId | null;

  // ── 子标签（按 toolId 分组）──
  subTabs: Record<string, SubTabEntry[]>;  // toolId → SubTabEntry[]
  activeSubTabId: string | null;

  // ── 项目标签（works 工具多 tab）──
  projectTabs: string[];
  activeProjectTabId: string | null;
}

interface RightToolsActions {
  openTool: (id: ToolId) => void;
  closeTool: (id: ToolId) => void;
  setActiveTool: (id: ToolId) => void;
  toggleTool: (id: ToolId) => void;
  isOpen: (id: ToolId) => boolean;

  // ── 子标签操作 ──
  addSubTab: (toolId: ToolId, entry: SubTabEntry) => void;
  removeSubTab: (toolId: ToolId, entryId: string) => void;
  setActiveSubTab: (entryId: string | null) => void;
  clearSubTabs: (toolId: ToolId) => void;

  // ── 项目标签操作 ──
  openProjectTab: (id: string) => void;
  closeProjectTab: (id: string) => void;
  setActiveProjectTab: (id: string | null) => void;
  clearProjectTabs: () => void;
}

export const useRightToolsStore = create<RightToolsState & RightToolsActions>((set, get) => ({
  // ── 初始状态：6 个主要工具默认打开（对齐 v6.2 HTML + Sprint 8 新增 stage）──
  openTools: ['catalog', 'progress', 'growth', 'works', 'training', 'stage'],
  activeToolId: 'catalog',
  subTabs: {},
  activeSubTabId: null,
  projectTabs: [],
  activeProjectTabId: null,

  // ── 工具操作 ──

  openTool: (id) => {
    const { openTools } = get();
    if (!openTools.includes(id)) {
      openTools.push(id);
    }
    set({ openTools: [...openTools], activeToolId: id });
  },

  closeTool: (id) => {
    const s = get();
    const filtered = s.openTools.filter((t: string) => t !== id);
    // 关闭工具时同时清除其子标签
    const { [id]: _removed, ...restSubTabs } = s.subTabs;
    // 关闭 works 工具时同步清空项目标签
    const clearProj = id === 'works';
    set({
      openTools: filtered,
      activeToolId: s.activeToolId === id
        ? (filtered[filtered.length - 1] ?? null)
        : s.activeToolId,
      subTabs: restSubTabs,
      activeSubTabId: s.activeSubTabId && s.subTabs[id]?.some(st => st.id === s.activeSubTabId)
        ? s.activeSubTabId
        : null,
      ...(clearProj ? { projectTabs: [], activeProjectTabId: null } : {}),
    });
  },

  setActiveTool: (id) => {
    set({ activeToolId: id });
  },

  toggleTool: (id) => {
    const { openTools } = get();
    if (openTools.includes(id)) {
      get().closeTool(id);
    } else {
      get().openTool(id);
    }
  },

  isOpen: (id) => get().openTools.includes(id),

  // ── 子标签操作 ──

  addSubTab: (toolId, entry) => {
    const { subTabs } = get();
    const current = subTabs[toolId] ?? [];
    if (current.some(st => st.id === entry.id)) {
      // 已存在，仅切换激活
      set({ activeSubTabId: entry.id });
      return;
    }
    set({
      subTabs: {
        ...subTabs,
        [toolId]: [...current, entry],
      },
      activeSubTabId: entry.id,
    });
  },

  removeSubTab: (toolId, entryId) => {
    const s = get();
    const current = s.subTabs[toolId] ?? [];
    const filtered = current.filter(st => st.id !== entryId);
    const nextSubTabs = { ...s.subTabs };
    if (filtered.length === 0) {
      delete nextSubTabs[toolId];
    } else {
      nextSubTabs[toolId] = filtered;
    }
    set({
      subTabs: nextSubTabs,
      activeSubTabId: s.activeSubTabId === entryId
        ? (filtered.length > 0 ? filtered[filtered.length - 1].id : null)
        : s.activeSubTabId,
    });
  },

  setActiveSubTab: (entryId) => {
    set({ activeSubTabId: entryId });
  },

  clearSubTabs: (toolId) => {
    const { subTabs, activeSubTabId } = get();
    const toolSubTabs = subTabs[toolId] ?? [];
    const { [toolId]: _removed, ...rest } = subTabs;
    set({
      subTabs: rest,
      activeSubTabId: toolSubTabs.some(st => st.id === activeSubTabId) ? null : activeSubTabId,
    });
  },

  // ── 项目标签操作 ──

  openProjectTab: (id) => {
    const { projectTabs } = get();
    if (!projectTabs.includes(id)) {
      projectTabs.push(id);
    }
    set({ projectTabs: [...projectTabs], activeProjectTabId: id });
  },

  closeProjectTab: (id) => {
    const { projectTabs, activeProjectTabId } = get();
    const filtered = projectTabs.filter(t => t !== id);
    set({
      projectTabs: filtered,
      activeProjectTabId: activeProjectTabId === id
        ? (filtered[filtered.length - 1] ?? null)
        : activeProjectTabId,
    });
  },

  setActiveProjectTab: (id) => {
    set({ activeProjectTabId: id });
  },

  clearProjectTabs: () => {
    set({ projectTabs: [], activeProjectTabId: null });
  },
}));
