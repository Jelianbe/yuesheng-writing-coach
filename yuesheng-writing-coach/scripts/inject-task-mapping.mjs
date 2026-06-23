// scripts/inject-task-mapping.mjs
// T15-B.2 + T15-B.3: 给 training-library.json 和 ability-atlas.json 注入映射字段
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const ROOT = path.join(__dirname, '..');

const mapping = JSON.parse(
  fs.readFileSync(path.join(ROOT, 'resources/config/task-id-mapping.json'), 'utf-8')
);

// === 1) training-library.json 注入 relatedChallengeIds ===
const trainingLibPath = path.join(ROOT, 'resources/02-prescription/training-library.json');
const trainingLib = JSON.parse(fs.readFileSync(trainingLibPath, 'utf-8'));

let trainInjected = 0;
for (const entry of trainingLib.entries) {
  if (entry.id.startsWith('TRAIN-P')) {
    const chMap = mapping.TRAIN_to_CH[entry.id];
    if (chMap) {
      entry.relatedChallengeIds = chMap.relatedChallenges;
      trainInjected++;
    }
  } else if (entry.id.startsWith('PRAC-')) {
    const pracMap = mapping.PRAC_to_syndrome[entry.id];
    if (pracMap) {
      entry.relatedSyndromeId = pracMap.primarySyndrome;
    }
    // PRAC 通用任务不挂 CH 映射
  }
}

// 写入 change_log 标记本次注入
if (!trainingLib.change_log) trainingLib.change_log = [];
trainingLib.change_log.unshift({
  date: '2026-06-23',
  version: '1.2.0',
  changes: `T15-B.2: 注入 relatedChallengeIds 字段（${trainInjected} 条 TRAIN-PXXX）和 relatedSyndromeId 字段（8 条 PRAC-XXX）。新增 task-id-mapping.json 引用。`
});

fs.writeFileSync(trainingLibPath, JSON.stringify(trainingLib, null, 2) + '\n', 'utf-8');
console.log(`[training-library.json] 注入 ${trainInjected} 条 relatedChallengeIds`);

// === 2) ability-atlas.json 注入 mappingToTrainingLibrary ===
const abilityAtlasPath = path.join(ROOT, 'resources/knowledge-graph/ability-atlas.json');
const abilityAtlas = JSON.parse(fs.readFileSync(abilityAtlasPath, 'utf-8'));

let t0xxInjected = 0;
for (const task of abilityAtlas.training_tasks) {
  const tMap = mapping.T0XX_to_TRAIN[task.id];
  if (tMap) {
    task.mappingToTrainingLibrary = tMap.mapsTo === 'TBD' ? null : tMap.mapsTo;
    task.mappingRationale = tMap.rationale;
    t0xxInjected++;
  }
}

// 在 abilities 节点上加 relatedTrainingTasks 字段（指向 TRAIN-PXXX 增强可追溯性）
for (const ability of abilityAtlas.abilities) {
  const t0xxList = ability.primary_tasks || [];
  const trainList = t0xxList
    .map(tid => mapping.T0XX_to_TRAIN[tid]?.mapsTo)
    .filter(Boolean)
    .filter(x => x !== 'TBD');
  if (trainList.length > 0) {
    ability.relatedTrainingTasks = trainList;
  }
}

if (!abilityAtlas.change_log) abilityAtlas.change_log = [];
abilityAtlas.change_log.unshift({
  date: '2026-06-23',
  version: '1.1.0',
  changes: `T15-B.3: 注入 mappingToTrainingLibrary + mappingRationale 字段（${t0xxInjected} 条 T0XX）。在 abilities 中新增 relatedTrainingTasks 字段指向 TRAIN-PXXX。`
});

fs.writeFileSync(abilityAtlasPath, JSON.stringify(abilityAtlas, null, 2) + '\n', 'utf-8');
console.log(`[ability-atlas.json] 注入 ${t0xxInjected} 条 mappingToTrainingLibrary`);

console.log('\nDone.');
