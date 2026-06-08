/**
 * TabBar — 范式 A 主内容区顶部标签栏
 *
 * 五个入口：对话教学 | 能力训练 | 作品诊断 | 成长记录 | 创作工具
 * 点击切换 activeTab，由父组件根据 activeTab 渲染对应内容。
 */

import React from 'react';

/** 范式 A 可用的 tab 标识 */
export type ParadigmATabId =
  | 'chat'       // 对话教学
  | 'training'   // 能力训练
  | 'diagnosis'  // 作品诊断
  | 'growth'     // 成长记录
  | 'tools';     // 创作工具

export interface TabItem {
  id: ParadigmATabId;
  label: string;
  /** Lucide 图标名或 emoji */
  icon: string;
}

/** 默认 tab 定义（对齐 fusion-demo V2） */
export const PARADIGM_A_TABS: TabItem[] = [
  { id: 'chat', label: '对话', icon: 'MessageCircle' },
  { id: 'training', label: '训练', icon: 'Target' },
  { id: 'diagnosis', label: '成就', icon: 'ClipboardList' },
  { id: 'growth', label: '地图', icon: 'TrendingUp' },
  { id: 'tools', label: '工具', icon: 'Wrench' },
];

export interface TabBarProps {
  /** 当前激活的 tab */
  activeTab: ParadigmATabId;
  /** tab 切换回调 */
  onTabChange: (tabId: ParadigmATabId) => void;
  /** 自定义 tab 列表（默认使用 PARADIGM_A_TABS） */
  tabs?: TabItem[];
}

/**
 * 简易图标渲染（V1 用 emoji/Lucide 字符，后续可替换为 lucide-react 组件）
 */
function TabIcon({ name }: { name: string }) {
  // 映射常见图标名为 unicode 符号或 emoji
  const iconMap: Record<string, string> = {
    MessageCircle: '💬',
    Target: '◎',
    ClipboardList: '📋',
    TrendingUp: '📈',
    Wrench: '🔧',
  };
  return <span>{iconMap[name] ?? name}</span>;
}

export const TabBar: React.FC<TabBarProps> = React.memo(({
  activeTab,
  onTabChange,
  tabs = PARADIGM_A_TABS,
}) => {
  return (
    <nav
      className="paradigm-a-tabbar"
      role="tablist"
      aria-label="功能导航"
      style={{
        display: 'flex',
        alignItems: 'center',
        gap: 0,
        borderBottom: '1px solid var(--border)',
        background: 'var(--bg-main)',
        padding: '0 20px',
        flexShrink: 0,
        userSelect: 'none',
        position: 'sticky',
        top: 0,
        zIndex: 10,
      }}
    >
      {tabs.map((tab) => {
        const isActive = tab.id === activeTab;
        return (
          <button
            key={tab.id}
            role="tab"
            aria-selected={isActive}
            tabIndex={isActive ? 0 : -1}
            onClick={() => onTabChange(tab.id)}
            style={{
              display: 'flex',
              alignItems: 'center',
              gap: '6px',
              padding: '0 14px', height: 32,
              borderRadius: 6,
              border: 'none',
              background: isActive ? 'var(--amber-light)' : 'transparent',
              color: isActive ? 'var(--amber-text)' : 'var(--text-secondary)',
              fontFamily: 'var(--font-body)',
              fontSize: 13,
              fontWeight: isActive ? 500 : 400,
              cursor: 'pointer',
              transition: 'all 0.15s',
              whiteSpace: 'nowrap',
            }}
            onMouseEnter={(e) => {
              if (!isActive) {
                (e.currentTarget as HTMLElement).style.background = 'var(--bg-hover)';
                (e.currentTarget as HTMLElement).style.color = 'var(--text)';
              }
            }}
            onMouseLeave={(e) => {
              if (!isActive) {
                (e.currentTarget as HTMLElement).style.background = 'transparent';
                (e.currentTarget as HTMLElement).style.color = 'var(--text-secondary)';
              }
            }}
          >
            <span style={{ fontSize: '1rem', lineHeight: 1 }}>
              <TabIcon name={tab.icon} />
            </span>
            <span>{tab.label}</span>
          </button>
        );
      })}
    </nav>
  );
});

TabBar.displayName = 'TabBar';
