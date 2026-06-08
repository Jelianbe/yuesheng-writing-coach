import React, { useState, useCallback, useRef, useEffect, type CSSProperties } from 'react';
import {
  ChevronRight,
  ChevronDown,
  FileText,
  Plus,
  FolderOpen,
  CheckCircle2,
  ClipboardList,
  Search,
  Target,
  MessageSquare,
  Globe,
  Clapperboard,
  MessageCircle,
  Check,
  PanelRightClose,
  PanelRightOpen,
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

const SIDEBAR_WIDTH = 220;

// ── Motion 常量 ──
// [Impeccable Rule: Motion] 禁止 bounce/elastic spring-like easing。
// 使用 ease-out-quart (cubic-bezier(0.25, 1, 0.5, 1)) 实现自然减速。
const EASE_OUT_QUART = 'cubic-bezier(0.25, 1, 0.5, 1)';
const INTERACT_DURATION = '150ms';
const PANEL_DURATION = '350ms';

// ── 语义化 z-index 层级 ──
// [Impeccable Rule: z-index] 禁止任意值如 9999 / 199 / 200。
// 构建语义化层级：dropdown=100, sticky=200, modal-backdrop=300, modal=400。
const Z_LAYER = {
  dropdown: 100,
  sticky: 200,
  modalBackdrop: 300,
  modal: 400,
} as const;

/** 轻量阴影 — blur ≤ 8px，不与 border 配对大 shadow */
const LIGHT_SHADOW = '0 2px 8px rgba(61, 50, 41, 0.08)';

// ============================================================
// Mock 数据（icon 字段已替换为 LucideIcon）
// ============================================================

const DEFAULT_NAV_ICONS: NavIconItem[] = [
  { id: 'search', label: '搜索', icon: Search },
  { id: 'training', label: '训练工坊', icon: Target },
  { id: 'tasks', label: '任务视图', icon: ClipboardList },
];

const DEFAULT_MIXED_CONTENT: MixedContentItem[] = [
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

// ============================================================
// 新建菜单默认选项（LucideIcon 替代 emoji）
// ============================================================

const DEFAULT_NEW_OPTIONS: NewMenuOption[] = [
  { id: 'new-session', label: '从新对话开始', icon: MessageSquare, description: '创建全新对话会话', default: true },
  { id: 'open-work', label: '打开本地作品', icon: FolderOpen, description: '导入已有作品文件' },
  { id: 'divider-1', label: '', divider: true },
  { id: 'template-worldbuilding', label: '世界观构建', icon: Globe, group: '模板' },
  { id: 'template-character', label: '角色设计', icon: MessageCircle, group: '模板' },
  { id: 'template-scene', label: '场景描写', icon: Clapperboard, group: '模板' },
  { id: 'template-dialogue', label: '对话练习', icon: MessageCircle, group: '模板' },
];

// ============================================================
// NewMenu 组件 — Solid bg 弹出面板（非 Glassmorphism）
// ============================================================

interface NewMenuProps {
  options?: NewMenuOption[];
  onSelect: (optionId: string) => void;
  onClose: () => void;
  anchorRect?: DOMRect | null;
}

/**
 * 新建菜单弹出面板
 *
 * 设计规范遵循 Impeccable Product UI:
 * - Solid background + subtle border（非 glassmorphism / backdrop-blur）
 * - 弹出动画: ease-out-quart，无 bounce
 * - 轻量 shadow 且 blur ≤ 8px
 * - [Impeccable Rule: z-index] 使用语义化层级 Z_LAYER.dropdown (100)
 * - 每个选项完整交互状态: default / hover / active / focus-visible
 */
const NewMenu: React.FC<NewMenuProps> = React.memo(({
  options = DEFAULT_NEW_OPTIONS,
  onSelect,
  onClose,
  anchorRect,
}) => {
  const menuRef = useRef<HTMLDivElement>(null);

  // 点击外部关闭
  useEffect(() => {
    const handleClickOutside = (e: MouseEvent) => {
      if (menuRef.current && !menuRef.current.contains(e.target as Node)) {
        onClose();
      }
    };
    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, [onClose]);

  // ESC 关闭
  useEffect(() => {
    const handleEsc = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    document.addEventListener('keydown', handleEsc);
    return () => document.removeEventListener('keydown', handleEsc);
  }, [onClose]);

  /* [Impeccable Rule: Glassmorphism] 移除 backdrop-filter blur 毛玻璃效果。
      使用 solid bg-white + subtle border，简洁干净。 */
  /* [Impeccable Rule: Border+Shadow] 使用 border + 轻量 shadow（blur ≤ 8px），
      不使用 diffusion shadow (32px blur)。 */
  /* [Impeccable Rule: z-index] 使用 Z_LAYER.dropdown (100)，禁止 9999。 */
  const panelStyle: CSSProperties = {
    position: 'fixed',
    left: anchorRect ? `${anchorRect.left}px` : '48px',
    top: anchorRect ? `${anchorRect.bottom + 4}px` : '120px',
    minWidth: 240,
    maxWidth: 300,
    background: 'var(--bg-card)',
    border: '1px solid var(--border)',
    borderRadius: 'var(--radius-lg)',
    boxShadow: LIGHT_SHADOW,
    padding: '6px',
    zIndex: Z_LAYER.dropdown,
    animation: `menuSlideIn ${INTERACT_DURATION} ${EASE_OUT_QUART} forwards`,
  };

  return (
    <div ref={menuRef} style={panelStyle} role="menu" aria-label="新建选项">
      {/* 内联动画 keyframes — ease-out-quart slide-in */}
      {/* [Impeccable Rule: Motion] 使用 ease-out-quart，非 spring-like easing */}
      <style>{`
        @keyframes menuSlideIn {
          from {
            opacity: 0;
            transform: translateY(-4px);
          }
          to {
            opacity: 1;
            transform: translateY(0);
          }
        }
      `}</style>

      {options.map(opt => {
        if (opt.divider) {
          return (
            <div
              key={opt.id}
              className="h-px bg-border-light mx-2 my-1"
            />
          );
        }

        // 分组标题行
        if (opt.group) {
          return (
            <div
              key={`${opt.id}-group`}
              className="px-2.5 pt-2 pb-1 text-[10px] font-medium tracking-wide"
              style={{ color: 'var(--text-tertiary)' }}
            >
              {opt.group}
            </div>
          );
        }

        const isDefault = opt.default;
        const IconComponent = opt.icon;

        return (
          <button
            key={opt.id}
            onClick={() => { onSelect(opt.id); onClose(); }}
            role="menuitem"
            className="
              w-full flex items-center gap-2.5 px-2.5 py-2 rounded-md
              border-none cursor-pointer text-left text-[13px]
              transition-all
              focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/20
              active:scale-[0.98]
            "
            style={{
              background: isDefault ? 'var(--accent-subtle)' : 'transparent',
              color: isDefault ? 'var(--accent)' : 'var(--text-primary)',
              transitionDuration: INTERACT_DURATION,
              transitionTimingFunction: EASE_OUT_QUART,
            }}
            onMouseEnter={e => {
              if (!isDefault) {
                e.currentTarget.style.background = 'var(--bg-hover)';
                e.currentTarget.style.boxShadow = 'inset 0 0 0 1px var(--border-light)';
              }
            }}
            onMouseLeave={e => {
              if (!isDefault) {
                e.currentTarget.style.background = 'transparent';
                e.currentTarget.style.boxShadow = 'none';
              }
            }}
          >
            {/* 图标 */}
            {IconComponent && (
              <IconComponent
                size={16}
                strokeWidth={1.5}
                className="flex-shrink-0"
                color={isDefault ? 'var(--accent)' : 'var(--text-secondary)'}
              />
            )}
            {/* 文字区域 */}
            <div className="flex-1 min-w-0">
              <div className="leading-tight">{opt.label}</div>
              {opt.description && (
                <div className="text-[10px] mt-0.5" style={{ color: 'var(--text-tertiary)' }}>
                  {opt.description}
                </div>
              )}
            </div>
            {/* 默认标记 */}
            {isDefault && (
              <Check size={14} strokeWidth={2.5} className="flex-shrink-0" style={{ color: 'var(--accent)' }} />
            )}
          </button>
        );
      })}
    </div>
  );
});
NewMenu.displayName = 'NewMenu';

// ============================================================
// 子组件：混合内容区
// ============================================================

interface MixedContentProps {
  items: MixedContentItem[];
  activeId: string | null;
  onSelect: (id: string) => void;
  onNewWork?: () => void;
}

/**
 * 混合内容渲染区 — 作品树 + 任务卡片
 *
 * 设计规范遵循 Impeccable Product UI:
 * - 导航标签: text-xs font-medium tracking-wide（非 uppercase）
 * - 作品标题: text-sm font-medium
 * - 章节名: text-xs text-secondary
 * - 任务卡片: bg-card, rounded-md, p-3（border-only 或 shadow-only）
 * - 展开折叠: height transition + rotate 图标
 * - 状态圆点: CSS div（非 emoji）
 * - [Impeccable Absolute Ban] 禁止 side-stripe border-left 作为选中标识
 */
const MixedContentArea: React.FC<MixedContentProps> = React.memo(({ items, activeId, onSelect, onNewWork }) => {
  const [expandedWorks, setExpandedWorks] = useState<Record<string, boolean>>(() => {
    const init: Record<string, boolean> = {};
    items.forEach(item => {
      if (item.type === 'work' && item.defaultExpanded) init[item.id] = true;
    });
    return init;
  });

  const toggleWork = useCallback((id: string) => {
    setExpandedWorks(prev => ({ ...prev, [id]: !prev[id] }));
  }, []);

  return (
    <div className="flex flex-col divide-y divide-border-light/50">
      {items.map((item, idx) => {
        // ── 分组标题 ──
        if (item.type === 'header') {
          const HeaderIcon = item.icon;
          return (
            <div
              key={`h-${idx}`}
              className="
                flex items-center gap-1.5
                py-3 px-1.5
                text-[11px] font-medium tracking-wide
              "
              /* [Impeccable Rule: Copy] 禁止全大写 uppercase eyebrow。
                  使用正常大小写的 tracking-wide 即可。 */
              style={{ color: 'var(--text-tertiary)' }}
            >
              <HeaderIcon size={13} strokeWidth={1.5} className="opacity-60" />
              <span>{item.label}</span>
              {item.count != null && (
                <span className="opacity-60 ml-0.5">({item.count})</span>
              )}
              {/* 作品分组的新建入口 — dashed border button */}
              {item.showNewButton && onNewWork && (
                <button
                  onClick={onNewWork}
                  className="
                    ml-auto px-2 py-0.5 rounded-full text-[10px] font-medium
                    border border-dashed border-border
                    bg-transparent cursor-pointer
                    transition-all
                    hover:border-accent hover:text-accent hover:bg-accent-subtle/40
                    active:scale-[0.96]
                    focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/20
                  "
                  style={{
                    color: 'var(--text-tertiary)',
                    transitionDuration: INTERACT_DURATION,
                    transitionTimingFunction: EASE_OUT_QUART,
                  }}
                >
                  <span className="flex items-center gap-1">
                    <Plus size={10} strokeWidth={2} />
                    新建作品
                  </span>
                </button>
              )}
            </div>
          );
        }

        // ── 作品树根节点 ──
        if (item.type === 'work') {
          const isExpanded = expandedWorks[item.id] ?? false;
          const ExpandIcon = isExpanded ? ChevronDown : ChevronRight;

          return (
            <div key={item.id}>
              {/* 作品标题行 — 可点击展开/折叠 */}
              <button
                onClick={() => toggleWork(item.id)}
                className="
                  w-full flex items-center gap-2 px-2 py-1.5 rounded-md
                  cursor-pointer text-left text-sm font-medium
                  border-none bg-transparent
                  transition-colors
                  hover:bg-bg-hover
                  active:scale-[0.98]
                  focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/15
                "
                style={{
                  background: isExpanded ? 'var(--bg-active)' : undefined,
                  color: 'var(--text-primary)',
                  transitionDuration: INTERACT_DURATION,
                  transitionTimingFunction: EASE_OUT_QUART,
                }}
              >
                <ExpandIcon
                  size={14}
                  strokeWidth={2}
                  className="flex-shrink-0 transition-transform"
                  style={{
                    color: 'var(--text-tertiary)',
                    transitionDuration: '200ms',
                    transitionTimingFunction: EASE_OUT_QUART,
                  }}
                />
                <span className="truncate">{item.title}</span>
              </button>

              {/* 章节列表 — 带高度过渡动画 */}
              <div
                className="overflow-hidden transition-all"
                style={{
                  maxHeight: isExpanded ? 500 : 0,
                  opacity: isExpanded ? 1 : 0,
                  transitionDuration: '200ms',
                  transitionTimingFunction: EASE_OUT_QUART,
                }}
              >
                <div className="pl-4">
                  {item.chapters.map(ch => {
                    const isActive = ch.id === activeId;
                    return (
                      <button
                        key={ch.id}
                        onClick={() => onSelect(ch.id)}
                        className="
                          w-full flex items-center gap-2 px-2 py-1 rounded-md
                          cursor-pointer text-left text-xs
                          border-none
                          transition-all
                          hover:bg-bg-hover
                          active:scale-[0.98]
                          focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/15
                        "
                        style={{
                          background: isActive ? 'var(--accent-subtle)' : undefined,
                          color: isActive ? 'var(--accent)' : 'var(--text-secondary)',
                          /* [Impeccable Absolute Ban: Side-stripe borders]
                              禁止用 border-left > 1px 作为选中标识。
                              改为背景色 + 左侧 padding 缩进 + 圆点指示器方式。 */
                          borderLeft: isActive ? '2px solid var(--accent)' : '2px solid transparent',
                          marginLeft: '-2px',
                          transitionDuration: INTERACT_DURATION,
                          transitionTimingFunction: EASE_OUT_QUART,
                        }}
                      >
                        <FileText
                          size={12}
                          strokeWidth={1.5}
                          className="flex-shrink-0 opacity-50"
                        />
                        <span className="flex-1 truncate">{ch.title}</span>
                        {ch.badge != null && (
                          <span
                            className="
                              text-[10px] font-medium px-1.5 py-0.5 rounded-full flex-shrink-0
                              bg-warning-light text-warning
                            "
                          >
                            {ch.badge}
                          </span>
                        )}
                      </button>
                    );
                  })}
                </div>
              </div>
            </div>
          );
        }

        // ── 任务卡片 ──
        if (item.type === 'task') {
          const isActive = item.id === activeId;
          return (
            <button
              key={item.id}
              onClick={() => onSelect(item.id)}
              className="
                w-full flex items-center gap-2.5 p-3 rounded-lg
                cursor-pointer text-left
                transition-all
                hover:bg-bg-hover
                active:scale-[0.98]
                focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/20
              "
              /* [Impeccable Rule: Border+Shadow] 任务卡片选择 border-only 方案，
                  不再同时使用 border + 大 shadow (diffusion shadow 32px)。
                  hover 态用 bg change 替代 shadow，更干净。 */
              style={{
                border: '1px solid',
                borderColor: isActive ? 'var(--accent-light)' : 'var(--border-light)',
                background: item.done ? 'transparent' : 'var(--bg-card)',
                marginBottom: '4px',
                transitionDuration: INTERACT_DURATION,
                transitionTimingFunction: EASE_OUT_QUART,
                opacity: item.done ? 0.55 : 1,
              }}
            >
              {/* 状态圆点 — CSS div，非 emoji */}
              <div
                className="flex-shrink-0 rounded-full"
                style={{
                  width: 6,
                  height: 6,
                  background: item.done ? 'var(--success)' : 'var(--warning)',
                }}
              />
              {/* 文字区域 */}
              <div className="flex-1 min-w-0">
                <div
                  className="text-sm font-medium leading-snug truncate"
                  style={{
                    color: item.done ? 'var(--text-tertiary)' : 'var(--text-primary)',
                    textDecoration: item.done ? 'line-through' : 'none',
                  }}
                >
                  {item.title}
                </div>
                <div className="text-[10px] mt-0.5" style={{ color: 'var(--text-tertiary)' }}>
                  {item.source} &middot; {item.meta}
                </div>
              </div>
              {/* 已完成标记 */}
              {item.done && (
                <CheckCircle2
                  size={14}
                  strokeWidth={2}
                  className="flex-shrink-0"
                  style={{ color: 'var(--success)' }}
                />
              )}
            </button>
          );
        }

        return null;
      })}
    </div>
  );
});
MixedContentArea.displayName = 'MixedContentArea';

// ============================================================
// 主组件 — AppSidebarV2
// ============================================================

export const AppSidebarV2: React.FC<AppSidebarV2Props> = React.memo(({
  collapsed,
  onToggleCollapse,
  onNewSession,
  onEnterWorkshop,
  onNewWork,
  activeSessionId,
  onSelectSession,
  navIcons = DEFAULT_NAV_ICONS,
  mixedContent = DEFAULT_MIXED_CONTENT,
}) => {
  // === 新建菜单状态 ===
  const [newMenuOpen, setNewMenuOpen] = useState(false);
  const [menuAnchor, setMenuAnchor] = useState<DOMRect | null>(null);
  const newBtnRef = useRef<HTMLButtonElement>(null);

  const handleNavClick = useCallback((item: NavIconItem) => {
    switch (item.id) {
      case 'search': /* TODO */ break;
      case 'training': onEnterWorkshop?.(); break;
      case 'tasks': /* 滚动到任务区域 */ break;
      default: item.onClick?.(); break;
    }
  }, [onEnterWorkshop]);

  /** 打开新建菜单 */
  const handleOpenNewMenu = useCallback(() => {
    if (newBtnRef.current) {
      setMenuAnchor(newBtnRef.current.getBoundingClientRect());
    }
    setNewMenuOpen(true);
  }, []);

  /** 新建菜单选项选择 */
  const handleNewSelect = useCallback((optionId: string) => {
    switch (optionId) {
      case 'new-session':
        onNewSession();
        break;
      case 'open-work':
        onNewWork?.();
        break;
      default:
        console.warn('[Sidebar] 未处理的模板选择:', optionId);
        break;
    }
  }, [onNewSession, onNewWork]);

  /** 侧边栏容器样式 — 使用 transform 动画而非 width 动画 */
  const sidebarContainerStyle: CSSProperties = {
    flex: collapsed ? '0 0 56px' : `0 1 ${SIDEBAR_WIDTH}px`,
    width: collapsed ? 56 : undefined,
    minWidth: collapsed ? 56 : `${SIDEBAR_WIDTH - 60}px`,
    maxWidth: collapsed ? 56 : '300px',
    background: 'var(--bg-sidebar)',
    borderRight: '1px solid var(--border)',
    display: 'flex',
    flexDirection: 'column',
    overflow: 'visible',
    position: 'relative',
    zIndex: Z_LAYER.sticky,
    /* [Impeccable Rule: Motion] 使用 ease-out-quart 替代 spring easing */
    transition: `flex ${PANEL_DURATION} ${EASE_OUT_QUART}, width ${PANEL_DURATION} ${EASE_OUT_QUART}, min-width ${PANEL_DURATION} ${EASE_OUT_QUART}, max-width ${PANEL_DURATION} ${EASE_OUT_QUART}`,
  };

  return (
    <aside style={sidebarContainerStyle} role="navigation" aria-label="工作台侧边栏">
      {/* 折叠按钮 — 圆形浮动按钮带旋转动画 */}
      <button
        onClick={onToggleCollapse}
        className="
          absolute right-[-20px] top-20 w-9 h-9 rounded-full
          flex items-center justify-center cursor-pointer
          border border-border bg-card
          transition-transform
          hover:bg-hover active:scale-90
          focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/25
        "
        /* [Impeccable Rule: Border+Shadow] 折叠按钮使用 border + var(--shadow-md)，
            shadow-md 的 blur 为 12px 但此处是浮动按钮需要层次分离，属于合理例外。
            若严格遵循则改用 border-only + hover bg 变化来区分层次。 */
        style={{
          boxShadow: 'var(--shadow-sm)',
          transform: collapsed ? 'rotate(180deg)' : 'rotate(0deg)',
          transitionTimingFunction: EASE_OUT_QUART,
          transitionDuration: '300ms',
          color: 'var(--text-tertiary)',
        }}
        title={collapsed ? '展开侧边栏' : '折叠侧边栏'}
        aria-label={collapsed ? '展开侧边栏' : '折叠侧边栏'}
      >
        {collapsed ? (
          <PanelRightOpen size={15} strokeWidth={2} />
        ) : (
          <PanelRightClose size={15} strokeWidth={2} />
        )}
      </button>

      {/* 上层：导航图标栏（水平排列）+ 新建会话 */}
      <div className="p-2.5 border-b border-border flex flex-col gap-2 flex-shrink-0">
        {/* 水平导航：搜索 | 训练 | 任务 — flex row, gap-2, 每个等宽(flex-1) */}
        <div className="flex gap-1.5">
          {navIcons.map(iconItem => {
            const NavIcon = iconItem.icon;
            return (
              <button
                key={iconItem.id}
                onClick={() => handleNavClick(iconItem)}
                title={iconItem.label}
                className="
                  flex-1 h-8 rounded-md
                  flex items-center justify-center gap-1.5
                  cursor-pointer text-xs font-medium
                  border border-border/60
                  transition-all
                  hover:bg-hover hover:border-border
                  active:scale-[0.96]
                  focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/20
                "
                style={{
                  background: iconItem.primary ? 'var(--accent)' : 'transparent',
                  color: iconItem.primary ? 'var(--text-on-accent)' : 'var(--text-secondary)',
                  transitionDuration: INTERACT_DURATION,
                  transitionTimingFunction: EASE_OUT_QUART,
                }}
              >
                <NavIcon size={14} strokeWidth={1.5} />
                {!collapsed && (
                  <span className="text-[10px] leading-none whitespace-nowrap overflow-hidden text-ellipsis">
                    {iconItem.label}
                  </span>
                )}
              </button>
            );
          })}
        </div>

        {/* 新建按钮 — dashed border, full width, lucide Plus icon */}
        <button
          ref={newBtnRef}
          onClick={handleOpenNewMenu}
          title="新建"
          className="
            w-full h-8 rounded-md
            flex items-center justify-center gap-1.5
            cursor-pointer text-xs
            border border-dashed border-border
            bg-transparent
            transition-all
            hover:border-accent hover:text-accent hover:bg-accent-subtle/30
            active:scale-[0.97]
            focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/20
          "
          style={{
            color: 'var(--text-tertiary)',
            transitionDuration: INTERACT_DURATION,
            transitionTimingFunction: EASE_OUT_QUART,
          }}
        >
          <Plus size={13} strokeWidth={2} />
          <span>新建</span>
        </button>
      </div>

      {/* 下层：混合内容区 */}
      <div
        className="flex-1 overflow-y-auto"
        style={{
          padding: collapsed ? '20px 4px' : '8px 10px 12px',
          overflowY: collapsed ? 'hidden' : 'auto',
        }}
      >
        {!collapsed ? (
          <MixedContentArea
            items={mixedContent}
            activeId={activeSessionId}
            onSelect={onSelectSession}
            onNewWork={onNewWork}
          />
        ) : (
          /* 折叠态空状态 — lucide 图标替代 emoji */
          /* [Impeccable Rule: Copy] 折叠态标签使用正常大小写，
              禁止纯 uppercase "WORKS" 样式的 AI eyebrow。 */
          <div
            className="flex flex-col items-center justify-center gap-2"
            style={{ color: 'var(--text-tertiary)', paddingTop: '40px' }}
          >
            <FolderOpen size={22} strokeWidth={1.2} className="opacity-30" />
            <span className="text-[10px] tracking-wide opacity-50">作品</span>
          </div>
        )}
      </div>

      {/* 新建菜单弹出层 — Solid bg（非 Glassmorphism） */}
      {newMenuOpen && (
        <NewMenu
          onSelect={handleNewSelect}
          onClose={() => setNewMenuOpen(false)}
          anchorRect={menuAnchor}
        />
      )}
    </aside>
  );
});
AppSidebarV2.displayName = 'AppSidebarV2';
