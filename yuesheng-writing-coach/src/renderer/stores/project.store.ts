// 项目状态管理（Zustand）
// 负责：管理项目列表和选中状态
// 依赖：zustand, electron IPC (IPC_CHANNELS.PROJECT_*)

import { create } from 'zustand';
import { IPC_CHANNELS } from '../shared/constants';
import { getInvoke } from '../utils/ipc';
import type { ProjectInfo } from '../../shared/api-contracts/project.contract';

export type { ProjectInfo };

interface ProjectState {
  projects: ProjectInfo[];
  loading: boolean;
  error: string | null;
}

interface ProjectActions {
  fetchList: () => Promise<void>;
  getById: (id: string) => ProjectInfo | undefined;
}

export const useProjectStore = create<ProjectState & ProjectActions>((set, get) => ({
  // State
  projects: [],
  loading: false,
  error: null,

  // Actions
  fetchList: async () => {
    set({ loading: true, error: null });
    try {
      const invoke = getInvoke();
      const res = await invoke(IPC_CHANNELS.PROJECT_LIST, {}) as { success: boolean; data?: ProjectInfo[]; error?: string };
      if (res.success && res.data) {
        set({ projects: res.data, loading: false });
      } else {
        set({ error: res.error || '获取项目列表失败', loading: false });
      }
    } catch (err) {
      set({ error: err instanceof Error ? err.message : '获取项目列表异常', loading: false });
    }
  },

  getById: (id: string) => {
    return get().projects.find(p => p.id === id);
  },
}));
