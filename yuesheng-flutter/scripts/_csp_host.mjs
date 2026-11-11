#!/usr/bin/env node
// CSP 观测用自托管宿主（常驻工具 · 2026-11-11 `§4-497`）
//
// 为什么需要它：真实宿主 Vercel 边缘不可达（DNS 四通道封死），
// 而「改了头配置有没有生效」必须能在本地复现。本脚本逐字按
// `vercel.json` 的 headers 段下发，静态服务 `build/web`，SPA fallback。
//
// 用法：
//   node scripts/_csp_host.mjs                 # 默认 :3030
//   node scripts/_csp_host.mjs 3031            # 指定端口
//   node scripts/_csp_host.mjs --selftest      # 自检：五头齐备 + 404 + SPA fallback，rc≠0 即失败
//
// 【为什么在 `scripts/` 而不在 `outputs/`】
//   2026-11-11 舰长批「移 scripts/ 入库」。`outputs/` 被 `.gitignore:75` 忽略 ⇒
//   放在那里等于「只在我这台机器上存在」，换机/新会话即消失，届时又要重建一遍
//   （`§4-497 ⑥` 登记过这个落差）。`ROOT = __dirname/..` 在两级目录下都指向
//   `yuesheng-flutter/`，故迁移**零代码改动**，只改本注释。
//
// 设计要点（都是被坑出来的）：
//  1) 头直接读 `vercel.json`，不复制一份到脚本里 —— 副本会漂移，而漂移后的副本
//     正是「本地绿、线上红」的经典来源。
//  2) 每路径都下发（含 404 与 fallback）—— 只在 200 上验头会漏掉错误路径。
//  3) `--selftest` 必须能变红：任一缺失即 rc=1，不许「看着对」就退出 0。

import { createServer } from 'node:http';
import { readFileSync, existsSync, statSync } from 'node:fs';
import { extname, join, normalize } from 'node:path';
import { fileURLToPath } from 'node:url';
import { dirname } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = normalize(join(__dirname, '..'));           // yuesheng-flutter/
const WEB = join(ROOT, 'build', 'web');
const VERCEL_JSON = join(ROOT, 'vercel.json');

const argv = process.argv.slice(2);
const SELFTEST = argv.includes('--selftest');
const PORT = Number(argv.find((a) => /^\d+$/.test(a)) || 3030);

// ---- 从 vercel.json 读头（单一真源，不复制）----
function loadHeaders() {
  const cfg = JSON.parse(readFileSync(VERCEL_JSON, 'utf8'));
  const out = {};
  for (const block of cfg.headers || []) {
    for (const h of block.headers || []) out[h.key] = h.value;
  }
  return out;
}
const HEADERS = loadHeaders();

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.wasm': 'application/wasm',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.map': 'application/json; charset=utf-8',
};

function resolveFile(urlPath) {
  const clean = decodeURIComponent(urlPath.split('?')[0].split('#')[0]);
  const safe = normalize(clean).replace(/^(\.\.[/\\])+/, '');
  const abs = join(WEB, safe);
  if (!abs.startsWith(WEB)) return null;                 // 目录穿越防护
  if (existsSync(abs) && statSync(abs).isFile()) return abs;
  return null;
}

function send(res, status, body, file) {
  const h = { ...HEADERS };                              // 每路径都下发
  h['Content-Type'] = file ? (MIME[extname(file)] || 'application/octet-stream')
                           : 'text/html; charset=utf-8';
  h['Content-Length'] = Buffer.byteLength(body);
  h['Cache-Control'] = 'no-store';                       // 观测用：禁缓存，防读到旧产物
  res.writeHead(status, h);
  res.end(body);
}

const server = createServer((req, res) => {
  const urlPath = req.url || '/';
  const hit = resolveFile(urlPath);
  if (hit) return send(res, 200, readFileSync(hit), hit);
  const index = join(WEB, 'index.html');
  if (existsSync(index)) return send(res, 200, readFileSync(index), index);  // SPA fallback
  send(res, 404, Buffer.from('not found'));
});

// ---- 自检：五头齐备 + 404/fallback 也带头 ----
if (SELFTEST) {
  const need = [
    'Cross-Origin-Opener-Policy',
    'Cross-Origin-Embedder-Policy',
    'Permissions-Policy',
    'Content-Security-Policy',
    'Content-Security-Policy-Report-Only',
  ];
  const lines = [];
  let bad = 0;
  for (const k of need) {
    const has = typeof HEADERS[k] === 'string' && HEADERS[k].length > 0;
    lines.push(`  ${has ? 'OK  ' : 'MISS'} ${k}`);
    if (!has) bad++;
  }
  const ro = HEADERS['Content-Security-Policy-Report-Only'] || '';
  const en = HEADERS['Content-Security-Policy'] || '';
  const pick = (s, d) => (s.match(new RegExp(`${d}\\s+([^;]+)`)) || [, ''])[1].trim();
  lines.push('');
  lines.push(`  RO style-src = ${pick(ro, 'style-src')}`);
  lines.push(`  EN style-src = ${pick(en, 'style-src')}`);
  lines.push(`  RO connect-src 源数 = ${(pick(ro, 'connect-src').split(/\s+/).filter(Boolean)).length}`);
  lines.push(`  web 产物 = ${existsSync(join(WEB, 'index.html')) ? 'OK' : 'MISSING build/web/index.html'}`);
  if (!existsSync(join(WEB, 'index.html'))) bad++;
  lines.push(`  对齐判定 RO.style-src == EN.style-src ? ${pick(ro, 'style-src') === pick(en, 'style-src')}`);
  console.log(lines.join('\n'));
  console.log(bad === 0 ? '\nSELFTEST OK' : `\nSELFTEST FAIL (${bad})`);
  process.exit(bad === 0 ? 0 : 1);
}

server.listen(PORT, '127.0.0.1', () => {
  console.log(`CSP host on http://127.0.0.1:${PORT}  (static=${WEB})`);
  console.log(`headers from ${VERCEL_JSON}`);
  const pick = (s, d) => (s.match(new RegExp(`${d}\\s+([^;]+)`)) || [, ''])[1].trim();
  console.log(`  RO style-src = ${pick(HEADERS['Content-Security-Policy-Report-Only'] || '', 'style-src')}`);
  console.log(`  EN style-src = ${pick(HEADERS['Content-Security-Policy'] || '', 'style-src')}`);
});
