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
  Check,
} from 'lucide-react';
import { useChapterStore } from '../../stores/chapter.store';
import { useEditorStore, type EditorTheme } from '../../stores/editor.store';
import {
  EASE_OUT_QUART,
  EDITOR_SAVE_DEBOUNCE_MS,
  EDITOR_FONT_SIZE_MIN,
  EDITOR_FONT_SIZE_MAX,
  Z_INDEX,
} from '../layout/layout.constants';

// ===== 常量（布局常量已迁移至 layout.constants.ts） =====

/**
 * 字体层级系统（4 档，每级差 ≥2px，解决扁平化问题）
 * - DISPLAY: 标题/主标题（14px）
 * - BODY:    正文/标签名（13px）
 * - CAPTION: 辅助说明/提示（11px）
 * - MICRO:   状态栏/微型标注（10px）
 */
const FONT = {
  display: '14px',   // 0.875rem — 页面标题、面板标题
  body: '13px',      // 0.8125rem — 正文、按钮文字、标签名
  caption: '11px',   // 0.6875rem — 辅助说明、次要提示
  micro: '10px',     // 0.625rem — 状态栏、微型信息、关闭按钮
} as const;

// ===== 主题色板定义 =====

/** 各主题的完整配色方案 */
const THEME_PALETTES: Record<EditorTheme, { bg: string; text: string; border: string; toolbarBg: string; statusBarBg: string; caret: string }> = {
  paper: {
    bg: '#FEFCF8',
    text: '#2C2416',
    border: '#EDE7DD',
    toolbarBg: '#FAF7F2',
    statusBarBg: '#F8F4EE',
    caret: '#C4883A',
  },
  sepia: {
    bg: '#F5ECD7',
    text: '#3E3224',
    border: '#E0D5C0',
    toolbarBg: '#F0E6D0',
    statusBarBg: '#EBDFC8',
    caret: '#B07830',
  },
  dark: {
    bg: '#1A1816',
    text: '#D4CCC2',
    border: '#2E2A26',
    toolbarBg: '#201E1B',
    statusBarBg: '#1C1A18',
    caret: '#D4A56A',
  },
  custom: {
    bg: '#FEFCF8',  // 占位，运行时由 store 填充
    text: '#2C2416',
    border: '#EDE7DD',
    toolbarBg: '#FAF7F2',
    statusBarBg: '#F8F4EE',
    caret: '#C4883A',
  },
};

// ===== 子组件：设置面板弹出层 =====

const SettingsPopover: React.FC = () => {
  const settings = useEditorStore();
  const { theme, customBgColor, customTextColor, format, fontSize } = settings;

  /** 主题选项 */
  const themes: { id: EditorTheme; label: string; bg: string; textColor: string }[] = [
    { id: 'paper', label: '纸张', bg: '#FEFCF8', textColor: '#2C2416' },
    { id: 'sepia', label: '护眼', bg: '#F5ECD7', textColor: '#3E3224' },
    { id: 'dark', label: '暗色', bg: '#1A1816', textColor: '#D4CCC2' },
    { id: 'custom', label: '自定义', bg: customBgColor, textColor: customTextColor === '#2C2416' ? '#2C2416' : customTextColor },
  ];

  return (
    <div
      data-settings-popover
      style={{
        position: 'absolute',
        top: '100%',
        right: 0,
        marginTop: 6,
        width: 276,
        backgroundColor: 'var(--bg-card)',
        borderRadius: 'var(--radius-md)',
        boxShadow: '0 4px 24px rgba(0,0,0,0.08), 0 1px 4px rgba(0,0,0,0.04)',
        zIndex: 'var(--z-dropdown)',
        overflow: 'hidden',
        animation: 'popIn 180ms cubic-bezier(0.25, 1, 0.5, 1) both',
      }}
      onClick={e => e.stopPropagation()}
      onMouseDown={e => e.stopPropagation()}
    >
      {/* 标题 */}
      <div style={{
        padding: '12px 16px 10px',
        fontSize: FONT.display,
        fontWeight: 600,
        color: 'var(--text-primary)',
        letterSpacing: '-0.01em',
      }}>
        编辑器设置
      </div>

      {/* 主题选择 */}
      <div style={{ padding: '4px 16px 12px' }}>
        <div style={{ fontSize: FONT.caption, fontWeight: 500, color: 'var(--text-secondary)', marginBottom: 8 }}>
          背景主题
        </div>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 6 }}>
          {themes.map(t => (
            <button
              key={t.id}
              onClick={() => settings.setTheme(t.id)}
              style={{
                padding: '10px 4px 8px',
                borderRadius: 'var(--radius-sm)',
                border: theme === t.id ? '2px solid var(--accent)' : '1px solid var(--border)',
                background: t.bg,
                cursor: 'pointer',
                display: 'flex',
                flexDirection: 'column',
                alignItems: 'center',
                gap: 4,
                transition: `all 150ms ${EASE_OUT_QUART}`,
                position: 'relative',
              }}
            >
              {/* 预览文字 */}
              <span style={{
                fontSize: FONT.micro,
                fontWeight: theme === t.id ? 600 : 400,
                color: t.textColor,
                lineHeight: 1.3,
              }}>
                Aa
              </span>
              {/* 标签 */}
              <span style={{
                fontSize: FONT.micro,
                fontWeight: theme === t.id ? 600 : 400,
                color: t.textColor,
                opacity: theme === t.id ? 1 : 0.55,
              }}>
                {t.label}
              </span>
              {/* 选中标记 */}
              {theme === t.id && (
                <div style={{
                  position: 'absolute', top: 4, right: 4,
                  width: 14, height: 14, borderRadius: '50%',
                  background: 'var(--accent)', color: '#fff',
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                }}>
                  <Check size={9} strokeWidth={3} />
                </div>
              )}
            </button>
          ))}
        </div>
      </div>

      {/* 分隔线 */}
      <div style={{ height: 1, background: 'var(--border-light)', margin: '0 16px' }} />

      {/* 自定义颜色（仅自定义模式显示） */}
      {theme === 'custom' && (
        <div style={{ padding: '12px 16px' }}>
          <div style={{ fontSize: FONT.caption, fontWeight: 500, color: 'var(--text-secondary)', marginBottom: 10 }}>
            自定义颜色
          </div>
          <div style={{ display: 'flex', gap: 20, alignItems: 'center' }}>
            <label style={{ display: 'flex', alignItems: 'center', gap: 8, cursor: 'pointer' }}>
              <input
                type="color"
                value={customBgColor}
                onChange={e => settings.setCustomBgColor(e.target.value)}
                style={{
                  width: 28, height: 28, border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)',
                  cursor: 'pointer', padding: 0, background: customBgColor,
                }}
              />
              <span style={{ fontSize: FONT.caption, color: 'var(--text-secondary)' }}>背景</span>
            </label>
            <label style={{ display: 'flex', alignItems: 'center', gap: 8, cursor: 'pointer' }}>
              <input
                type="color"
                value={customTextColor}
                onChange={e => settings.setCustomTextColor(e.target.value)}
                style={{
                  width: 28, height: 28, border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)',
                  cursor: 'pointer', padding: 0, background: customTextColor,
                }}
              />
              <span style={{ fontSize: FONT.caption, color: 'var(--text-secondary)' }}>文字</span>
            </label>
          </div>
        </div>
      )}

      {/* 分隔线 */}
      <div style={{ height: 1, background: 'var(--border-light)', margin: '0 16px' }} />

      {/* 排版设置 */}
      <div style={{ padding: '12px 16px' }}>
        <div style={{ fontSize: FONT.caption, fontWeight: 500, color: 'var(--text-secondary)', marginBottom: 10 }}>
          排版格式
        </div>

        {/* 首行缩进 */}
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 10 }}>
          <span style={{ fontSize: FONT.body, color: 'var(--text-primary)' }}>首行缩进</span>
          <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
            <button
              onClick={() => settings.updateFormat({ firstLineIndent: Math.max(0, format.firstLineIndent - 1) })}
              disabled={format.firstLineIndent <= 0}
              style={stepperBtnStyle(format.firstLineIndent <= 0)}
            >
              <Minus size={11} strokeWidth={2.5} />
            </button>
            <span style={{ fontSize: FONT.body, fontWeight: 600, color: 'var(--text-primary)', minWidth: 22, textAlign: 'center' }}>
              {format.firstLineIndent}
            </span>
            <button
              onClick={() => settings.updateFormat({ firstLineIndent: Math.min(6, format.firstLineIndent + 1) })}
              disabled={format.firstLineIndent >= 6}
              style={stepperBtnStyle(format.firstLineIndent >= 6)}
            >
              <Plus size={11} strokeWidth={2.5} />
            </button>
            <span style={{ fontSize: FONT.micro, color: 'var(--text-tertiary)' }}>格</span>
          </div>
        </div>

        {/* 段落间距 */}
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <span style={{ fontSize: FONT.body, color: 'var(--text-primary)' }}>段落间空行</span>
          <button
            onClick={() => settings.updateFormat({ paragraphSpacing: !format.paragraphSpacing })}
            style={{
              width: 42, height: 22, borderRadius: 11,
              border: 'none', background: format.paragraphSpacing ? 'var(--accent)' : 'var(--border)',
              color: '#fff', cursor: 'pointer', position: 'relative',
              transition: `all 150ms ${EASE_OUT_QUART}`,
            }}
          >
            <span style={{
              position: 'absolute', top: 2, left: format.paragraphSpacing ? 20 : 2,
              width: 18, height: 18, borderRadius: '50%', background: '#fff',
              transition: `left 150ms ${EASE_OUT_QUART}`, boxShadow: '0 1px 3px rgba(0,0,0,0.15)',
            }} />
          </button>
        </div>
      </div>

      {/* 底部信息栏 */}
      <div style={{
        padding: '8px 16px',
        borderTop: '1px solid var(--border-light)',
        fontSize: FONT.micro,
        color: 'var(--text-tertiary)',
        textAlign: 'center',
        background: 'var(--bg-hover)',
      }}>
        字号 {fontSize}px · 行高 {format.lineHeight.toFixed(1)}x
      </div>
    </div>
  );
};

/** 步进按钮样式工厂 */
function stepperBtnStyle(disabled: boolean): React.CSSProperties {
  return {
    width: 24, height: 24, borderRadius: 'var(--radius-sm)',
    border: '1px solid var(--border)',
    background: disabled ? 'transparent' : 'var(--bg-hover)',
    color: disabled ? 'var(--text-tertiary)' : 'var(--text-primary)',
    cursor: disabled ? 'not-allowed' : 'pointer',
    display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 0,
    opacity: disabled ? 0.35 : 1,
    transition: `all 120ms ${EASE_OUT_QUART}`,
  };
}

// ===== 自动排版工具函数 =====

/**
 * 对文本执行自动排版：
 * 0. 清理已有全角空格缩进（防止重复排版导致累积）
 * 1. 合并连续空行为段落分隔符
 * 2. 每个段落首行插入指定数量的全角空格缩进
 * 3. 段落间按配置决定是否加空行
 */
function applyAutoFormat(text: string, config: { indent: number; spacing: boolean }): string {
  if (!text.trim()) return text;

  // 先全局清除已有的全角空格缩进（修复累积 bug）
  const cleaned = text.replace(/^\u3000+/gm, '');

  const rawLines = cleaned.split('\n');
  const paragraphs: string[] = [];
  let currentParagraph: string[] = [];

  for (const line of rawLines) {
    if (line.trim() === '') {
      if (currentParagraph.length > 0) {
        paragraphs.push(currentParagraph.join('\n'));
        currentParagraph = [];
      }
    } else {
      currentParagraph.push(line);
    }
  }
  if (currentParagraph.length > 0) {
    paragraphs.push(currentParagraph.join('\n'));
  }

  const indentStr = '\u3000'.repeat(config.indent);

  return paragraphs.map((para) => {
    if (config.indent > 0) {
      const lines = para.split('\n');
      // 只对每段第一行加缩进（后续行如换行不断不加）
      lines[0] = indentStr + lines[0];
      return lines.join('\n');
    }
    return para;
  }).join(config.spacing ? '\n\n' : '\n');
}

// ===== 主组件 =====

const ManuscriptPanel: React.FC = () => {
  const {
    openFiles,
    openTabMeta,
    currentChapter,
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
    } catch {
      // 静默处理
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
      // 检查点击是否在设置按钮或弹出层外部
      const isBtn = settingsBtnRef.current?.contains(target);
      const isPopover = popoverRef.current?.contains(target);
      if (!isBtn && !isPopover) {
        closeSettings();
      }
    };
    // 使用 mousedown 而非 click，确保在弹出层内部点击之前就关闭
    document.addEventListener('mousedown', handleMouseDown);
    return () => document.removeEventListener('mousedown', handleMouseDown);
  }, [settingsOpen, closeSettings]);

  // ── 键盘快捷键（Ctrl+S 保存 / Ctrl+=/- 字号） ──
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      // Ctrl+S / Cmd+S：立即保存
      if ((e.ctrlKey || e.metaKey) && e.key === 's') {
        e.preventDefault();
        doSave(localContent);
        return;
      }
      // Ctrl+= / Ctrl+-：调整字号
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

  // 计算当前主题完整色板
  const themeId = useEditorStore(s => s.theme);
  const customBgColor = useEditorStore(s => s.customBgColor);
  const customTextColor = useEditorStore(s => s.customTextColor);
  const palette = themeId === 'custom'
    ? { ...THEME_PALETTES.custom, bg: customBgColor, text: customTextColor }
    : THEME_PALETTES[themeId];

  // ── 空状态 ──
  if (openFiles.length === 0) {
    return (
      <div style={{
        display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center',
        height: '100%', gap: 16, padding: 40, textAlign: 'center',
        color: 'var(--text-tertiary)', userSelect: 'none',
      }}>
        <div style={{
          width: 52, height: 52, borderRadius: 'var(--radius-md)',
          background: 'var(--bg-hover)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
        }}>
          <BookOpen size={24} strokeWidth={1.4} opacity={0.35} />
        </div>
        <div style={{ fontSize: FONT.display, fontWeight: 500, color: 'var(--text-secondary)' }}>
          暂无打开的章节
        </div>
        <div style={{ fontSize: FONT.body, lineHeight: 1.6, opacity: 0.65, maxWidth: 200 }}>
          在左侧栏点击章节，将在右侧打开编辑器
        </div>
      </div>
    );
  }

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%', position: 'relative', background: palette.bg }}>
      {/* ══════════ 标签栏 ══════════ */}
      <div style={{
        display: 'flex', gap: 0, padding: '0 10px',
        borderBottom: `1px solid ${palette.border}`,
        background: palette.toolbarBg,
        flexShrink: 0,
        overflowX: 'auto',
        scrollbarWidth: 'none',
        alignItems: 'center',
        minHeight: 36,
      }}>
        {/* 标签列表 */}
        {openFiles.map(chId => {
          const meta = openTabMeta[chId];
          const isActive = chId === currentChapter?.id;
          return (
            <div
              key={chId}
              onClick={() => select(chId)}
              style={{
                display: 'flex', alignItems: 'center', gap: 6,
                padding: '8px 12px', cursor: 'pointer',
                fontSize: FONT.caption, fontWeight: isActive ? 600 : 450,
                color: isActive ? palette.text : 'var(--text-tertiary)',
                whiteSpace: 'nowrap',
                borderBottom: isActive ? `2px solid var(--accent)` : '2px solid transparent',
                transition: `all 180ms ${EASE_OUT_QUART}`,
                position: 'relative', userSelect: 'none',
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
              <span style={{ maxWidth: 90, overflow: 'hidden', textOverflow: 'ellipsis' }}>
                {meta?.title || '未知'}
              </span>
              <button
                onClick={e => { e.stopPropagation(); closeTab(chId); }}
                style={{
                  display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
                  border: 'none', background: 'transparent', cursor: 'pointer', padding: 0,
                  width: 15, height: 15, borderRadius: '50%',
                  color: 'inherit', opacity: 0.45,
                  transition: `opacity 120ms ${EASE_OUT_QUART}`, flexShrink: 0,
                }}
                onMouseEnter={e => { e.currentTarget.style.opacity = '1'; e.currentTarget.style.color = 'var(--error)'; }}
                onMouseLeave={e => { e.currentTarget.style.opacity = '0.45'; e.currentTarget.style.color = 'inherit'; }}
              >
                <X size={10} strokeWidth={2.5} />
              </button>
            </div>
          );
        })}

        {/* 右侧：设置按钮 */}
        <div style={{ marginLeft: 'auto', paddingLeft: 8, position: 'relative' }}>
          <button
            ref={settingsBtnRef}
            onClick={(e) => { e.stopPropagation(); toggleSettings(); }}
            style={{
              width: 28, height: 28, borderRadius: 'var(--radius-sm)',
              border: '1px solid transparent',
              background: settingsOpen ? 'var(--bg-hover)' : 'transparent',
              color: settingsOpen ? 'var(--accent)' : 'var(--text-tertiary)',
              cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 0,
              transition: `all 150ms ${EASE_OUT_QUART}`,
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
        <div style={{
          display: 'flex', alignItems: 'center', gap: 2, padding: '7px 18px',
          borderBottom: `1px solid ${palette.border}`,
          background: palette.toolbarBg,
          flexShrink: 0,
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
          <span style={{
            fontSize: FONT.caption, fontWeight: 600, color: palette.text,
            minWidth: 34, textAlign: 'center', fontFamily: 'monospace',
            opacity: 0.8,
          }}>
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
          <div style={{ width: 1, height: 18, backgroundColor: `${palette.text}14`, margin: '0 8px' }} />

          {/* 自动排版 */}
          <ToolbarBtn onClick={handleAutoFormat} title="自动排版（首行缩进+段落间距）" palette={palette}>
            <AlignLeft size={14} strokeWidth={1.8} />
            <span style={{ marginLeft: 4, fontSize: FONT.caption, fontWeight: 500 }}>排版</span>
          </ToolbarBtn>

          {/* 右侧：保存状态 */}
          <div style={{ marginLeft: 'auto', display: 'flex', alignItems: 'center', gap: 6 }}>
            <span style={{ fontSize: FONT.micro, color: palette.text, opacity: 0.35 }}>
              {activeTabMeta?.manuscriptTitle || ''}
            </span>
            <div style={{
              display: 'inline-flex', width: 6, height: 6, borderRadius: '50%',
              background: saving ? 'var(--accent-light)' : lastSaved ? '#4A7C59' : 'transparent',
              transition: `all 300ms ${EASE_OUT_QUART}`,
            }} />
            <span style={{ fontSize: FONT.micro, color: palette.text, opacity: 0.4 }}>
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
          style={{
            flex: 1,
            padding: `${24 + formatConfig.firstLineIndent * fontSize * 0.3}px 32px`,
            border: 'none',
            outline: 'none',
            resize: 'none',
            background: palette.bg,
            color: palette.text,
            fontFamily,
            fontSize: `${fontSize}px`,
            lineHeight: formatConfig.lineHeight,
            width: '100%',
            boxSizing: 'border-box',
            caretColor: palette.caret,
            scrollbarWidth: 'thin',
            scrollbarColor: `${palette.text}22 transparent`,
          }}
        />
      ) : (
        <div style={{
          display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center',
          flex: 1, gap: 14, color: 'var(--text-tertiary)', padding: 32, userSelect: 'none',
        }}>
          <BookOpen size={28} strokeWidth={1.2} opacity={0.18} />
          <span style={{ fontSize: FONT.body, fontWeight: 500 }}>选择一个标签页开始编辑</span>
        </div>
      )}

      {/* ══════════ 状态栏 ══════════ */}
      {currentChapter && (
        <div style={{
          display: 'flex', alignItems: 'center', gap: 12, padding: '5px 20px',
          borderTop: `1px solid ${palette.border}`,
          background: palette.statusBarBg,
          fontSize: FONT.micro,
          color: palette.text,
          opacity: 0.58,
          flexShrink: 0,
        }}>
          <span>{wordCount} 字</span>
          <span style={{ opacity: 0.3 }}>{String.fromCharCode(183)}</span>
          <span>{localContent.replace(/\s/g, '').length} 字（去空格）</span>
          <span style={{ opacity: 0.3 }}>{String.fromCharCode(183)}</span>
          <span>~{Math.max(1, Math.ceil(wordCount / 500))} 分钟阅读</span>
          <span style={{ flex: 1 }} />
          <span>{currentChapter.status === 'draft' ? '草稿' : currentChapter.status === 'revising' ? '修改中' : '已完成'}</span>
        </div>
      )}

      {/* ══════════ 自动排版确认对话框 ══════════ */}
      {formatConfirmOpen && (
        <div style={{
          position: 'absolute', inset: 0,
          background: 'rgba(0,0,0,0.25)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          zIndex: Z_INDEX.formatConfirm, borderRadius: 'var(--radius-md)',
        }} onClick={() => setFormatConfirmOpen(false)}>
          <div
            onClick={e => e.stopPropagation()}
            style={{
              background: 'var(--bg-card)',
              borderRadius: 'var(--radius-md)',
              boxShadow: '0 8px 32px rgba(0,0,0,0.12)',
              padding: '24px 28px',
              maxWidth: 380,
              width: '90%',
            }}
          >
            <div style={{ fontSize: FONT.display, fontWeight: 600, color: 'var(--text-primary)', marginBottom: 8 }}>
              确认自动排版
            </div>
            <div style={{ fontSize: FONT.body, color: 'var(--text-secondary)', lineHeight: 1.6, marginBottom: 20 }}>
              将对全文执行以下操作：
              {formatConfig.firstLineIndent > 0 && (
                <div style={{ marginTop: 8, paddingLeft: 12 }}>
                  · 首行缩进 {formatConfig.firstLineIndent} 格全角空格
                </div>
              )}
              {formatConfig.paragraphSpacing && (
                <div style={{ paddingLeft: 12 }}>· 段落间插入空行</div>
              )}
              {!formatConfig.firstLineIndent && !formatConfig.paragraphSpacing && (
                <div style={{ marginTop: 8, paddingLeft: 12, color: 'var(--text-tertiary)' }}>
                  （当前无缩进和间距设置，操作不会产生可见变化）
                </div>
              )}
            </div>
            <div style={{ display: 'flex', gap: 10, justifyContent: 'flex-end' }}>
              <button
                onClick={() => setFormatConfirmOpen(false)}
                style={{
                  padding: '7px 18px', borderRadius: 'var(--radius-sm)',
                  border: '1px solid var(--border)', background: 'transparent',
                  color: 'var(--text-secondary)', cursor: 'pointer',
                  fontSize: FONT.body,
                }}
              >
                取消
              </button>
              <button
                onClick={confirmAutoFormat}
                style={{
                  padding: '7px 20px', borderRadius: 'var(--radius-sm)',
                  border: 'none', background: 'var(--accent)', color: '#fff',
                  cursor: 'pointer', fontSize: FONT.body, fontWeight: 500,
                }}
              >
                确认排版
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

// ===== 工具栏按钮子组件 =====

interface ToolbarBtnProps {
  children: React.ReactNode;
  onClick: () => void;
  title?: string;
  disabled?: boolean;
  palette: { text: string };
}

const ToolbarBtn: React.FC<ToolbarBtnProps> = ({ children, onClick, title, disabled, palette }) => (
  <button
    onClick={disabled ? undefined : onClick}
    title={title}
    style={{
      display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 3,
      padding: '5px 9px', borderRadius: 'var(--radius-sm)',
      border: '1px solid transparent',
      background: 'transparent',
      color: disabled ? `${palette.text}22` : palette.text,
      cursor: disabled ? 'not-allowed' : 'pointer',
      fontSize: FONT.caption,
      opacity: disabled ? 0.3 : 0.7,
      transition: `all 120ms ${EASE_OUT_QUART}`,
      whiteSpace: 'nowrap',
    }}
    onMouseEnter={e => {
      if (!disabled) {
        e.currentTarget.style.background = `${palette.text}0a`;
        e.currentTarget.style.opacity = '1';
      }
    }}
    onMouseLeave={e => {
      if (!disabled) {
        e.currentTarget.style.background = 'transparent';
        e.currentTarget.style.opacity = '0.7';
      }
    }}
  >
    {children}
  </button>
);

export default ManuscriptPanel;
