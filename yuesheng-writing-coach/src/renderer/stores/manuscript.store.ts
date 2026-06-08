// 作品状态管理（Zustand）
// 负责：管理用户作品列表和当前选中作品的状态
// 依赖：zustand, electron IPC (IPC_CHANNELS.MANUSCRIPT_*)

import { create } from 'zustand';
import { IPC_CHANNELS } from '../shared/constants';
import type { Manuscript } from '../shared/types';
import { getInvoke } from '../utils/ipc';

interface ManuscriptState {
  /** 作品列表 */
  manuscripts: Manuscript[];
  /** 当前选中的作品 */
  currentManuscript: Manuscript | null;
  /** 是否正在加载 */
  loading: boolean;
  /** 错误消息 */
  error: string | null;
}

interface ManuscriptActions {
  /** 从主进程获取作品列表 */
  fetchList: () => Promise<void>;
  /** 选中某个作品 */
  select: (id: string) => void;
  /** 创建新作品 */
  create: (title: string, description?: string, genre?: string) => Promise<Manuscript | null>;
  /** 更新作品信息 */
  update: (id: string, data: Partial<Pick<Manuscript, 'title' | 'description' | 'genre' | 'status'>>) => Promise<void>;
  /** 清除错误 */
  clearError: () => void;
}

export const useManuscriptStore = create<ManuscriptState & ManuscriptActions>((set, get) => ({
  // State
  manuscripts: [],
  currentManuscript: null,
  loading: false,
  error: null,

  // Actions
  fetchList: async () => {
    set({ loading: true, error: null });
    try {
      const invoke = getInvoke();
      const res = await invoke(IPC_CHANNELS.MANUSCRIPT_LIST, {}) as { success: boolean; data?: Manuscript[]; error?: string };
      if (res.success && res.data) {
        set({ manuscripts: res.data, loading: false });
      } else {
        set({ error: res.error || '获取作品列表失败', loading: false });
      }
    } catch (err) {
      set({ error: err instanceof Error ? err.message : '获取作品列表异常', loading: false });
    }
  },

  select: (id: string) => {
    const { manuscripts } = get();
    const found = manuscripts.find(m => m.id === id) || null;
    set({ currentManuscript: found });
  },

  create: async (title: string, description?: string, genre?: string) => {
    set({ loading: true, error: null });
    try {
      const invoke = getInvoke();
      const res = await invoke(IPC_CHANNELS.MANUSCRIPT_CREATE, { title, description, genre }) as { success: boolean; data?: Manuscript; error?: string };
      if (res.success && res.data) {
        await get().fetchList();
        set({ loading: false });
        return res.data;
      } else {
        set({ error: res.error || '创建作品失败', loading: false });
        return null;
      }
    } catch (err) {
      set({ error: err instanceof Error ? err.message : '创建作品异常', loading: false });
      return null;
    }
  },

  update: async (id: string, data: Partial<Pick<Manuscript, 'title' | 'description' | 'genre' | 'status'>>) => {
    try {
      const invoke = getInvoke();
      const res = await invoke(IPC_CHANNELS.MANUSCRIPT_UPDATE, { id, ...data }) as { success: boolean; data?: Manuscript; error?: string };
      if (res.success) {
        // 刷新列表
        await get().fetchList();
        // 如果更新的是当前选中的作品，同步更新
        if (get().currentManuscript?.id === id) {
          set({ currentManuscript: res.data ?? null });
        }
      } else {
        set({ error: res.error || '更新作品失败' });
      }
    } catch (err) {
      set({ error: err instanceof Error ? err.message : '更新作品异常' });
    }
  },

  clearError: () => set({ error: null }),
}));
