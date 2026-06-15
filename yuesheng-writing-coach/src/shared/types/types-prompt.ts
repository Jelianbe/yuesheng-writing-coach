/**
 * Prompt / Role-Skill 类型定义
 * 用于角色 Skill 拆分和动态注入
 */

export type TeachingRole = 'teacher' | 'assistant' | 'clown';

export interface RoleSkillConfig {
  roleId: string;
  name: string;
  description: string;
  knowledgeBoundary: {
    allowedSources: string[];
    tokenBudget: { contextRounds: number; maxTokens: number };
    contextRetention: Record<string, string[]>;
  };
  style: {
    tone: string;
    personality: string;
  };
}

export interface RoleSchedule {
  phase: string;
  subphase: string | null;
  roleId: TeachingRole;
}

export interface RoleSchedulesConfig {
  version: string;
  schedules: RoleSchedule[];
  contextPruningRules: {
    onRoleSwitch: boolean;
    pruneStrategy: string;
    knowledgeCleanup: string;
  };
}
