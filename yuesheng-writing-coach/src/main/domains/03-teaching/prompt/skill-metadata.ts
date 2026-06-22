/**
 * Skill 元数据接口
 * 负责：YAML frontmatter 解析 + 校验 + 暴露给 SkillDispatcher
 *
 * 设计依据：Sprint 13 设计文档 §五
 * Sprint 13 版本：最小化（id / estimatedTokens / loadWhen.phases/attitudes）
 * 完整版本（depends / tokenPriority / version / conditions）推迟到 Sprint 14+ 方向 C
 */

import * as fs from 'fs';
import * as path from 'path';

/** 教学阶段（P0~P4） */
export type TeachingPhase =
  | 'P0_INIT'
  | 'P1_WORLD'
  | 'P2_PRACTICE_LOOP'
  | 'P3_TRAINING'
  | 'P4_REVIEW';

/** 态度档位（三档） */
export type AttitudeLevel = 'doubao' | 'yuesheng' | 'sensei';

/** 运行时加载条件（运行时由 context 评估）
 * Sprint 14 新增：所有 condition 必须满足才加载 SKILL（AND 语义）
 */
export type LoadCondition =
  | { type: 'evidence.quality'; op: 'IN' | 'NOT_IN'; values: Array<'low' | 'medium' | 'high'> }
  | { type: 'user.safetyWord'; op: 'IS' | 'IS_NOT'; value: boolean }
  | { type: 'user.dominantSyndrome'; op: 'EQ' | 'NEQ'; syndromeId: string };

/** Skill 加载条件 */
export interface SkillLoadWhen {
  phases: TeachingPhase[];
  attitudes: AttitudeLevel[];
  /** Sprint 14 新增：运行时条件（AND 语义） */
  conditions?: LoadCondition[];
}

/** Skill 元数据（YAML frontmatter 解析后）
 * Sprint 14-prior 扩展（解决 D-DEBT-11）：
 * - tokenPriority: 截断时优先级（10 最高，1 最低，默认 5）
 * - isCoreSubset: 是否核心子集（用于 dispatcher 子集过滤）
 * - parentId: 父 SKILL ID（标识拆分来源）
 *
 * 完整版本（depends / version / conditions）推迟到 Sprint 14+ 方向 C
 */
export interface SkillMetadata {
  id: string;
  estimatedTokens: number;
  loadWhen: SkillLoadWhen;
  /** 截断时优先级（10 最高，1 最低），可选，默认 5 */
  tokenPriority?: number;
  /** 是否核心子集（dispatcher 用 isCoreSubset=true 过滤），可选，默认 false */
  isCoreSubset?: boolean;
  /** 父 SKILL ID（如 core-iron-triangle → core-identity），可选 */
  parentId?: string | null;
  /** Sprint 14 新增：语义化版本（默认 '1.0'） */
  version?: string;
  /** Sprint 14 新增：依赖的其他 SKILL id 列表（默认 []） */
  depends?: string[];
}

/** Skill 文件（meta + content） */
export interface Skill {
  meta: SkillMetadata;
  content: string;
}

/**
 * 解析 SKILL 文件的 YAML frontmatter
 * 格式：--- ... ---\n\n# content
 */
export function parseSkillFile(filePath: string): Skill {
  const raw = fs.readFileSync(filePath, 'utf-8');
  const match = raw.match(/^---\n([\s\S]*?)\n---\n([\s\S]*)$/);

  if (!match) {
    throw new Error(
      `[parseSkillFile] Missing YAML frontmatter in ${filePath}. ` +
      `Expected format: ---\n...\n---\n\n# content`,
    );
  }

  const yamlBlock = match[1];
  const content = match[2].trim();

  const meta: SkillMetadata = {
    id: extractYamlString(yamlBlock, 'id'),
    estimatedTokens: parseInt(extractYamlString(yamlBlock, 'estimatedTokens'), 10),
    loadWhen: parseLoadWhen(yamlBlock),
    tokenPriority: parseOptionalYamlNumber(yamlBlock, 'tokenPriority', 5),
    isCoreSubset: parseOptionalYamlBoolean(yamlBlock, 'isCoreSubset', false),
    parentId: parseOptionalYamlStringOrNull(yamlBlock, 'parentId'),
    version: parseOptionalYamlString(yamlBlock, 'version', '1.0'),
    depends: parseOptionalYamlStringArray(yamlBlock, 'depends', []),
  };

  validateMetadata(meta, filePath);
  return { meta, content };
}

function extractYamlString(yaml: string, key: string): string {
  const match = yaml.match(new RegExp(`^${key}:\\s*(.+)$`, 'm'));
  if (!match) {
    throw new Error(`[parseSkillFile] Missing required key: ${key}`);
  }
  return match[1].trim();
}

function parseLoadWhen(yaml: string): SkillLoadWhen {
  const phasesMatch = yaml.match(/phases:\s*\[([^\]]+)\]/);
  const attitudesMatch = yaml.match(/attitudes:\s*\[([^\]]+)\]/);

  if (!phasesMatch || !attitudesMatch) {
    throw new Error('[parseSkillFile] Invalid loadWhen format');
  }

  return {
    phases: phasesMatch[1].split(',').map(s => s.trim()) as TeachingPhase[],
    attitudes: attitudesMatch[1].split(',').map(s => s.trim()) as AttitudeLevel[],
    conditions: parseConditions(yaml),
  };
}

/**
 * 解析 conditions（支持两种 YAML 格式）
 *
 * 1. 简写数组：`conditions: [a, b, c]`
 * 2. 完整对象列表：
 *    ```yaml
 *    conditions:
 *      - type: user.safetyWord
 *        op: IS_NOT
 *        value: true
 *      - type: evidence.quality
 *        op: IN
 *        values: [low, medium]
 *    ```
 *
 * 完整格式会构造结构化 LoadCondition，简写格式回退为 identifier 列表。
 *
 * @internal
 */
function parseConditions(yaml: string): LoadCondition[] | undefined {
  // 先检测是否存在多行对象列表（以 "- " 开头）
  // 找到 "conditions:" 行（不是数组形式），然后扫描后续行
  const lines = yaml.split('\n');
  const conditionsLineIdx = lines.findIndex((l, i) => {
    if (!/^\s*conditions:\s*$/.test(l)) return false;
    // 必须是 list 形式（不是 inline array）
    const next = lines[i + 1] ?? '';
    return /^\s*-\s+/.test(next);
  });

  if (conditionsLineIdx >= 0) {
    // 从 conditionsLineIdx + 1 开始，收集到下一个顶级 key 或空行
    const block: string[] = [];
    for (let i = conditionsLineIdx + 1; i < lines.length; i++) {
      const line = lines[i];
      // 顶级 key（行首是字母/数字，不是缩进）停止
      if (/^[a-zA-Z]/.test(line)) break;
      block.push(line);
    }
    if (block.length > 0) {
      return parseConditionsList(block.join('\n'));
    }
  }

  // 退回简写数组
  const inlineMatch = yaml.match(/conditions:\s*\[([^\]]+)\]/);
  if (inlineMatch) {
    const items = inlineMatch[1].split(',').map(s => s.trim()).filter(s => s.length > 0);
    return items.map(item => ({ type: 'user.dominantSyndrome', op: 'EQ', syndromeId: item }));
  }

  return undefined;
}

/**
 * 解析完整条件对象列表（每项以 `- ` 开头）
 * @internal
 */
function parseConditionsList(raw: string): LoadCondition[] {
  const items: LoadCondition[] = [];
  // 用 trim 清理每行（处理前导空格）
  const lines = raw.split('\n').map(l => l.replace(/^\s+|\s+$/g, ''));
  let current: Record<string, string> | null = null;

  for (const line of lines) {
    if (line === '') continue; // 跳过空行
    if (line.startsWith('- ')) {
      // 提交上一个
      if (current) {
        const cond = buildCondition(current);
        if (cond) items.push(cond);
      }
      // 起始新项（key: value 在 "- " 同一行）
      const inline = line.slice(2).trim();
      current = {};
      if (inline.includes(':')) {
        const idx = inline.indexOf(':');
        const k = inline.slice(0, idx).trim();
        const v = inline.slice(idx + 1).trim();
        current[k] = v;
      }
    } else if (current) {
      // 缩进的 key: value
      const idx = line.indexOf(':');
      if (idx > 0) {
        const k = line.slice(0, idx).trim();
        const v = line.slice(idx + 1).trim();
        current[k] = v;
      }
    }
  }
  if (current) {
    const cond = buildCondition(current);
    if (cond) items.push(cond);
  }

  return items;
}

/**
 * 从扁平 key-value 对象构造 LoadCondition
 * @internal
 */
function buildCondition(raw: Record<string, string>): LoadCondition | null {
  const type = raw.type;
  const op = raw.op;
  if (!type) return null;

  switch (type) {
    case 'evidence.quality': {
      const valuesStr = raw.values ?? '';
      const values = valuesStr
        .replace(/[[\]]/g, '')
        .split(',')
        .map(s => s.trim())
        .filter(s => s.length > 0) as Array<'low' | 'medium' | 'high'>;
      return { type, op: op as 'IN' | 'NOT_IN', values };
    }
    case 'user.safetyWord': {
      const value = raw.value === 'true';
      return { type, op: op as 'IS' | 'IS_NOT', value };
    }
    case 'user.dominantSyndrome': {
      return { type, op: op as 'EQ' | 'NEQ', syndromeId: raw.syndromeId ?? '' };
    }
    default:
      return null;
  }
}

function validateMetadata(meta: SkillMetadata, filePath: string): void {
  if (!meta.id) throw new Error(`[parseSkillFile] Empty id in ${filePath}`);
  if (isNaN(meta.estimatedTokens) || meta.estimatedTokens <= 0) {
    throw new Error(`[parseSkillFile] Invalid estimatedTokens in ${filePath}: ${meta.estimatedTokens}`);
  }
  if (meta.loadWhen.phases.length === 0) {
    throw new Error(`[parseSkillFile] Empty phases in ${filePath}`);
  }
  if (meta.loadWhen.attitudes.length === 0) {
    throw new Error(`[parseSkillFile] Empty attitudes in ${filePath}`);
  }
  // Sprint 14-prior: tokenPriority 范围校验
  if (meta.tokenPriority !== undefined && (meta.tokenPriority < 1 || meta.tokenPriority > 10)) {
    throw new Error(`[parseSkillFile] tokenPriority out of range [1,10] in ${filePath}: ${meta.tokenPriority}`);
  }
  // Sprint 14: version 格式校验（简单 semver）
  if (meta.version !== undefined && !/^\d+\.\d+(\.\d+)?$/.test(meta.version)) {
    throw new Error(`[parseSkillFile] Invalid version format in ${filePath}: ${meta.version}`);
  }
  // Sprint 14: depends 不能包含自身
  if (meta.depends && meta.depends.includes(meta.id)) {
    throw new Error(`[parseSkillFile] SKILL ${meta.id} depends on itself in ${filePath}`);
  }
}

/** 解析可选的 YAML number 字段（不存在则返回 defaultValue） */
function parseOptionalYamlNumber(yaml: string, key: string, defaultValue: number): number {
  const match = yaml.match(new RegExp(`^${key}:\\s*(.+)$`, 'm'));
  if (!match) return defaultValue;
  const parsed = parseInt(match[1].trim(), 10);
  return isNaN(parsed) ? defaultValue : parsed;
}

/** 解析可选的 YAML boolean 字段（不存在则返回 defaultValue） */
function parseOptionalYamlBoolean(yaml: string, key: string, defaultValue: boolean): boolean {
  const match = yaml.match(new RegExp(`^${key}:\\s*(.+)$`, 'm'));
  if (!match) return defaultValue;
  const value = match[1].trim();
  if (value === 'true') return true;
  if (value === 'false') return false;
  return defaultValue;
}

/** 解析可选的 YAML string 字段（null 字符串转为 JS null） */
function parseOptionalYamlStringOrNull(yaml: string, key: string): string | null {
  const match = yaml.match(new RegExp(`^${key}:\\s*(.+)$`, 'm'));
  if (!match) return null;
  const value = match[1].trim();
  if (value === 'null' || value === '~') return null;
  return value;
}

/** 解析可选的 YAML string 字段（带默认值） */
function parseOptionalYamlString(yaml: string, key: string, defaultValue: string): string {
  const match = yaml.match(new RegExp(`^${key}:\\s*(.+)$`, 'm'));
  if (!match) return defaultValue;
  return match[1].trim();
}

/** 解析可选的 YAML string 数组（[a, b, c] 格式） */
function parseOptionalYamlStringArray(yaml: string, key: string, defaultValue: string[]): string[] {
  const match = yaml.match(new RegExp(`^${key}:\\s*\\[([^\\]]*)\\]\\s*$`, 'm'));
  if (!match) return defaultValue;
  const content = match[1].trim();
  if (content === '') return [];
  return content.split(',').map(s => s.trim()).filter(s => s.length > 0);
}

/** 扫描 skills 目录下所有 .md 文件 */
export function loadAllSkills(skillsDir: string): Skill[] {
  if (!fs.existsSync(skillsDir)) {
    throw new Error(`[loadAllSkills] Directory not found: ${skillsDir}`);
  }

  const files = fs.readdirSync(skillsDir).filter(f => f.endsWith('.md'));
  return files.map(f => parseSkillFile(path.join(skillsDir, f)));
}
