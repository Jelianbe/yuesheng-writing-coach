/**
 * CenterHeader.tsx — 中间栏 Header 子组件（Phase G / Sprint 9 G-2）
 *
 * 职责：
 * - 渲染中间栏顶部的折叠条 + 项目下拉 + 状态徽章 + 会话徽章 + 操作按钮
 * - 多项目支持：项目下拉从 useProjectStore 读取，移除硬编码
 * - X-01：通过 panelBus 派发工具打开/关闭，避免直接 import right-tools.store
 *
 * 设计动机（G-2）：
 * - CenterPanel 之前耦合了 Header 渲染 + 多种 store 监听
 * - 拆出后 CenterPanel 只负责内容区（ChatView / Training / Editor / Empty）
 * - Header 逻辑集中可测、可复用、可独立演进（如未来加多项目 Tab）
 */

import React, { useEffect, useMemo, useState, useRef, useCallback } from 'react';
import { useSessionStore } from '../../../stores/session.store';
import { useTeachingStateStore } from '../../../stores/teaching-state.store';
import { useUiStore } from '../../../stores/ui.store';
import { useProjectStore } from '../../../stores/project.store';
import { panelBus } from '../../../bus/panel-bus';
import type { CenterMode } from '../../../shared/types';
import styles from './index.module.css';

export interface CenterHeaderProps {
  collapsedLeft: boolean;
  setCollapsedLeft: (v: boolean) => void;
  centerMode: CenterMode;
  onNewSession: () => void;
  onBackToChat: () => void;
}

const SUBPHASE_LABELS: Record<string, string> = {
  S1: '待诊断', S2: '诊断中', S3: '待训练',
  S4: '训练中', S5: '待回顾', S6: '回顾中', S7: '已完成',
};

export const CenterHeader: React.FC<CenterHeaderProps> = ({
  collapsedLeft,
  setCollapsedLeft,
  centerMode,
  onNewSession,
  onBackToChat,
}) => {
  const { sessions, currentSessionId, loadSessions } = useSessionStore();
  const { currentState } = useTeachingStateStore();
  const selectedProjectId = useUiStore(s => s.selectedProjectId);
  const setSelectedProjectId = useUiStore(s => s.setSelectedProjectId);
  const projects = useProjectStore(s => s.projects);
  const fetchProjects = useProjectStore(s => s.fetchList);

  const [dropdownOpen, setDropdownOpen] = useState(false);
  const dropdownRef = useRef<HTMLDivElement | null>(null);

  // 挂载时拉取项目列表与 session 列表
  useEffect(() => {
    fetchProjects();
    loadSessions();
  }, [fetchProjects, loadSessions]);

  // 点击外部关闭下拉
  useEffect(() => {
    if (!dropdownOpen) return;
    const onDocClick = (e: MouseEvent): void => {
      if (dropdownRef.current && !dropdownRef.current.contains(e.target as Node)) {
        setDropdownOpen(false);
      }
    };
    document.addEventListener('mousedown', onDocClick);
    return () => document.removeEventListener('mousedown', onDocClick);
  }, [dropdownOpen]);

  // 当前项目
  const currentProject = useMemo(
    () => projects.find(p => p.id === selectedProjectId) ?? null,
    [projects, selectedProjectId],
  );

  const projectButtonLabel = currentProject?.name ?? '选择项目';
  const projectButtonClass = currentProject ? styles.projectBtn : styles.projectBtnPlaceholder;

  // 教学状态徽章文本
  const statusText = useMemo(() => {
    if (!currentState?.currentSubphase) return '教学中';
    return SUBPHASE_LABELS[currentState.currentSubphase] ?? currentState.currentSubphase;
  }, [currentState]);

  const currentSession = useMemo(
    () => sessions.find(s => s.id === currentSessionId) ?? null,
    [sessions, currentSessionId],
  );

  // 选中项目 → 通过 panelBus 打开 works 工具
  const handleSelectProject = useCallback((projectId: string) => {
    setSelectedProjectId(projectId);
    panelBus.dispatch({ type: 'open-project-tab', projectId });
    panelBus.dispatch({ type: 'open-tool', toolId: 'works' });
    setDropdownOpen(false);
  }, [setSelectedProjectId]);

  // 打开设置工具
  const handleOpenSettings = useCallback(() => {
    panelBus.dispatch({ type: 'open-tool', toolId: '__settings__' });
  }, []);

  return (
    <header className={styles.header}>
      <div className={styles.headerLeft}>
        {collapsedLeft && (
          <div className={styles.collapsedBar}>
            <div className={styles.collapsedBarLogo}>月</div>
            <button
              className={styles.expandBtn}
              onClick={() => setCollapsedLeft(false)}
              title="展开"
            >☰</button>
          </div>
        )}

        {/* G-3: 多项目下拉（移除"我的第一本小说"硬编码） */}
        <div className={styles.projectDropdown} ref={dropdownRef}>
          <button
            className={projectButtonClass}
            onClick={() => setDropdownOpen(v => !v)}
            title="切换项目"
          >
            <span className={styles.projectBtnArrow}>▼</span>
            <span>{projectButtonLabel}</span>
            <span className={styles.projectBtnArrow}>▾</span>
          </button>
          {dropdownOpen && (
            <div className={styles.dropdownPanel}>
              {projects.length === 0 ? (
                <div className={styles.dropdownEmpty}>暂无项目</div>
              ) : (
                projects.map(p => (
                  <button
                    key={p.id}
                    className={`${styles.dropdownItem} ${
                      p.id === selectedProjectId ? styles.dropdownItemActive : ''
                    }`}
                    onClick={() => handleSelectProject(p.id)}
                  >
                    <span className={styles.dropdownItemName}>{p.name}</span>
                    {p.description && (
                      <span className={styles.dropdownItemDesc}>{p.description}</span>
                    )}
                  </button>
                ))
              )}
            </div>
          )}
        </div>

        <span className={styles.statusBadge}>
          <span className={styles.statusDot} />
          <span>{statusText}</span>
        </span>

        {currentSession && (
          <span className={styles.sessionBadge}>{currentSession.title}</span>
        )}
      </div>

      <div className={styles.headerActions}>
        {centerMode === 'training' && (
          <button
            className={styles.headerBackBtn}
            onClick={onBackToChat}
            title="返回对话"
          >← 返回</button>
        )}
        <button
          className={styles.headerBtn}
          onClick={onNewSession}
          title="新建会话"
        >＋</button>
        <button
          className={styles.headerBtn}
          onClick={handleOpenSettings}
          title="设置"
        >⚙</button>
      </div>
    </header>
  );
};
