// 项目状态管理（Zustand）
// 负责：管理项目列表和选中状态
// 依赖：zustand, electron IPC (IPC_CHANNELS.PROJECT_*)

import { create } from 'zustand';
import { IPC_CHANNELS } from '../shared/constants';
import { typedInvoke } from '../services/ipc-client';
import type {
  ProjectInfo,
  ProjectListResponse,
  ProjectCreateRequest,
  ProjectCreateResponse,
  ProjectUpdateRequest,
  ProjectUpdateResponse,
  ProjectDeleteRequest,
  ProjectGetRequest,
  ProjectGetResponse,
} from '../../shared/api-contracts/project.contract';

export type { ProjectInfo };

interface ProjectState {
  projects: ProjectInfo[];
  loading: boolean;
  error: string | null;
}

interface ProjectActions {
  fetchList: () => Promise<void>;
  getById: (id: string) => ProjectInfo | undefined;
  fetchById: (id: string) => Promise<ProjectInfo | null>;
  createProject: (input: ProjectCreateRequest) => Promise<ProjectInfo | null>;
  updateProject: (id: string, data: Partial<ProjectUpdateRequest>) => Promise<ProjectInfo | null>;
  removeProject: (id: string) => Promise<boolean>;
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
      const res = await typedInvoke<Record<string, never>, ProjectListResponse>(
        IPC_CHANNELS.PROJECT_LIST,
        {},
      );
      if (res.success && res.data) {
        set({ projects: res.data, loading: false });
        return;
      }
      set({ error: !res.success ? res.error : '获取项目列表失败', loading: false });
    } catch (err) {
      set({ error: err instanceof Error ? err.message : '获取项目列表异常', loading: false });
    }
  },

  getById: (id: string) => {
    return get().projects.find(p => p.id === id);
  },

  fetchById: async (id: string) => {
    try {
      const payload: ProjectGetRequest = { projectId: id };
      const res = await typedInvoke<ProjectGetRequest, ProjectGetResponse>(
        IPC_CHANNELS.PROJECT_GET,
        payload,
      );
      if (res.success && res.data) {
        set((state) => ({
          projects: state.projects.some(p => p.id === res.data.id)
            ? state.projects.map(p => p.id === res.data.id ? res.data : p)
            : [...state.projects, res.data],
        }));
        return res.data;
      }
      return null;
    } catch (err) {
      set({ error: err instanceof Error ? err.message : '获取项目详情异常' });
      return null;
    }
  },

  createProject: async (input) => {
    set({ loading: true, error: null });
    try {
      const res = await typedInvoke<ProjectCreateRequest, ProjectCreateResponse>(
        IPC_CHANNELS.PROJECT_CREATE,
        input,
      );
      if (res.success && res.data) {
        set((state) => ({ projects: [...state.projects, res.data], loading: false }));
        return res.data;
      }
      set({ error: !res.success ? res.error : '创建项目失败', loading: false });
      return null;
    } catch (err) {
      set({ error: err instanceof Error ? err.message : '创建项目异常', loading: false });
      return null;
    }
  },

  updateProject: async (id, data) => {
    try {
      const payload: ProjectUpdateRequest = { projectId: id, ...data };
      const res = await typedInvoke<ProjectUpdateRequest, ProjectUpdateResponse>(
        IPC_CHANNELS.PROJECT_UPDATE,
        payload,
      );
      if (res.success && res.data) {
        set((state) => ({
          projects: state.projects.map(p => p.id === id ? res.data : p),
        }));
        return res.data;
      }
      set({ error: !res.success ? res.error : '更新项目失败' });
      return null;
    } catch (err) {
      set({ error: err instanceof Error ? err.message : '更新项目异常' });
      return null;
    }
  },

  removeProject: async (id) => {
    try {
      const payload: ProjectDeleteRequest = { projectId: id };
      const res = await typedInvoke<ProjectDeleteRequest, { success: true }>(
        IPC_CHANNELS.PROJECT_DELETE,
        payload,
      );
      if (res.success) {
        set((state) => ({ projects: state.projects.filter(p => p.id !== id) }));
        return true;
      }
      set({ error: res.error || '删除项目失败' });
      return false;
    } catch (err) {
      set({ error: err instanceof Error ? err.message : '删除项目异常' });
      return false;
    }
  },
}));
