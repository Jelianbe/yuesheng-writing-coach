# 月笙写作教练 - 项目开发参考手册

**版本**: V1.0  
**创建日期**: 2026-06-01  
**状态**: draft  
**目标读者**: 开发团队、项目经理、技术利益相关者

---

## 目录

1. [项目概述](#1-项目概述)
2. [方案对比与决策记录](#2-方案对比与决策记录)
3. [技术架构总览](#3-技术架构总览)
4. [技术栈与选型](#4-技术栈与选型)
5. [完整开发工作流](#5-完整开发工作流)
6. [核心代码实现](#6-核心代码实现)
7. [数据结构与接口](#7-数据结构与接口)
8. [关键技术与考虑](#8-关键技术与考虑)
9. [风险与缓解](#9-风险与缓解)
10. [附录：规则体系](#10-附录规则体系)

---

## 1. 项目概述

### 1.1 项目定位

月笙写作教练是一个 AI 写作教练桌面应用，核心理念为：

- **不替用户写** — 只给示范，不替完成
- **不替用户决定** — 给选择，不给答案
- **帮用户看清问题** — 让用户自己解决

### 1.2 项目目标

| 目标 | 说明 | 验证方式 |
|------|------|----------|
| AI 按图索骥教学 | 诊断表记录用户问题，AI 后续对话参考 | 多轮对话验证 |
| 诊断书与 AI 回复同步 | 诊断表由 AI 同时输出，天然一致 | 一致性检查 |
| 布置习作 | 诊断表包含建议动作，可映射到训练任务 | 任务推荐功能 |
| 用户成长轨迹 | 诊断表存储到数据库，可追踪进步 | 历史查询功能 |

### 1.3 已完成内容

| 类别 | 内容 | 状态 |
|------|------|------|
| Prompt 体系 | V3.0（约 2100 字） | ✅ 完成 |
| 教学动作库 | A001-A008 | ✅ 完成 |
| 病症识别手册 | P001-P007 | ✅ 完成 |
| 训练任务库 | T001-T014 | ✅ 完成 |
| 验证报告 | 28 个测试点，病症识别 100%，动作触发 96.4% | ✅ 完成 |
| PRD 文档 | 完整产品需求文档 | ✅ 完成 |
| 诊断引擎基础 | diagnosis-engine.ts | ✅ 完成 |
| 诊断表解析器 | diagnosis-parser.ts | ✅ 完成 |
| 类型定义 | shared/types.ts | ✅ 完成 |
| 诊断状态管理 | diag.store.ts | ✅ 完成 |
| 诊断面板 UI | DiagnosisPanel.tsx | ✅ 完成 |
| API 配置界面 | 配置 + 测试连接 | ✅ 完成 |

### 1.4 当前阶段

**诊断层开发阶段** → 产品工程启动阶段

---

## 2. 方案对比与决策记录

### 2.1 诊断方案演进

| 方案 | 诊断主体 | 优点 | 缺点 | 状态 |
|------|---------|------|------|------|
| **规则引擎诊断** | diagnosis-engine.ts | 速度快、成本低、可控 | 硬编码误判率高、不理解上下文 | ❌ 已放弃 |
| **规则引擎 + AI** | 规则引擎先诊断，AI 参考 | 减少 AI 依赖 | 规则引擎误判会误导 AI | ❌ 已放弃 |
| **纯 AI 诊断** | AI 输出结构化诊断表 | 理解上下文、准确率高 | 依赖 AI 稳定性、成本略高 | ✅ 最终方案 |

### 2.2 关键决策点

| 决策 | 选项 | 选择 | 理由 |
|------|------|------|------|
| 诊断主体 | 规则引擎 vs AI | AI | 规则引擎无法理解上下文，误判率高 |
| 诊断表格式 | 自由文本 vs JSON | JSON | 结构化数据便于存储、查询、展示 |
| 解析方式 | 标记截取 vs API 返回 | 标记截取 | 兼容现有 API，无需修改 |
| 历史参考 | 无 vs 最近 N 轮 | 最近 3 轮 | 按图索骥需要上下文 |
| 漏斗设计 | 统一处理 | L1明确/L2分类/L3复杂 | 优化响应速度和准确率 |
| 快速过滤 | 规则引擎快速识别 | 删除 | 与 AI 诊断冲突，增加复杂度 |

### 2.3 目标对齐度

| 目标 | 方案对齐度 | 说明 |
|------|-----------|------|
| AI 按图索骥教学 | ✅ 完全对齐 | 诊断表记录用户问题，AI 后续对话参考 |
| 诊断书与 AI 回复同步 | ✅ 完全对齐 | 诊断表由 AI 同时输出，天然一致 |
| 布置习作 | ✅ 完全对齐 | 诊断表包含建议动作，可映射到训练任务 |
| 用户成长轨迹 | ✅ 完全对齐 | 诊断表存储到数据库，可追踪进步 |

---

## 3. 技术架构总览

### 3.1 整体架构

```
┌─────────────────────────────────────────────────────────┐
│ 渲染进程 (Renderer)                                       │
│  ┌─────────────┐  ┌──────────────┐  ┌─────────────────┐ │
│  │ Diagnosis   │  │ Chat         │  │ Zustand Store   │ │
│  │ Panel       │  │ Interface    │  │ (diag.store)    │ │
│  └──────┬──────┘  └──────┬───────┘  └────────┬────────┘ │
│         │                │                    │          │
│         └────────────────┼────────────────────┘          │
│                          │ IPC                           │
└──────────────────────────┼───────────────────────────────┘
                           │
┌──────────────────────────┼───────────────────────────────┐
│ 主进程 (Main)              │                               │
│  ┌────────────────────────┴───────────────────────────┐  │
│  │ 聊天服务 (chat.service.ts)                          │  │
│  │  ┌─────────────┐  ┌────────────────────────────┐  │  │
│  │  │ AI 调用      │  │ 诊断表解析                  │  │  │
│  │  │ (callAI)    │→ │ (parseDiagnosisFromAI)     │  │  │
│  │  └─────────────┘  └────────────┬───────────────┘  │  │
│  │                                │                  │  │
│  │  ┌─────────────────────────────┴───────────────┐  │  │
│  │  │ IPC 推送 (webContents.send)                  │  │  │
│  │  │ diagnosis:update → 渲染进程                  │  │  │
│  │  └─────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

### 3.2 分层架构

| 层 | 职责 | 组件 |
|---|------|------|
| 引擎层 | AI 调用、诊断表解析 | chat.service.ts, diagnosis-parser.ts |
| 通信层 | IPC 通道管理、消息路由 | ipc-handlers/ |
| 状态层 | 诊断数据管理 | diag.store.ts |
| UI 层 | 诊断结果展示 | DiagnosisPanel.tsx |

### 3.3 诊断层漏斗式设计

```
L1 - 明确指令 → 规则+模板匹配
  ↓ (未匹配)
L2 - 明显病症 → 分类+规则配对
  ↓ (未匹配)
L3 - 复杂/混合 → 主 LM 完整处理
```

---

## 4. 技术栈与选型

### 4.1 技术栈详情

| 层 | 技术 | 版本 | 说明 |
|---|------|------|------|
| 框架 | Electron | 28+ | 桌面应用框架 |
| 语言 | TypeScript | strict | 类型安全 |
| 前端 | React | 18+ | UI 渲染 |
| 构建工具 | Vite | 5+ | 快速构建 |
| 样式 | Tailwind CSS | 3+ | 原子化 CSS |
| 状态管理 | Zustand | 4+ | 轻量级状态管理 |
| 存储 | electron-store | 8+ | 配置存储 |
| 数据库 | better-sqlite3 | 9+ | 数据持久化 |
| AI 模型 | DPV4 | - | 用户自备 API Key |
| 通信 | IPC | contextIsolation + contextBridge | 主渲染进程通信 |

### 4.2 选型确认

| 项目 | 当前选型 | 确认/建议 |
|------|---------|----------|
| 模型 | DPV4（用户自备 API Key） | ✅ 合理，需在 UI 中提示用户申请 DeepSeek API Key |
| 流式输出 | fetch + ReadableStream | ✅ 主流做法，注意处理中断（AbortController） |
| 数据库 | better-sqlite3 | ✅ 同步 API 简单，适合桌面应用 |
| 状态管理 | Zustand | ✅ 轻量，配置用 electron-store，运行时状态用 Zustand |
| 诊断引擎位置 | 主进程 | ✅ 避免渲染进程卡顿 |
| IPC 通信 | 自定义通道 | ✅ 清晰，建议增加错误处理通道 |

---

## 5. 完整开发工作流

### 5.1 需求收集阶段

**目标**: 明确产品定位、核心功能、用户需求

| 活动 | 交付物 | 完成标准 |
|------|--------|----------|
| 用户访谈 | 用户需求文档 | 明确核心痛点 |
| 竞品分析 | 竞品分析报告 | 识别差异化优势 |
| 技术调研 | 技术选型报告 | 确定技术可行性 |

**关键里程碑**: M0 - 需求确认

### 5.2 设计阶段

**目标**: 完成架构设计、接口定义、UI 设计

| 活动 | 交付物 | 完成标准 |
|------|--------|----------|
| 架构设计 | 架构设计文档 | 四层架构定义清晰 |
| 接口设计 | 接口规范文档 | IPC 通道、数据结构定义完成 |
| UI 设计 | 前端原型 | 界面布局和交互流程确认 |
| 诊断表设计 | 诊断表格式规范 | JSON 格式定义完成 |

**关键里程碑**: M1 - 设计评审通过

### 5.3 开发阶段

**目标**: 实现核心功能，分层开发

| 模块 | 优先级 | 交付物 | 完成标准 |
|------|--------|--------|----------|
| API 配置界面 | P0 | ConfigPanel 组件 | 用户能配置并测试 API 连接 |
| 聊天界面 | P0 | ChatInterface 组件 | 消息收发、流式显示 |
| 诊断表解析器 | P0 | diagnosis-parser.ts | 正确解析 AI 输出 |
| 诊断状态管理 | P0 | diag.store.ts | 状态订阅、历史查询 |
| 诊断面板 UI | P0 | DiagnosisPanel.tsx | 展示诊断结果 |
| 聊天服务集成 | P0 | chat.service.ts | AI 调用、诊断推送 |
| 训练任务系统 | P1 | TrainingTask 组件 | 任务推荐、进度追踪 |
| 用户画像系统 | P1 | UserProfile 组件 | 诊断历史、进步追踪 |

**关键里程碑**: 
- M2 - MVP 核心功能完成
- M3 - 诊断层完整流程跑通
- M4 - 训练任务集成完成

### 5.4 测试阶段

**目标**: 验证功能正确性、性能、用户体验

| 测试类型 | 内容 | 完成标准 |
|----------|------|----------|
| 单元测试 | 解析器、状态管理 | 覆盖率 > 80% |
| 集成测试 | IPC 通信、AI 调用 | 端到端流程通过 |
| 盲测验证 | 5 个案例多轮对话 | 诊断准确率 > 85% |
| 性能测试 | 响应时间、内存占用 | 响应时间 < 3s |

**关键里程碑**: M5 - 测试通过

### 5.5 部署阶段

**目标**: 打包发布、用户部署

| 活动 | 交付物 | 完成标准 |
|------|--------|----------|
| 打包配置 | electron-builder 配置 | Windows 安装包生成 |
| 安装测试 | 安装验证报告 | 安装/卸载正常 |
| 用户手册 | 使用指南文档 | 用户能独立完成配置 |

**关键里程碑**: M6 - MVP 发布

### 5.6 维护阶段

**目标**: 持续优化、用户反馈响应

| 活动 | 频率 | 说明 |
|------|------|------|
| Bug 修复 | 持续 | 用户反馈问题及时修复 |
| 功能迭代 | 每 2 周 | 根据用户反馈优化 |
| 模型更新 | 按需 | 适配新模型版本 |
| 规则更新 | 每 1 月 | 诊断规则优化 |

---

## 6. 核心代码实现

### 6.1 诊断表解析器

```typescript
// src/main/services/diagnosis-parser.ts
// 负责：解析 AI 回复中的诊断表 JSON
// 设计原则：
//   1. 容错优先：AI 未输出或格式错误时降级处理
//   2. 安全性：不信任 AI 输出，验证字段类型
//   3. 可调试：详细日志记录解析过程

import { DiagnosisEntry, SyndromeId, ActionId, SyndromeResult, SeverityLevel } from '../../renderer/shared/types';

/** 诊断表标记 */
const DIAGNOSIS_START = '---DIAGNOSIS_START---';
const DIAGNOSIS_END = '---DIAGNOSIS_END---';

/**
 * 解析 AI 回复中的诊断表
 * 
 * AI 回复格式：
 * 你的问题在于...
 * 
 * ---DIAGNOSIS_START---
 * {
 *   "syndromes": [...],
 *   "actions": ["A001"],
 *   "confidence": 0.85
 * }
 * ---DIAGNOSIS_END---
 * 
 * @param fullResponse - AI 完整回复（含诊断表）
 * @param sessionId - 会话 ID
 * @param messageId - 消息 ID
 * @returns 纯净回复 + 诊断表对象
 */
export function parseDiagnosisFromAIResponse(
  fullResponse: string,
  sessionId: string,
  messageId: string,
): { cleanResponse: string; diagnosis: DiagnosisEntry | null } {
  // 查找诊断表标记
  const startIndex = fullResponse.indexOf(DIAGNOSIS_START);
  const endIndex = fullResponse.indexOf(DIAGNOSIS_END);

  // 未找到完整标记，返回原始回复
  if (startIndex === -1 || endIndex === -1) {
    console.log('[DiagnosisParser] No diagnosis markers found, returning original response');
    return { cleanResponse: fullResponse, diagnosis: null };
  }

  // 截取 JSON 部分
  const jsonStr = fullResponse.substring(
    startIndex + DIAGNOSIS_START.length,
    endIndex
  ).trim();

  // 移除诊断表标记，得到纯净回复
  const cleanResponse = fullResponse
    .substring(0, startIndex)
    .concat(fullResponse.substring(endIndex + DIAGNOSIS_END.length))
    .trim();

  try {
    const parsed = JSON.parse(jsonStr);
    const diagnosis = validateAndBuildDiagnosis(parsed, sessionId, messageId);
    return { cleanResponse, diagnosis };
  } catch (error) {
    console.warn('[DiagnosisParser] Failed to parse diagnosis JSON:', error);
    return { cleanResponse, diagnosis: null };
  }
}

/**
 * 验证并构建诊断对象
 * 不信任 AI 输出，验证字段类型和值域
 */
function validateAndBuildDiagnosis(
  parsed: unknown,
  sessionId: string,
  messageId: string,
): DiagnosisEntry | null {
  if (!parsed || typeof parsed !== 'object') {
    console.warn('[DiagnosisParser] Invalid diagnosis format: not an object');
    return null;
  }

  const obj = parsed as Record<string, unknown>;

  // 验证 syndromes 数组
  const syndromes = validateSyndromes(obj.syndromes);
  
  // 验证 actions 数组
  const actions = validateActions(obj.actions);

  // 验证 confidence
  const confidence = typeof obj.confidence === 'number'
    ? Math.max(0, Math.min(1, obj.confidence))
    : 0;

  return {
    sessionId,
    messageId,
    syndromes,
    suggestedActions: actions,
    confidence,
    timestamp: new Date().toISOString(),
    nextFocus: validateNextFocus(obj.nextFocus),
  };
}
```

**关键说明**:
- 使用标记 `---DIAGNOSIS_START---` 和 `---DIAGNOSIS_END---` 截取诊断表
- JSON 解析失败时降级为无诊断状态
- 严格验证字段类型，不信任 AI 输出

### 6.2 诊断状态管理

```typescript
// src/renderer/stores/diag.store.ts
// 负责：管理诊断数据的接收、存储和查询
// 依赖：zustand, DiagnosisEntry 类型

import { create } from 'zustand';
import { DiagnosisEntry, SeverityLevel, SyndromeId, ActionId } from '../shared/types';

export interface DiagState {
  /** 当前轮次的诊断结果 */
  currentDiagnosis: DiagnosisEntry | null;
  /** 历史诊断记录（按会话ID分组） */
  history: Record<string, DiagnosisEntry[]>;
  /** 是否正在加载诊断数据 */
  isLoading: boolean;
  /** 诊断错误信息 */
  error: string | null;

  /** 设置当前诊断结果 */
  setCurrentDiagnosis: (entry: DiagnosisEntry | null) => void;
  /** 添加诊断到历史记录 */
  addToHistory: (sessionId: string, entry: DiagnosisEntry) => void;
  /** 查询指定会话的诊断历史 */
  getHistoryBySession: (sessionId: string) => DiagnosisEntry[];
  /** 清除所有诊断数据 */
  clear: () => void;
}

export const useDiagStore = create<DiagState>((set, get) => ({
  currentDiagnosis: null,
  history: {},
  isLoading: false,
  error: null,

  setCurrentDiagnosis: (entry: DiagnosisEntry | null) => {
    set({ currentDiagnosis: entry, error: null });
  },

  addToHistory: (sessionId: string, entry: DiagnosisEntry) => {
    set((state) => {
      const sessionHistory = state.history[sessionId] || [];
      return {
        history: {
          ...state.history,
          [sessionId]: [...sessionHistory, entry],
        },
      };
    });
  },

  getHistoryBySession: (sessionId: string) => {
    return get().history[sessionId] || [];
  },

  clear: () => {
    set({
      currentDiagnosis: null,
      history: {},
      error: null,
      isLoading: false,
    });
  },
}));

/** 便捷选择器：获取当前诊断的病症列表 */
export const selectCurrentSyndromes = (state: DiagState) =>
  state.currentDiagnosis?.syndromes ?? [];

/** 便捷选择器：获取当前诊断的建议动作列表 */
export const selectCurrentActions = (state: DiagState) =>
  state.currentDiagnosis?.suggestedActions ?? [];

/** 便捷选择器：获取当前诊断的置信度 */
export const selectCurrentConfidence = (state: DiagState) =>
  state.currentDiagnosis?.confidence ?? 0;

/** 便捷选择器：判断是否有诊断结果 */
export const selectHasDiagnosis = (state: DiagState) =>
  state.currentDiagnosis !== null && state.currentDiagnosis.syndromes.length > 0;
```

**关键说明**:
- 使用 Zustand 管理状态，轻量且高效
- 提供便捷选择器方法，减少组件中状态访问代码
- 支持多会话诊断记录查询

### 6.3 诊断面板组件

```typescript
// src/renderer/components/DiagnosisPanel.tsx
// 负责：展示当前轮次的诊断结果

import React from 'react';
import { useDiagStore, selectCurrentSyndromes, selectCurrentActions, selectCurrentConfidence, selectHasDiagnosis } from '../stores/diag.store';
import { SyndromeResult, ActionId, SeverityLevel } from '../shared/types';

/** 严重度颜色映射 */
const SEVERITY_COLORS: Record<SeverityLevel, { bg: string; text: string; bar: string; label: string }> = {
  L1: { bg: 'bg-emerald-500/10', text: 'text-emerald-400', bar: 'bg-emerald-500', label: '轻度' },
  L2: { bg: 'bg-amber-500/10', text: 'text-amber-400', bar: 'bg-amber-500', label: '中度' },
  L3: { bg: 'bg-red-500/10', text: 'text-red-400', bar: 'bg-red-500', label: '重度' },
};

/** 教学动作描述映射 */
const ACTION_DESCRIPTIONS: Record<ActionId, string> = {
  A001: '缩小范围：从宏大设定拉回具体场景',
  A002: '回归主角：从上帝视角回到角色眼睛',
  A003: '现实锚点：把角色放回具体生活场景',
  A004: '核心生长：从核心设定逐步扩展',
  A005: '展示不讲述：用具体细节代替抽象词汇',
  A006: '对话训练：练习对话节奏和信息密度',
  A007: '翻转拆解：打破固定视角',
  A008: '阅读任务：给阅读任务而非书单',
};

/**
 * 病症卡片组件
 * 展示单个病症的编号、名称、严重度、证据片段
 */
function SyndromeCard({ syndrome }: { syndrome: SyndromeResult }): React.ReactElement {
  const colors = SEVERITY_COLORS[syndrome.severity];
  const severityPercent = syndrome.score ? Math.min(100, (syndrome.score / 8) * 100) : 0;

  return (
    <div className={`rounded-lg p-3 ${colors.bg} border border-white/5`}>
      <div className="flex items-center justify-between mb-2">
        <span className={`text-xs font-bold ${colors.text}`}>{syndrome.id}</span>
        <span className="text-sm font-medium text-slate-200">{syndrome.name}</span>
      </div>

      {/* 严重度进度条 */}
      <div className="h-1.5 bg-slate-700 rounded-full overflow-hidden mb-1.5">
        <div
          className={`h-full ${colors.bar} rounded-full transition-all duration-500`}
          style={{ width: `${severityPercent}%` }}
        />
      </div>
      <div className="text-xs text-slate-400">
        严重度：{colors.label}{syndrome.score ? ` | 信号分: ${syndrome.score}` : ''}
      </div>

      {/* 证据列表 */}
      {syndrome.evidence.length > 0 && (
        <div className="mt-2 pt-2 border-t border-white/10">
          <div className="text-xs text-slate-500 mb-1">证据片段:</div>
          {syndrome.evidence.map((evidence, idx) => (
            <div key={idx} className="text-xs text-slate-400 flex items-center gap-1 py-0.5">
              <span className="text-slate-500">·</span>
              <span>{evidence}</span>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
```

**关键说明**:
- 纯展示组件，通过 Zustand store 订阅数据
- 严重度用颜色区分（L1 绿色、L2 黄色、L3 红色）
- 展示证据片段而非触发信号，更符合 AI 诊断输出

### 6.4 类型定义

```typescript
// src/renderer/shared/types.ts
// 负责：核心数据类型的统一定义，主进程与渲染进程共享使用

/** 诊断严重度等级 */
export type SeverityLevel = 'L1' | 'L2' | 'L3';

/** 病症 ID 枚举 */
export enum SyndromeId {
  WorldviewBloat = 'P001',          // 世界观膨胀
  CharacterTool = 'P002',           // 角色工具人化
  EmotionLabeling = 'P003',         // 情绪标签化
  InfoDumping = 'P004',             // 信息硬塞
  PerspectiveDrift = 'P005',        // 视角漂移
  PacingStagnation = 'P006',        // 节奏停滞
  ReadingStructureSingle = 'P007',  // 阅读结构单一
}

/** 教学动作 ID 枚举 */
export enum ActionId {
  NarrowScope = 'A001',        // 缩小范围
  ReturnToProtagonist = 'A002', // 回归主角
  GroundInReality = 'A003',    // 现实锚点
  BuildFromCore = 'A004',      // 核心生长
  ShowDontTell = 'A005',       // 展示不讲述
  DialogueDrill = 'A006',      // 对话训练
  FlipPerspective = 'A007',    // 翻转拆解
  ReadingAssignment = 'A008',  // 阅读任务
}

/** 单个病症诊断结果（AI 输出格式） */
export interface SyndromeResult {
  /** 病症 ID */
  id: SyndromeId;
  /** 病症名称 */
  name: string;
  /** 严重度等级 */
  severity: SeverityLevel;
  /** 用户原文证据片段 */
  evidence: string[];
  /** 信号分（可选，用于排序） */
  score?: number;
  /** 建议教学动作 */
  suggestedActions: ActionId[];
}

/** 完整诊断条目（AI 输出格式） */
export interface DiagnosisEntry {
  /** 所属会话 ID */
  sessionId: string;
  /** 所属消息 ID */
  messageId: string;
  /** 识别到的病症列表（按严重度排序） */
  syndromes: SyndromeResult[];
  /** 合并后的建议动作列表（去重） */
  suggestedActions: ActionId[];
  /** 整体置信度（0-1） */
  confidence: number;
  /** 诊断时间戳（ISO 8601 格式） */
  timestamp: string;
  /** 下一步建议关注的病症 ID */
  nextFocus?: SyndromeId;
}

/** IPC 通道常量 */
export const IPC_CHANNELS = {
  CONFIG_GET: 'config:get',
  CONFIG_SET: 'config:set',
  CONFIG_TEST_CONNECTION: 'config:testConnection',
  DIAGNOSIS_UPDATE: 'diagnosis:update',
  DIAGNOSIS_QUERY: 'diagnosis:query',
} as const;
```

**关键说明**:
- 所有类型在 shared/types.ts 中统一定义
- 主进程和渲染进程共享使用，确保类型一致性
- 使用 enum 而非 string literal 提供编译时检查

### 6.5 IPC 监听集成

```typescript
// src/renderer/App.tsx
// 监听主进程推送的诊断结果

useEffect(() => {
  const electronAPI = (window as Window & {
    electronAPI?: {
      on: (channel: string, callback: (...args: unknown[]) => void) => (() => void);
    }
  }).electronAPI;

  if (!electronAPI) return;

  const cleanup = electronAPI.on('diagnosis:update', (data: unknown) => {
    const entry = data as DiagnosisEntry;
    setCurrentDiagnosis(entry);
    addToHistory(entry.sessionId, entry);
  });

  return cleanup;
}, [setCurrentDiagnosis, addToHistory]);
```

**关键说明**:
- 使用 useEffect 监听 IPC 事件
- 返回清理函数防止内存泄漏
- 类型安全地处理 IPC 数据

---

## 7. 数据结构与接口

### 7.1 诊断表 JSON 格式

```json
{
  "syndromes": [
    {
      "id": "P001",
      "name": "世界观膨胀",
      "severity": "L2",
      "evidence": ["用户原文片段1", "用户原文片段2"],
      "score": 4,
      "suggestedActions": ["A001", "A004"]
    }
  ],
  "actions": ["A001", "A004"],
  "confidence": 0.85,
  "nextFocus": "P002"
}
```

### 7.2 IPC 通道定义

| 通道 | 方向 | 用途 | 数据类型 |
|------|------|------|----------|
| `config:get` | 渲染 → 主 | 获取配置 | `{ key: string }` |
| `config:set` | 渲染 → 主 | 设置配置 | `{ key: string; value: any }` |
| `config:testConnection` | 渲染 → 主 | 测试连接 | `{ apiKey, baseUrl }` |
| `diagnosis:update` | 主 → 渲染 | 推送诊断结果 | `DiagnosisEntry` |
| `diagnosis:query` | 渲染 → 主 | 查询诊断历史 | `{ sessionId: string }` |

### 7.3 数据库表结构（规划中）

```sql
-- 诊断记录表
CREATE TABLE diagnosis_entries (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id TEXT NOT NULL,
  message_id TEXT NOT NULL,
  syndromes TEXT NOT NULL,  -- JSON 数组
  suggested_actions TEXT NOT NULL,  -- JSON 数组
  confidence REAL NOT NULL,
  timestamp TEXT NOT NULL,
  next_focus TEXT,
  FOREIGN KEY (session_id) REFERENCES sessions(id)
);

-- 会话表
CREATE TABLE sessions (
  id TEXT PRIMARY KEY,
  title TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
```

---

## 8. 关键技术与考虑

### 8.1 安全性

| 考虑 | 措施 |
|------|------|
| contextIsolation | 设置为 true，隔离主进程和渲染进程 |
| contextBridge | 仅暴露白名单 IPC 通道 |
| API Key 存储 | electron-store 明文存储，建议后续加密 |
| 输入验证 | 不信任 AI 输出，验证字段类型和值域 |

### 8.2 性能

| 考虑 | 措施 |
|------|------|
| 诊断表解析 | 在流结束后执行，不阻塞 UI |
| 状态更新 | Zustand 轻量级，无额外渲染 |
| 历史查询 | 按会话分组，限制查询范围 |
| 内存管理 | 组件卸载时清理 IPC 监听 |

### 8.3 可靠性

| 考虑 | 措施 |
|------|------|
| AI 未输出诊断表 | 降级为无诊断状态 |
| JSON 解析失败 | try-catch 捕获，记录警告 |
| 网络错误 | 错误处理通道（chat:error） |
| 并发诊断 | 请求队列或取消机制（规划中） |

### 8.4 可维护性

| 考虑 | 措施 |
|------|------|
| 诊断表格式 | 由 Prompt 定义，修改 Prompt 即可调整 |
| 类型定义 | 共享 types.ts，主渲染进程共用 |
| 日志记录 | 详细日志记录解析过程 |
| 文档同步 | 代码变更时同步更新文档 |

---

## 9. 风险与缓解

### 9.1 技术风险

| 风险 | 影响 | 缓解措施 | 状态 |
|------|------|---------|------|
| AI 未输出诊断表 | 诊断面板为空 | 降级为无诊断状态，记录日志 | ✅ 已处理 |
| AI 输出格式错误 | 解析失败 | try-catch 捕获，返回原始回复 | ✅ 已处理 |
| 诊断表与回复不一致 | 用户困惑 | 由 AI 同时输出，天然一致 | ✅ 已处理 |
| 历史上下文过长 | AI 上下文窗口溢出 | 限制最近 3 轮诊断 | ✅ 已规划 |
| 用户 API Key 无效 | 调用失败 | 配置界面测试连接 | ✅ 已实现 |
| 诊断引擎规则膨胀 | 维护困难 | 外部 JSON 配置加载 | 📋 规划中 |
| 并发诊断冲突 | 数据不一致 | 请求队列机制 | 📋 规划中 |

### 9.2 产品风险

| 风险 | 影响 | 缓解措施 | 状态 |
|------|------|---------|------|
| 用户不按照提示词提问 | 诊断不准确 | AI 理解上下文，不依赖固定格式 | ✅ 已处理 |
| 用户不知道自己问题 | 诊断困难 | AI 帮助识别，诊断表记录 | ✅ 已处理 |
| 教学动作优先级固定 | 不灵活 | 动态优先级，结合信号分 | 📋 规划中 |
| 跨轮次诊断缺失 | 漏诊 | analyzeSession 函数（规划中） | 📋 规划中 |

---

## 10. 附录：规则体系

### 10.1 规则分层

| 层级 | alwaysApply | 说明 | 示例 |
|------|-------------|------|------|
| L1 | true | 核心规则，始终生效 | R-004 准出标准, R-009 用户主权 |
| L2 | false | 关键节点规则，特定时刻检查 | R-001 原子化, R-016 Git规范 |
| L3 | false | 智能触发规则，条件满足时激活 | R-006 回退机制, R-012 假设驱动 |

### 10.2 核心规则列表

| 编号 | 名称 | 优先级 | 说明 |
|------|------|--------|------|
| R-001 | 原子化与状态管理 | High | 将复杂更改分解为最小原子单元 |
| R-002 | 依赖锁定机制 | High | 启动前检查上游依赖状态 |
| R-003 | 里程碑节点管理 | High | 阶段结束时设置里程碑 |
| R-004 | 准出标准（DoD） | Medium | 每个阶段前定义完成标准 |
| R-005 | 全流程文档化 | Medium | 代码中包含逻辑解释 |
| R-006 | 回退机制规范 | High | 每次改动前必须有回退路径 |
| R-007 | 双向绑定 | Medium | 前后端状态保持一致 |
| R-008 | 文档同步准则 | High | 文档与代码保持同步 |
| R-009 | 用户主权 | Highest | 用户指令优先于所有规则 |
| R-010 | 最小化范围 | Medium | 变更范围最小化 |
| R-011 | 记忆强化 | High | 重要信息持久化记录 |
| R-012 | 假设驱动开发 | Medium | 变更前提出假设并验证 |
| R-013 | 测试覆盖率 | High | 新增功能有测试覆盖 |
| R-014 | 配置外置规范 | Medium | 禁止硬编码业务映射表 |
| R-015 | AI 协作规范 | High | 定义 AI 何时使用 sub-agent |
| R-016 | Git 提交规范 | Medium | 提交信息遵循约定格式 |
| R-017 | 文档与报告管理 | Medium | 统一文档分类和版本控制 |

---

**文档版本历史**

| 版本 | 日期 | 变更内容 | 变更人 |
|------|------|---------|--------|
| V1.0 | 2026-06-01 | 初始版本，整合所有项目文档为单一参考手册 | AI 助手 |
