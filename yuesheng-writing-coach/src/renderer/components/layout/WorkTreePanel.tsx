import React, { useState, useRef, useEffect, useCallback } from 'react';
import {
  Plus,
  FileText,
  ChevronDown,
  ChevronRight,
} from 'lucide-react';
import type { Manuscript, Chapter } from '../../shared/types-manuscript';
import { useChapterStore } from '../../stores/chapter.store';
import { useManuscriptStore } from '../../stores/manuscript.store';
import { useDrawerStore } from '../../stores/drawer.store';
import styles from './WorkTreePanel.module.css';

const EASE = 'cubic-bezier(0.25, 1, 0.5, 1)';

/** 图标按钮基础样式 */
const iconBtnStyle: React.CSSProperties = {
  display: 'inline-flex',
  alignItems: 'center',
  justifyContent: 'center',
  border: 'none',
  background: 'transparent',
  cursor: 'pointer',
  borderRadius: 'var(--radius-sm)',
  transition: `all 120ms ${EASE}`,
  outline: 'none',
};

export interface WorkTreePanelProps {
  manuscripts: Manuscript[];
  chapters: Chapter[];
  currentManuscriptId: string | null;
  currentChapterId: string | null;
  onSelectManuscript: (id: string) => void;
  onSelectChapter: (id: string) => void;
  onOpenTab: (chapterId: string, manuscriptTitle: string) => void;
  fetchChapters: (manuscriptId: string) => void;
}

export const WorkTreePanel: React.FC<WorkTreePanelProps> = ({
  manuscripts,
  chapters,
  currentManuscriptId,
  currentChapterId,
  onSelectManuscript,
  onSelectChapter,
  onOpenTab,
  fetchChapters,
}) => {
  // 新建作品弹出卡
  const [showWorkPopup, setShowWorkPopup] = useState(false);
  const [workTitle, setWorkTitle] = useState('');
  const [workError, setWorkError] = useState<string | null>(null);
  const workInputRef = useRef<HTMLInputElement>(null);

  // 新建章节弹出卡
  const [showChapterPopup, setShowChapterPopup] = useState<string | null>(null);
  const [chapterTitle, setChapterTitle] = useState('');
  const [chapterError, setChapterError] = useState<string | null>(null);
  const chapterInputRef = useRef<HTMLInputElement>(null);

  // 展开状态
  const [expandedManuscripts, setExpandedManuscripts] = useState<Set<string>>(new Set());

  useEffect(() => { if (showWorkPopup) workInputRef.current?.focus(); }, [showWorkPopup]);
  useEffect(() => { if (showChapterPopup) chapterInputRef.current?.focus(); }, [showChapterPopup]);

  /* ── 渲染：作品树节点 ── */
  const renderManuscriptItem = useCallback((ms: Manuscript) => {
    const isActive = ms.id === currentManuscriptId;
    const isExpanded = expandedManuscripts.has(ms.id);

    const toggleExpand = (e: React.MouseEvent) => {
      e.stopPropagation();
      const next = new Set(expandedManuscripts);
      if (isExpanded) {
        next.delete(ms.id);
      } else {
        next.add(ms.id);
        fetchChapters(ms.id);
      }
      setExpandedManuscripts(next);
    };

    const handleSelectManuscript = () => {
      onSelectManuscript(ms.id);
      if (!isExpanded) {
        const next = new Set(expandedManuscripts);
        next.add(ms.id);
        setExpandedManuscripts(next);
        fetchChapters(ms.id);
      }
    };

    const chapterList = chapters.filter(c => c.manuscript_id === ms.id);

    return (
      <div key={ms.id}>
        <div
          className={`${styles.manuscriptItem} ${isActive ? styles.manuscriptActive : ''}`}
          onClick={handleSelectManuscript}
        >
          <button
            onClick={toggleExpand}
            style={iconBtnStyle}
            aria-label={isExpanded ? '折叠' : '展开'}
          >
            {isExpanded ? <ChevronDown size={12} strokeWidth={1.8} /> : <ChevronRight size={12} strokeWidth={1.8} />}
          </button>
          <FileText size={14} strokeWidth={1.6} className={styles.icon} />
          <span className={styles.manuscriptTitle}>{ms.title}</span>
        </div>

        {isExpanded && (
          <div className={styles.chapterArea}>
            {chapterList.length === 0 ? (
              <div className={styles.emptyChapters}>暂无章节</div>
            ) : (
              chapterList.map(ch => {
                const isChapterActive = ch.id === currentChapterId;
                return (
                  <div
                    key={ch.id}
                    className={`${styles.chapterItem} ${isChapterActive ? styles.chapterActive : ''}`}
                    onClick={async () => {
                      if (chapters.filter(c => c.manuscript_id === ms.id).length === 0) {
                        await fetchChapters(ms.id);
                      }
                      onSelectChapter(ch.id);
                      onOpenTab(ch.id, ms.title);
                      useDrawerStore.getState().openPanel('works');
                    }}
                  >
                    <span className={styles.chapterTitle}>{ch.title}</span>
                  </div>
                );
              })
            )}

            {/* 新建章节按钮与弹出卡 */}
            {showChapterPopup === ms.id ? (
              <div className={`animate-pop-in ${styles.chapterPopup}`}>
                <input
                  ref={chapterInputRef}
                  type="text"
                  value={chapterTitle}
                  onChange={e => { setChapterTitle(e.target.value); setChapterError(null); }}
                  onKeyDown={async e => {
                    if (e.key === 'Enter' && chapterTitle.trim()) {
                      const r = await useChapterStore.getState().createChapter(ms.id, chapterTitle.trim());
                      if (r) { setChapterTitle(''); setShowChapterPopup(null); }
                      else { setChapterError(useChapterStore.getState().error || '创建失败'); }
                    }
                    if (e.key === 'Escape') { setChapterTitle(''); setShowChapterPopup(null); }
                  }}
                  placeholder="章节名称..."
                  className={styles.popupInput}
                />
                {chapterError && <div className={styles.popupError}>{chapterError}</div>}
                <div className={styles.popupActions}>
                  <button
                    onClick={() => { setChapterTitle(''); setShowChapterPopup(null); }}
                    className={styles.popupCancel}
                  >
                    取消
                  </button>
                  <button
                    onClick={async () => {
                      if (chapterTitle.trim()) {
                        const r = await useChapterStore.getState().createChapter(ms.id, chapterTitle.trim());
                        if (r) { setChapterTitle(''); setShowChapterPopup(null); }
                        else { setChapterError(useChapterStore.getState().error || '创建失败'); }
                      }
                    }}
                    className={styles.popupConfirm}
                  >
                    创建
                  </button>
                </div>
              </div>
            ) : (
              <button
                onClick={e => {
                  e.stopPropagation();
                  setShowWorkPopup(false);
                  setShowChapterPopup(prev => prev === ms.id ? null : ms.id);
                }}
                className={styles.newChapterBtn}
              >
                <Plus size={11} strokeWidth={2} />
                <span>新建章节</span>
              </button>
            )}
          </div>
        )}
      </div>
    );
  }, [chapters, currentManuscriptId, currentChapterId, expandedManuscripts, fetchChapters, onSelectManuscript, onSelectChapter, onOpenTab]);

  return (
    <div className={styles.container}>
      {/* 新作品按钮 */}
      <button
        onClick={e => {
          e.stopPropagation();
          setShowChapterPopup(null);
          setShowWorkPopup(prev => !prev);
        }}
        className={styles.newWorkBtn}
      >
        <Plus size={14} strokeWidth={2} />
        <span>新作品</span>
      </button>

      {/* 新建作品弹出卡 */}
      {showWorkPopup && (
        <div className={`animate-pop-in ${styles.workPopup}`}>
          <div className={styles.workPopupTitle}>新建作品</div>
          <input
            ref={workInputRef}
            type="text"
            value={workTitle}
            onChange={e => { setWorkTitle(e.target.value); setWorkError(null); }}
            onKeyDown={async e => {
              if (e.key === 'Enter' && workTitle.trim()) {
                const r = await useManuscriptStore.getState().create(workTitle.trim());
                if (r) { setWorkTitle(''); setShowWorkPopup(false); }
                else { setWorkError(useManuscriptStore.getState().error || '创建失败'); }
              }
              if (e.key === 'Escape') { setWorkTitle(''); setShowWorkPopup(false); }
            }}
            placeholder="输入作品名称..."
            className={styles.workInput}
          />
          {workError && <div className={styles.workError}>{workError}</div>}
          <div className={styles.workActions}>
            <button
              onClick={() => { setWorkTitle(''); setShowWorkPopup(false); }}
              className={styles.popupCancel}
            >
              取消
            </button>
            <button
              onClick={async () => {
                if (workTitle.trim()) {
                  const r = await useManuscriptStore.getState().create(workTitle.trim());
                  if (r) { setWorkTitle(''); setShowWorkPopup(false); }
                  else { setWorkError(useManuscriptStore.getState().error || '创建失败'); }
                }
              }}
              className={styles.popupConfirm}
            >
              创建
            </button>
          </div>
        </div>
      )}

      {/* 作品列表 */}
      {manuscripts.map(renderManuscriptItem)}

      {/* 空状态 */}
      {manuscripts.length === 0 && (
        <div className={styles.emptyState}>暂无作品</div>
      )}
    </div>
  );
};
