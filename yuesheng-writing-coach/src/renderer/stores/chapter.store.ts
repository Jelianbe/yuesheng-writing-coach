// 章节状态管理（Zustand）
// 负责：管理章节列表、当前章节、打开的文件标签页和内容缓存
// 依赖：zustand, electron IPC (IPC_CHANNELS.CHAPTER_*)

import { create } from 'zustand';
import { IPC_CHANNELS } from '../shared/constants';
import type { Chapter } from '../shared/types';
import { getInvoke } from '../utils/ipc';

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
  deleteChapter: (id: string) => Promise<boolean>;
  /** 清除错误 */
  clearError: () => void;
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

  // Actions
  fetchByWork: async (manuscriptId: string) => {
    set({ loading: true, error: null });
    try {
      const invoke = getInvoke();
      const res = await invoke(IPC_CHANNELS.CHAPTER_LIST, { manuscriptId }) as { success: boolean; data?: Chapter[]; error?: string };
      if (res.success && res.data) {
        set({ chapters: res.data, loading: false });
      } else {
        set({ error: res.error || '获取章节列表失败', loading: false });
      }
    } catch (err) {
      set({ error: err instanceof Error ? err.message : '获取章节列表异常', loading: false });
    }
  },

  select: (id: string) => {
    const { chapters } = get();
    const found = chapters.find(c => c.id === id) || null;
    set({ currentChapter: found });
  },

  loadContent: async (id: string) => {
    // 优先从缓存读取
    const cached = get().contentCache[id];
    if (cached !== undefined) return cached;

    try {
      const invoke = getInvoke();
      const res = await invoke(IPC_CHANNELS.CHAPTER_GET, { id }) as { success: boolean; data?: Chapter; error?: string };
      if (res.success && res.data) {
        // 写入缓存并返回
        set((s) => ({
          contentCache: { ...s.contentCache, [id]: res.data!.content },
        }));
        return res.data.content;
      }
      return null;
    } catch {
      return null;
    }
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
    // 选中该章节
    get().select(chapterId);
  },

  closeTab: (chapterId: string) => {
    const { openFiles, currentChapter, openTabMeta } = get();
    const newFiles = openFiles.filter(id => id !== chapterId);
    const { [chapterId]: _removed, ...restMeta } = openTabMeta;
    set({ openFiles: newFiles, openTabMeta: restMeta });

    // 如果关闭的是当前章节，选中列表中的最后一个
    if (currentChapter?.id === chapterId) {
      if (newFiles.length > 0) {
        get().select(newFiles[newFiles.length - 1]);
      } else {
        set({ currentChapter: null });
      }
    }
  },

  updateContent: async (id: string, content: string) => {
    try {
      const invoke = getInvoke();
      const res = await invoke(IPC_CHANNELS.CHAPTER_UPDATE_CONTENT, { id, content }) as { success: boolean; data?: { wordCount: number }; error?: string };
      if (res.success && res.data) {
        // 更新缓存
        set((s) => ({
          contentCache: { ...s.contentCache, [id]: content },
        }));
        return res.data;
      }
      set({ error: res.error || '更新章节失败' });
      return null;
    } catch (err) {
      set({ error: err instanceof Error ? err.message : '更新章节异常' });
      return null;
    }
  },

  createChapter: async (manuscriptId: string, title: string) => {
    try {
      const invoke = getInvoke();
      const res = await invoke(IPC_CHANNELS.CHAPTER_CREATE, { manuscriptId, title }) as { success: boolean; data?: Chapter; error?: string };
      if (res.success && res.data) {
        await get().fetchByWork(manuscriptId);
        return res.data;
      }
      set({ error: res.error || '创建章节失败' });
      return null;
    } catch (err) {
      set({ error: err instanceof Error ? err.message : '创建章节异常' });
      return null;
    }
  },

  deleteChapter: async (id: string) => {
    try {
      const invoke = getInvoke();
      const res = await invoke(IPC_CHANNELS.CHAPTER_DELETE, { id }) as { success: boolean; error?: string };
      if (res.success) {
        const { currentChapter } = get();
        // 刷新当前作品的章节列表
        const mid = currentChapter?.manuscript_id;
        if (mid) {
          await get().fetchByWork(mid);
        }
        // 如果删除的是当前章节，清除选中
        if (currentChapter?.id === id) {
          set({ currentChapter: null });
        }
        return true;
      }
      set({ error: res.error || '删除章节失败' });
      return false;
    } catch (err) {
      set({ error: err instanceof Error ? err.message : '删除章节异常' });
      return false;
    }
  },

  clearError: () => set({ error: null }),
}));
