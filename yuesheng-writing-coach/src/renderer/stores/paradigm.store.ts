/**
 * 范式状态管理（双范式架构核心 Store）
 *
 * 职责：
 * 1. activeParadigm — 当前范式（chat-first / editor-centric）
 * 2. activeTab — 范式 A 中的当前 tab（对话/训练/诊断/成长/工具）
 * 3. sidebarTab — Sidebar 当前显示的面板（作品/任务）
 * 4. 持久化 — 记住用户的范式偏好
 */

import { create } from 'zustand';

// ===== 类型 =====

export type ParadigmMode = 'chat' | 'editor';

/** 范式 A 中的 Tab 标识 */
export type ParadigmATabId = 'chat' | 'training' | 'diagnosis' | 'growth' | 'tools';

export type SidebarTab = 'works' | 'tasks';

interface ParadigmState {
  /** 当前激活的范式 */
  activeParadigm: ParadigmMode;

  /** 范式 A 中当前激活的 tab */
  activeTab: ParadigmATabId;

  /** Sidebar 当前 tab（作品列表 / 任务列表） */
  sidebarTab: SidebarTab;

  // === Actions ===
  /** 切换范式 */
  setParadigm: (mode: ParadigmMode) => void;
}

// ===== 默认值 =====

const STORAGE_KEY = 'yuesheng_paradigm_prefs';

function loadPrefs(): Partial<Pick<ParadigmState, 'activeParadigm' | 'activeTab'>> {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (raw) return JSON.parse(raw);
  } catch { /* ignore */ }
  return {};
}

// ===== Store =====

export const useParadigmStore = create<ParadigmState>((set) => ({
  // 默认：聊天模式 + 对话 tab
  activeParadigm: loadPrefs().activeParadigm ?? 'chat',
  activeTab: loadPrefs().activeTab ?? 'chat',
  sidebarTab: 'tasks', // 范式 A 默认显示任务

  setParadigm: (mode) => {
    set({ activeParadigm: mode });
    // 切换到编辑器模式时，sidebar 自动切到作品 tab
    if (mode === 'editor') set({ sidebarTab: 'works' });
    // 切回聊天模式时，sidebar 自动切回任务 tab
    if (mode === 'chat') set({ sidebarTab: 'tasks' });
    // 持久化
    try {
      const prev = JSON.parse(localStorage.getItem(STORAGE_KEY) ?? '{}');
      localStorage.setItem(STORAGE_KEY, JSON.stringify({ ...prev, activeParadigm: mode }));
    } catch { /* ignore */ }
  },
}));
