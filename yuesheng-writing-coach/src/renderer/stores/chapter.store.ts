// 章节状态管理（Zustand）
// 负责：管理章节列表、当前章节、打开的文件标签页和内容缓存
// 依赖：zustand, service-bridge (Sprint 26 阶段 3.6: 调用方迁移)
// 注意：bridge 模式返回纯数据（Chapter 对象 / null / { wordCount }），无 { success, data } 包装。

import { create } from 'zustand';
import { serviceBridge } from '../services/service-bridge';
import type { Chapter } from '../shared/types';

interface OpenTabMeta {
  title: string;
  manuscriptId: string;
  manuscriptTitle: string;
}

interface ChapterState {
  /** 当前作品的章节列表 */
  chapters: Chapter[];
  /** 当前选中的章节 */
  currentChapter: Chapter | null;
  /** 打开的文件标签页列表（按打开顺序） */
  openFiles: string[];
  /** 打开标签页的元数据 */
  openTabMeta: Record<string, OpenTabMeta>;
  /** 内容缓存（chapterId → content） */
  contentCache: Record<string, string>;
  /** 是否正在加载 */
  loading: boolean;
  /** 错误消息 */
  error: string | null;
  /** X-02: 训练改写待应用内容（由训练工坊写入，编辑器消费） */
  pendingRewrite: string | null;
}

interface ChapterActions {
  /** 根据作品 ID 获取章节列表 */
  fetchByWork: (manuscriptId: string) => Promise<void>;
  /** 选中某个章节 */
  select: (id: string) => void;
  /** 加载章节内容（含缓存） */
  loadContent: (id: string) => Promise<string | null>;
  /** 打开章节标签页（自动加入 openFiles） */
  openTab: (chapterId: string, manuscriptTitle?: string) => void;
  /** 关闭章节标签页 */
  closeTab: (chapterId: string) => void;
  /** 更新章节正文 */
  updateContent: (id: string, content: string) => Promise<{ wordCount: number } | null>;
  /** 创建新章节 */
  createChapter: (manuscriptId: string, title: string) => Promise<Chapter | null>;
  /** 删除章节 */
  deleteChapter: (id: string, manuscriptId: string) => Promise<boolean>;
  /** X-02: 应用训练改写结果到当前章节 */
  applyRewrite: (id: string, content: string) => Promise<boolean>;
  /** X-02: 清除待应用的改写结果 */
  clearRewrite: () => void;
}

export const useChapterStore = create<ChapterState & ChapterActions>((set, get) => ({
  // State
  chapters: [],
  currentChapter: null,
  openFiles: [],
  openTabMeta: {},
  contentCache: {},
  loading: false,
  error: null,
  pendingRewrite: null,

  // Actions
  fetchByWork: async (manuscriptId: string) => {
    set({ loading: true, error: null, openFiles: [], openTabMeta: {} });
    const data = await serviceBridge.invoke<{ manuscriptId: string }, Chapter[]>(
      'chapter:list',
      { manuscriptId },
    );
    if (data) {
      set({ chapters: data, loading: false });
    } else {
      set({ error: '获取章节列表失败', loading: false });
    }
  },

  select: (id: string) => {
    const { chapters } = get();
    const found = chapters.find(c => c.id === id) || null;
    set({ currentChapter: found });
  },

  loadContent: async (id: string) => {
    const cached = get().contentCache[id];
    if (cached !== undefined) return cached;

    const data = await serviceBridge.invoke<{ id: string }, Chapter>(
      'chapter:get',
      { id },
    );
    if (data) {
      set((s) => ({
        contentCache: { ...s.contentCache, [id]: data.content },
      }));
      return data.content;
    }
    return null;
  },

  openTab: (chapterId: string, manuscriptTitle?: string) => {
    const { openFiles, chapters } = get();
    if (!openFiles.includes(chapterId)) {
      const chapter = chapters.find(c => c.id === chapterId);
      if (chapter) {
        set(s => ({
          openFiles: [...s.openFiles, chapterId],
          openTabMeta: {
            ...s.openTabMeta,
            [chapterId]: {
              title: chapter.title,
              manuscriptId: chapter.manuscript_id,
              manuscriptTitle: manuscriptTitle || '',
            },
          },
        }));
      } else {
        set(s => ({ openFiles: [...s.openFiles, chapterId] }));
      }
    }
    get().select(chapterId);
  },

  closeTab: (chapterId: string) => {
    const { openFiles, currentChapter, openTabMeta } = get();
    const newFiles = openFiles.filter(id => id !== chapterId);
    const { [chapterId]: _removed, ...restMeta } = openTabMeta;
    set({ openFiles: newFiles, openTabMeta: restMeta });

    if (currentChapter?.id === chapterId) {
      if (newFiles.length > 0) {
        get().select(newFiles[newFiles.length - 1]);
      } else {
        set({ currentChapter: null });
      }
    }
  },

  updateContent: async (id: string, content: string) => {
    const data = await serviceBridge.invoke<{ id: string; content: string }, { wordCount: number }>(
      'chapter:updateContent',
      { id, content },
    );
    if (data) {
      set((s) => ({
        contentCache: { ...s.contentCache, [id]: content },
      }));
      return data;
    }
    set({ error: '更新章节失败' });
    return null;
  },

  createChapter: async (manuscriptId: string, title: string) => {
    const data = await serviceBridge.invoke<{ manuscriptId: string; title: string }, Chapter>(
      'chapter:create',
      { manuscriptId, title },
    );
    if (data) {
      get().fetchByWork(manuscriptId).catch(() => {});
      return data;
    }
    set({ error: '创建章节失败' });
    return null;
  },

  deleteChapter: async (id: string, manuscriptId: string) => {
    const data = await serviceBridge.invoke<{ id: string }, { deleted: boolean }>(
      'chapter:delete',
      { id },
    );
    if (data?.deleted) {
      get().fetchByWork(manuscriptId).catch(() => {});
      if (get().currentChapter?.id === id) {
        set({ currentChapter: null });
      }
      return true;
    }
    set({ error: '删除章节失败' });
    return false;
  },

  // ===== X-02: 训练改写结果 =====

  applyRewrite: async (id: string, content: string) => {
    const data = await serviceBridge.invoke<{ id: string; content: string }, { wordCount: number }>(
      'chapter:updateContent',
      { id, content },
    );
    if (data) {
      set((s) => ({
        contentCache: { ...s.contentCache, [id]: content },
        pendingRewrite: null,
      }));
      return true;
    }
    return false;
  },

  clearRewrite: () => { set({ pendingRewrite: null }); },
}));
