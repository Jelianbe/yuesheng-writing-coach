// scripts/audit-prompt-assets.js
// 扫描指定根目录下的文本资产，输出 JSON 到 stdout
// 用法: node scripts/audit-prompt-assets.js <root1> [root2] ...
// 输出: { "<root>": [{ path, size, mtime, hash }, ...], ... }

'use strict';

const fs = require('fs').promises;
const { createHash } = require('crypto');
const path = require('path');

const TEXT_EXT = new Set(['.md', '.json', '.ts', '.js', '.txt', '.yaml', '.yml', '.mjs', '.cjs']);
const IGNORE_DIRS = new Set([
  'node_modules', 'dist', 'build', '.git', 'archive',
  'icons', 'distillation-versions', '__tests__',
]);

async function walk(root) {
  const out = [];
  let entries;
  try {
    entries = await fs.readdir(root, { withFileTypes: true });
  } catch (err) {
    console.error(`warn: cannot read ${root}: ${err.message}`);
    return out;
  }
  for (const e of entries) {
    if (IGNORE_DIRS.has(e.name)) continue;
    if (e.name.startsWith('.')) continue;
    const full = path.join(root, e.name);
    if (e.isDirectory()) {
      out.push(...(await walk(full)));
    } else if (TEXT_EXT.has(path.extname(e.name).toLowerCase())) {
      out.push(full);
    }
  }
  return out;
}

async function statFile(p) {
  const s = await fs.stat(p);
  const content = await fs.readFile(p, 'utf8');
  const hash = createHash('sha256').update(content).digest('hex').slice(0, 12);
  return {
    size: s.size,
    mtime: new Date(s.mtimeMs).toISOString().slice(0, 10),
    hash,
  };
}

async function main() {
  const roots = process.argv.slice(2);
  if (roots.length === 0) {
    console.error('Usage: node scripts/audit-prompt-assets.js <root1> [root2] ...');
    process.exit(1);
  }

  const result = {};
  let totalFiles = 0;
  for (const r of roots) {
    const abs = path.resolve(r);
    const files = await walk(abs);
    const records = [];
    for (const f of files) {
      const rel = path.relative(abs, f).replaceAll('\\', '/');
      const meta = await statFile(f);
      records.push({ path: rel, ...meta });
    }
    records.sort((a, b) => a.path.localeCompare(b.path));
    result[r] = records;
    totalFiles += records.length;
  }
  result._meta = { totalFiles, scannedAt: new Date().toISOString() };
  console.log(JSON.stringify(result, null, 2));
}

main().catch((err) => {
  console.error('fatal:', err);
  process.exit(1);
});
