/**
 * Skill Registry — Skill 元数据注册表(Sprint 20 增量 1)
 *
 * 设计目标:
 * - 扫描 resources/prompts/skills/*.md 解析 frontmatter
 * - 提供 getById / getAll / compatibleWith(version) 等查询
 * - 配合 prompt-contract 的 required_skills 校验,实现"提示词独立迭代"
 *
 * 为什么需要版本过滤:
 * - 不同 prompt 版本可能引用不同 skill 子集
 * - 旧 prompt 不应该加载为新 prompt 设计的 skill(避免无谓的 token 消耗)
 * - 新 prompt 不应该依赖未声明兼容的旧 skill(避免运行时找不到)
 *
 * 数据格式约定(每个 SKILL-*.md 文件头):
 * ```yaml
 * ---
 * id: <skill-id>
 * estimatedTokens: <number>
 * compatiblePromptVersions: [<version-string>, ...]
 * ---
 * ```
 *
 * 依据: dev-docs/tasks/sprint-20-plan.md §增量 1 / D-055 端到端验证
 */

import * as fs from 'node:fs';
import * as path from 'node:path';
import type { SkillRef } from './orchestrator.types';

/** 解析后的 skill 元数据(包含 SkillRef 全部字段 + 源文件路径) */
export interface SkillMetadata extends SkillRef {
  /** skill 文件绝对路径(便于调试) */
  sourcePath: string;
}

/** frontmatter 解析结果 */
interface ParsedFrontmatter {
  id?: string;
  estimatedTokens?: number;
  compatiblePromptVersions?: string[];
}

/**
 * 解析 YAML frontmatter(简化版,只支持单层 key + inline 数组)
 * 失败 → 抛 Error(本实现假设 skill 文件格式受控)
 */
function parseFrontmatter(frontmatter: string): ParsedFrontmatter {
  const result: ParsedFrontmatter = {};
  const lines = frontmatter.split('\n');

  for (const raw of lines) {
    const line = raw.replace(/\r$/, ''); // CRLF 兼容
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;

    // id: <value>
    const idMatch = trimmed.match(/^id:\s*(.+)$/);
    if (idMatch) {
      result.id = idMatch[1].trim();
      continue;
    }

    // estimatedTokens: <number>
    const tokensMatch = trimmed.match(/^estimatedTokens:\s*(\d+)$/);
    if (tokensMatch) {
      result.estimatedTokens = parseInt(tokensMatch[1], 10);
      continue;
    }

    // compatiblePromptVersions: [v1, v2, ...]
    const versionsMatch = trimmed.match(/^compatiblePromptVersions:\s*\[(.*)\]$/);
    if (versionsMatch) {
      result.compatiblePromptVersions = versionsMatch[1]
        .split(',')
        .map(s => s.trim())
        .filter(Boolean);
      continue;
    }
  }

  return result;
}

/** 从 .md 文件内容中提取 frontmatter 块(---...---) */
function extractFrontmatter(md: string): string | null {
  const m = md.match(/^---\r?\n([\s\S]*?)\r?\n---/);
  return m ? m[1] : null;
}

/**
 * Skill 注册表
 *
 * 构造时立即扫描 skillsDir 加载所有 skill;不可变对象
 * 如需重新加载,创建新实例
 */
export class SkillRegistry {
  private readonly skills: Map<string, SkillMetadata>;

  constructor(skillsDir: string) {
    this.skills = this.loadAll(skillsDir);
  }

  /** 扫描目录加载所有 .md skill 文件 */
  private loadAll(skillsDir: string): Map<string, SkillMetadata> {
    const map = new Map<string, SkillMetadata>();
    if (!fs.existsSync(skillsDir)) {
      throw new Error(`SkillRegistry: skills 目录不存在: ${skillsDir}`);
    }

    const files = fs.readdirSync(skillsDir).filter(f => f.endsWith('.md'));
    for (const file of files) {
      const filePath = path.join(skillsDir, file);
      const content = fs.readFileSync(filePath, 'utf-8');
      const fm = extractFrontmatter(content);
      if (!fm) {
        continue; // 无 frontmatter 跳过
      }

      const parsed = parseFrontmatter(fm);
      const id = parsed.id ?? file.replace(/\.md$/, '');

      const meta: SkillMetadata = {
        id,
        estimatedTokens: parsed.estimatedTokens ?? 500,
        phases: [], // phase 过滤由 orchestrator 负责(暂不解析 loadWhen.phases)
        compatiblePromptVersions: parsed.compatiblePromptVersions ?? [],
        sourcePath: filePath,
      };
      map.set(id, meta);
    }

    return map;
  }

  /** 通过 ID 查找 skill(不存在 → undefined) */
  getById(id: string): SkillMetadata | undefined {
    return this.skills.get(id);
  }

  /** 返回所有 skill */
  getAll(): SkillMetadata[] {
    return [...this.skills.values()];
  }

  /** 全部已注册 skill 的 ID 列表 */
  ids(): string[] {
    return [...this.skills.keys()];
  }

  /** 返回与指定 prompt 版本兼容的所有 skill */
  compatibleWith(version: string): SkillMetadata[] {
    return this.getAll().filter(s => s.compatiblePromptVersions.includes(version));
  }

  /** 统计信息(调试用) */
  stats(): { total: number; withVersion: number; withoutVersion: number } {
    const all = this.getAll();
    const withVersion = all.filter(s => s.compatiblePromptVersions.length > 0).length;
    return {
      total: all.length,
      withVersion,
      withoutVersion: all.length - withVersion,
    };
  }
}

/**
 * 默认注册表工厂(从项目根 resources/prompts/skills 加载)
 * 供生产代码使用
 */
export function createDefaultSkillRegistry(projectRoot: string): SkillRegistry {
  const skillsDir = path.join(projectRoot, 'resources/prompts/skills');
  return new SkillRegistry(skillsDir);
}
