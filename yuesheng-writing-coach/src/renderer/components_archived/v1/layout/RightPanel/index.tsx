/**
 * RightPanel — 右侧栏容器（V6.2 风格）
 *
 * 组合 ToolTabs + SubTabs + 工作区内容。
 * 工作区内容根据 activeTool 切换显示：
 *   - 'progress' -> 教学进度
 *   - 'training' -> 训练会话内容
 *   - 'works' -> WorksWorkspace
 *   - 'tools' -> CatalogWorkspace
 *   - 其他 -> 占位显示工具名
 *   - null -> ToolGrid
 *
 * 折叠状态处理（collapsed 时只显示图标条）。
 *
 * 用法:
 * ```tsx
 * <RightPanel />
 * ```
 */
import { useCallback } from 'react';
import { useUiLayoutStore } from '@/stores/ui-layout.store';
import { useDrawerStore, type DrawerPanelId } from '@/stores/drawer.store';
import { ToolTabs } from '@/components/right/ToolTabs';
import { SubTabs } from '@/components/right/SubTabs';
import { ToolGrid } from '@/components/right/ToolGrid';
import { CatalogWorkspace } from '@/components/right/CatalogWorkspace';
import { WorksWorkspace } from '@/components/right/WorksWorkspace';
import { ProgressWorkspace } from '@/components/right/ProgressWorkspace';
import { DiagnosisWorkspace } from '@/components/right/DiagnosisWorkspace';
import { TrainingWorkspace } from '@/components/right/TrainingWorkspace';
import { GrowthWorkspace } from '@/components/right/GrowthWorkspace';
import { SettingsWorkspace } from '@/components/right/SettingsWorkspace';
import { ProfileWorkspace } from '@/components/right/ProfileWorkspace';
import { LearningLogWorkspace } from '@/components/right/LearningLogWorkspace';
import { TeachingNoteWorkspace } from '@/components/right/TeachingNoteWorkspace';
import styles from './index.module.css';

/** 图标条工具按钮（与 ToolTabs 相同的工具集） */
interface StripItem {
  id: DrawerPanelId;
  icon: string;
  label: string;
}

const STRIP_TOOLS: StripItem[] = [
  { id: 'progress', icon: '\uD83D\uDCCA', label: '进度' },
  { id: 'works', icon: '\uD83D\uDCDD', label: '作品' },
  { id: 'diagnosis', icon: '\uD83D\uDD0D', label: '诊断' },
  { id: 'training', icon: '\uD83C\uDFAF', label: '训练' },
  { id: 'growth', icon: '\uD83D\uDCC8', label: '成长' },
  { id: 'tools', icon: '\uD83E\uDDF0', label: '工具' },
  { id: '__settings__', icon: '\u2699\uFE0F', label: '设置' },
];

/**
 * 根据 activePanel 渲染对应的工作区内容
 */
function WorkspaceContent({ activePanel }: { activePanel: DrawerPanelId | null }): JSX.Element {
  if (activePanel === null) {
    return <ToolGrid />;
  }

  switch (activePanel) {
    case 'works':
      return <WorksWorkspace />;
    case 'tools':
      return <CatalogWorkspace />;
    case 'progress':
      return <ProgressWorkspace />;
    case 'diagnosis':
      return <DiagnosisWorkspace />;
    case 'training':
      return <TrainingWorkspace />;
    case 'growth':
      return <GrowthWorkspace />;
    case '__settings__':
      return <SettingsWorkspace />;
    case 'profile':
      return <ProfileWorkspace />;
    case 'search':
      return <div className={styles.placeholder}>搜索（待实现）</div>;
    case 'learning-log':
      return <LearningLogWorkspace />;
    case 'teaching-note':
      return <TeachingNoteWorkspace />;
    default:
      return <ToolGrid />;
  }
}

/**
 * 折叠态图标条
 */
function CollapsedStrip(): JSX.Element {
  const activePanel = useDrawerStore((s) => s.activePanel);
  const openPanel = useDrawerStore((s) => s.openPanel);

  const handleClick = useCallback(
    (panelId: DrawerPanelId) => {
      openPanel(panelId);
    },
    [openPanel],
  );

  return (
    <div className={styles.iconStrip} role="tablist" aria-label="右侧工具图标条">
      {STRIP_TOOLS.map(({ id, icon, label }) => {
        const isActive = activePanel === id;
        return (
          <button
            key={id}
            className={[
              styles.stripBtn,
              isActive ? styles.stripBtnActive : '',
            ]
              .filter(Boolean)
              .join(' ')}
            onClick={() => handleClick(id)}
            role="tab"
            aria-selected={isActive}
            type="button"
            title={label}
          >
            <span aria-hidden="true">{icon}</span>
          </button>
        );
      })}
    </div>
  );
}

export function RightPanel(): JSX.Element {
  const collapsed = useDrawerStore((s) => s.collapsed);
  const activePanel = useDrawerStore((s) => s.activePanel);
  const rightPanelWidth = useUiLayoutStore((s) => s.rightPanelWidth);

  if (collapsed) {
    return (
      <aside className={styles.collapsed} data-testid="right-panel-collapsed">
        <CollapsedStrip />
      </aside>
    );
  }

  return (
    <aside
      className={styles.panel}
      style={{ width: rightPanelWidth }}
      data-testid="right-panel"
    >
      {/* 顶部工具标签栏 */}
      <ToolTabs />

      {/* 子标签栏（有 session 时显示） */}
      <SubTabs />

      {/* 工作区内容 */}
      <div className={styles.content}>
        <WorkspaceContent activePanel={activePanel} />
      </div>
    </aside>
  );
}
