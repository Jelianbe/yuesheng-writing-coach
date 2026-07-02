// 作品状态管理（Zustand）
// 负责：管理用户作品列表和当前选中作品的状态
// 依赖：zustand, electron IPC (IPC_CHANNELS.MANUSCRIPT_*)

import { create } from 'zustand';
import { IPC_CHANNELS } from '../shared/constants';
import type { Manuscript } from '../shared/types';
import { typedInvoke } from '../services/ipc-client';
import type {
  ManuscriptListResponse,
  ManuscriptCreateRequest,
  ManuscriptCreateResponse,
  ManuscriptUpdateRequest,
  ManuscriptDeleteRequest,
} from '../../shared/api-contracts/manuscript.contract';

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
  create: (title: string, content?: string, genre?: string) => Promise<Manuscript | null>;
  /** 更新作品信息 */
  update: (id: string, data: Partial<Pick<Manuscript, 'title' | 'description' | 'genre' | 'status'>>) => Promise<void>;
  /** 删除作品 */
  remove: (id: string) => Promise<boolean>;
}

/** API 投影 ManuscriptInfo → 本地 Manuscript(补齐 DB 字段默认值) */
const toManuscript = (info: { id: string; title: string; genre?: string; createdAt: number; updatedAt: number }): Manuscript => ({
  id: info.id,
  title: info.title,
  description: '',
  genre: info.genre ?? '',
  status: 'active',
  created_at: info.createdAt,
  updated_at: info.updatedAt,
  sort_order: 0,
});

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
      const res = await typedInvoke<Record<string, never>, ManuscriptListResponse>(
        IPC_CHANNELS.MANUSCRIPT_LIST,
        {},
      );
      if (res.success && res.data) {
        set({ manuscripts: res.data.manuscripts.map(toManuscript), loading: false });
        return;
      }
      set({ error: !res.success ? res.error : '获取作品列表失败', loading: false });
    } catch (err) {
      set({ error: err instanceof Error ? err.message : '获取作品列表异常', loading: false });
    }
  },

  select: (id: string) => {
    const { manuscripts } = get();
    const found = manuscripts.find(m => m.id === id) || null;
    set({ currentManuscript: found });
  },

  create: async (title: string, content?: string, genre?: string) => {
    set({ loading: true, error: null });
    try {
      const res = await typedInvoke<ManuscriptCreateRequest, ManuscriptCreateResponse>(
        IPC_CHANNELS.MANUSCRIPT_CREATE,
        { title, content, genre },
      );
      if (res.success && res.data) {
        await get().fetchList();
        set({ loading: false });
        return toManuscript(res.data.manuscript);
      }
      set({ error: !res.success ? res.error : '创建作品失败', loading: false });
      return null;
    } catch (err) {
      set({ error: err instanceof Error ? err.message : '创建作品异常', loading: false });
      return null;
    }
  },

  update: async (id: string, data: Partial<Pick<Manuscript, 'title' | 'description' | 'genre' | 'status'>>) => {
    try {
      const payload: ManuscriptUpdateRequest = {
        manuscriptId: id,
        title: data.title,
        content: data.description,
        genre: data.genre,
      };
      const res = await typedInvoke<ManuscriptUpdateRequest, ManuscriptCreateResponse>(
        IPC_CHANNELS.MANUSCRIPT_UPDATE,
        payload,
      );
      if (res.success) {
        await get().fetchList();
        if (get().currentManuscript?.id === id && res.data) {
          set({ currentManuscript: toManuscript(res.data.manuscript) });
        }
        return;
      }
      set({ error: res.error || '更新作品失败' });
    } catch (err) {
      set({ error: err instanceof Error ? err.message : '更新作品异常' });
    }
  },

  remove: async (id: string) => {
    try {
      const payload: ManuscriptDeleteRequest = { manuscriptId: id };
      const res = await typedInvoke<ManuscriptDeleteRequest, { success: true }>(
        IPC_CHANNELS.MANUSCRIPT_DELETE,
        payload,
      );
      if (res.success) {
        await get().fetchList();
        if (get().currentManuscript?.id === id) {
          set({ currentManuscript: null });
        }
        return true;
      }
      set({ error: res.error || '删除作品失败' });
      return false;
    } catch (err) {
      set({ error: err instanceof Error ? err.message : '删除作品异常' });
      return false;
    }
  },

  clearError: () => set({ error: null }),
}));
