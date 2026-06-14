/**
 * CSS 颜色合规性检测脚本（E-04 WCAG AA 对比度修复）
 *
 * 运行：npx tsx scripts/check-a11y-colors.ts
 *
 * 规则：
 *   - CSS 文件中禁止使用硬编码十六进制颜色作为 text/border/background 色值
 *   - 必须通过 CSS 变量引用（var(--xxx)）
 *   - 允许：CSS 变量定义（--xxx: #xxx）、box-shadow、注释
 *
 * 退出码：发现违规时返回 1
 */

import * as fs from 'fs';
import * as path from 'path';

interface Violation {
  filePath: string;
  line: number;
  content: string;
}

const SRC_DIR = path.resolve(__dirname, '../src/renderer');
const HEX_RE = /#[0-9a-fA-F]{3,8}/;
const STYLE_ATTRS = /\b(color|background|background-color|border|border-color|border-top|border-right|border-bottom|border-left|outline|outline-color)\s*:/i;

/** 区分外观属性与 shadow/gradient 等非对比度属性 */
function isStyleProperty(line: string): boolean {
  return STYLE_ATTRS.test(line);
}

/** 是否是 CSS 变量定义行 */
function isVarDefinition(line: string): boolean {
  return /^\s*--[\w-]+:\s*#[0-9a-fA-F]/.test(line.trim());
}

/** 是否是注释行 */
function isComment(line: string): boolean {
  return /^\s*(\/\/|\/\*|\*)/.test(line.trim());
}

/** 是否是 box-shadow / text-shadow / filter 等非前景区 */
function isShadowOrFilter(line: string): boolean {
  return /\b(box-shadow|text-shadow|filter|-webkit-filter)\s*:/i.test(line.trim());
}

/** 检查 hex 颜色是否在 var() fallback 中 */
function isInsideVarFallback(line: string, hexIndex: number): boolean {
  const before = line.slice(0, hexIndex);
  const lastVarOpen = before.lastIndexOf('var(');
  if (lastVarOpen === -1) return false;

  // 检查 var( 之后是否还有未闭合的括号
  let depth = 0;
  for (let i = lastVarOpen + 4; i < hexIndex; i++) {
    if (line[i] === '(') depth++;
    if (line[i] === ')') depth--;
  }
  return depth >= 0;
}

/** 行中是否有不在 var() fallback 内的 hex 颜色 */
function hasHardcodedHex(line: string): boolean {
  let match: RegExpExecArray | null;
  const regex = /#[0-9a-fA-F]{3,8}/g;
  while ((match = regex.exec(line)) !== null) {
    if (!isInsideVarFallback(line, match.index)) return true;
  }
  return false;
}

/** 扫描 CSS 文件 */
function scanCSSFiles(dir: string, results: string[]): void {
  if (!fs.existsSync(dir)) return;
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  for (const entry of entries) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory() && !entry.name.startsWith('.')) {
      scanCSSFiles(fullPath, results);
    } else if (entry.name.endsWith('.css')) {
      results.push(fullPath);
    }
  }
}

function main(): void {
  console.log('🎨 CSS 颜色合规性检测（E-04 WCAG AA）\n');
  console.log(`扫描目录: ${SRC_DIR}\n`);

  const files: string[] = [];
  scanCSSFiles(SRC_DIR, files);
  const violations: Violation[] = [];

  for (const file of files) {
    const content = fs.readFileSync(file, 'utf-8');
    const lines = content.split('\n');

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];

      if (isComment(line)) continue;
      if (isVarDefinition(line)) continue;
      if (isShadowOrFilter(line)) continue;
      if (!hasHardcodedHex(line)) continue;
      if (!isStyleProperty(line)) continue;

      violations.push({
        filePath: file,
        line: i + 1,
        content: line.trim(),
      });
    }
  }

  if (violations.length === 0) {
    console.log('✅ 未发现硬编码颜色，所有色值均通过 CSS 变量引用');
    process.exit(0);
    return;
  }

  console.log(`🔴 发现 ${violations.length} 处硬编码颜色：\n`);
  for (const v of violations) {
    const relPath = v.filePath.replace(SRC_DIR, 'src/renderer/');
    console.log(`  ${relPath}:${v.line}`);
    console.log(`    代码: ${v.content}`);
    console.log();
  }

  console.log('❌ 检测未通过：请将硬编码颜色替换为 CSS 变量');
  console.log('   参考 src/renderer/styles/variables.css 中的变量定义');
  process.exit(1);
}

main();
