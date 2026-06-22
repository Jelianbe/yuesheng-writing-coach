#!/usr/bin/env node
/**
 * ID 命名规范一致性检查脚本
 *
 * 功能:
 * 1. 扫描 resources/ 下的所有 JSON 文件
 * 2. 检查已知 ID 字段的格式合规性
 * 3. 输出统计报告（不修改文件，不阻塞构建）
 *
 * 依据: dev-docs/standards/2026-06-23-id-naming-spec.md v1.0
 *
 * 使用:
 *   node scripts/check-id-naming.mjs
 *   npm run lint:id
 */

import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = fileURLToPath(new URL('.', import.meta.url));
const projectRoot = resolve(__dirname, '..');
const resourcesDir = join(projectRoot, 'resources');

/* eslint-disable no-console */

// ID 格式正则
const ID_PATTERNS = {
  ABL: /^ABL-\d{3}$/,
  AB: /^AB-\d{3}$/,
  P: /^P\d{3}$/,
  TRAIN: /^TRAIN-P\d{3}-\d{3}$/,
  PRAC: /^PRAC-[A-Z]+-\d{3}$/, // 基础能力训练（PRAC-EYE-001 观察力, PRAC-PEN-001 笔力）
  CH: /^CH-P\d{3}-\d{3}$/,
  DST: /^DST-\d{3}-\d{3}$/,
  TQ: /^TQ-\d{3}$/,
  SLUG: /^[A-Z][A-Z0-9_]*$/,
};

// 旧 ID 兼容（仅 warning，不阻塞）
const LEGACY_PATTERNS = {
  T0XX: /^T\d{3}$/, // T001-T020 占位任务
  P_SHORT: /^P-?\d{1,2}$/, // P1 / P-1 / P01（应规范化为 P001）
  ABL_SHORT: /^ABL-?\d{1,2}$/,
  AB_SHORT: /^AB-?\d{1,2}$/,
};

// ID 字段映射表：JSON 路径 → 期望的 ID 类型
// 注: training-library.json 同时含 TRAIN-PXXX 和 PRAC-XXX 两种格式，需分别校验
const ID_FIELD_RULES = [
  {
    file: '02-prescription/training-library.json',
    jsonPath: 'entries',
    idField: 'id',
    expectedType: ['TRAIN', 'PRAC'], // 二选一
    required: true,
  },
  {
    file: 'config/challenge-templates.json',
    jsonPath: 'templates',
    idField: 'id',
    expectedType: 'CH',
    required: true,
  },
  {
    file: 'knowledge-graph/ability-atlas.json',
    jsonPath: 'abilities',
    idField: 'id',
    expectedType: 'ABL',
    required: true,
  },
  {
    file: 'knowledge-graph/ability-atlas.json',
    jsonPath: 'syndromes',
    idField: 'id',
    expectedType: 'P',
    required: true,
  },
  {
    file: '02-prescription/ability-nodes/ability-node-prototypes.json',
    jsonPath: 'nodes',
    idField: 'id',
    expectedType: 'AB',
    required: true,
  },
  {
    file: '01-diagnosis/syndromes/syndrome-action-map.json',
    jsonPath: 'mappings', // 注意：是 mappings 不是 entries
    idField: 'syndromeId',
    expectedType: 'P',
    required: true,
  },
  {
    file: '01-diagnosis/syndromes/syndrome-classical-map.json',
    jsonPath: 'mappings', // 注意：是 mappings 不是 entries
    idField: 'syndromeId',
    expectedType: 'P',
    required: true,
  },
  {
    file: 'distillation-index.json',
    jsonPath: 'entries',
    idField: 'id',
    expectedType: 'DST',
    required: false, // 待创建
  },
  {
    file: 'config/technique-library.json',
    jsonPath: 'entries',
    idField: 'id',
    expectedType: 'TQ',
    required: false, // 待索引化
  },
];

/**
 * 递归获取 JSON 对象在路径下的数组
 */
function getArrayAtPath(obj, path) {
  return obj?.[path];
}

/**
 * 检查 ID 格式
 */
function checkID(id, type) {
  const pattern = ID_PATTERNS[type];
  if (!pattern) return { valid: false, error: `Unknown ID type: ${type}` };
  if (pattern.test(id)) return { valid: true };

  // 检查是否匹配旧格式
  for (const [legacyName, legacyPattern] of Object.entries(LEGACY_PATTERNS)) {
    if (legacyPattern.test(id)) {
      return {
        valid: false,
        isLegacy: true,
        legacyType: legacyName,
        suggestion: id.replace(/(\d{1,3})/g, (m) => m.padStart(3, '0'))
          .replace(/-(?=\d)/g, ''),
      };
    }
  }

  return { valid: false, error: `ID "${id}" does not match ${type} pattern` };
}

/**
 * 扫描 resources/ 下的所有 JSON 文件
 */
function* walkJSON(dir) {
  for (const name of readdirSync(dir)) {
    const fullPath = join(dir, name);
    const stat = statSync(fullPath);
    if (stat.isDirectory()) {
      yield* walkJSON(fullPath);
    } else if (name.endsWith('.json')) {
      yield fullPath;
    }
  }
}

/**
 * 主检查函数
 */
function check() {
  console.log('[ID Naming Check]');
  console.log('='.repeat(60));

  const stats = {
    ABL: { total: 0, valid: 0, legacy: 0 },
    AB: { total: 0, valid: 0, legacy: 0 },
    P: { total: 0, valid: 0, legacy: 0 },
    TRAIN: { total: 0, valid: 0, legacy: 0 },
    PRAC: { total: 0, valid: 0, legacy: 0 },
    CH: { total: 0, valid: 0, legacy: 0 },
    DST: { total: 0, valid: 0, legacy: 0 },
    TQ: { total: 0, valid: 0, legacy: 0 },
  };

  const legacyItems = [];
  const errors = [];

  for (const rule of ID_FIELD_RULES) {
    const fullPath = join(resourcesDir, rule.file);
    let data;
    try {
      const content = readFileSync(fullPath, 'utf-8');
      data = JSON.parse(content);
    } catch (err) {
      if (rule.required) {
        errors.push(`❌ ${rule.file}: ${err.message}`);
      } else {
        // 跳过待创建文件
        continue;
      }
      continue;
    }

    const arr = getArrayAtPath(data, rule.jsonPath);
    if (!Array.isArray(arr)) {
      if (rule.required) {
        errors.push(`❌ ${rule.file}: ${rule.jsonPath} 不是数组`);
      }
      continue;
    }

    for (const item of arr) {
      const id = item[rule.idField];
      if (!id) continue;

      // expectedType 可能是单个或数组（多选一）
      const expectedTypes = Array.isArray(rule.expectedType)
        ? rule.expectedType
        : [rule.expectedType];

      let matched = null;
      let result = null;
      for (const type of expectedTypes) {
        const r = checkID(id, type);
        if (r.valid) {
          matched = type;
          result = r;
          break;
        }
        // 记住最后一次失败用于错误提示
        result = r;
      }

      // 统计：记到第一个匹配的 type 上
      const statType = matched ?? expectedTypes[0];
      stats[statType].total += 1;

      if (matched) {
        stats[matched].valid += 1;
      } else if (result?.isLegacy) {
        stats[statType].legacy += 1;
        legacyItems.push({
          file: rule.file,
          id,
          legacyType: result.legacyType,
          suggestion: result.suggestion,
        });
      } else {
        errors.push(
          `❌ ${rule.file}: ${rule.idField}="${id}" 不符合 [${expectedTypes.join(', ')}] 格式 (${result?.error ?? 'unknown'})`,
        );
      }
    }
  }

  // 输出统计
  for (const [type, stat] of Object.entries(stats)) {
    if (stat.total === 0) {
      console.log(`⏳ ${type}: 无条目`);
      continue;
    }
    const status = stat.valid === stat.total ? '✅' : stat.legacy > 0 ? '⚠️' : '❌';
    const detail = stat.legacy > 0 ? ` (${stat.legacy} 旧格式)` : '';
    console.log(
      `${status} ${type}: ${stat.valid}/${stat.total} 合规${detail}`,
    );
  }

  // 输出遗留项
  if (legacyItems.length > 0) {
    console.log('');
    console.log('[Legacy IDs - 建议规范化]');
    for (const item of legacyItems) {
      console.log(`  - ${item.file}: ${item.id} → ${item.suggestion}`);
    }
  }

  // 输出错误
  if (errors.length > 0) {
    console.log('');
    console.log('[Errors]');
    for (const err of errors) {
      console.log(`  ${err}`);
    }
  }

  console.log('='.repeat(60));

  // 退出码：旧 ID 不算错（warning），新违规算错
  const hasError = errors.length > 0;
  return hasError ? 1 : 0;
}

const exitCode = check();
process.exit(exitCode);
