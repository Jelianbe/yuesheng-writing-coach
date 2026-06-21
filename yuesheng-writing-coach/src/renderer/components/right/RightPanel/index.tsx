import React, { useCallback, useRef } from 'react';
import { useRightToolsStore, ALL_TOOLS, type ToolId } from '../../../stores/right-tools.store';
import { useProjectStore } from '../../../stores/project.store';
import { CatalogWorkspace } from '../workspaces/CatalogWorkspace';
import { ProgressWorkspace } from '../workspaces/ProgressWorkspace';
import { LearningLogWorkspace } from '../workspaces/LearningLogWorkspace';
import { WorksWorkspace } from '../workspaces/WorksWorkspace';
import { TeachingNoteWorkspace } from '../workspaces/TeachingNoteWorkspace';
import { SettingsWorkspace } from '../workspaces/SettingsWorkspace';
import { ToolGrid } from '../ToolGrid';
import { ToolTabs } from '../ToolTabs';
import { SubTabs, type SubTabItem } from '../SubTabs';
import styles from './index.module.css';

interface RightPanelProps {
  setCollapsedRight: (v: boolean) => void;
}

const WORKSPACE_MAP: Record<ToolId, React.FC> = {
  catalog: CatalogWorkspace,
  progress: ProgressWorkspace,
  growth: LearningLogWorkspace,
  works: WorksWorkspace,
  training: TeachingNoteWorkspace,
  __settings__: SettingsWorkspace,
};

export const RightPanel: React.FC<RightPanelProps> = ({
  setCollapsedRight,
}) => {
  const {
    openTools, activeToolId, openTool, setActiveTool, closeTool,
    subTabs, activeSubTabId, removeSubTab, setActiveSubTab,
    projectTabs, activeProjectTabId, setActiveProjectTab, closeProjectTab,
  } = useRightToolsStore();

  const [showPopup, setShowPopup] = React.useState(false);
  const popupRef = useRef<HTMLDivElement>(null);
  const addBtnRef = useRef<HTMLButtonElement>(null);

  // ── 加工具弹窗 ──
  const handleAddTool = useCallback(() => setShowPopup(v => !v), []);
  const handleSelectTool = useCallback((id: ToolId) => {
    openTool(id);
    setShowPopup(false);
  }, [openTool]);

  // 点击弹窗外关闭
  React.useEffect(() => {
    if (!showPopup) return;
    const handler = (e: MouseEvent) => {
      if (popupRef.current && !popupRef.current.contains(e.target as Node) &&
          addBtnRef.current && !addBtnRef.current.contains(e.target as Node)) {
        setShowPopup(false);
      }
    };
    window.addEventListener('mousedown', handler);
    return () => window.removeEventListener('mousedown', handler);
  }, [showPopup]);

  // ── 可用工具（未打开的）──
  const availTools = ALL_TOOLS.filter(t => !openTools.includes(t.id));

  // ── 收起面板 ──
  const handleCollapse = useCallback(() => setCollapsedRight(true), [setCollapsedRight]);

  // ── 当前工具的子标签 ──
  const currentSubTabs = activeToolId ? (subTabs[activeToolId] ?? []) : [];
  const hasSubTabs = currentSubTabs.length > 0;
  const isWorks = activeToolId === 'works';
  const projectTabItems = projectTabs.map(pid => {
    const p = useProjectStore.getState().getById(pid);
    return { id: pid, label: p?.name.replace('第', '') ?? pid };
  });

  return (
    <div className={styles.panel}>
      {/* ═══ #rightHdr — ToolTabs (拆分为独立组件) ═══ */}
      <ToolTabs
        openTools={openTools}
        activeToolId={activeToolId}
        onSetActive={setActiveTool}
        onCloseTool={closeTool}
        onAddTool={handleAddTool}
        onCollapse={handleCollapse}
        addBtnRef={addBtnRef}
      />

      {/* ═══ #rightSubHdr — SubTabs (拆分为独立组件) ═══ */}
      {isWorks ? (
        <SubTabs
          items={projectTabItems}
          activeId={activeProjectTabId}
          onSelect={setActiveProjectTab}
          onClose={closeProjectTab}
          emptyHint="从左侧栏选择章节"
        />
      ) : hasSubTabs ? (
        <SubTabs
          items={currentSubTabs as SubTabItem[]}
          activeId={activeSubTabId}
          onSelect={setActiveSubTab}
          onClose={(id) => { if (activeToolId) removeSubTab(activeToolId, id); }}
          emptyHint={activeToolId === 'catalog' ? '选择技法开始训练' : ''}
          showAddBtn={activeToolId === 'catalog'}
          addBtnTitle="回到目录"
        />
      ) : (
        <SubTabs
          items={[]}
          activeId={null}
          onSelect={() => {}}
          onClose={() => {}}
          emptyHint={activeToolId === 'catalog' ? '选择技法开始训练' : ''}
          showAddBtn={activeToolId === 'catalog'}
          addBtnTitle="回到目录"
        />
      )}

      {/* ═══ #rightBody — 内容体 ═══ */}
      <div className={styles.rightBody} id="rightBody">
        {activeToolId ? (
          (() => {
            const Workspace = WORKSPACE_MAP[activeToolId];
            return Workspace ? <Workspace /> : (
              <div className={styles.empty}>
                <div>{ALL_TOOLS.find(t => t.id === activeToolId)?.name ?? activeToolId}</div>
                <div className={styles.emptySub}>通过 IPC {activeToolId} 通道读取数据</div>
              </div>
            );
          })()
        ) : (
          <ToolGrid onOpenTool={openTool} />
        )}
      </div>

      {/* ═══ Add-tool popup ═══ */}
      {showPopup && (
        <div className={styles.popup} ref={popupRef}>
          {availTools.length === 0 ? (
            <div className={styles.popupEmpty}>全部已打开</div>
          ) : (
            availTools.map(t => (
              <button key={t.id} className={styles.popupBtn} onClick={() => handleSelectTool(t.id)}>
                <span className={styles.popupIcon}>{t.icon}</span>
                <span>{t.name}</span>
              </button>
            ))
          )}
        </div>
      )}
    </div>
  );
};
