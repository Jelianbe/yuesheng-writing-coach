// scripts/generate-inventory-md.js
// 从 inventory.json 生成 markdown 摘要
// 用法: node scripts/generate-inventory-md.js <inventory.json> > <output.md>

'use strict';

const fs = require('fs');
const path = require('path');

const invPath = process.argv[2] || 'dev-docs/audits/2026-06-23-prompt-asset-inventory.json';
const data = JSON.parse(fs.readFileSync(invPath, 'utf8'));
const { _meta } = data;
delete data._meta;

const lines = [];
const out = (s) => lines.push(s);

// 标题与元数据
out('# 资产普查报告 — 2026-06-23');
out('');
out('> **Sprint**: 11 (设计 005 Sprint 0)');
out('> **范围**: resources/prompts + resources/01-05 + 4 个 IDE skills');
out(`> **总文件数**: ${_meta.totalFiles}`);
out(`> **扫描时间**: ${_meta.scannedAt}`);
out('> **完整数据**: `inventory.json`（同目录）');
out('');

// 按目录统计
out('## 摘要');
out('');
out('| 目录 | 文件数 | 备注 |');
out('|------|------:|------|');

const dirLabels = {
  'resources/prompts': '老根目录（含 5 个 SKILL + v3 prompt + 多个 agent prompt）',
  'resources/01-diagnosis': '诊断（signals 9 + syndromes 5 + 2 文件）',
  'resources/02-prescription': '处方（principles + learning-paths + techniques + 4 文件）',
  'resources/03-teaching': '教学（config 17 + feedback 2 + actions 3 + prompts 9）',
  'resources/04-validation': '验证（evaluation 2 + mastery 2）',
  'resources/05-retro': '复盘（cases 2）',
  '.trae/skills': 'TRAE IDE skill（项目专有 3 个）',
  '.agents/skills': '通用 agent skills（70+，系统级，与项目无关）',
  '.claude/skills': 'Claude IDE skill（空）',
  '.qoder/skills': 'Qoder IDE skill（空）',
};
for (const [dir, records] of Object.entries(data)) {
  out(`| \`${dir}/\` | ${records.length} | ${dirLabels[dir] || ''} |`);
}
out('');

// 命名异常
out('## 命名异常');
out('');
out('| 文件 | 问题 | 建议 |');
out('|------|------|------|');
out('| `resources/prompts/teaching-agent-prompt-v1.md` | v1 与 v2 同存 | 归档 v1 |');
out('| `resources/prompts/teaching-agent-prompt-v2草案.md` | 含"草案"后缀 | 评估是否合并到 v2 后归档 |');
out('| `resources/03-teaching/prompts/yuesheng-prompt-v3.md` | 与老位置同名 | Sprint 12 合并为 v5 |');
out('| `resources/03-teaching/prompts/teaching-agent-prompt-v2.md` | 与老位置同名 | 视为唯一真源 |');
out('| `resources/03-teaching/config/behavior-derivation-prompt-v1.md` | 与老位置同名 | 去重 |');
out('| `resources/03-teaching/prompts/skills/SKILL-*.md` | 5 个 v4 拆分产物 | Sprint 12 合并回 v5 |');
out('| `resources/prompts/skills/SKILL-*.md` | 5 个 v4 拆分产物副本 | Sprint 12 合并回 v5 |');
out('');

// v3/v4 关键文件
out('## v3 / v4 / 拆分关键文件');
out('');
out('| 路径 | size | mtime | hash |');
out('|------|-----:|------|------|');
const keyPaths = [
  'resources/prompts/yuesheng-prompt-v3.md',
  'resources/03-teaching/prompts/yuesheng-prompt-v3.md',
  'resources/prompts/teaching-agent-prompt-v1.md',
  'resources/prompts/teaching-agent-prompt-v2.md',
  'resources/03-teaching/prompts/teaching-agent-prompt-v2.md',
  'resources/prompts/behavior-derivation-prompt-v1.md',
  'resources/03-teaching/config/behavior-derivation-prompt-v1.md',
  'resources/03-teaching/prompts/diagnosis-agent-prompt-v2.md',
  'resources/04-validation/evaluation/training-evaluator-prompt-v1.md',
];
for (const [dir, records] of Object.entries(data)) {
  for (const r of records) {
    const full = `${dir}/${r.path}`;
    if (keyPaths.includes(full)) {
      out(`| \`${full}\` | ${r.size} | ${r.mtime} | \`${r.hash}\` |`);
    }
  }
}
out('');

// 跨域引用（命名相同的文件）
out('## 跨域同名文件（hash 对比）');
out('');
out('| 路径 A | 路径 B | hash A | hash B | 一致？|');
out('|--------|--------|--------|--------|:----:|');
const allFiles = [];
for (const [dir, records] of Object.entries(data)) {
  for (const r of records) {
    allFiles.push({ path: `${dir}/${r.path}`, hash: r.hash, size: r.size });
  }
}
const byName = {};
for (const f of allFiles) {
  const name = f.path.split('/').pop();
  byName[name] = byName[name] || [];
  byName[name].push(f);
}
for (const [name, group] of Object.entries(byName)) {
  if (group.length >= 2) {
    const a = group[0];
    const b = group[1];
    out(`| \`${a.path}\` | \`${b.path}\` | \`${a.hash}\` | \`${b.hash}\` | ${a.hash === b.hash ? '✓' : '✗'} |`);
  }
}
out('');

console.log(lines.join('\n'));
