import React, { useState, useCallback } from 'react';
import {
  ChevronRight,
  ChevronDown,
  FileText,
  Plus,
  CheckCircle2,
} from 'lucide-react';
import type { MixedContentItem } from './AppSidebar.types';
import { EASE_OUT_QUART } from './AppSidebar.types';
import styles from './AppSidebar.module.css';

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
export const MixedContentArea: React.FC<MixedContentProps> = React.memo(({ items, activeId, onSelect, onNewWork }) => {
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
    <div className={styles.mixedContent}>
      {items.map((item, idx) => {
        // ── 分组标题 ──
        if (item.type === 'header') {
          const HeaderIcon = item.icon;
          return (
            <div key={`h-${idx}`} className={styles.sectionHeader}>
              <HeaderIcon size={13} strokeWidth={1.5} className="opacity-60" />
              <span>{item.label}</span>
              {item.count != null && (
                <span className="opacity-60 ml-0.5">({item.count})</span>
              )}
              {/* 作品分组的新建入口 */}
              {item.showNewButton && onNewWork && (
                <button onClick={onNewWork} className={styles.newWorkButton}>
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
                className={[
                  styles.workTitleBtn,
                  isExpanded ? styles.workTitleExpanded : '',
                ].join(' ')}
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
                className={[
                  styles.chapterList,
                  isExpanded ? styles.chapterListExpanded : styles.chapterListCollapsed,
                ].join(' ')}
              >
                <div className="pl-4">
                  {item.chapters.map(ch => {
                    const isActive = ch.id === activeId;
                    return (
                      <button
                        key={ch.id}
                        onClick={() => onSelect(ch.id)}
                        className={[
                          styles.chapterBtn,
                          isActive ? styles.chapterBtnActive : '',
                        ].join(' ')}
                      >
                        <FileText
                          size={12}
                          strokeWidth={1.5}
                          className="flex-shrink-0 opacity-50"
                        />
                        <span className="flex-1 truncate">{ch.title}</span>
                        {ch.badge != null && (
                          <span className={styles.chapterBadge}>
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
              className={[
                styles.taskCard,
                isActive ? styles.taskCardActive : '',
                item.done ? styles.taskCardDone : styles.taskCardNotDone,
              ].join(' ')}
            >
              {/* 状态圆点 — CSS div，非 emoji */}
              <div
                className={[
                  styles.statusDot,
                  item.done ? styles.statusDotDone : styles.statusDotPending,
                ].join(' ')}
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
