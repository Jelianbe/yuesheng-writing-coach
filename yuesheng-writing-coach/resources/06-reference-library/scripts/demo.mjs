// 检索路由演示 / 数据自检（读取真实 JSON，复刻 library-loader 的合并逻辑）
// 用法：node scripts/demo.mjs
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = join(__dirname, '..');
const entries = JSON.parse(readFileSync(join(root, 'entries', 'library-entries.json'), 'utf8'));
const index = JSON.parse(readFileSync(join(root, 'library-index.json'), 'utf8'));
const byId = new Map(entries.map((e) => [e.id, e]));

// 与 library-loader 保持一致：从 entries 对账补入索引，避免索引过期遗漏新卡（幂等）
for (const e of entries) {
  const addU = (a, id) => { if (!a.includes(id)) a.push(id); };
  for (const s of e.relatedSyndromes || []) addU(index.syndromeMap[s] ||= [], e.id);
  for (const sc of e.scenarios || []) addU(index.scenarioMap[sc] ||= [], e.id);
  const toks = new Set([...(e.retrievalKeywords || []), ...(e.title || '').split(/\s+/), e.categoryLabel ?? '']);
  for (const r of toks) { const k = r.toLowerCase().trim(); if (!k) continue; addU(index.keywordIndex[k] ||= [], e.id); }
}

// ---- 数据自检 ----
const errors = [];
const ids = new Set();
for (const e of entries) {
  if (ids.has(e.id)) errors.push(`重复 ID: ${e.id}`);
  ids.add(e.id);
  for (const f of ['id', 'title', 'category', 'summary', 'corePoints', 'examples', 'teachingTips', 'difficulty', 'retrievalKeywords', 'scenarios']) {
    if (e[f] === undefined) errors.push(`${e.id} 缺少字段 ${f}`);
  }
  if (!Array.isArray(e.corePoints) || e.corePoints.length < 1) errors.push(`${e.id} corePoints 异常`);
  if (!Array.isArray(e.examples) || e.examples.length < 1) errors.push(`${e.id} examples 异常`);
  if (!Array.isArray(e.teachingTips) || e.teachingTips.length < 1) errors.push(`${e.id} teachingTips 异常`);
  for (const s of e.relatedSyndromes || []) if (!/^P\d{3}$/.test(s)) errors.push(`${e.id} 非法症候 ${s}`);
}

function tokenize(t) { return t.toLowerCase().split(/[\s,，。、；;:：！!？?（）()""''《》<>/]+/).map((x) => x.trim()).filter(Boolean); }

function search(query, limit = 8) {
  const scored = new Map();
  const ql = query.toLowerCase();
  for (const t of tokenize(query)) for (const id of index.keywordIndex[t] || []) scored.set(id, (scored.get(id) || 0) + 3);
  for (const e of entries) {
    let kwHit = false;
    for (const kw of e.retrievalKeywords) if (kw && ql.includes(kw.toLowerCase())) { scored.set(e.id, (scored.get(e.id) || 0) + 3); kwHit = true; }
    if (kwHit) continue;
    const hay = (e.title + ' ' + e.corePoints.join(' ')).toLowerCase();
    for (const t of tokenize(query)) if (t.length >= 2 && hay.includes(t)) scored.set(e.id, (scored.get(e.id) || 0) + 1);
  }
  return [...scored.entries()].sort((a, b) => b[1] - a[1]).slice(0, limit).map(([id]) => byId.get(id)).filter(Boolean);
}

function getForTeachingContext({ syndrome, scenario, query, limit = 6 }) {
  const ranked = new Map();
  if (syndrome) for (const e of (index.syndromeMap[syndrome] || []).map((id) => byId.get(id)).filter(Boolean)) ranked.set(e.id, (ranked.get(e.id) || 0) + 10);
  for (const e of (index.scenarioMap[scenario] || []).map((id) => byId.get(id)).filter(Boolean)) ranked.set(e.id, (ranked.get(e.id) || 0) + 5);
  if (query) for (const e of search(query, limit * 2)) ranked.set(e.id, (ranked.get(e.id) || 0) + 2);
  return [...ranked.entries()].sort((a, b) => b[1] - a[1]).slice(0, limit).map(([id]) => byId.get(id)).filter(Boolean);
}

console.log('=== 数据自检 ===');
console.log(errors.length ? 'FAIL:\n' + errors.join('\n') : `PASS：${entries.length} 条目全部字段完整、ID 唯一、症候格式合法`);

console.log('\n=== 路由演示 1：诊断 P009（角色动机缺失）→ post-diagnosis ===');
for (const e of getForTeachingContext({ syndrome: 'P009', scenario: 'post-diagnosis' })) {
  console.log(`  [${e.id}] ${e.title}（${e.difficulty}）`);
}

console.log('\n=== 路由演示 1b：诊断 P006（开头乏力/节奏失控）→ 应召回新增短篇结构卡 REF-C1-005 ===');
const p006 = getForTeachingContext({ syndrome: 'P006', scenario: 'post-diagnosis', limit: 10 }).map((e) => e.id);
console.log('  P006 命中：' + p006.join(', '));
console.log('  REF-C1-005 已接入：' + p006.includes('REF-C1-005'));

console.log('\n=== 路由演示 2：自由查询「怎么写对话潜台词」===');
for (const e of getForTeachingContext({ scenario: 'in-flow-coaching', query: '怎么写对话潜台词' })) {
  console.log(`  [${e.id}] ${e.title}`);
}

console.log('\n=== 路由演示 3：onboarding 场景（新用户引导）===');
for (const e of getForTeachingContext({ scenario: 'onboarding', limit: 5 })) {
  console.log(`  [${e.id}] ${e.title}`);
}

console.log('\n=== 路由演示 4：诊断 P005（视角漂移）+ 查询「头跳」===');
for (const e of getForTeachingContext({ syndrome: 'P005', scenario: 'post-diagnosis', query: '头跳 视角切换' })) {
  console.log(`  [${e.id}] ${e.title}`);
}
