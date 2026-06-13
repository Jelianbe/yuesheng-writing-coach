/**
 * 编辑器偏好设置 Store（Zustand）
 *
 * 管理：字体大小、背景色、文字色、排版格式等编辑器 UI 偏好。
 * 设置持久化到 localStorage，跨会话保持。
 */

import { create } from 'zustand';
import { persist } from 'zustand/middleware';

// ===== 类型定义 =====

/** 编辑器背景主题 */
export type EditorTheme =
  | 'paper'      // 米白色纸张
  | 'sepia'      // 护眼暖黄
  | 'dark'       // 暗色模式
  | 'custom';    // 自定义颜色

/** 排版格式配置 */
export interface FormatConfig {
  /** 首行缩进（字符数，0 = 不缩进） */
  firstLineIndent: number;
  /** 段落间是否插入空行 */
  paragraphSpacing: boolean;
  /** 行高倍数 */
  lineHeight: number;
}

/** 编辑器设置完整状态 */
export interface EditorSettings {
  // ----- 外观 -----
  /** 字体大小 (px)，范围 12-28 */
  fontSize: number;
  /** 字体族 */
  fontFamily: string;
  /** 背景主题 */
  theme: EditorTheme;
  /** 自定义背景色（仅 theme='custom' 时生效） */
  customBgColor: string;
  /** 自定义文字色（仅 theme='custom' 时生效） */
  customTextColor: string;

  // ----- 排版 -----
  format: FormatConfig;

  // ----- UI 状态 -----
  /** 设置面板是否展开 */
  settingsOpen: boolean;
}

/** 编辑器 Store Actions */
interface EditorActions {
  /** 调整字体大小 (+1 或 -1) */
  adjustFontSize: (delta: number) => void;
  /** 设置字体大小 */
  setFontSize: (size: number) => void;
  /** 切换主题 */
  setTheme: (theme: EditorTheme) => void;

  /** 切换设置面板 */
  toggleSettings: () => void;
  /** 关闭设置面板 */
  closeSettings: () => void;
}

// ===== 主题预设 =====

const THEME_PRESETS: Record<EditorTheme, { bg: string; text: string }> = {
  paper:   { bg: '#fefcf8', text: '#2c241b' },
  sepia:   { bg: '#f5ecd7', text: '#3e3224' },
  dark:    { bg: '#1a1816', text: '#d4ccc2' },
  custom:  { bg: '#fefcf8', text: '#2c241b' }, // fallback
};

const DEFAULT_FORMAT: FormatConfig = {
  firstLineIndent: 2,
  paragraphSpacing: true,
  lineHeight: 1.9,
};

const DEFAULT_SETTINGS: EditorSettings = {
  fontSize: 15,
  fontFamily: 'Georgia, "Noto Serif SC", "Source Han Serif SC", "STSong", serif',
  theme: 'paper',
  customBgColor: '#fefcf8',
  customTextColor: '#2c241b',
  format: { ...DEFAULT_FORMAT },
  settingsOpen: false,
};

// ===== Store =====

export const useEditorStore = create<EditorSettings & EditorActions>()(
  persist(
    (set) => ({
      ...DEFAULT_SETTINGS,

      adjustFontSize: (delta: number) => {
        set((s) => ({
          fontSize: Math.max(12, Math.min(28, s.fontSize + delta)),
        }));
      },

      setFontSize: (size: number) => {
        set({ fontSize: Math.max(12, Math.min(28, size)) });
      },

      setTheme: (theme: EditorTheme) => {
        set({ theme });
      },

      toggleSettings: () => {
        set((s) => ({ settingsOpen: !s.settingsOpen }));
      },

      closeSettings: () => {
        set({ settingsOpen: false });
      },
    }),
    {
      name: 'yuesheng-editor-settings',
      // 只持久化用户偏好，不持久化 UI 状态
      partialize: (state) => ({
        fontSize: state.fontSize,
        fontFamily: state.fontFamily,
        theme: state.theme,
        customBgColor: state.customBgColor,
        customTextColor: state.customTextColor,
        format: state.format,
      }),
    }
  )
);

// ===== 预设导出（供组件使用） =====

export { THEME_PRESETS };
