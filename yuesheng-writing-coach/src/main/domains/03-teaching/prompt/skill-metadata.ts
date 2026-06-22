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
  const conditionsMatch = yaml.match(/conditions:\s*\[([^\]]+)\]/);

  if (!phasesMatch || !attitudesMatch) {
    throw new Error('[parseSkillFile] Invalid loadWhen format');
  }

  return {
    phases: phasesMatch[1].split(',').map(s => s.trim()) as TeachingPhase[],
    attitudes: attitudesMatch[1].split(',').map(s => s.trim()) as AttitudeLevel[],
    conditions: conditionsMatch ? parseConditions(conditionsMatch[1]) : undefined,
  };
}

/**
 * 解析 conditions 简写语法
 * Sprint 14 T14-5: 简写格式 — 逗号分隔的字符串
 *   完整 YAML 形式（如 evidence.quality IN [...]）解析待后续 Sprint 15
 *   当前实现：仅解析为标识符，保留语义在 dispatcher 评估
 *
 * 实际 dispatcher 不依赖 conditions 字符串的语义（YAML 解析结果仅用于诊断），
 * 真正的 condition 定义由 PhaseConfig / RuntimeContext 注入。
 *
 * @internal
 */
function parseConditions(raw: string): LoadCondition[] {
  const items = raw.split(',').map(s => s.trim()).filter(s => s.length > 0);
  // 简写语法：每个 item 作为 identifier（保留为 LoadCondition 数组）
  // 真实语义由 RuntimeContext 注入时由 dispatch 调用方构造完整 LoadCondition
  return items.map(item => ({ type: 'user.dominantSyndrome', op: 'EQ', syndromeId: item }));
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
