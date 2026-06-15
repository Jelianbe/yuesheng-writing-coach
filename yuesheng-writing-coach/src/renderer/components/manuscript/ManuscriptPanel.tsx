/**
 * ManuscriptPanel — 传统文字处理风格多标签编辑器（V3）
 *
 * 布局：
 *   ┌─ 标签栏 ──────────────────────────────── [⚙] ─┐
 *   ├─ 工具栏 ─ [A-] 15px [A+] │ [排版] ───── 保存态 ┤
 *   ├─ 编辑区（textarea，主题色背景）──────────────────┤
 *   └─ 状态栏 ─ 1234字 · 去空格 · 阅读时间 · 草稿 ───┘
 *
 * V3 改进：
 * - 设置面板完全可交互（主题切换 / 自定义颜色 / 排版格式）
 * - 更宽敞的编辑区（配合 RightDrawer works=520px 宽度）
 * - 温暖纸张质感配色体系
 * - 点击外部自动关闭设置面板
 */

import React, { useEffect, useState, useCallback, useRef } from 'react';
import {
  BookOpen,
  X,
  Settings,
  Plus,
  Minus,
  AlignLeft,
} from 'lucide-react';
import { useChapterStore } from '../../stores/chapter.store';
import { useEditorStore } from '../../stores/editor.store';
import {
  EDITOR_SAVE_DEBOUNCE_MS,
  EDITOR_FONT_SIZE_MIN,
  EDITOR_FONT_SIZE_MAX,
} from '../layout/layout.constants';
import { FONT, applyAutoFormat } from './manuscript.constants';
import { SettingsPopover } from './SettingsPopover';
import { FormatConfirmDialog } from './FormatConfirmDialog';
import { ToolbarBtn } from './ToolbarBtn';
import { EmptyEditorState } from './EmptyEditorState';
import { useEditorPalette } from './useEditorPalette';
import styles from './ManuscriptPanel.module.css';

// ===== 主组件 =====

export const ManuscriptPanel: React.FC = () => {
  const {
    openFiles,
    openTabMeta,
    currentChapter,
    pendingRewrite,
    select,
    closeTab,
    loadContent,
    updateContent,
    contentCache,
  } = useChapterStore();

  // 编辑器设置
  const fontSize = useEditorStore(s => s.fontSize);
  const fontFamily = useEditorStore(s => s.fontFamily);
  const formatConfig = useEditorStore(s => s.format);
  const adjustFontSize = useEditorStore(s => s.adjustFontSize);
  const settingsOpen = useEditorStore(s => s.settingsOpen);
  const toggleSettings = useEditorStore(s => s.toggleSettings);
  const closeSettings = useEditorStore(s => s.closeSettings);

  // 本地状态
  const [localContent, setLocalContent] = useState('');
  const [saving, setSaving] = useState(false);
  const [lastSaved, setLastSaved] = useState<Date | null>(null);
  const [wordCount, setWordCount] = useState(0);
  const saveTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const contentRef = useRef(localContent);
  contentRef.current = localContent;
  const editorRef = useRef<HTMLTextAreaElement>(null);
  const settingsBtnRef = useRef<HTMLButtonElement>(null);
  const popoverRef = useRef<HTMLDivElement>(null);
  const [formatConfirmOpen, setFormatConfirmOpen] = useState(false);

  // 主题色板
  const palette = useEditorPalette();

  // 当 currentChapter 变化时加载内容
  useEffect(() => {
    if (!currentChapter) {
      setLocalContent('');
      setWordCount(0);
      return;
    }
    const cached = contentCache[currentChapter.id];
    if (cached !== undefined) {
      setLocalContent(cached);
      setWordCount(cached.length);
    } else {
      loadContent(currentChapter.id).then(c => {
        setLocalContent(c || '');
        setWordCount((c || '').length);
      });
    }
  }, [currentChapter?.id]);

  // 自动保存防抖
  const doSave = useCallback(async (text: string) => {
    if (!currentChapter) return;
    setSaving(true);
    try {
      const result = await updateContent(currentChapter.id, text);
      if (result) setLastSaved(new Date());
    } catch (e) {
      // 静默处理，避免阻塞UI
      console.warn('[ManuscriptPanel] Failed to update content:', e);
    } finally {
      setSaving(false);
    }
  }, [currentChapter, updateContent]);

  useEffect(() => {
    if (!currentChapter) return;
    if (saveTimerRef.current) clearTimeout(saveTimerRef.current);
    saveTimerRef.current = setTimeout(() => {
      doSave(contentRef.current);
    }, EDITOR_SAVE_DEBOUNCE_MS);
    return () => { if (saveTimerRef.current) clearTimeout(saveTimerRef.current); };
  }, [localContent, currentChapter?.id]);

  // 内容变更
  const handleContentChange = (e: React.ChangeEvent<HTMLTextAreaElement>) => {
    const text = e.target.value;
    setLocalContent(text);
    setWordCount(text.length);
  };

  // 自动排版 — 先弹出确认对话框
  const handleAutoFormat = useCallback(() => {
    setFormatConfirmOpen(true);
  }, []);

  // 确认执行排版
  const confirmAutoFormat = useCallback(() => {
    const formatted = applyAutoFormat(localContent, {
      indent: formatConfig.firstLineIndent,
      spacing: formatConfig.paragraphSpacing,
    });
    setLocalContent(formatted);
    setWordCount(formatted.length);
    setFormatConfirmOpen(false);
    if (editorRef.current) editorRef.current.focus();
  }, [localContent, formatConfig]);

  // 点击外部关闭设置面板 — 使用 ref 直接检测
  useEffect(() => {
    if (!settingsOpen) return;
    const handleMouseDown = (e: MouseEvent) => {
      const target = e.target as HTMLElement;
      const isBtn = settingsBtnRef.current?.contains(target);
      const isPopover = popoverRef.current?.contains(target);
      if (!isBtn && !isPopover) {
        closeSettings();
      }
    };
    document.addEventListener('mousedown', handleMouseDown);
    return () => document.removeEventListener('mousedown', handleMouseDown);
  }, [settingsOpen, closeSettings]);

  // ── 键盘快捷键（Ctrl+S 保存 / Ctrl+=/- 字号） ──
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if ((e.ctrlKey || e.metaKey) && e.key === 's') {
        e.preventDefault();
        doSave(localContent);
        return;
      }
      if ((e.ctrlKey || e.metaKey) && (e.key === '=' || e.key === '-')) {
        e.preventDefault();
        adjustFontSize(e.key === '=' ? 1 : -1);
      }
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [localContent, doSave, adjustFontSize]);

  const activeTabMeta = currentChapter
    ? openTabMeta[currentChapter.id]
    : null;

  // ── 空状态 ──
  if (openFiles.length === 0) {
    return <EmptyEditorState />;
  }

  return (
    <div className={styles.panel} style={{ background: palette.bg }}>
      {/* ══════════ 训练改写待应用横幅 ══════════ */}
      {currentChapter && pendingRewrite && (
        <div className={styles.rewriteBanner} style={{ borderBottom: `1px solid ${palette.border}` }}>
          <span>训练改写结果待应用</span>
          <button onClick={() => { void useChapterStore.getState().applyRewrite(currentChapter.id, pendingRewrite); }}>
            应用
          </button>
          <button onClick={() => useChapterStore.getState().clearRewrite()}>
            忽略
          </button>
        </div>
      )}

      {/* ══════════ 标签栏 ══════════ */}
      <div className={styles.tabBar} style={{
        borderBottom: `1px solid ${palette.border}`,
        background: palette.toolbarBg,
      }}>
        {/* 标签列表 */}
        {openFiles.map(chId => {
          const meta = openTabMeta[chId];
          const isActive = chId === currentChapter?.id;
          return (
            <div
              key={chId}
              onClick={() => select(chId)}
              className={`${styles.tab} ${isActive ? styles.tabActive : styles.tabInactive}`}
              style={{
                color: isActive ? palette.text : undefined,
                borderBottom: isActive ? '2px solid var(--accent)' : '2px solid transparent',
              }}
              onMouseEnter={e => {
                if (!isActive) {
                  e.currentTarget.style.color = 'var(--text-secondary)';
                  e.currentTarget.style.background = 'rgba(0,0,0,0.03)';
                }
              }}
              onMouseLeave={e => {
                if (!isActive) {
                  e.currentTarget.style.color = 'var(--text-tertiary)';
                  e.currentTarget.style.background = 'transparent';
                }
              }}
            >
              <span className={styles.tabTitle}>
                {meta?.title || '未知'}
              </span>
              <button
                onClick={e => { e.stopPropagation(); closeTab(chId); }}
                className={styles.closeBtnTab}
                style={{ color: 'inherit', opacity: 0.45 }}
                onMouseEnter={e => { e.currentTarget.style.opacity = '1'; e.currentTarget.style.color = 'var(--error)'; }}
                onMouseLeave={e => { e.currentTarget.style.opacity = '0.45'; e.currentTarget.style.color = 'inherit'; }}
              >
                <X size={10} strokeWidth={2.5} />
              </button>
            </div>
          );
        })}

        {/* 右侧：设置按钮 */}
        <div className={styles.tabRight}>
          <button
            ref={settingsBtnRef}
            onClick={(e) => { e.stopPropagation(); toggleSettings(); }}
            className={styles.settingsBtn}
            style={{
              background: settingsOpen ? 'var(--bg-hover)' : 'transparent',
              color: settingsOpen ? 'var(--accent)' : 'var(--text-tertiary)',
            }}
            onMouseEnter={e => { if (!settingsOpen) e.currentTarget.style.color = 'var(--text-secondary)'; }}
            onMouseLeave={e => { if (!settingsOpen) e.currentTarget.style.color = 'var(--text-tertiary)'; }}
            title="编辑器设置"
          >
            <Settings size={15} strokeWidth={1.8} />
          </button>

          {/* 设置弹出层 */}
          {settingsOpen && (
            <div ref={popoverRef}>
              <SettingsPopover />
            </div>
          )}
        </div>
      </div>

      {/* ══════════ 工具栏 ══════════ */}
      {currentChapter && (
        <div className={styles.toolbar} style={{
          borderBottom: `1px solid ${palette.border}`,
          background: palette.toolbarBg,
        }}>
          {/* 字体缩小 */}
          <ToolbarBtn
            onClick={() => adjustFontSize(-1)}
            title="缩小字体"
            disabled={fontSize <= EDITOR_FONT_SIZE_MIN}
            palette={palette}
          >
            <Minus size={14} strokeWidth={1.8} />
          </ToolbarBtn>

          {/* 当前字号显示 */}
          <span className={styles.fontSizeLabel} style={{ color: palette.text }}>
            {fontSize}px
          </span>

          {/* 字体放大 */}
          <ToolbarBtn
            onClick={() => adjustFontSize(1)}
            title="放大字体"
            disabled={fontSize >= EDITOR_FONT_SIZE_MAX}
            palette={palette}
          >
            <Plus size={14} strokeWidth={1.8} />
          </ToolbarBtn>

          {/* 分隔符 */}
          <div className={styles.toolbarSep} style={{ backgroundColor: `${palette.text}14` }} />

          {/* 自动排版 */}
          <ToolbarBtn onClick={handleAutoFormat} title="自动排版（首行缩进+段落间距）" palette={palette}>
            <AlignLeft size={14} strokeWidth={1.8} />
            <span style={{ marginLeft: 4, fontSize: FONT.caption, fontWeight: 500 }}>排版</span>
          </ToolbarBtn>

          {/* 右侧：保存状态 */}
          <div className={styles.toolbarRight}>
            <span className={styles.toolbarManuscriptTitle} style={{ color: palette.text }}>
              {activeTabMeta?.manuscriptTitle || ''}
            </span>
            <div className={`${styles.saveDot}${saving ? ` ${styles.saveDotSaving}` : lastSaved ? ` ${styles.saveDotSaved}` : ''}`} />
            <span className={styles.saveLabel} style={{ color: palette.text }}>
              {saving ? '保存中...' : lastSaved ? '已保存' : ''}
            </span>
          </div>
        </div>
      )}

      {/* ══════════ 编辑区 ══════════ */}
      {currentChapter ? (
        <textarea
          ref={editorRef}
          value={localContent}
          onChange={handleContentChange}
          placeholder="开始编写你的章节..."
          spellCheck={false}
          className={styles.textarea}
          style={{
            padding: `${24 + formatConfig.firstLineIndent * fontSize * 0.3}px 32px`,
            background: palette.bg,
            color: palette.text,
            fontFamily,
            fontSize: `${fontSize}px`,
            lineHeight: formatConfig.lineHeight,
            caretColor: palette.caret,
            scrollbarColor: `${palette.text}22 transparent`,
          }}
        />
      ) : (
        <div className={styles.editorEmpty}>
          <BookOpen size={28} strokeWidth={1.2} opacity={0.18} />
          <span className={styles.editorEmptyLabel}>选择一个标签页开始编辑</span>
        </div>
      )}

      {/* ══════════ 状态栏 ══════════ */}
      {currentChapter && (
        <div className={styles.statusBar} style={{
          borderTop: `1px solid ${palette.border}`,
          background: palette.statusBarBg,
          color: palette.text,
        }}>
          <span>{wordCount} 字</span>
          <span className={styles.statusSep}>{String.fromCharCode(183)}</span>
          <span>{localContent.replace(/\s/g, '').length} 字（去空格）</span>
          <span className={styles.statusSep}>{String.fromCharCode(183)}</span>
          <span>~{Math.max(1, Math.ceil(wordCount / 500))} 分钟阅读</span>
          <span className={styles.statusSpacer} />
          <span>{currentChapter.status === 'draft' ? '草稿' : currentChapter.status === 'revising' ? '修改中' : '已完成'}</span>
        </div>
      )}

      {/* ══════════ 自动排版确认对话框 ══════════ */}
      <FormatConfirmDialog
        open={formatConfirmOpen}
        onConfirm={confirmAutoFormat}
        onCancel={() => setFormatConfirmOpen(false)}
      />
    </div>
  );
};
