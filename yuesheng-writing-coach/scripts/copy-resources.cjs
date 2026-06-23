/**
 * copy-resources.cjs — 复制 resources/ 到 dist/resources/
 *
 * 解决：tsc 编译到 dist/ 后，相对路径 `../../../../resources/...`
 * 在 dist 下解析为 `dist/resources/...`，但 resources/ 在项目根。
 *
 * 同步复制整个 resources/ 目录（含子目录、JSON、prompt MD）到 dist/resources/。
 */

const fs = require('fs');
const path = require('path');

const src = path.resolve(__dirname, '..', 'resources');
const dst = path.resolve(__dirname, '..', 'dist', 'resources');

function copyDir(from, to) {
  if (!fs.existsSync(from)) {
    console.error('[copy-resources] source not found:', from);
    process.exit(1);
  }
  fs.mkdirSync(to, { recursive: true });
  const entries = fs.readdirSync(from, { withFileTypes: true });
  let count = 0;
  for (const e of entries) {
    const srcPath = path.join(from, e.name);
    const dstPath = path.join(to, e.name);
    if (e.isDirectory()) {
      copyDir(srcPath, dstPath);
    } else {
      fs.copyFileSync(srcPath, dstPath);
      count++;
    }
  }
  return count;
}

const n = copyDir(src, dst);
console.log(`[copy-resources] copied ${n} files → ${path.relative(process.cwd(), dst)}`);
