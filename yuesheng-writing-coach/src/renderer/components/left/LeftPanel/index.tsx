import React, { useState, useMemo, useEffect } from 'react';
import { useSessionStore } from '../../../stores/session.store';
import { useUiStore } from '../../../stores/ui.store';
import { useProjectStore } from '../../../stores/project.store';
import { panelBus } from '../../../bus/panel-bus';
import { SessionList } from '../SessionList';
import { ProjectList } from '../ProjectList';
import styles from './index.module.css';

interface LeftPanelProps {
  collapsed: boolean;
  setCollapsed: (v: boolean) => void;
}

export const LeftPanel: React.FC<LeftPanelProps> = ({ collapsed, setCollapsed }) => {
  // X-01: 不再直接 import right-tools.store,改用 panel-bus
  const tab = useUiStore(s => s.leftTab);
  const setTab = useUiStore(s => s.setLeftTab);
  const [searchQuery, setSearchQuery] = useState('');
  const [sessionFilter, setSessionFilter] = useState<'all' | 'chat' | 'train'>('all');
  const { sessions, currentSessionId, switchSession } = useSessionStore();
  const activeProjectTabId = useUiStore(s => s.selectedProjectId);
  const setActiveProjectId = useUiStore(s => s.setSelectedProjectId);
  const projects = useProjectStore(s => s.projects);
  const fetchProjects = useProjectStore(s => s.fetchList);

  // 首次挂载时从后端加载项目列表
  useEffect(() => { fetchProjects(); }, [fetchProjects]);

  const handleTabChange = (newTab: 'chat' | 'proj') => {
    setTab(newTab);
    if (newTab === 'proj') {
      // 切换到项目 tab:关闭 training 工具
      panelBus.dispatch({ type: 'close-tool', toolId: 'training' });
    } else if (newTab === 'chat') {
      // 切换到对话 tab:关闭 training 和 works 工具,清空项目 tab 列表
      panelBus.dispatch({ type: 'close-tool', toolId: 'training' });
      panelBus.dispatch({ type: 'close-tool', toolId: 'works' });
      panelBus.dispatch({ type: 'clear-project-tabs' });
    }
  };

  const filteredSessions = useMemo(() => {
    let result = sessions;
    if (sessionFilter === 'chat') {
      result = result.filter(s => !s.title.startsWith('训练:'));
    } else if (sessionFilter === 'train') {
      result = result.filter(s => s.title.startsWith('训练:'));
    }
    if (!searchQuery.trim()) return result;
    const q = searchQuery.toLowerCase();
    return result.filter(s =>
      s.title.toLowerCase().includes(q) ||
      (s.lastMessage && s.lastMessage.toLowerCase().includes(q))
    );
  }, [sessions, searchQuery, sessionFilter]);

  const filteredProjects = useMemo(() => {
    if (!searchQuery.trim()) return projects;
    const q = searchQuery.toLowerCase();
    return projects.filter(p =>
      p.name.toLowerCase().includes(q) ||
      (p.description && p.description.toLowerCase().includes(q))
    );
  }, [searchQuery, projects]);

  return (
    <div className={styles.panel}>
      {/* Header */}
      <div className={styles.header}>
        <div className={styles.brand}>
          <div className={styles.logo}>月</div>
          <span className={styles.brandName}>月笙</span>
        </div>
        <button className={styles.collapseBtn} onClick={() => setCollapsed(!collapsed)} title="收起">☰</button>
      </div>

      {/* Tabs */}
      <div className={styles.tabBar}>
        <button
          className={`${styles.tab} ${tab === 'chat' ? styles.tabActive : ''}`}
          onClick={() => handleTabChange('chat')}
        >对话</button>
        <button
          className={`${styles.tab} ${tab === 'proj' ? styles.tabActive : ''}`}
          onClick={() => handleTabChange('proj')}
        >项目</button>
      </div>

      <div className={styles.divider} />

      {/* Search */}
      <div className={styles.searchWrap}>
        <div className={styles.searchBox}>
          <span className={styles.searchIcon}>⌕</span>
          <input
            type="text"
            placeholder="搜索..."
            className={styles.searchInput}
            value={searchQuery}
            onChange={e => setSearchQuery(e.target.value)}
          />
        </div>
      </div>

      {/* List */}
      <div className={styles.listArea}>
        {tab === 'chat' ? (
          <SessionList
            sessions={filteredSessions}
            currentSessionId={currentSessionId}
            onSelect={(id) => switchSession(id)}
            filter={sessionFilter}
            onFilterChange={setSessionFilter}
          />
        ) : (
          <ProjectList
            projects={filteredProjects}
            selectedProjectId={activeProjectTabId}
            onSelect={(id) => {
              setActiveProjectId(id);
              // X-01: 通过总线打开项目工作区
              panelBus.dispatch({ type: 'open-project-tab', projectId: id });
              panelBus.dispatch({ type: 'open-tool', toolId: 'works' });
            }}
          />
        )}
      </div>
    </div>
  );
};
