import React from 'react';
import { Check, Minus, Plus } from 'lucide-react';
import { useEditorStore, type EditorTheme } from '../../stores/editor.store';
import styles from './ManuscriptPanel.module.css';

export const SettingsPopover: React.FC = () => {
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
      className={styles.popover}
      onClick={e => e.stopPropagation()}
      onMouseDown={e => e.stopPropagation()}
    >
      {/* 标题 */}
      <div className={styles.popoverHeader}>
        编辑器设置
      </div>

      {/* 主题选择 */}
      <div className={styles.popoverSection}>
        <div className={styles.popoverSectionLabel}>
          背景主题
        </div>
        <div className={styles.themeGrid}>
          {themes.map(t => (
            <button
              key={t.id}
              onClick={() => settings.setTheme(t.id)}
              className={styles.themeBtn}
              style={{
                border: theme === t.id ? '2px solid var(--accent)' : '1px solid var(--border)',
                background: t.bg,
              }}
            >
              {/* 预览文字 */}
              <span
                className={styles.themePreview}
                style={{
                  fontWeight: theme === t.id ? 600 : 400,
                  color: t.textColor,
                }}
              >
                Aa
              </span>
              {/* 标签 */}
              <span
                className={styles.themeLabel}
                style={{
                  fontWeight: theme === t.id ? 600 : 400,
                  color: t.textColor,
                  opacity: theme === t.id ? 1 : 0.55,
                }}
              >
                {t.label}
              </span>
              {/* 选中标记 */}
              {theme === t.id && (
                <div className={styles.themeCheck}>
                  <Check size={9} strokeWidth={3} />
                </div>
              )}
            </button>
          ))}
        </div>
      </div>

      {/* 分隔线 */}
      <div className={styles.separator} />

      {/* 自定义颜色（仅自定义模式显示） */}
      {theme === 'custom' && (
        <div className={styles.popoverSection}>
          <div className={styles.popoverSectionLabel2}>
            自定义颜色
          </div>
          <div className={styles.colorRow}>
            <label className={styles.colorLabel} style={{ background: customBgColor }}>
              <input
                type="color"
                value={customBgColor}
                onChange={e => settings.setCustomBgColor(e.target.value)}
                className={styles.colorInput}
                style={{ background: customBgColor }}
              />
              <span className={styles.colorLabelText}>背景</span>
            </label>
            <label className={styles.colorLabel} style={{ background: customTextColor }}>
              <input
                type="color"
                value={customTextColor}
                onChange={e => settings.setCustomTextColor(e.target.value)}
                className={styles.colorInput}
                style={{ background: customTextColor }}
              />
              <span className={styles.colorLabelText}>文字</span>
            </label>
          </div>
        </div>
      )}

      {/* 分隔线 */}
      <div className={styles.separator} />

      {/* 排版设置 */}
      <div className={styles.formatSection}>
        <div className={styles.popoverSectionLabel2}>
          排版格式
        </div>

        {/* 首行缩进 */}
        <div className={styles.formatRow}>
          <span className={styles.formatLabel}>首行缩进</span>
          <div className={styles.stepperGroup}>
            <button
              onClick={() => settings.updateFormat({ firstLineIndent: Math.max(0, format.firstLineIndent - 1) })}
              disabled={format.firstLineIndent <= 0}
              className={styles.stepperBtn}
              style={{
                background: format.firstLineIndent <= 0 ? 'transparent' : 'var(--bg-hover)',
                color: format.firstLineIndent <= 0 ? 'var(--text-tertiary)' : 'var(--text-primary)',
                cursor: format.firstLineIndent <= 0 ? 'not-allowed' : 'pointer',
                opacity: format.firstLineIndent <= 0 ? 0.35 : 1,
              }}
            >
              <Minus size={11} strokeWidth={2.5} />
            </button>
            <span className={styles.stepperValue}>
              {format.firstLineIndent}
            </span>
            <button
              onClick={() => settings.updateFormat({ firstLineIndent: Math.min(6, format.firstLineIndent + 1) })}
              disabled={format.firstLineIndent >= 6}
              className={styles.stepperBtn}
              style={{
                background: format.firstLineIndent >= 6 ? 'transparent' : 'var(--bg-hover)',
                color: format.firstLineIndent >= 6 ? 'var(--text-tertiary)' : 'var(--text-primary)',
                cursor: format.firstLineIndent >= 6 ? 'not-allowed' : 'pointer',
                opacity: format.firstLineIndent >= 6 ? 0.35 : 1,
              }}
            >
              <Plus size={11} strokeWidth={2.5} />
            </button>
            <span className={styles.stepperUnit}>格</span>
          </div>
        </div>

        {/* 段落间距 */}
        <div className={styles.formatRow}>
          <span className={styles.formatLabel}>段落间空行</span>
          <button
            onClick={() => settings.updateFormat({ paragraphSpacing: !format.paragraphSpacing })}
            className={styles.toggleBtn}
            style={{
              background: format.paragraphSpacing ? 'var(--accent)' : 'var(--border)',
            }}
          >
            <span className={`${styles.toggleKnob} ${format.paragraphSpacing ? styles.toggleKnobOn : styles.toggleKnobOff}`} />
          </button>
        </div>
      </div>

      {/* 底部信息栏 */}
      <div className={styles.popoverFooter}>
        字号 {fontSize}px · 行高 {format.lineHeight.toFixed(1)}x
      </div>
    </div>
  );
};
