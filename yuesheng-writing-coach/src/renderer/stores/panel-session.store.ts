/**
 * panel-session.store.ts — 右侧栏工具会话标签管理（L1 Header）
 *
 * 职责：
 * - 管理右侧栏打开的工具会话列表（编辑/训练/诊断/...）
 * - 每个会话是一个"标签页"，可共存、切换、关闭
 * - 图标条点击 → 自动创建或激活对应类型的会话
 *
 * 数据流：
 *   左侧点章节 / 图标条点击 → upsertSession(...) → RightDrawer L1 显示标签
 *   点击 L1 标签 → switchSession(id) → L2 + 内容区切换
 *   点击 × → removeSession(id) → 关闭该会话
 */

import { create } from 'zustand';

/** 会话类型，对应图标条的各个工具 */
export type PanelSessionType = 'edit' | 'training' | 'diagnosis' | 'growth' | 'profile' | 'search' | 'tools' | 'settings';

/** 各类型会话的关联数据形状（discriminated union） */
export type PanelSessionData =
  | { type: 'edit'; manuscriptId?: string; chapterId?: string }
  | { type: 'training'; syndromeId?: string; challengeId?: string }
  | { type: 'diagnosis'; sessionId?: string }
  | { type: 'growth' }
  | { type: 'profile' }
  | { type: 'search'; query?: string }
  | { type: 'tools' }
  | { type: 'settings' };

/** 单个工具会话 */
export interface PanelSession {
  /** 唯一 ID（crypto.randomUUID） */
  id: string;
  /** 会话类型 */
  type: PanelSessionType;
  /** 标签显示名称 */
  title: string;
  /** 标签图标（Lucide 组件名标识，由 SESSION_LUCIDE_ICON 渲染） */
  icon: string;
  /** 可选的关联数据（discriminated by type） */
  data?: PanelSessionData;
  /** 创建时间 */
  createdAt: number;
}

interface PanelSessionState {
  /** 所有已打开的会话（按创建顺序） */
  sessions: PanelSession[];
  /** 当前激活的会话 ID */
  activeSessionId: string | null;
}

interface PanelSessionActions {
  /** 添加或激活一个会话（若同类型已存在则直接激活） */
  upsertSession: (type: PanelSessionType, title: string, icon: string, data?: PanelSessionData) => string;
  /** 切换到指定会话 */
  switchSession: (id: string) => void;
  /** 移除指定会话（若移除的是当前激活的，自动切换到上一个） */
  removeSession: (id: string) => void;
  /** 清除所有会话 */
  clearAll: () => void;
}

/** 使用 crypto.randomUUID 生成唯一 ID（无模块级可变变量） */
const genId = () => `psess-${crypto.randomUUID()}`;

export const usePanelSessionStore = create<PanelSessionState & PanelSessionActions>((set, get) => ({
  // State
  sessions: [],
  activeSessionId: null,

  // Actions
  upsertSession: (type, title, icon, data) => {
    const { sessions } = get();
    // 同类型只保留一个实例：若已存在则复用并激活
    const existing = sessions.find(s => s.type === type);
    if (existing) {
      set({ activeSessionId: existing.id });
      return existing.id;
    }
    const newSession: PanelSession = {
      id: genId(),
      type,
      title,
      icon,
      data,
      createdAt: Date.now(),
    };
    set({
      sessions: [...sessions, newSession],
      activeSessionId: newSession.id,
    });
    return newSession.id;
  },

  switchSession: (id) => {
    const { sessions } = get();
    if (sessions.some(s => s.id === id)) {
      set({ activeSessionId: id });
    }
  },

  removeSession: (id) => {
    const { sessions, activeSessionId } = get();
    const filtered = sessions.filter(s => s.id !== id);
    let newActive = activeSessionId;
    if (activeSessionId === id) {
      // 激活被删除的会话 → 切换到最后一个剩余的
      newActive = filtered.length > 0 ? filtered[filtered.length - 1].id : null;
    }
    set({ sessions: filtered, activeSessionId: newActive });
  },

  clearAll: () => set({ sessions: [], activeSessionId: null }),
}));
