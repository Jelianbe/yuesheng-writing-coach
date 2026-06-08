/**
 * 文件行数上限检测脚本（R-019 代码规范标准）
 *
 * 运行：npx tsx scripts/check-file-size.ts
 *
 * 规则：
 *   - 单文件 > 500 行：🔴 错误
 *   - 单文件 300-500 行：⚠️ 警告
 *
 * 退出码：发现错误时返回 1
 */

import * as fs from 'fs';
import * as path from 'path';

interface FileResult {
  filePath: string;
  lines: number;
  level: 'error' | 'warning';
}

const SRC_DIR = path.resolve(__dirname, '../src');
const WARN_THRESHOLD = 300;
const ERROR_THRESHOLD = 500;
const EXTS = ['.ts', '.tsx'];

/** 递归扫描目录下的所有 .ts/.tsx 文件 */
function scanFiles(dir: string, results: string[]): void {
  if (!fs.existsSync(dir)) return;
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  for (const entry of entries) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      scanFiles(fullPath, results);
    } else if (EXTS.includes(path.extname(entry.name))) {
      results.push(fullPath);
    }
  }
}

/** 统计文件行数 */
function countLines(filePath: string): number {
  const content = fs.readFileSync(filePath, 'utf-8');
  return content.split('\n').length;
}

function main(): void {
  console.log('📏 文件行数上限检测（R-019）\n');
  console.log(`扫描目录: ${SRC_DIR}\n`);

  const files: string[] = [];
  scanFiles(SRC_DIR, files);

  const violations: FileResult[] = [];

  for (const file of files) {
    const lines = countLines(file);
    if (lines > ERROR_THRESHOLD) {
      violations.push({ filePath: file, lines, level: 'error' });
    } else if (lines > WARN_THRESHOLD) {
      violations.push({ filePath: file, lines, level: 'warning' });
    }
  }

  // 按行数降序排序
  violations.sort((a, b) => b.lines - a.lines);

  if (violations.length === 0) {
    console.log('✅ 所有文件都在行数限制内');
    process.exit(0);
    return;
  }

  const errors = violations.filter(v => v.level === 'error');
  const warnings = violations.filter(v => v.level === 'warning');

  if (warnings.length > 0) {
    console.log(`⚠️  警告 (${warnings.length} 个文件，${WARN_THRESHOLD}-${ERROR_THRESHOLD} 行)：`);
    for (const v of warnings) {
      console.log(`  ${v.lines} 行  ${v.filePath.replace(SRC_DIR, 'src/')}`);
    }
    console.log();
  }

  if (errors.length > 0) {
    console.log(`🔴 错误 (${errors.length} 个文件，>${ERROR_THRESHOLD} 行)：`);
    for (const v of errors) {
      console.log(`  ${v.lines} 行  ${v.filePath.replace(SRC_DIR, 'src/')}`);
    }
    console.log();
  }

  console.log(`总计：${warnings.length} 个警告，${errors.length} 个错误`);

  if (errors.length > 0) {
    console.log('\n❌ 检测未通过：存在超过 500 行的文件，必须拆分');
    process.exit(1);
  } else {
    console.log('\n⚠️  检测通过（有警告）：建议计划拆分超长文件');
    process.exit(0);
  }
}

main();