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

const EASE_OUT_QUART = 'cubic-bezier(0.25, 1, 0.5, 1)';
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
  }, [currentChapter?.id]);

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
  }, [content, currentChapter?.id]);

  // 找当前作品名
  const workTitle = manuscripts.find(m => m.id === currentManuscript?.id)?.title || '未选择作品';
  const chapterTitle = currentChapter?.title || '未选择章节';

  if (!currentChapter) {
    return (
      <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', flex: 1, gap: 16, color: 'var(--text-tertiary)' }}>
        <BookOpen size={48} strokeWidth={1.2} opacity={0.2} />
        <span style={{ fontSize: '0.95rem' }}>未选择章节</span>
        <span style={{ fontSize: '0.78rem' }}>点击左侧栏或右侧面板中的章节开始编辑</span>
        <button onClick={() => setParadigm('chat')}
          style={{ padding: '6px 16px', border: '1px solid var(--accent)', borderRadius: 'var(--radius-full)', background: 'transparent', color: 'var(--accent)', cursor: 'pointer', fontSize: '0.82rem', fontFamily: 'var(--font-body)' }}>
          返回对话模式
        </button>
      </div>
    );
  }

  return (
    <div style={{ display: 'flex', flexDirection: 'column', flex: 1, height: '100%' }}>
      {/* 编辑器顶栏 */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '8px 16px', borderBottom: '1px solid var(--border)', background: 'var(--bg-surface)' }}>
        <button onClick={() => setParadigm('chat')}
          style={{ padding: '4px', border: 'none', background: 'transparent', color: 'var(--text-secondary)', cursor: 'pointer', display: 'flex', borderRadius: 'var(--radius-sm)', transition: `all 150ms ${EASE_OUT_QUART}` }}
          onMouseEnter={e => { e.currentTarget.style.background = 'var(--bg-hover)'; }}
          onMouseLeave={e => { e.currentTarget.style.background = 'transparent'; }}>
          <ArrowLeft size={16} strokeWidth={1.6} />
        </button>
        <FileText size={15} strokeWidth={1.6} style={{ color: 'var(--accent)' }} />
        <div style={{ fontSize: '0.82rem', color: 'var(--text-primary)', fontWeight: 500, flex: 1 }}>
          {chapterTitle}
        </div>
        <div style={{ fontSize: '0.68rem', color: 'var(--text-tertiary)' }}>
          {workTitle}
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 4, fontSize: '0.68rem', color: saving ? 'var(--accent)' : 'var(--text-tertiary)' }}>
          {saving ? <Loader size={12} strokeWidth={1.6} className="animate-spin" /> : <Save size={12} strokeWidth={1.6} />}
          {saving ? '保存中...' : lastSaved ? `已保存 ${lastSaved.toLocaleTimeString()}` : ''}
        </div>
      </div>

      {/* 编辑器主体 */}
      {loading ? (
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', flex: 1, padding: 24 }}>
          <div style={{ color: 'var(--text-tertiary)', fontSize: '0.82rem' }}>加载中...</div>
        </div>
      ) : (
        <textarea
          value={content}
          onChange={e => setContent(e.target.value)}
          placeholder="开始编写你的章节..."
          style={{
            flex: 1,
            padding: '20px 24px',
            border: 'none',
            outline: 'none',
            resize: 'none',
            background: 'var(--bg-page)',
            color: 'var(--text-primary)',
            fontFamily: 'Georgia, "Noto Serif SC", serif',
            fontSize: '1rem',
            lineHeight: 1.8,
            width: '100%',
            boxSizing: 'border-box',
          }}
        />
      )}

      {/* 底部状态 */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '6px 16px', borderTop: '1px solid var(--border)', background: 'var(--bg-surface)', fontSize: '0.68rem', color: 'var(--text-tertiary)' }}>
        <span>字数: {content.length}</span>
        <span>字符(去空格): {content.replace(/\s/g, '').length}</span>
        <span style={{ flex: 1 }} />
        <span>{currentChapter.status === 'draft' ? '草稿' : currentChapter.status === 'revising' ? '修改中' : '已完成'}</span>
      </div>
    </div>
  );
};
