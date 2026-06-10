import React, { useState, useCallback, useRef, type CSSProperties } from 'react';
import {
  Plus,
  FolderOpen,
  PanelRightClose,
  PanelRightOpen,
} from 'lucide-react';
import type { AppSidebarV2Props, NavIconItem } from './AppSidebar.types';
import {
  SIDEBAR_WIDTH,
  DEFAULT_NAV_ICONS,
  DEFAULT_MIXED_CONTENT,
} from './AppSidebar.types';
import { NewMenu } from './NewMenu';
import { MixedContentArea } from './MixedContentArea';
import styles from './AppSidebar.module.css';

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

  /** 侧边栏容器样式 */
  const sidebarContainerStyle: CSSProperties = {
    flex: collapsed ? '0 0 56px' : `0 1 ${SIDEBAR_WIDTH}px`,
    width: collapsed ? 56 : undefined,
    minWidth: collapsed ? 56 : `${SIDEBAR_WIDTH - 60}px`,
    maxWidth: collapsed ? 56 : '300px',
    background: 'var(--bg-sidebar)',
  };

  return (
    <aside
      className={styles.sidebarContainer}
      style={sidebarContainerStyle}
      role="navigation"
      aria-label="工作台侧边栏"
    >
      {/* 折叠按钮 — 圆形浮动按钮带旋转动画 */}
      <button
        onClick={onToggleCollapse}
        className={[
          styles.collapseToggleBtn,
          collapsed ? styles.collapseToggleCollapsed : '',
        ].join(' ')}
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
        {/* 水平导航：搜索 | 训练 | 任务 */}
        <div className="flex gap-1.5">
          {navIcons.map(iconItem => {
            const NavIcon = iconItem.icon;
            return (
              <button
                key={iconItem.id}
                onClick={() => handleNavClick(iconItem)}
                title={iconItem.label}
                className={[
                  styles.navIconBtn,
                  iconItem.primary ? styles.navIconBtnPrimary : '',
                ].join(' ')}
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

        {/* 新建按钮 */}
        <button
          ref={newBtnRef}
          onClick={handleOpenNewMenu}
          title="新建"
          className={styles.newSessionBtn}
        >
          <Plus size={13} strokeWidth={2} />
          <span>新建</span>
        </button>
      </div>

      {/* 下层：混合内容区 */}
      <div
        className={[
          styles.contentArea,
          collapsed ? styles.contentAreaCollapsed : styles.contentAreaExpanded,
        ].join(' ')}
      >
        {!collapsed ? (
          <MixedContentArea
            items={mixedContent}
            activeId={activeSessionId}
            onSelect={onSelectSession}
            onNewWork={onNewWork}
          />
        ) : (
          /* 折叠态空状态 */
          <div className={styles.collapsedEmptyState}>
            <FolderOpen size={22} strokeWidth={1.2} className="opacity-30" />
            <span className="text-[10px] tracking-wide opacity-50">作品</span>
          </div>
        )}
      </div>

      {/* 新建菜单弹出层 */}
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
