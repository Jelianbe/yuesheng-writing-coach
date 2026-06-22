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

/** Skill 加载条件 */
export interface SkillLoadWhen {
  phases: TeachingPhase[];
  attitudes: AttitudeLevel[];
}

/** Skill 元数据（YAML frontmatter 解析后） */
export interface SkillMetadata {
  id: string;
  estimatedTokens: number;
  loadWhen: SkillLoadWhen;
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
  };
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
}

/** 扫描 skills 目录下所有 .md 文件 */
export function loadAllSkills(skillsDir: string): Skill[] {
  if (!fs.existsSync(skillsDir)) {
    throw new Error(`[loadAllSkills] Directory not found: ${skillsDir}`);
  }

  const files = fs.readdirSync(skillsDir).filter(f => f.endsWith('.md'));
  return files.map(f => parseSkillFile(path.join(skillsDir, f)));
}
