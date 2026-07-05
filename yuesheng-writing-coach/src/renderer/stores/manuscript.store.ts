// 作品状态管理（Zustand）
// 负责：管理用户作品列表和当前选中作品的状态
// 依赖：zustand, service-bridge (Sprint 26 阶段 3.6: 调用方迁移)
// 注意：bridge 模式返回纯 SQL row 数组 / row 对象，无 { success, data } 包装。

import { create } from 'zustand';
import { serviceBridge } from '../services/service-bridge';
import type { Manuscript } from '../shared/types';

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

/** SQL row 类型 — manuscripts 表的原始返回 */
interface ManuscriptRow {
  id: string;
  title: string;
  description?: string;
  genre?: string;
  status?: string;
  created_at: number;
  updated_at: number;
  sort_order?: number;
}

/** API 投影 ManuscriptRow → 本地 Manuscript(补齐 DB 字段默认值) */
const toManuscript = (row: ManuscriptRow): Manuscript => ({
  id: row.id,
  title: row.title,
  description: row.description ?? '',
  genre: row.genre ?? '',
  status: (row.status as Manuscript['status']) ?? 'active',
  created_at: row.created_at,
  updated_at: row.updated_at,
  sort_order: row.sort_order ?? 0,
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
    const data = await serviceBridge.invoke<Record<string, never>, ManuscriptRow[]>(
      'manuscript:list',
      {},
    );
    if (data) {
      set({ manuscripts: data.map(toManuscript), loading: false });
    } else {
      set({ error: '获取作品列表失败', loading: false });
    }
  },

  select: (id: string) => {
    const { manuscripts } = get();
    const found = manuscripts.find(m => m.id === id) || null;
    set({ currentManuscript: found });
  },

  create: async (title: string, content?: string, genre?: string) => {
    set({ loading: true, error: null });
    const data = await serviceBridge.invoke<{ title: string; description?: string; genre?: string }, ManuscriptRow>(
      'manuscript:create',
      { title, description: content, genre },
    );
    if (data) {
      // 自动创建对应的项目，保持数据一致
      const projectData = await serviceBridge.invoke<{ name: string; description?: string; settingTreeType?: string }, { id: string }>(
        'project:create',
        { name: title, description: content, settingTreeType: 'default' },
      );
      const manuscript = Object.assign(toManuscript(data), { projectId: projectData?.id });
      // 重新从 DB 加载后，把新创建的 projectId 附着到对应作品上
      await get().fetchList();
      set(state => ({
        manuscripts: state.manuscripts.map(m =>
          m.id === manuscript.id ? { ...m, projectId: manuscript.projectId } : m
        ),
        loading: false,
      }));
      return manuscript;
    }
    set({ error: '创建作品失败', loading: false });
    return null;
  },

  update: async (id: string, data: Partial<Pick<Manuscript, 'title' | 'description' | 'genre' | 'status'>>) => {
    const updated = await serviceBridge.invoke<
      { id: string; title?: string; description?: string; genre?: string; status?: 'active' | 'archived' },
      ManuscriptRow
    >('manuscript:update', {
      id,
      title: data.title,
      description: data.description,
      genre: data.genre,
      status: data.status,
    });
    if (updated) {
      await get().fetchList();
      if (get().currentManuscript?.id === id) {
        set({ currentManuscript: toManuscript(updated) });
      }
      return;
    }
    set({ error: '更新作品失败' });
  },

  remove: async (id: string) => {
    const data = await serviceBridge.invoke<{ id: string }, { deleted: boolean }>(
      'manuscript:delete',
      { id },
    );
    if (data?.deleted) {
      await get().fetchList();
      if (get().currentManuscript?.id === id) {
        set({ currentManuscript: null });
      }
      return true;
    }
    set({ error: '删除作品失败' });
    return false;
  },

  clearError: () => set({ error: null }),
}));
