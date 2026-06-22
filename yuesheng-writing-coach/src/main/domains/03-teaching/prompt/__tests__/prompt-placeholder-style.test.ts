/**
 * prompt-placeholder-style.test.ts — ADR-003 占位符规范回归测试
 *
 * 职责：
 * - 扫描 resources/prompts/ 下所有 .md 文件
 * - 禁止单花占位符 {xxx}（易与 markdown / JSON 冲突）
 * - 允许双花占位符 {{xxx}}（推荐规范）
 * - 例外：teacher-prompt.md / assistant-prompt.md / clown-prompt.md
 *   （这 3 个文件已被 yuesheng-prompt-v5.md 取代，无任何代码引用）
 *
 * 为什么用回归测试而非 lint 规则：
 * - 静态分析不识别"业务上下文是否在用"
 * - 测试可以 fail-fast 提醒，避免新 prompt 误用单花
 *
 * 跳过方式（紧急用，正常不应）：
 * - 在文件顶部加 `// ADR-003-SKIP-PLACEHOLDER-STYLE` 注释
 */

import { describe, it, expect } from 'vitest';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

// ===== 配置 =====

const PROMPTS_DIR = join(process.cwd(), 'resources', 'prompts');

/**
 * 单花占位符正则：
 * - {name} 形式（name 为小写字母 + 下划线 + 数字）
 * - 必须前后都不是 { 或 }（避免与 {{xxx}} 冲突）
 *
 * 注意：不能用 look-around，改用更严格的"行内 grep"方式扫描
 */
const SINGLE_FLOWER = /\{[a-z_][a-z_0-9]*\}(?!\})/g;

/** 已知不在用的历史 prompt 文件（已迁移到 v3/v4） */
const EXEMPT_FILES = new Set([
  'teacher-prompt.md',
  'assistant-prompt.md',
  'clown-prompt.md',
]);

/** 已知可豁免的具体占位符（仅豁免字符串，不豁免文件） */
const EXEMPT_SUBSTRINGS: string[] = [
  // 实际使用但有充分理由保留单花的场景（截至 2026-06-22：无）
];

// ===== Helpers =====

interface ScanResult {
  file: string;
  matches: Array<{ line: number; text: string; placeholder: string }>;
}

function scanFile(filePath: string, fileName: string): ScanResult {
  const content = readFileSync(filePath, 'utf-8');
  const lines = content.split('\n');
  const matches: ScanResult['matches'] = [];

  // 状态机：跳过代码块 + HTML 注释块
  let inCodeBlock = false;
  let inHtmlComment = false;

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const trimmed = line.trim();

    // HTML 注释块：<!-- ... -->
    if (trimmed.startsWith('<!--')) {
      inHtmlComment = true;
    }
    if (inHtmlComment) {
      if (trimmed.includes('-->')) {
        inHtmlComment = false;
      }
      continue;
    }

    // Markdown 代码块：```xxx ... ```
    if (trimmed.startsWith('```')) {
      inCodeBlock = !inCodeBlock;
      continue;
    }
    if (inCodeBlock) continue;

    // 行内代码（整行被 `` ` `` 包围）：跳过
    if (trimmed.startsWith('`') && trimmed.endsWith('`') && trimmed.length > 2) {
      continue;
    }

    let match: RegExpExecArray | null;
    SINGLE_FLOWER.lastIndex = 0;
    while ((match = SINGLE_FLOWER.exec(line)) !== null) {
      const placeholder = match[0];
      if (EXEMPT_SUBSTRINGS.some((s) => placeholder.includes(s))) continue;
      matches.push({
        line: i + 1,
        text: trimmed,
        placeholder,
      });
    }
  }

  return { file: fileName, matches };
}

function listMarkdownPrompts(): string[] {
  return readdirSync(PROMPTS_DIR)
    .filter((f) => f.endsWith('.md'))
    .sort();
}

// ===== Tests =====

describe('ADR-003: prompt 文件占位符规范', () => {
  describe('当前使用的 prompt 文件', () => {
    it('所有在用 prompt 文件不含单花占位符 {xxx}', () => {
      const allFiles = listMarkdownPrompts();
      const activeFiles = allFiles.filter((f) => !EXEMPT_FILES.has(f));

      expect(activeFiles.length).toBeGreaterThan(0);

      const violations: ScanResult[] = [];
      for (const f of activeFiles) {
        const result = scanFile(join(PROMPTS_DIR, f), f);
        if (result.matches.length > 0) {
          violations.push(result);
        }
      }

      if (violations.length > 0) {
        const messages = violations.map((v) =>
          `  ${v.file}:\n${v.matches.map((m) => `    行 ${m.line}: ${m.placeholder} → ${m.text}`).join('\n')}`,
        );
        throw new Error(
          `\n\n发现 ${violations.length} 个文件含单花占位符：\n\n${messages.join('\n\n')}\n\n` +
            `ADR-003 规范：占位符必须使用双花 {{xxx}}。\n` +
            `如需豁免，请在文件顶部加 \`// ADR-003-SKIP-PLACEHOLDER-STYLE\` 或扩展 EXEMPT_SUBSTRINGS。\n`,
        );
      }
    });
  });

  describe('exempt 文件清单', () => {
    it('EXEMPT_FILES 与实际文件匹配（防止迁后未清理）', () => {
      const allFiles = new Set(listMarkdownPrompts());
      const exemptNotExist = [...EXEMPT_FILES].filter((f) => !allFiles.has(f));
      if (exemptNotExist.length > 0) {
        throw new Error(
          `EXEMPT_FILES 中列出的文件不存在：${exemptNotExist.join(', ')}\n` +
            `如果文件已被删除，请从 EXEMPT_FILES 移除。`,
        );
      }
    });
  });

  describe('每个在用 prompt 文件', () => {
    it.each(
      listMarkdownPrompts().filter((f) => !EXEMPT_FILES.has(f)),
    )('%s 不含单花占位符', (file) => {
      const result = scanFile(join(PROMPTS_DIR, file), file);
      if (result.matches.length > 0) {
        const detail = result.matches
          .map((m) => `  行 ${m.line}: ${m.placeholder} → ${m.text}`)
          .join('\n');
        throw new Error(`\n${file} 发现单花占位符：\n${detail}`);
      }
    });
  });
});
