export interface ThemePalette {
  bg: string;
  text: string;
  border: string;
  toolbarBg: string;
  statusBarBg: string;
  caret: string;
}

export const THEME_PALETTES: Record<string, ThemePalette> = {
  'warm-paper': {
    bg: '#f5e6c8',
    text: '#3e2c1a',
    border: '#c9a96e',
    toolbarBg: '#ede0c8',
    statusBarBg: '#e6d5b8',
    caret: '#8b5e3c',
  },
  'cool-slate': {
    bg: '#e8edf2',
    text: '#1e2a3a',
    border: '#8a9bb5',
    toolbarBg: '#dce3ec',
    statusBarBg: '#d0d9e4',
    caret: '#3a5a8c',
  },
  'dark-charcoal': {
    bg: '#2a2a2e',
    text: '#d4d4dc',
    border: '#4a4a50',
    toolbarBg: '#222226',
    statusBarBg: '#1a1a1e',
    caret: '#e0e0e0',
  },
  'cream-ivory': {
    bg: '#faf8f0',
    text: '#3a3028',
    border: '#d4c8a8',
    toolbarBg: '#f2efe4',
    statusBarBg: '#ece8da',
    caret: '#7a6a50',
  },
  'sepia-tone': {
    bg: '#f2e3c6',
    text: '#4a3728',
    border: '#b8956a',
    toolbarBg: '#e8d8b8',
    statusBarBg: '#e0cea8',
    caret: '#8b5e3c',
  },
  'forest-mist': {
    bg: '#e6efe0',
    text: '#1e2e1a',
    border: '#8aaa7a',
    toolbarBg: '#d8e4ce',
    statusBarBg: '#cadebc',
    caret: '#3a6a2a',
  },
  'ocean-breeze': {
    bg: '#dceaf0',
    text: '#1a2e3a',
    border: '#6a9ab5',
    toolbarBg: '#cedee8',
    statusBarBg: '#bcd2de',
    caret: '#2a6a8c',
  },
  'custom': {
    bg: '#ffffff',
    text: '#000000',
    border: '#cccccc',
    toolbarBg: '#f5f5f5',
    statusBarBg: '#e8e8e8',
    caret: '#000000',
  },
};

export const FONT = {
  display: '14px',
  body: '13px',
  caption: '11px',
  micro: '10px',
} as const;

export function applyAutoFormat(text: string, opts: { indent: number; spacing: boolean }): string {
  const paragraphs = text.split(/\n\s*\n/);

  const formatted = paragraphs.map((p) => {
    const trimmed = p.trim();
    if (!trimmed) return '';
    let result = trimmed;
    if (opts.indent > 0) {
      result = ' '.repeat(opts.indent) + result;
    }
    return result;
  });

  const separator = opts.spacing ? '\n\n\n' : '\n\n';
  return formatted.filter(Boolean).join(separator);
}
