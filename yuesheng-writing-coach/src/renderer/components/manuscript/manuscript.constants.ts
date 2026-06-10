import type { EditorTheme } from '../../stores/editor.store';

/**
 * 字体层级系统（4 档，每级差 ≥2px，解决扁平化问题）
 * - DISPLAY: 标题/主标题（14px）
 * - BODY:    正文/标签名（13px）
 * - CAPTION: 辅助说明/提示（11px）
 * - MICRO:   状态栏/微型标注（10px）
 */
export const FONT = {
  display: '14px',
  body: '13px',
  caption: '11px',
  micro: '10px',
} as const;

/** 各主题的完整配色方案 */
export const THEME_PALETTES: Record<EditorTheme, { bg: string; text: string; border: string; toolbarBg: string; statusBarBg: string; caret: string }> = {
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
    bg: '#FEFCF8',
    text: '#2C2416',
    border: '#EDE7DD',
    toolbarBg: '#FAF7F2',
    statusBarBg: '#F8F4EE',
    caret: '#C4883A',
  },
};

/**
 * 对文本执行自动排版：
 * 0. 清理已有全角空格缩进（防止重复排版导致累积）
 * 1. 合并连续空行为段落分隔符
 * 2. 每个段落首行插入指定数量的全角空格缩进
 * 3. 段落间按配置决定是否加空行
 */
export function applyAutoFormat(text: string, config: { indent: number; spacing: boolean }): string {
  if (!text.trim()) return text;

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
      lines[0] = indentStr + lines[0];
      return lines.join('\n');
    }
    return para;
  }).join(config.spacing ? '\n\n' : '\n');
}
