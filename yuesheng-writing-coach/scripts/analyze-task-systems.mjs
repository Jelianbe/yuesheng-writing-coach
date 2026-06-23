// scripts/analyze-task-systems.mjs
// T15-B 调研脚本：分析三套训练任务体系
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const ROOT = path.join(__dirname, '..');

// 1) 解析 training-library.json
const trainingLib = JSON.parse(
  fs.readFileSync(path.join(ROOT, 'resources/02-prescription/training-library.json'), 'utf-8')
);
console.log('=== training-library.json ===');
console.log('Total entries:', trainingLib.entries.length);
const trainIds = trainingLib.entries.map(e => e.id).sort();
const trainBySyndrome = {};
for (const e of trainingLib.entries) {
  if (!trainBySyndrome[e.syndromeId]) trainBySyndrome[e.syndromeId] = [];
  trainBySyndrome[e.syndromeId].push({ id: e.id, title: e.title, difficulty: e.difficulty, mode: e.mode });
}
for (const [s, list] of Object.entries(trainBySyndrome).sort()) {
  console.log(`  ${s}: ${list.length} 条`);
  for (const t of list) console.log(`    - ${t.id} | ${t.title} | ${t.difficulty}/${t.mode}`);
}

// 2) 解析 ability-atlas.json
const abilityAtlas = JSON.parse(
  fs.readFileSync(path.join(ROOT, 'resources/knowledge-graph/ability-atlas.json'), 'utf-8')
);
console.log('\n=== ability-atlas.json ===');
console.log('Training tasks (T0XX):', abilityAtlas.training_tasks.length);
const tBySyndrome = {};
for (const t of abilityAtlas.training_tasks) {
  if (!tBySyndrome[t.syndrome]) tBySyndrome[t.syndrome] = [];
  tBySyndrome[t.syndrome].push({ id: t.id, type: t.type, difficulty: t.difficulty });
}
for (const [s, list] of Object.entries(tBySyndrome).sort()) {
  console.log(`  ${s}: ${list.length} 条`);
  for (const t of list) console.log(`    - ${t.id} | ${t.type} | d=${t.difficulty}`);
}

// 3) 解析 challenge-templates.json
const challenge = JSON.parse(
  fs.readFileSync(path.join(ROOT, 'resources/04-validation/mastery/challenge-templates.json'), 'utf-8')
);
console.log('\n=== challenge-templates.json ===');
console.log('Templates total:', challenge.templates.length);
const chBySyndrome = {};
for (const c of challenge.templates) {
  if (!chBySyndrome[c.syndromeId]) chBySyndrome[c.syndromeId] = [];
  chBySyndrome[c.syndromeId].push({ id: c.id, mode: c.mode, tier: c.tier, wordCount: c.wordCount });
}
for (const [s, list] of Object.entries(chBySyndrome).sort()) {
  console.log(`  ${s}: ${list.length} 条`);
  for (const c of list) console.log(`    - ${c.id} | ${c.mode}/${c.tier} | wc=${c.wordCount}`);
}

// 4) 症候分布对比
console.log('\n=== 症候分布对比 ===');
const allSyndromes = new Set([
  ...Object.keys(trainBySyndrome),
  ...Object.keys(tBySyndrome),
  ...Object.keys(chBySyndrome),
]);
for (const s of [...allSyndromes].sort()) {
  const t = (trainBySyndrome[s] || []).map(x => x.id);
  const a = (tBySyndrome[s] || []).map(x => x.id);
  const c = (chBySyndrome[s] || []).map(x => x.id);
  console.log(`  ${s}: TRAIN=${t.length} [${t.join(',')}] | T0XX=${a.length} [${a.join(',')}] | CHALLENGE=${c.length} [${c.join(',')}]`);
}

// 5) 总数
console.log('\n=== Summary ===');
console.log(`TRAIN-PXXX: ${trainIds.length} 条`);
console.log(`T0XX: ${abilityAtlas.training_tasks.length} 条`);
console.log(`CH-PXXX: ${challenge.templates.length} 条`);
console.log(`症候覆盖: ${[...allSyndromes].sort().join(', ')}`);
