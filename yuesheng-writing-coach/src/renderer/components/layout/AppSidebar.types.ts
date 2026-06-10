import type React from 'react';
import {
  Search,
  Target,
  ClipboardList,
  FolderOpen,
  CheckCircle2,
  MessageSquare,
  Globe,
  Clapperboard,
  MessageCircle,
} from 'lucide-react';

// ============================================================
// 类型定义
// ============================================================

/** Lucide 图标组件类型（含 Lucide 特有属性） */
export type LucideIcon = React.ComponentType<React.SVGProps<SVGSVGElement> & { size?: number | string; strokeWidth?: number | string }>;

/** 新建菜单选项 */
export interface NewMenuOption {
  id: string;
  label: string;
  icon?: LucideIcon;
  description?: string;
  /** 是否为默认选中项 */
  default?: boolean;
  /** 是否为分隔线 */
  divider?: boolean;
  /** 分组标题 */
  group?: string;
}

/** 侧边栏导航图标项 */
export interface NavIconItem {
  id: string;
  label: string;
  icon: LucideIcon;
  primary?: boolean;
  onClick?: () => void;
}

/** 章节节点 */
export interface ChapterNode {
  type: 'chapter';
  id: string;
  title: string;
  badge?: number;
}

/** 作品树节点 */
export interface WorkTreeNode {
  type: 'work';
  id: string;
  title: string;
  chapters: ChapterNode[];
  defaultExpanded?: boolean;
}

/** 任务卡片 */
export interface TaskCardItem {
  type: 'task';
  id: string;
  title: string;
  source: string;
  meta: string;
  done: boolean;
}

/** 分组标题 */
export interface SectionHeaderItem {
  type: 'header';
  label: string;
  icon: LucideIcon;
  count?: number;
  /** 是否显示「新建」按钮（仅作品分组使用） */
  showNewButton?: boolean;
}

/** 混合内容区项类型 */
export type MixedContentItem = SectionHeaderItem | WorkTreeNode | ChapterNode | TaskCardItem;

export interface AppSidebarV2Props {
  collapsed: boolean;
  onToggleCollapse: () => void;
  onNewSession: () => void;
  onEnterWorkshop?: () => void;
  onNewWork?: () => void;
  activeSessionId: string;
  onSelectSession: (id: string) => void;
  /** 导航图标列表 */
  navIcons?: NavIconItem[];
  /** 混合内容区数据（Phase 3 接入真实数据） */
  mixedContent?: MixedContentItem[];
}

// ============================================================
// 样式常量
// ============================================================

export const SIDEBAR_WIDTH = 220;

// ── Motion 常量 ──
// [Impeccable Rule: Motion] 禁止 bounce/elastic spring-like easing。
// 使用 ease-out-quart (cubic-bezier(0.25, 1, 0.5, 1)) 实现自然减速。
export const EASE_OUT_QUART = 'cubic-bezier(0.25, 1, 0.5, 1)';
export const INTERACT_DURATION = '150ms';
export const PANEL_DURATION = '350ms';

// ── 语义化 z-index 层级 ──
// [Impeccable Rule: z-index] 禁止任意值如 9999 / 199 / 200。
// 构建语义化层级：dropdown=100, sticky=200, modal-backdrop=300, modal=400。
export const Z_LAYER = {
  dropdown: 100,
  sticky: 200,
  modalBackdrop: 300,
  modal: 400,
} as const;

/** 轻量阴影 — blur ≤ 8px，不与 border 配对大 shadow */
export const LIGHT_SHADOW = '0 2px 8px rgba(61, 50, 41, 0.08)';

// ============================================================
// Mock 数据
// ============================================================

export const DEFAULT_NAV_ICONS: NavIconItem[] = [
  { id: 'search', label: '搜索', icon: Search },
  { id: 'training', label: '训练工坊', icon: Target },
  { id: 'tasks', label: '任务视图', icon: ClipboardList },
];

export const DEFAULT_MIXED_CONTENT: MixedContentItem[] = [
  // 作品分组（带新建入口）
  { type: 'header', label: '我的作品', icon: FolderOpen, showNewButton: true },
  {
    type: 'work', id: 'w1', title: '《星河之外》',
    defaultExpanded: true,
    chapters: [
      { type: 'chapter', id: 'w1-c1', title: '第一章：启程', badge: 3 },
      { type: 'chapter', id: 'w1-c2', title: '第二章：迷雾' },
      { type: 'chapter', id: 'w1-c3', title: '第三章：暗流', badge: 1 },
      { type: 'chapter', id: 'w1-c4', title: '第四章：抉择' },
      { type: 'chapter', id: 'w1-c5', title: '第五章：归途' },
    ],
  },
  {
    type: 'work', id: 'w2', title: '《长安夜雨》',
    chapters: [
      { type: 'chapter', id: 'w2-c1', title: '开篇试写' },
      { type: 'chapter', id: 'w2-c2', title: '人物初设讨论' },
    ],
  },
  // 待处理分组
  { type: 'header', label: '待处理', icon: ClipboardList, count: 3 },
  { type: 'task', id: 't1', title: '完成「展示而非告知」训练', source: '训练工坊', meta: '剩余 2 题', done: false },
  { type: 'task', id: 't2', title: '修改第三章对话节奏', source: '诊断反馈', meta: '待改写', done: false },
  { type: 'task', id: 't3', title: '《深海回声》序章重写', source: '自我标记', meta: '下周截止', done: false },
  // 已完成分组
  { type: 'header', label: '已完成', icon: CheckCircle2, count: 3 },
  { type: 'task', id: 't4', title: 'POV一致性检查训练', source: '训练工坊', meta: '得分 85', done: true },
  { type: 'task', id: 't5', title: '修正对话枯燥问题', source: '诊断反馈', meta: '已完成改写', done: true },
  { type: 'task', id: 't6', title: '《长安夜雨》开篇试写', source: '已完成', meta: '昨天提交', done: true },
];

export const DEFAULT_NEW_OPTIONS: NewMenuOption[] = [
  { id: 'new-session', label: '从新对话开始', icon: MessageSquare, description: '创建全新对话会话', default: true },
  { id: 'open-work', label: '打开本地作品', icon: FolderOpen, description: '导入已有作品文件' },
  { id: 'divider-1', label: '', divider: true },
  { id: 'template-worldbuilding', label: '世界观构建', icon: Globe, group: '模板' },
  { id: 'template-character', label: '角色设计', icon: MessageCircle, group: '模板' },
  { id: 'template-scene', label: '场景描写', icon: Clapperboard, group: '模板' },
  { id: 'template-dialogue', label: '对话练习', icon: MessageCircle, group: '模板' },
];
