import React from 'react';
import { useEditorStore } from '../../stores/editor.store';
import type { EditorTheme } from '../../stores/editor.store';
import { THEME_PALETTES, FONT } from './manuscript.constants';

const themes = Object.keys(THEME_PALETTES) as EditorTheme[];

export const SettingsPopover: React.FC = () => {
  const fontSize = useEditorStore((s) => s.fontSize);
  const theme = useEditorStore((s) => s.theme);
  const setFontSize = useEditorStore((s) => s.setFontSize);
  const setTheme = useEditorStore((s) => s.setTheme);

  return (
    <div
      style={{
        position: 'absolute',
        top: '100%',
        right: 0,
        zIndex: 100,
        background: 'var(--bg-primary, #fff)',
        border: '1px solid var(--border, #ddd)',
        borderRadius: 8,
        boxShadow: '0 4px 16px rgba(0,0,0,0.12)',
        padding: 16,
        minWidth: 200,
      }}
    >
      <div style={{ marginBottom: 12 }}>
        <div
          style={{
            fontSize: FONT.caption,
            fontWeight: 600,
            marginBottom: 8,
            color: 'var(--text-secondary, #666)',
            textTransform: 'uppercase',
            letterSpacing: '0.5px',
          }}
        >
          主题
        </div>
        <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
          {themes.map((t) => (
            <button
              key={t}
              onClick={() => setTheme(t)}
              style={{
                width: 28,
                height: 28,
                borderRadius: '50%',
                border: theme === t ? '2px solid var(--accent, #3b82f6)' : '1px solid var(--border, #ddd)',
                background: THEME_PALETTES[t].bg,
                cursor: 'pointer',
                outline: 'none',
              }}
              title={t}
            />
          ))}
        </div>
      </div>

      <div>
        <div
          style={{
            fontSize: FONT.caption,
            fontWeight: 600,
            marginBottom: 8,
            color: 'var(--text-secondary, #666)',
            textTransform: 'uppercase',
            letterSpacing: '0.5px',
          }}
        >
          字号
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <button
            onClick={() => setFontSize(Math.max(10, fontSize - 1))}
            style={{
              width: 28,
              height: 28,
              border: '1px solid var(--border, #ddd)',
              borderRadius: 4,
              background: 'var(--bg-hover, #f5f5f5)',
              cursor: 'pointer',
              fontSize: 16,
              lineHeight: '1',
            }}
          >
            −
          </button>
          <span
            style={{
              fontSize: FONT.body,
              minWidth: 32,
              textAlign: 'center',
              color: 'var(--text-primary, #333)',
            }}
          >
            {fontSize}
          </span>
          <button
            onClick={() => setFontSize(Math.min(32, fontSize + 1))}
            style={{
              width: 28,
              height: 28,
              border: '1px solid var(--border, #ddd)',
              borderRadius: 4,
              background: 'var(--bg-hover, #f5f5f5)',
              cursor: 'pointer',
              fontSize: 16,
              lineHeight: '1',
            }}
          >
            +
          </button>
        </div>
      </div>
    </div>
  );
};
