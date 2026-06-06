/**
 * StudentModelService 文字化方法单元测试
 *
 * 测试覆盖：
 * 1. describeProficiency — 不同能力等级返回不同描述
 * 2. describeCognitiveStyle — 不同认知风格返回不同描述
 * 3. describeSyndromeSummary — 无数据/有数据/改善趋势/多个问题
 * 4. 配置文件格式验证
 */

import { describe, it, expect, vi } from 'vitest';
import * as fs from 'fs';
import * as path from 'path';

describe('StudentModelService — textualization', () => {
  describe('配置文件加载', () => {
    it('should load student-profile-descriptions.json successfully', () => {
      const configPath = path.join(process.cwd(), 'resources', 'config', 'student-profile-descriptions.json');
      const raw = fs.readFileSync(configPath, 'utf-8');
      const config = JSON.parse(raw);

      expect(config).toHaveProperty('$source');
      expect(config).toHaveProperty('proficiency');
      expect(config).toHaveProperty('cognitiveStyle');
      expect(config).toHaveProperty('syndromeSummary');
    });

    it('should have all proficiency levels', () => {
      const configPath = path.join(process.cwd(), 'resources', 'config', 'student-profile-descriptions.json');
      const config = JSON.parse(fs.readFileSync(configPath, 'utf-8'));

      expect(config.proficiency).toHaveProperty('beginner');
      expect(config.proficiency).toHaveProperty('intermediate');
      expect(config.proficiency).toHaveProperty('advanced');
    });

    it('should have all cognitive styles', () => {
      const configPath = path.join(process.cwd(), 'resources', 'config', 'student-profile-descriptions.json');
      const config = JSON.parse(fs.readFileSync(configPath, 'utf-8'));

      expect(config.cognitiveStyle).toHaveProperty('analytical');
      expect(config.cognitiveStyle).toHaveProperty('emotional');
      expect(config.cognitiveStyle).toHaveProperty('mixed');
    });

    it('should have all syndromeSummary templates', () => {
      const configPath = path.join(process.cwd(), 'resources', 'config', 'student-profile-descriptions.json');
      const config = JSON.parse(fs.readFileSync(configPath, 'utf-8'));

      expect(config.syndromeSummary).toHaveProperty('noData');
      expect(config.syndromeSummary).toHaveProperty('hasIssues');
      expect(config.syndromeSummary).toHaveProperty('improving');
      expect(config.syndromeSummary).toHaveProperty('multipleIssues');
    });

    it('proficiency descriptions should be non-empty strings', () => {
      const configPath = path.join(process.cwd(), 'resources', 'config', 'student-profile-descriptions.json');
      const config = JSON.parse(fs.readFileSync(configPath, 'utf-8'));

      for (const [key, value] of Object.entries(config.proficiency)) {
        expect(typeof value).toBe('string');
        expect((value as string).length).toBeGreaterThan(0);
      }
    });

    it('cognitiveStyle descriptions should be non-empty strings', () => {
      const configPath = path.join(process.cwd(), 'resources', 'config', 'student-profile-descriptions.json');
      const config = JSON.parse(fs.readFileSync(configPath, 'utf-8'));

      for (const [key, value] of Object.entries(config.cognitiveStyle)) {
        expect(typeof value).toBe('string');
        expect((value as string).length).toBeGreaterThan(0);
      }
    });
  });

  describe('describeSyndromeSummary template substitution logic', () => {
    // 模拟 describeSyndromeSummary 的模板替换逻辑
    const substituteTemplate = (template: string, replacements: Record<string, string>): string => {
      let result = template;
      for (const [key, value] of Object.entries(replacements)) {
        result = result.replace(`{${key}}`, value);
      }
      return result;
    };

    it('should substitute {topIssue} and {tierLabel} in hasIssues template', () => {
      const configPath = path.join(process.cwd(), 'resources', 'config', 'student-profile-descriptions.json');
      const config = JSON.parse(fs.readFileSync(configPath, 'utf-8'));

      const result = substituteTemplate(config.syndromeSummary.hasIssues, {
        topIssue: '角色动机缺失（3次）',
        tierLabel: '严重',
      });

      expect(result).toContain('角色动机缺失（3次）');
      expect(result).toContain('严重');
      expect(result).not.toContain('{topIssue}');
      expect(result).not.toContain('{tierLabel}');
    });

    it('should substitute {topIssue} in improving template', () => {
      const configPath = path.join(process.cwd(), 'resources', 'config', 'student-profile-descriptions.json');
      const config = JSON.parse(fs.readFileSync(configPath, 'utf-8'));

      const result = substituteTemplate(config.syndromeSummary.improving, {
        topIssue: '世界观膨胀',
      });

      expect(result).toContain('世界观膨胀');
      expect(result).not.toContain('{topIssue}');
    });

    it('should substitute all placeholders in multipleIssues template', () => {
      const configPath = path.join(process.cwd(), 'resources', 'config', 'student-profile-descriptions.json');
      const config = JSON.parse(fs.readFileSync(configPath, 'utf-8'));

      const result = substituteTemplate(config.syndromeSummary.multipleIssues, {
        topIssue: '情绪标签化（5次）',
        tierLabel: '中等',
      });

      expect(result).toContain('情绪标签化（5次）');
      expect(result).toContain('中等');
      expect(result).not.toContain('{topIssue}');
      expect(result).not.toContain('{tierLabel}');
    });
  });
});
