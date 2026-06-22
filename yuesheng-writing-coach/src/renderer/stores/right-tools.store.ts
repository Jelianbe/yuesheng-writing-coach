/**
 * right-tools.store.ts — 右侧栏工具运行时状态（V6.2 Shell 版 + ADR-002）
 *
 * 注册表（id/name/icon）由 workspace-registry.ts 管理。
 * 本文件只管理运行时状态：哪些工具打开/激活、子标签、项目标签。
 *
 * ToolId 现在是 WorkspaceId 的别名 — 保持向后兼容。
 */

import { create } from 'zustand';
import type { WorkspaceId } from '../registry/workspace-registry';
import {
  getDefaultOpenWorkspaces,
  getAllWorkspaces,
} from '../registry/workspace-registry';
// 触发自注册（必须在 getDefaultOpenWorkspaces 之前）
import '../registry/workspaces-index';

export type ToolId = WorkspaceId;

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

/**
 * 计算默认打开的工具集（来自注册表的 defaultOpen）
 * 注意：此函数必须在 workspaces-index 已被 import 后调用。
 */
function computeDefaultOpenToolIds(): ToolId[] {
  return getDefaultOpenWorkspaces().map(w => w.id);
}

export const useRightToolsStore = create<RightToolsState & RightToolsActions>((set, get) => ({
  // ── 初始状态：来自注册表的 defaultOpen workspaces ──
  openTools: computeDefaultOpenToolIds(),
  activeToolId: (computeDefaultOpenToolIds()[0] ?? null) as ToolId | null,
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

/** 重新导出以保留 ALL_TOOLS 的引用兼容（已迁移到注册表） */
export function getAvailableTools() {
  return getAllWorkspaces();
}
