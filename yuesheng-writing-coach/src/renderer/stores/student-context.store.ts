// 学生模型上下文管理 (Phase 1: Prompt 注入版)
// ⚠️ 本文件 catch 块中的 console.error / console.warn 仅用于开发调试，
//    生产环境应通过构建工具（如 terser drop_console）自动移除。
// 负责：维护轻量级学生状态，用于注入 System Prompt
// 依赖：zustand, localStorage
// 设计原则：
//   1. 不建数据库，先用 localStorage 持久化
//   2. 维护关键字段：userType、confidence、lastErrors、effectiveStrategies
//   3. 提供 toJSON() 方法导出为 Prompt 注入格式
// 依据：SPEC_adaptive-teaching_V1.0.md §3.2 StudentModel 数据结构（Phase 1 简化版）

import { create } from 'zustand';

/** 用户类型 */
export type UserType = 'beginner' | 'intermediate' | 'advanced';

/** 信心水平 */
export type ConfidenceLevel = 'low' | 'medium' | 'high';

/** 思维风格 */
export type ThinkingStyle = 'analytical' | 'emotional' | 'mixed';

/** 错误严重程度 */
export type ErrorSeverity = 'fatal' | 'structural' | 'cosmetic';

/** 错误记录 */
export interface ErrorRecord {
  errorId: string;           // 错误 ID，如 "P004"
  abilityId: string;         // 关联能力，如 "ABL-004"
  severity: ErrorSeverity;
  detectedAt: string;        // ISO 时间戳
  description: string;       // 简短描述
}

/** 学生上下文状态 */
export interface StudentContext {
  // === 用户画像 ===
  userType: UserType;
  confidenceLevel: ConfidenceLevel;
  thinkingStyle: ThinkingStyle;

  // === 错误历史 ===
  lastErrors: ErrorRecord[];

  // === 有效策略 ===
  effectiveStrategies: string[];

  // === 挫折计数 ===
  frustrationCount: number;

  // === 方法 ===
  updateFromDiagnosis: (syndromes: Array<{ id: string; name: string; severity: string }>) => void;
  updateFromInteraction: (outcome: 'success' | 'partial' | 'frustrated') => void;
  setUserType: (type: UserType) => void;
  setThinkingStyle: (style: ThinkingStyle) => void;
  toJSON: () => string;
  persist: () => void;
  load: () => void;
  reset: () => void;
}

const STORAGE_KEY = 'yuesheng-student-context';

/** 默认状态 */
const defaultState = {
  userType: 'beginner' as UserType,
  confidenceLevel: 'medium' as ConfidenceLevel,
  thinkingStyle: 'mixed' as ThinkingStyle,
  lastErrors: [] as ErrorRecord[],
  effectiveStrategies: [] as string[],
  frustrationCount: 0,
};

/**
 * 创建学生上下文 Zustand store
 * Phase 1: 使用 localStorage 持久化
 */
export const useStudentContextStore = create<StudentContext>((set, get) => ({
  ...defaultState,

  /** 从诊断结果更新 */
  updateFromDiagnosis: (syndromes) => {
    const errors: ErrorRecord[] = syndromes.map((s) => ({
      errorId: s.id,
      abilityId: `ABL-${s.id.replace('P', '')}`,
      severity: s.severity === 'L3' ? 'fatal' : s.severity === 'L2' ? 'structural' : 'cosmetic',
      detectedAt: new Date().toISOString(),
      description: s.name,
    }));

    set((state) => {
      const updatedErrors = [...state.lastErrors, ...errors].slice(-10); // 保留最近 10 条

      // 自动推断用户类型（基于错误严重程度和数量）
      let userType = state.userType;
      const fatalCount = updatedErrors.filter((e) => e.severity === 'fatal').length;
      if (fatalCount >= 3) {
        userType = 'beginner';
      } else if (updatedErrors.length > 5 && fatalCount === 0) {
        userType = 'advanced';
      } else if (updatedErrors.length > 2) {
        userType = 'intermediate';
      }

      return {
        lastErrors: updatedErrors,
        userType,
      };
    });

    get().persist();
  },

  /** 从交互结果更新 */
  updateFromInteraction: (outcome) => {
    set((state) => {
      const updates: Partial<StudentContext> = {};

      if (outcome === 'success') {
        // 成功 → 增加信心，减少挫折
        updates.confidenceLevel =
          state.confidenceLevel === 'low' ? 'medium' : state.confidenceLevel === 'medium' ? 'high' : 'high';
        updates.frustrationCount = Math.max(0, state.frustrationCount - 1);
      } else if (outcome === 'partial') {
        // 部分成功 → 保持
      } else if (outcome === 'frustrated') {
        // 挫折 → 降低信心，增加挫折计数
        updates.confidenceLevel =
          state.confidenceLevel === 'high' ? 'medium' : state.confidenceLevel === 'medium' ? 'low' : 'low';
        updates.frustrationCount = state.frustrationCount + 1;
      }

      return updates;
    });

    get().persist();
  },

  /** 设置用户类型 */
  setUserType: (type) => {
    set({ userType: type });
    get().persist();
  },

  /** 设置思维风格 */
  setThinkingStyle: (style) => {
    set({ thinkingStyle: style });
    get().persist();
  },

  /** 导出为 JSON 字符串（用于注入 Prompt） */
  toJSON: () => {
    const state = get();
    const lastErrorsText =
      state.lastErrors.length > 0
        ? state.lastErrors
            .slice(-3)
            .map((e) => `${e.description}(${e.errorId}, ${e.severity === 'fatal' ? '致命伤' : e.severity === 'structural' ? '结构病' : '皮肤症'})`)
            .join('、')
        : '无';

    const effectiveStrategiesText =
      state.effectiveStrategies.length > 0 ? state.effectiveStrategies.join('、') : '无';

    return [
      `- 用户类型：${state.userType === 'beginner' ? '新手' : state.userType === 'intermediate' ? '进阶' : '高阶'}`,
      `- 信心水平：${state.confidenceLevel === 'low' ? '低' : state.confidenceLevel === 'medium' ? '中' : '高'}`,
      `- 思维风格：${state.thinkingStyle === 'analytical' ? '理性分析型' : state.thinkingStyle === 'emotional' ? '感性体验型' : '混合型'}`,
      `- 最近错误：${lastErrorsText}`,
      `- 有效策略：${effectiveStrategiesText}`,
      `- 挫折计数：${state.frustrationCount}`,
    ].join('\n');
  },

  /** 持久化到 localStorage */
  persist: () => {
    try {
      const state = get();
      const data = {
        userType: state.userType,
        confidenceLevel: state.confidenceLevel,
        thinkingStyle: state.thinkingStyle,
        lastErrors: state.lastErrors,
        effectiveStrategies: state.effectiveStrategies,
        frustrationCount: state.frustrationCount,
      };
      localStorage.setItem(STORAGE_KEY, JSON.stringify(data));
    } catch (err) {
      console.warn('[StudentContext] Failed to persist:', err);
    }
  },

  /** 从 localStorage 加载 */
  load: () => {
    try {
      const raw = localStorage.getItem(STORAGE_KEY);
      if (raw) {
        const data = JSON.parse(raw);
        set({
          userType: data.userType ?? defaultState.userType,
          confidenceLevel: data.confidenceLevel ?? defaultState.confidenceLevel,
          thinkingStyle: data.thinkingStyle ?? defaultState.thinkingStyle,
          lastErrors: data.lastErrors ?? defaultState.lastErrors,
          effectiveStrategies: data.effectiveStrategies ?? defaultState.effectiveStrategies,
          frustrationCount: data.frustrationCount ?? defaultState.frustrationCount,
        });
      }
    } catch (err) {
      console.warn('[StudentContext] Failed to load:', err);
    }
  },

  /** 重置为默认状态 */
  reset: () => {
    set(defaultState);
    localStorage.removeItem(STORAGE_KEY);
  },
}));

/** 便捷选择器 */
export const selectUserType = (state: StudentContext) => state.userType;
export const selectConfidenceLevel = (state: StudentContext) => state.confidenceLevel;
export const selectLastErrors = (state: StudentContext) => state.lastErrors;
export const selectFrustrationCount = (state: StudentContext) => state.frustrationCount;

/** 判断是否需要降级到豆包模式 */
export const selectNeedsDoubaMode = (state: StudentContext) =>
  state.confidenceLevel === 'low' || state.frustrationCount >= 3;
