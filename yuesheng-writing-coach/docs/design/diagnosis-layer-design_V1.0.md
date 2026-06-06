# 月笙写作教练 - 诊断层技术设计文档

**版本**: V1.0  
**创建日期**: 2026-06-01  
**状态**: draft  
**关联文档**: [PRD_V1.0.md](../PRD_V1.0.md), [frontend-design_V1.0.md](./frontend-design_V1.0.md)

---

## 目录

1. [方案对比总结](#1-方案对比总结)
2. [技术架构](#2-技术架构)
3. [完整工作流](#3-完整工作流)
4. [核心代码实现](#4-核心代码实现)
5. [数据结构定义](#5-数据结构定义)
6. [风险与缓解](#6-风险与缓解)

---

## 1. 方案对比总结

### 1.1 诊断方案演进

| 方案 | 诊断主体 | 优点 | 缺点 | 状态 |
|------|---------|------|------|------|
| **规则引擎诊断** | diagnosis-engine.ts | 速度快、成本低、可控 | 硬编码误判率高、不理解上下文 | ❌ 已放弃 |
| **规则引擎 + AI** | 规则引擎先诊断，AI 参考 | 减少 AI 依赖 | 规则引擎误判会误导 AI | ❌ 已放弃 |
| **纯 AI 诊断** | AI 输出结构化诊断表 | 理解上下文、准确率高 | 依赖 AI 稳定性、成本略高 | ✅ 最终方案 |

### 1.2 关键决策点

| 决策 | 选项 | 选择 | 理由 |
|------|------|------|------|
| 诊断主体 | 规则引擎 vs AI | AI | 规则引擎无法理解上下文，误判率高 |
| 诊断表格式 | 自由文本 vs JSON | JSON | 结构化数据便于存储、查询、展示 |
| 解析方式 | 标记截取 vs API 返回 | 标记截取 | 兼容现有 API，无需修改 |
| 历史参考 | 无 vs 最近 N 轮 | 最近 3 轮 | 按图索骥需要上下文 |

### 1.3 目标对齐

| 目标 | 方案对齐度 | 说明 |
|------|-----------|------|
| AI 按图索骥教学 | ✅ 完全对齐 | 诊断表记录用户问题，AI 后续对话参考 |
| 诊断书与 AI 回复同步 | ✅ 完全对齐 | 诊断表由 AI 同时输出，天然一致 |
| 布置习作 | ✅ 完全对齐 | 诊断表包含建议动作，可映射到训练任务 |
| 用户成长轨迹 | ✅ 完全对齐 | 诊断表存储到数据库，可追踪进步 |

---

## 2. 技术架构

### 2.1 整体架构

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

### 2.2 技术栈

| 层 | 技术 | 说明 |
|---|------|------|
| 框架 | Electron 28+ | 桌面应用框架 |
| 语言 | TypeScript (strict) | 类型安全 |
| 前端 | React + Vite + Tailwind CSS | UI 渲染 |
| 状态 | Zustand | 轻量级状态管理 |
| 存储 | electron-store + better-sqlite3 | 配置 + 数据 |
| 模型 | DPV4（用户自备 API Key） | AI 推理 |
| 通信 | IPC（contextIsolation + contextBridge） | 主渲染进程通信 |

### 2.3 关键技术考虑

| 考虑 | 方案 |
|------|------|
| 安全性 | contextIsolation=true, 仅暴露白名单 IPC 通道 |
| 性能 | 诊断表解析在流结束后执行，不阻塞 UI |
| 可靠性 | AI 未输出诊断表时降级为无诊断状态 |
| 可维护性 | 诊断表格式由 Prompt 定义，修改 Prompt 即可调整 |

---

## 3. 完整工作流

### 3.1 用户交互流程

```
1. 用户发送消息
   ↓
2. 渲染进程通过 IPC 发送消息到主进程
   ↓
3. 主进程调用 AI（含 System Prompt + 历史诊断上下文）
   ↓
4. AI 生成回复（末尾带诊断表 JSON）
   ↓
5. 主进程解析 AI 回复：
   - 截取诊断表 JSON
   - 分离纯净回复
   ↓
6. 主进程推送两部分：
   - 回复内容 → 聊天界面
   - 诊断表 → DiagnosisPanel
   ↓
7. Zustand store 更新
   ↓
8. UI 自动刷新展示
```

### 3.2 诊断表存储流程

```
1. 解析出 DiagnosisEntry
   ↓
2. 存储到 SQLite 数据库（diagnosis_entries 表）
   ↓
3. 更新 Zustand store（当前诊断 + 历史记录）
   ↓
4. 推送 IPC 事件到渲染进程
   ↓
5. 渲染进程更新 DiagnosisPanel
```

### 3.3 里程碑节点

| 阶段 | 里程碑 | 交付物 | 状态 |
|------|--------|--------|------|
| M1 | 环境配置 | API 配置界面 + 测试连接 | ✅ 已完成 |
| M2 | 诊断层基础 | 诊断表格式 + AI Prompt + 解析器 | 进行中 |
| M3 | 诊断 UI | DiagnosisPanel 组件 + IPC 集成 | ✅ 已完成 |
| M4 | 聊天集成 | 聊天界面 + 诊断表解析 + 推送 | 待开发 |
| M5 | 历史诊断 | SQLite 存储 + 按图索骥 | 待开发 |
| M6 | 训练任务 | 诊断→任务映射 + 任务推荐 | 待开发 |

---

## 4. 核心代码实现

### 4.1 诊断表解析器

```typescript
// src/main/services/diagnosis-parser.ts
// 负责：解析 AI 回复中的诊断表 JSON

/**
 * 解析 AI 回复中的诊断表
 * 
 * AI 回复格式：
 * 你的问题在于...
 * 
 * ---DIAGNOSIS_START---
 * {"syndromes": [...], "actions": [...], "confidence": 0.85}
 * ---DIAGNOSIS_END---
 * 
 * @param fullResponse - AI 完整回复（含诊断表）
 * @returns 纯净回复 + 诊断表对象
 */
export function parseDiagnosisFromAIResponse(
  fullResponse: string,
  sessionId: string,
  messageId: string,
): { cleanResponse: string; diagnosis: DiagnosisEntry | null } {
  // 正则匹配诊断表标记
  const match = fullResponse.match(
    /---DIAGNOSIS_START---\n([\s\S]*?)\n---DIAGNOSIS_END---/
  );
  
  if (!match) {
    // AI 未输出诊断表时，返回原始回复 + null 诊断
    return { cleanResponse: fullResponse, diagnosis: null };
  }
  
  try {
    const diagnosisJson = JSON.parse(match[1]);
    // 移除诊断表标记，得到纯净回复
    const cleanResponse = fullResponse.replace(match[0], '').trim();
    
    // 构建 DiagnosisEntry 对象
    const diagnosis: DiagnosisEntry = {
      sessionId,
      messageId,
      syndromes: diagnosisJson.syndromes || [],
      suggestedActions: diagnosisJson.actions || [],
      confidence: diagnosisJson.confidence || 0,
      timestamp: new Date().toISOString(),
    };
    
    return { cleanResponse, diagnosis };
  } catch (error) {
    // JSON 解析失败时，记录警告并返回原始回复
    console.warn('[DiagnosisParser] Failed to parse diagnosis JSON:', error);
    return { cleanResponse: fullResponse, diagnosis: null };
  }
}
```

### 4.2 聊天服务集成

```typescript
// src/main/services/chat.service.ts
// 负责：调用 AI、解析诊断、推送结果

import { parseDiagnosisFromAIResponse } from './diagnosis-parser';
import { ipcMain, BrowserWindow } from 'electron';

/**
 * 处理用户消息，调用 AI 并推送结果
 * 
 * @param text - 用户消息
 * @param sessionId - 会话 ID
 * @param messageId - 消息 ID
 * @param mainWindow - 主窗口引用
 */
export async function handleChatMessage(
  text: string,
  sessionId: string,
  messageId: string,
  mainWindow: BrowserWindow,
): Promise<void> {
  // 1. 获取历史诊断上下文
  const historyContext = getDiagnosisHistory(sessionId);
  
  // 2. 构建 System Prompt（含诊断表输出指令）
  const systemPrompt = buildSystemPrompt(historyContext);
  
  // 3. 调用 AI（流式输出）
  const fullResponse = await callAI(systemPrompt, text);
  
  // 4. 解析诊断表
  const { cleanResponse, diagnosis } = parseDiagnosisFromAIResponse(
    fullResponse,
    sessionId,
    messageId,
  );
  
  // 5. 推送回复到聊天界面
  mainWindow.webContents.send('chat:response', {
    messageId,
    content: cleanResponse,
  });
  
  // 6. 推送诊断到诊断面板
  if (diagnosis) {
    mainWindow.webContents.send('diagnosis:update', diagnosis);
    // 存储到数据库
    saveDiagnosisToDatabase(diagnosis);
  }
}
```

### 4.3 System Prompt 构建

```typescript
// 构建 System Prompt（含诊断表输出指令）
function buildSystemPrompt(historyContext: string): string {
  return `
你是月笙，一个 AI 写作教练。你的定位是：
- 不替用户写 — 只给示范，不替完成
- 不替用户决定 — 给选择，不给答案
- 帮用户看清问题，让用户自己解决

## 病症识别手册
${loadSyndromeManual()}

## 教学动作库
${loadActionLibrary()}

## 诊断表输出要求
请在每次回复末尾输出诊断表，格式如下：

---DIAGNOSIS_START---
{
  "syndromes": [
    {
      "id": "P001",
      "name": "世界观膨胀",
      "severity": "L2",
      "evidence": ["用户原文片段"],
      "score": 4
    }
  ],
  "actions": ["A001"],
  "confidence": 0.85,
  "nextFocus": "P002"
}
---DIAGNOSIS_END---

${historyContext ? `## 历史诊断上下文\n${historyContext}` : ''}
`;
}
```

### 4.4 Zustand Store 监听

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

---

## 5. 数据结构定义

### 5.1 DiagnosisEntry

```typescript
interface DiagnosisEntry {
  /** 所属会话 ID */
  sessionId: string;
  /** 所属消息 ID */
  messageId: string;
  /** 识别到的病症列表 */
  syndromes: SyndromeResult[];
  /** 建议教学动作（去重） */
  suggestedActions: ActionId[];
  /** 整体置信度（0-1） */
  confidence: number;
  /** 诊断时间戳 */
  timestamp: string;
}

interface SyndromeResult {
  /** 病症 ID */
  id: SyndromeId;
  /** 病症名称 */
  name: string;
  /** 严重度等级 */
  severity: SeverityLevel;
  /** 用户原文证据 */
  evidence: string[];
  /** 信号分（可选） */
  score?: number;
}
```

### 5.2 病症 ID 枚举

```typescript
enum SyndromeId {
  WorldviewBloat = 'P001',  // 世界观膨胀
  CharacterTool = 'P002',   // 角色工具人化
  EmotionLabeling = 'P003', // 情绪标签化
  InfoDumping = 'P004',     // 信息硬塞
  PerspectiveDrift = 'P005', // 视角漂移
  PacingStagnation = 'P006', // 节奏停滞
  ReadingStructureSingle = 'P007', // 阅读结构单一
}
```

---

## 6. 风险与缓解

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| AI 未输出诊断表 | 诊断面板为空 | 降级为无诊断状态，记录日志 |
| AI 输出格式错误 | 解析失败 | try-catch 捕获，返回原始回复 |
| 诊断表与回复不一致 | 用户困惑 | 由 AI 同时输出，天然一致 |
| 历史上下文过长 | AI 上下文窗口溢出 | 限制最近 3 轮诊断 |
| 用户 API Key 无效 | 调用失败 | 配置界面测试连接 |

---

**文档版本历史**

| 版本 | 日期 | 变更内容 | 变更人 |
|------|------|---------|--------|
| V1.0 | 2026-06-01 | 初始版本 | AI 助手 |
