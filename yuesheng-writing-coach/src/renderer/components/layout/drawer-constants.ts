import type { LucideIcon } from 'lucide-react';
import {
  Search,
  ClipboardCheck,
  Target,
  TrendingUp,
  User,
  Wrench,
  Settings,
  FileText,
} from 'lucide-react';
import type { PanelSessionType } from '../../stores/panel-session.store';

// ============================================================
// drawer-constants.ts — RightDrawer 所有静态常量集中定义
// ============================================================

// ── 工具项接口 ──
export interface ToolItem {
  id: string;
  icon: LucideIcon;
  label: string;
  description?: string;
  onClick?: () => void;
  disabled?: boolean;
  featured?: boolean;
}

/** 默认工具列表 */
export const DEFAULT_TOOLS: ToolItem[] = [
  { id: 'works', icon: Search, label: '作品', description: '编辑作品内容' },
  { id: 'diagnosis', icon: ClipboardCheck, label: '诊断', description: '分析作品中的写作问题' },
  { id: 'training', icon: Target, label: '训练', description: '针对性能力训练' },
  { id: 'growth', icon: TrendingUp, label: '成长', description: '查看成长趋势和能力变化' },
  { id: 'profile', icon: User, label: '画像', description: '写作能力雷达图' },
  { id: 'tools', icon: Wrench, label: '工具', description: '世界观生成、角色设计等' },
];

/** toolId → SessionType 映射 */
export const TOOL_TO_SESSION_TYPE: Record<string, PanelSessionType> = {
  works: 'edit',
  training: 'training',
  diagnosis: 'diagnosis',
  growth: 'growth',
  profile: 'profile',
  search: 'search',
  tools: 'tools',
  __settings__: 'settings',
};

/** SessionType → toolId 反向映射（用于标签切换时同步 activePanel） */
export const SESSION_TYPE_TO_TOOL_ID: Record<PanelSessionType, string> = {
  edit: 'works',
  training: 'training',
  diagnosis: 'diagnosis',
  growth: 'growth',
  profile: 'profile',
  search: 'search',
  tools: 'tools',
  settings: '__settings__',
};

/** SessionType → 标签默认标题 */
export const SESSION_DEFAULT_TITLE: Record<PanelSessionType, string> = {
  edit: '作品',
  training: '训练',
  diagnosis: '诊断',
  growth: '诊断对比',
  profile: '能力画像',
  search: '搜索',
  tools: '工具箱',
  settings: '设置',
};

/** SessionType → 标签图标（Lucide SVG，禁止 emoji） */
export const SESSION_LUCIDE_ICON: Record<PanelSessionType, LucideIcon> = {
  edit: FileText,
  training: Target,
  diagnosis: ClipboardCheck,
  growth: TrendingUp,
  profile: User,
  search: Search,
  tools: Wrench,
  settings: Settings,
};

// ── 布局 / 动画 / 拖拽常量 ──
export const EASE_OUT_QUART = 'cubic-bezier(0.25, 1, 0.5, 1)';
export const ICON_STRIP_WIDTH = 44;
export const ICON_BUTTON_SIZE = 36;
export const DEFAULT_PANEL_WIDTH = 420;
export const RESIZE_MIN = 320;
export const RESIZE_MAX = 900;
export const STORAGE_KEY = 'right-drawer-width';

/** z-index 层级 */
export const Z_LAYER = {
  dropdown: 100,
  modal: 400,
} as const;

/** 字体层级（与 ManuscriptPanel 统一） */
export const FONT = {
  display: '14px',
  body: '13px',
  caption: '11px',
  micro: '10px',
} as const;
