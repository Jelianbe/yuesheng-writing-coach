/**
 * ChapterEditor — IDE 编辑器模式章节编辑器
 *
 * 显示当前选中的章节，提供内容编辑 + 自动保存。
 */

import React, { useEffect, useState, useCallback, useRef } from 'react';
import { Save, ArrowLeft, FileText, BookOpen, Loader } from 'lucide-react';
import { useChapterStore } from '../../stores/chapter.store';
import { useManuscriptStore } from '../../stores/manuscript.store';
import { useParadigmStore } from '../../stores/paradigm.store';
import { IPC_CHANNELS } from '../../shared/constants';
import styles from './chapter-editor.module.css';
import shared from '../profile/panel-shared.module.css';

const SAVE_DEBOUNCE_MS = 1500;

export const ChapterEditor: React.FC = () => {
  const { currentChapter, loadContent } = useChapterStore();
  const { currentManuscript, manuscripts } = useManuscriptStore();
  const setParadigm = useParadigmStore(s => s.setParadigm);
  const [content, setContent] = useState('');
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [lastSaved, setLastSaved] = useState<Date | null>(null);
  const saveTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const contentRef = useRef(content);
  contentRef.current = content;

  // 加载章节内容
  useEffect(() => {
    if (!currentChapter) {
      setLoading(false);
      return;
    }
    setLoading(true);
    loadContent(currentChapter.id)
      .then(c => { setContent(c || ''); setLoading(false); })
      .catch(() => { setContent(''); setLoading(false); });
  }, [currentChapter?.id]); // eslint-disable-line react-hooks/exhaustive-deps

  // 自动保存防抖
  const doSave = useCallback(async (text: string) => {
    if (!currentChapter) return;
    setSaving(true);
    try {
      const invoke = (await import('../../utils/ipc')).getInvoke();
      const result = await invoke(IPC_CHANNELS.CHAPTER_UPDATE_CONTENT, { id: currentChapter.id, content: text }) as { success: boolean };
      if (result.success) setLastSaved(new Date());
    } catch (e) {
      // 保存失败，记录警告
      console.warn('[ChapterEditor] Failed to save chapter:', e);
    } finally {
      setSaving(false);
    }
  }, [currentChapter]);

  useEffect(() => {
    if (!currentChapter) return;
    if (saveTimerRef.current) clearTimeout(saveTimerRef.current);
    saveTimerRef.current = setTimeout(() => {
      doSave(contentRef.current);
    }, SAVE_DEBOUNCE_MS);
    return () => { if (saveTimerRef.current) clearTimeout(saveTimerRef.current); };
  }, [content, currentChapter?.id]); // eslint-disable-line react-hooks/exhaustive-deps

  // 找当前作品名
  const workTitle = manuscripts.find(m => m.id === currentManuscript?.id)?.title || '未选择作品';
  const chapterTitle = currentChapter?.title || '未选择章节';

  if (!currentChapter) {
    return (
      <div className={`${shared.flexCol} ${shared.flexCenter} ${shared.flexGap16} ${styles.emptyState}`}>
        <BookOpen size={48} strokeWidth={1.2} opacity={0.2} />
        <span className={styles.emptyTitle}>未选择章节</span>
        <span className={styles.emptyHint}>点击左侧栏或右侧面板中的章节开始编辑</span>
        <button onClick={() => setParadigm('chat')} className={styles.backToChatBtn}>
          返回对话模式
        </button>
      </div>
    );
  }

  return (
    <div className={styles.editorContainer}>
      {/* 编辑器顶栏 */}
      <div className={`${shared.flexAlignCenter} ${shared.flexGap8} ${styles.toolbar}`}>
        <button onClick={() => setParadigm('chat')} className={styles.backBtn}>
          <ArrowLeft size={16} strokeWidth={1.6} />
        </button>
        <FileText size={15} strokeWidth={1.6} className={styles.fileIcon} />
        <div className={styles.toolbarTitle}>{chapterTitle}</div>
        <div className={styles.workName}>{workTitle}</div>
        <div className={`${shared.flexAlignCenter} ${shared.flexGap4} ${styles.saveStatus} ${saving ? styles.savingColor : styles.idleColor}`}>
          {saving ? <Loader size={12} strokeWidth={1.6} className="animate-spin" /> : <Save size={12} strokeWidth={1.6} />}
          {saving ? '保存中...' : lastSaved ? `已保存 ${lastSaved.toLocaleTimeString()}` : ''}
        </div>
      </div>

      {/* 编辑器主体 */}
      {loading ? (
        <div className={`${shared.flexCenter} ${styles.loadingArea}`}>
          <div className={styles.loadingText}>加载中...</div>
        </div>
      ) : (
        <textarea
          value={content}
          onChange={e => setContent(e.target.value)}
          placeholder="开始编写你的章节..."
          className={styles.textarea}
        />
      )}

      {/* 底部状态 */}
      <div className={`${shared.flexAlignCenter} ${shared.flexGap12} ${styles.statusBar}`}>
        <span>字数: {content.length}</span>
        <span>字符(去空格): {content.replace(/\s/g, '').length}</span>
        <span className={styles.spacer} />
        <span>{currentChapter.status === 'draft' ? '草稿' : currentChapter.status === 'revising' ? '修改中' : '已完成'}</span>
      </div>
    </div>
  );
};
