// 项目状态管理（Zustand）
// 负责：管理项目列表和选中状态
// 依赖：projectService (Sprint 26 阶段 3.4 Z-1: 调用方迁移,双轨透明)

import { create } from 'zustand';
import { projectService } from '../services/project.service';
import type {
  ProjectInfo,
  ProjectCreateRequest,
  ProjectUpdateRequest,
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

  // Actions — 全部走 projectService (双轨)
  fetchList: async () => {
    set({ loading: true, error: null });
    const list = await projectService.list();
    if (list.length > 0) {
      set({ projects: list, loading: false });
      return;
    }
    set({ error: '获取项目列表失败', loading: false });
  },

  getById: (id: string) => {
    return get().projects.find(p => p.id === id);
  },

  fetchById: async (id: string) => {
    const data = await projectService.getById(id);
    if (data) {
      set((state) => ({
        projects: state.projects.some(p => p.id === data.id)
          ? state.projects.map(p => p.id === data.id ? data : p)
          : [...state.projects, data],
      }));
      return data;
    }
    return null;
  },

  createProject: async (input) => {
    set({ loading: true, error: null });
    const data = await projectService.create(input);
    if (data) {
      set((state) => ({ projects: [...state.projects, data], loading: false }));
      return data;
    }
    set({ error: '创建项目失败', loading: false });
    return null;
  },

  updateProject: async (id, data) => {
    const updated = await projectService.update(id, {
      name: data.name,
      description: data.description,
      settingTree: data.settingTree,
      settingTreeType: data.settingTreeType,
    });
    if (updated) {
      set((state) => ({
        projects: state.projects.map(p => p.id === id ? updated : p),
      }));
      return updated;
    }
    set({ error: '更新项目失败' });
    return null;
  },

  removeProject: async (id) => {
    const success = await projectService.remove(id);
    if (success) {
      set((state) => ({ projects: state.projects.filter(p => p.id !== id) }));
      return true;
    }
    set({ error: '删除项目失败' });
    return false;
  },
}));
