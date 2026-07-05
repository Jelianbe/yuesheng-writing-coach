/**
 * PageStackStore — 移动端页面栈管理
 *
 * TabBar  3 tab 切换 + push/pop 子页面导航
 * 根页面（bookshelf / conversations / apps）显示 TabBar
 * 子页面（project-space / chat）隐藏 TabBar
 */

import { create } from 'zustand';

export type RootTab = 'bookshelf' | 'conversations' | 'apps';
export type PageName =
  | RootTab
  | 'project-space'
  | 'chat'
  | 'growth-report'
  | 'training-plan'
  | 'settings'
  | 'technique-library'
  | 'material-library';

export interface PageStackEntry {
  name: PageName;
  params?: Record<string, string>;
}

interface PageStackState {
  /** 当前活跃 Tab */
  activeTab: RootTab;
  /** 当前 Tab 内的页面栈（栈底为根页面） */
  stack: PageStackEntry[];
  /** 是否显示 TabBar */
  tabBarVisible: boolean;

  /** 切换到指定 Tab（清空栈，推到根页面） */
  navigateToTab: (tab: RootTab) => void;
  /** push 子页面（隐藏 TabBar） */
  push: (name: PageName, params?: Record<string, string>) => void;
  /** pop 回上一页 */
  pop: () => void;
  /** replace 当前页面 */
  replace: (name: PageName, params?: Record<string, string>) => void;
  /** 获取当前页面 */
  currentPage: () => PageStackEntry;
}

export const usePageStackStore = create<PageStackState>((set, get) => ({
  activeTab: 'bookshelf',
  stack: [{ name: 'bookshelf' }],
  tabBarVisible: true,

  navigateToTab: (tab: RootTab) => {
    set({ activeTab: tab, stack: [{ name: tab }], tabBarVisible: true });
  },

  push: (name: PageName, params?: Record<string, string>) => {
    const { stack } = get();
    set({ stack: [...stack, { name, params }], tabBarVisible: false });
  },

  pop: () => {
    const { stack } = get();
    if (stack.length <= 1) return;
    const newStack = stack.slice(0, -1);
    set({ stack: newStack, tabBarVisible: newStack.length <= 1 });
  },

  replace: (name: PageName, params?: Record<string, string>) => {
    const { stack } = get();
    const newStack = [...stack.slice(0, -1), { name, params }];
    set({ stack: newStack, tabBarVisible: newStack.length <= 1 });
  },

  currentPage: () => {
    const { stack } = get();
    return stack[stack.length - 1];
  },
}));
