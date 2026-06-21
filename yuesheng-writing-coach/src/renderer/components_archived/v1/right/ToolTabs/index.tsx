/**
 * ToolTabs — 右侧栏顶部工具标签栏
 *
 * 展示 7 个工具按钮：进度/作品/诊断/训练/成长/工具/设置
 * 当前激活的 tab 高亮显示（底部边框 + 文字强调）
 * 点击切换工具（调用 useDrawerStore.openPanel）
 *
 * 用法:
 * ```tsx
 * <ToolTabs />
 * ```
 */
import { useCallback } from 'react';
import { useDrawerStore, type DrawerPanelId } from '@/stores/drawer.store';
import styles from './index.module.css';

/** 工具按钮配置 */
interface ToolItem {
  id: DrawerPanelId;
  icon: string;
  label: string;
}

const TOOLS: ToolItem[] = [
  { id: 'progress', icon: '\uD83D\uDCCA', label: '进度' },
  { id: 'works', icon: '\uD83D\uDCDD', label: '作品' },
  { id: 'diagnosis', icon: '\uD83D\uDD0D', label: '诊断' },
  { id: 'training', icon: '\uD83C\uDFAF', label: '训练' },
  { id: 'growth', icon: '\uD83D\uDCC8', label: '成长' },
  { id: 'tools', icon: '\uD83E\uDDF0', label: '工具' },
  { id: '__settings__', icon: '\u2699\uFE0F', label: '设置' },
];

export function ToolTabs(): JSX.Element {
  const activePanel = useDrawerStore((s) => s.activePanel);
  const openPanel = useDrawerStore((s) => s.openPanel);

  const handleClick = useCallback(
    (panelId: DrawerPanelId) => {
      openPanel(panelId);
    },
    [openPanel],
  );

  return (
    <nav className={styles.toolbar} role="tablist" aria-label="右侧工具标签">
      {TOOLS.map(({ id, icon, label }) => {
        const isActive = activePanel === id;
        return (
          <button
            key={id}
            className={[
              styles.toolBtn,
              isActive ? styles.toolBtnActive : '',
            ]
              .filter(Boolean)
              .join(' ')}
            onClick={() => handleClick(id)}
            role="tab"
            aria-selected={isActive}
            type="button"
          >
            <span className={styles.icon} aria-hidden="true">{icon}</span>
            <span className={styles.label}>{label}</span>
          </button>
        );
      })}
    </nav>
  );
}
