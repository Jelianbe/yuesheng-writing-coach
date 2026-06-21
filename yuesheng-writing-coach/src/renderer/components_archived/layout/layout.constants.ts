/**
 * layout.constants.ts — 布局常量（单一数据源）
 *
 * 所有跨组件共享的布局数值集中定义在此文件。
 * 各组件通过 import 引用，禁止在组件内重复定义相同语义的魔法数字。
 *
 * 分类：
 *   - 图标条尺寸（RightDrawer 图标导航）
 *   - 面板宽度（可拖拽调节范围）
 *   - 编辑器参数（字号范围、防抖）
 *   - z-index 层级（避免层叠冲突）
 *   - 缓动曲线（统一动画手感）
 *   - LocalStorage 键（持久化键名）
 */

// ── 图标条 ──

/** 图标条宽度 px */
export const ICON_STRIP_WIDTH = 44;

/** 图标按钮尺寸 px */
export const ICON_BUTTON_SIZE = 36;

// ── 面板宽度 ──

/** 默认工作区宽度 px */
export const DEFAULT_PANEL_WIDTH = 420;

/** 拖拽最小宽度 px */
export const PANEL_RESIZE_MIN = 320;

/** 拖拽最大宽度 px */
export const PANEL_RESIZE_MAX = 900;

/** 设置弹出层宽度 px */
export const SETTINGS_POPOVER_WIDTH = 276;

/** 弹出层 + 面板最小总宽（防止溢出） */
export const SETTINGS_POPOVER_MIN_TOTAL = 320;

// ── 编辑器 ──

/** 字号最小值 px */
export const EDITOR_FONT_SIZE_MIN = 12;

/** 字号最大值 px */
export const EDITOR_FONT_SIZE_MAX = 28;

/** 自动保存防抖时间 ms */
export const EDITOR_SAVE_DEBOUNCE_MS = 1500;

// ── z-index 层级 ──

export const Z_INDEX = {
  /** 下拉/弹出层 */
  dropdown: 100,
  /** 格式确认弹窗 */
  formatConfirm: 200,
  /** 模态框/遮罩 */
  modal: 400,
} as const;

// ── 缓动曲线 ──

/** 统一缓动：快出慢入，用于面板展开/收起、hover 等过渡 */
export const EASE_OUT_QUART = 'cubic-bezier(0.25, 1, 0.5, 1)';

// ── AppShell 全局布局 ──

/** 应用最小宽度 px（防止三栏挤压） */
export const APP_SHELL_MIN_WIDTH = 1200;

/** 对话区（Chat Area）最小宽度 px */
export const CHAT_AREA_MIN_WIDTH = 400;

// ── LocalStorage 键 ──

export const LS_KEYS = {
  /** 右侧栏用户拖拽宽度持久化 */
  rightDrawerWidth: 'right-drawer-width',
} as const;
