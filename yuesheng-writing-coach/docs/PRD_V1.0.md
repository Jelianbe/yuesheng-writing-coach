# 月笙 (Yue Sheng) — 产品需求文档 (PRD)

> **文档版本**：V1.0  
> **生成日期**：2026-05-31  
> **项目阶段**：提示词工程完成 → 产品工程启动  
> **目标模型**：DPV4（用户自备 API Key，即 DeepSeek V4 系列模型，兼容 OpenAI API 格式，通过 `https://api.deepseek.com/v1` 接入，模型名填写 `deepseek-chat`）  
> **技术选型**：Electron + TypeScript + React + Vite

---

## 目录

1. [项目背景与目标](#1-项目背景与目标)
2. [技术需求](#2-技术需求)
3. [竞品分析](#3-竞品分析)
4. [技术调研与模块选型](#4-技术调研与模块选型)
5. [开发环境规范](#5-开发环境规范)
6. [产品架构](#6-产品架构)
7. [功能模块设计](#7-功能模块设计)
8. [成功指标与验收标准](#8-成功指标与验收标准)
9. [里程碑与排期](#9-里程碑与排期)

---

## 1. 项目背景与目标

### 1.1 背景

**月笙** 是一个基于大语言模型的 AI 写作教练系统，定位为**"教练"而非"助手"**：

- **不替用户写** — 只给示范，不替完成
- **不替用户决定** — 给选择，不给答案
- **帮用户看清问题，让用户自己解决**

**第一性原理**：找根因，不是找错误。治根因，表象自然消失。

**目标用户**：网文/小说创作者，从新手到有一定基础的作者。

**提示词工程已完成**：
- Prompt V3.0（约 2100 字，铁三角 + 参考抽屉结构）
- 教学动作库 A001-A008（共 8 种动作）
- 病症识别手册 P001-P007（共 7 种病症）
- 训练任务库 T001-T014
- 28 个测试点验证完成（病症识别 100%，动作触发 96.4%）

**提示词工程到这里已结束，当前进入产品工程阶段。**

### 1.2 项目目标

| 目标 | 描述 |
|------|------|
| **核心目标** | 将月笙 Prompt 体系产品化，让用户能够通过桌面应用与 AI 进行写作辅导对话 |
| **MVP 目标** | 提供最小可用的聊天界面 + API 接入 + Prompt 注入 + 基础诊断书展示 |
| **体验目标** | 对话流畅自然，诊断结果清晰可见，用户能直观看到月笙的教学过程 |

### 1.3 项目范围

#### MVP 包含（Phase 1）

| 功能模块 | 说明 | 优先级 |
|---------|------|--------|
| API 配置 | 用户输入 API Key / Base URL / 模型名称 | P0 |
| 聊天界面 | 支持文字对话，Markdown 渲染 | P0 |
| System Prompt 注入 | 将 V3.0 Prompt 作为系统提示词 | P0 |
| 会话管理 | 保存对话历史，跨轮次保持状态 | P0 |
| 诊断书展示 | 识别到的病症、严重度、建议动作 | P0 |
| 态度档位控制 | 豆包🟢 / 月笙如歌 手动切换 | P0 |
| 参考文件管理 | 动作库、病症手册等文件的加载 | P1 |
| 训练任务库 | T001-T014 任务列表与进度追踪 | P1 |

#### MVP 不包含（Phase 2+）

| 功能 | 说明 | 计划阶段 |
|------|------|---------|
| Sensei 模式🔴 | 处理自我感动型/反复辩驳型用户 | Phase 2 |
| 长期记忆 | 跨会话状态保持 | Phase 2 |
| 盲测验证系统 | 独立验证训练任务生成能力 | Phase 1.5 |
| 情绪识别模块 | 情绪安抚话术 | Phase 2 |
| 多人协作 | 多用户支持 | Phase 3 |

### 1.4 成功指标

| 指标 | 目标值 | 测量方式 |
|------|--------|---------|
| 首次对话成功率 | ≥ 90% | API 调用成功率 |
| 对话响应延迟 | ≤ 3 秒（P50）/ ≤ 8 秒（P95） | 计时统计 |
| 诊断准确率 | ≥ 90% | 与 Prompt V3.0 验证结果对齐 |
| 用户任务完成率 | ≥ 70% | 训练任务完成追踪 |
| 会话中断恢复率 | ≥ 85% | 异常中断后恢复对话的成功率 |

---

## 2. 技术需求

### 2.1 整体架构

```
┌─────────────────────────────────────────────────────────┐
│                        Electron Shell                    │
├─────────────────────────────────────────────────────────┤
│  Main Process (Node.js)                                  │
│  ├── API Proxy & Rate Limiting                           │
│  ├── Session Storage (SQLite)                            │
│  ├── Reference File Manager                              │
│  └── IPC Bridge (Main ↔ Renderer)                        │
├─────────────────────────────────────────────────────────┤
│  Renderer Process (React + TypeScript)                   │
│  ├── Chat UI Component                                   │
│  ├── Diagnosis Panel (诊断书)                            │
│  ├── API Config Panel                                    │
│  ├── Reference File Browser                              │
│  ├── Training Task Manager                               │
│  └── Settings Panel                                      │
├─────────────────────────────────────────────────────────┤
│  Preload Script                                          │
│  └── Secure IPC Bridge (contextBridge)                   │
└─────────────────────────────────────────────────────────┘
```

### 2.2 Electron 框架集成

#### 版本要求

| 组件 | 版本 | 说明 |
|------|------|------|
| Electron | `^28.0.0` | 使用 V8 引擎，支持最新 Web 标准 |
| electron-builder | `^24.0.0` | 打包与发布 |
| electron-store | `^9.0.0` | 本地持久化存储 |
| sqlite3 | `^5.1.7` | 本地数据库（对话记录、诊断历史） |

#### 项目结构

```
yuesheng/
├── package.json
── electron.vite.config.ts
├── src/
│   ├── main/
│   │   ├── index.ts                  # Electron 主进程入口
│   │   ├── api-proxy.ts              # API 代理与请求管理
│   │   ├── session-manager.ts        # 会话管理
│   │   ├── diagnosis-engine.ts       # 诊断书引擎（后台预处理）
│   │   ├── reference-manager.ts      # 参考文件管理
│   │   └── ipc-handlers.ts           # IPC 处理器注册
│   ├── preload/
│   │   └── index.ts                  # 安全预加载脚本
│   └── renderer/
│       ├── App.tsx                   # React 根组件
│       ├── components/
│       │   ├── chat/                 # 聊天相关组件
│       │   ├── diagnosis/            # 诊断书组件
│       │   ├── config/               # 配置面板
│       │   ├── tasks/                # 训练任务组件
│       │   └── common/               # 通用组件
│       ├── pages/
│       │   ├── ChatPage.tsx          # 主聊天页面
│       │   ├── SettingsPage.tsx      # 设置页面
│       │   └── TasksPage.tsx         # 训练任务页面
│       ├── stores/                   # 状态管理
│       ├── services/                 # 业务逻辑服务
│       └── styles/                   # 全局样式
├── resources/
│   ├── prompts/
│   │   ├── yuesheng-prompt-v3.md     # 主 Prompt
│   │   ├── action-library.md         # 教学动作库
│   │   ├── syndrome-manual.md        # 病症识别手册
│   │   └── training-tasks.md         # 训练任务库
│   └── icons/                        # 应用图标
├── build/                            # 构建输出
└── dist/                             # 打包输出
```

#### 主进程职责

| 职责 | 说明 |
|------|------|
| **窗口管理** | 创建主窗口，管理窗口尺寸、最小化、关闭行为 |
| **API 代理** | 转发请求到用户配置的 API 端点，支持流式输出 |
| **会话存储** | 将对话历史写入 SQLite 数据库 |
| **诊断引擎** | 后台对 AI 响应进行诊断分析，生成诊断书 |
| **文件管理** | 读取并缓存参考文件，按需提供给 AI |
| **系统菜单** | 应用菜单（关于、检查更新、偏好设置） |

#### IPC 通道定义

| 通道名 | 方向 | 参数 | 返回 | 说明 |
|--------|------|------|------|------|
| `chat:send` | R→M | `{ message: string, sessionId: string }` | Stream | 发送消息到 AI |
| `chat:stream:data` | M→R | `{ chunk: string }` | - | 流式数据到达 |
| `chat:stream:end` | M→R | `{ fullResponse: string }` | - | 流式数据结束 |
| `session:list` | R→M | - | `{ sessions: Session[] }` | 获取会话列表 |
| `session:create` | R→M | - | `{ sessionId: string }` | 创建新会话 |
| `session:delete` | R→M | `{ sessionId: string }` | - | 删除会话 |
| `config:get` | R→M | - | `Config` | 获取 API 配置 |
| `config:save` | R→M | `Config` | - | 保存 API 配置 |
| `config:test` | R→M | - | `{ success: boolean, error?: string }` | 测试 API 连接 |
| `diagnosis:get` | R→M | `{ sessionId: string }` | `DiagnosisReport` | 获取诊断书 |
| `reference:list` | R→M | - | `ReferenceFile[]` | 列出参考文件 |
| `reference:read` | R→M | `{ fileName: string }` | `string` | 读取参考文件内容 |
| `tasks:list` | R→M | - | `TrainingTask[]` | 获取训练任务列表 |
| `tasks:progress` | R→M | `{ taskId: string, progress: number }` | - | 更新任务进度 |

#### 窗口配置

```typescript
// src/main/index.ts 窗口配置
const mainWindowConfig: BrowserWindowConstructorOptions = {
  width: 1200,
  height: 800,
  minWidth: 900,
  minHeight: 600,
  backgroundColor: '#1a1a2e',
  titleBarStyle: process.platform === 'darwin' ? 'hiddenInset' : 'default',
  frame: process.platform !== 'darwin',
  webPreferences: {
    preload: path.join(__dirname, '../preload/index.js'),
    contextIsolation: true,
    nodeIntegration: false,
    sandbox: true,
    devTools: import.meta.env.DEV,
  },
};
```

### 2.3 TypeScript 实现规范

#### TypeScript 配置

```json
// tsconfig.json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true,
    "isolatedModules": true,
    "jsx": "react-jsx",
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noImplicitReturns": true,
    "noFallthroughCasesInSwitch": true,
    "paths": {
      "@/*": ["./src/renderer/*"],
      "@main/*": ["./src/main/*"],
      "@shared/*": ["./src/shared/*"]
    }
  }
}
```

#### 核心类型定义

```typescript
// src/shared/types.ts

// ========== 配置类型 ==========
export interface ApiConfig {
  apiKey: string;
  baseUrl: string;       // 默认: "https://api.deepseek.com/v1"
  modelName: string;     // 默认: "deepseek-chat" 或用户指定
  temperature: number;   // 默认: 0.7
  maxTokens: number;     // 默认: 4096
}

// ========== 会话类型 ==========
export interface Session {
  id: string;
  title: string;
  createdAt: number;     // Unix timestamp
  updatedAt: number;
  attitudeLevel: 'doubao' | 'yuesheng';  // 🟢 or 🟡
  messages: Message[];
}

export interface Message {
  id: string;
  role: 'system' | 'user' | 'assistant';
  content: string;
  timestamp: number;
  diagnosis?: DiagnosisEntry;  // 助手消息附带诊断信息
}

// ========== 诊断类型 ==========
export interface DiagnosisEntry {
  syndromes: SyndromeMatch[];    // 识别到的病症
  suggestedActions: Action[];    // 建议动作
  severity: 'mild' | 'moderate' | 'severe';
  confidence: number;            // 0-1 置信度
}

export interface SyndromeMatch {
  id: string;      // "P001" ~ "P007"
  name: string;    // "世界观膨胀"
  score: number;   // 信号总分
  severity: 'L1' | 'L2' | 'L3';
  signals: string[];  // 触发的信号描述
}

export interface Action {
  id: string;      // "A001" ~ "A008"
  name: string;    // "缩小范围"
  description: string;
  priority: number;
}

// ========== 训练任务类型 ==========
export interface TrainingTask {
  id: string;      // "T001" ~ "T014"
  name: string;
  description: string;
  syndrome: string;  // 对应病症编号
  difficulty: 'easy' | 'medium' | 'hard';
  forbiddenWords: string[];
  sceneRequirement: string;
  wordLimit: number;
  evaluationCriteria: string[];
  progress: number;  // 0-100
  status: 'pending' | 'in_progress' | 'completed';
}

// ========== 参考文件类型 ==========
export interface ReferenceFile {
  fileName: string;
  displayName: string;
  category: 'prompt' | 'action' | 'syndrome' | 'task' | 'case' | 'other';
  content?: string;   // 加载后填充
  size: number;       // 字节数
}
```

#### 诊断引擎实现

诊断书不能仅靠 Prompt 实现，需要后台代码辅助：

```typescript
// src/main/diagnosis-engine.ts

import { Message, DiagnosisEntry, SyndromeMatch, Action } from '../shared/types';

// 病症信号权重表（来自病症识别手册 V1.0）
const SYNDROME_SIGNALS: Record<string, { keyword: string; weight: number; pattern?: RegExp }[]> = {
  P001: [  // 世界观膨胀
    { keyword: '世界观', weight: 1, pattern: /世界观|设定|世界|大陆|种族|门派/ },
    { keyword: '主角未确定', weight: 2, pattern: /主角没确定|主角还没|还没确定主角/ },
    { keyword: '设定太多', weight: 1, pattern: /设定太多|设定太杂|世界观太/ },
  ],
  P002: [  // 角色工具人化
    { keyword: 'NPC感', weight: 2, pattern: /没有人味|像NPC|工具人/ },
    { keyword: '无动机', weight: 2, pattern: /不知道为什么要|不知道为什么/ },
  ],
  P003: [  // 情绪标签化
    { keyword: '情绪词', weight: 1, pattern: /紧张|害怕|难过|愤怒|开心|惊讶/ },
    { keyword: '无描写', weight: 2, pattern: /没有描写|缺乏细节/ },
  ],
  P004: [  // 信息硬塞
    { keyword: '说明句', weight: 1, pattern: /分为|是\/指|在XX的世界里/ },
    { keyword: '怕看不懂', weight: 1, pattern: /怕读者看不懂|怕读者不明白/ },
  ],
  P005: [  // 视角漂移
    { keyword: '全知描写', weight: 2, pattern: /大家都|众人|所有人|每个人/ },
    { keyword: '视角混乱', weight: 2, pattern: /视角混乱|视角切换/ },
  ],
  P006: [  // 节奏停滞
    { keyword: '无冲突', weight: 2, pattern: /没有冲突|没有钩子|没有推进/ },
    { keyword: '背景过多', weight: 1, pattern: /背景介绍|背景描述/ },
  ],
  P007: [  // 阅读结构单一
    { keyword: '只读网文', weight: 2, pattern: /只读网文|只读|读得乱/ },
    { keyword: '仿写网文', weight: 1, pattern: /仿照|仿写/ },
  ],
};

// 动作映射表
const ACTION_MAP: Record<string, string[]> = {
  P001: ['A001'],
  P002: ['A004'],
  P003: ['A004'],
  P004: ['A002'],
  P005: ['A002'],
  P006: ['A005'],
  P007: ['A008'],
};

// 动作优先级（多病症时按此顺序处理）
const ACTION_PRIORITY: Record<string, number> = {
  P004: 1,  // 信息硬塞（最高优先级）
  P006: 2,  // 节奏停滞
  P005: 3,  // 视角漂移
  P003: 4,  // 情绪标签化
  P001: 5,  // 世界观膨胀
  P002: 6,  // 角色工具人化
  P007: 7,  // 阅读结构单一
};

/**
 * 分析用户消息，生成诊断条目
 */
export function analyzeMessage(content: string): DiagnosisEntry | null {
  const matches: SyndromeMatch[] = [];

  for (const [syndromeId, signals] of Object.entries(SYNDROME_SIGNALS)) {
    let totalScore = 0;
    const triggeredSignals: string[] = [];

    for (const signal of signals) {
      if (signal.pattern && signal.pattern.test(content)) {
        totalScore += signal.weight;
        triggeredSignals.push(signal.keyword);
      }
    }

    if (totalScore >= 2) {
      const severity = totalScore >= 5 ? 'L3' : totalScore >= 3 ? 'L2' : 'L1';
      matches.push({
        id: syndromeId,
        name: getSyndromeName(syndromeId),
        score: totalScore,
        severity,
        signals: triggeredSignals,
      });
    }
  }

  if (matches.length === 0) return null;

  // 排序：优先级高的在前，最多保留 2 个
  matches.sort((a, b) => (ACTION_PRIORITY[a.id] || 99) - (ACTION_PRIORITY[b.id] || 99));
  const topMatches = matches.slice(0, 2);

  // 生成建议动作
  const actions = topMatches.flatMap(m =>
    (ACTION_MAP[m.id] || []).map(id => ({
      id,
      name: getActionName(id),
      description: getActionDescription(id),
      priority: ACTION_PRIORITY[m.id] || 99,
    }))
  );

  // 计算整体严重度
  const maxScore = Math.max(...matches.map(m => m.score));
  const severity = maxScore >= 5 ? 'severe' : maxScore >= 3 ? 'moderate' : 'mild';

  return {
    syndromes: topMatches,
    suggestedActions: actions,
    severity,
    confidence: Math.min(maxScore / 5, 1.0),
  };
}

// Helper functions
function getSyndromeName(id: string): string {
  const map: Record<string, string> = {
    P001: '世界观膨胀', P002: '角色工具人化', P003: '情绪标签化',
    P004: '信息硬塞', P005: '视角漂移', P006: '节奏停滞', P007: '阅读结构单一',
  };
  return map[id] || id;
}

function getActionName(id: string): string {
  const map: Record<string, string> = {
    A001: '缩小范围', A002: '回归主角', A003: '五问法',
    A004: '现实锚点', A005: '阶段拆分', A006: '对比展示',
    A007: '翻转拆解', A008: '阅读锚点拓展',
  };
  return map[id] || id;
}

function getActionDescription(id: string): string {
  const map: Record<string, string> = {
    A001: '把用户从宏大设定拉回具体场景',
    A002: '从上帝视角回到角色眼睛',
    A003: '用连续追问理清因果链',
    A004: '从"编故事"回到"真人会怎么做"',
    A005: '把大目标拆成可执行的小阶段',
    A006: '用事实对比替代辩论',
    A007: '把困境变成线索',
    A008: '给阅读任务而非书单',
  };
  return map[id] || '';
}
```

#### API 通信模块

```typescript
// src/main/api-proxy.ts

import { ApiConfig } from '../shared/types';

export interface ChatMessage {
  role: 'system' | 'user' | 'assistant';
  content: string;
}

export class ApiProxy {
  private config: ApiConfig;

  constructor(config: ApiConfig) {
    this.config = config;
  }

  async *chatStream(
    messages: ChatMessage[],
    abortSignal?: AbortSignal
  ): AsyncGenerator<string> {
    const response = await fetch(`${this.config.baseUrl}/chat/completions`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${this.config.apiKey}`,
      },
      body: JSON.stringify({
        model: this.config.modelName,
        messages,
        temperature: this.config.temperature,
        max_tokens: this.config.maxTokens,
        stream: true,
      }),
      signal: abortSignal,
    });

    if (!response.ok) {
      const error = await response.text();
      throw new Error(`API Error: ${response.status} ${error}`);
    }

    const reader = response.body?.getReader();
    if (!reader) throw new Error('No response body');

    const decoder = new TextDecoder();
    let buffer = '';

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;

      buffer += decoder.decode(value, { stream: true });
      const lines = buffer.split('\n');
      buffer = lines.pop() || '';

      for (const line of lines) {
        if (line.startsWith('data: ')) {
          const data = line.slice(6);
          if (data === '[DONE]') return;

          try {
            const parsed = JSON.parse(data);
            const content = parsed.choices?.[0]?.delta?.content;
            if (content) yield content;
          } catch {
            // Ignore malformed JSON chunks
          }
        }
      }
    }
  }

  async testConnection(): Promise<{ success: boolean; error?: string }> {
    try {
      const response = await fetch(`${this.config.baseUrl}/models`, {
        headers: { 'Authorization': `Bearer ${this.config.apiKey}` },
      });
      if (!response.ok) {
        return { success: false, error: `HTTP ${response.status}` };
      }
      return { success: true };
    } catch (e) {
      return { success: false, error: (e as Error).message };
    }
  }
}
```

### 2.4 技术流程文档

#### 流程 1：用户发送消息

```
用户输入 → 渲染进程发送 chat:send IPC
    → 主进程接收消息
    → 读取历史会话 + 注入 System Prompt
    → 调用 ApiProxy.chatStream()
    → 流式返回 chunks 给渲染进程
    → 渲染进程实时显示
    → 流结束后，主进程调用 diagnosisEngine.analyzeMessage()
    → 生成诊断条目并附加到消息
    → 保存到 SQLite 数据库
```

#### 流程 2：诊断书生成

```
AI 回复完成 → diagnosisEngine.analyzeMessage(content)
    → 扫描用户消息，匹配病症信号
    → 计算总分，判断严重度
    → 生成建议动作列表
    → 返回 DiagnosisEntry
    → 渲染进程在诊断面板展示
```

#### 流程 3：会话恢复

```
应用启动 → 从 SQLite 读取最近会话列表
    → 用户选择会话
    → 加载完整消息历史
    → 恢复 System Prompt + 对话上下文
    → 继续对话
```

---

## 3. 竞品分析

### 3.1 竞品识别

基于写作辅导领域的产品现状，选取以下三款技术产品进行分析：

| 竞品 | 类型 | 平台 | 核心定位 |
|------|------|------|---------|
| **NovelAI** | AI 写作辅助 | Web | AI 驱动的创意写作平台 |
| **Sudowrite** | AI 写作教练 | Web | 面向小说作者的 AI 写作工具 |
| **ChatGPT Custom GPT (写作类)** | 通用 AI | Web/移动端 | 用户自定义的写作助手 |

### 3.2 竞品分析详情

#### 竞品 A：NovelAI

| 维度 | 分析 |
|------|------|
| **核心功能** | AI 续写、故事编辑、风格模仿、世界构建助手 |
| **技术特点** | 自研模型（基于 GPT 微调），流式生成，本地化存储 |
| **优势** | 模型针对小说创作优化，支持长篇续写，风格一致性好 |
| **劣势** | 付费墙高，定位偏"替用户写"而非"教用户写" |
| **可借鉴点** | 世界构建助手的交互模式、流式输出的 UI 体验 |
| **差异化策略** | 月笙定位为"教练"而非"代写"，核心差异是"不给句子给方向" |

#### 竞品 B：Sudowrite

| 维度 | 分析 |
|------|------|
| **核心功能** | 描写扩展（Describe）、头脑风暴（Brainstorm）、改写（Rewrite）、情节建议 |
| **技术特点** | 基于 GPT-4，多按钮交互模式，上下文感知的生成 |
| **优势** | 功能丰富，按钮式交互降低使用门槛 |
| **劣势** | 偏向"帮写"，缺乏系统化的教学方法论 |
| **可借鉴点** | 按钮式快捷操作、描写扩展功能的设计思路 |
| **差异化策略** | 月笙用对话式教学代替按钮操作，用方法论代替功能堆叠 |

#### 竞品 C：ChatGPT Custom GPT（写作类）

| 维度 | 分析 |
|------|------|
| **核心功能** | 用户自定义 System Prompt，GPTs Store 中的写作类机器人 |
| **技术特点** | 基于 OpenAI GPT，知识库上传，Action 扩展 |
| **优势** | 零门槛创建，生态丰富 |
| **劣势** | Prompt 管理分散，无诊断反馈，无结构化教学方法 |
| **可借鉴点** | 知识库上传机制、System Prompt 管理方式 |
| **差异化策略** | 月笙提供结构化诊断书 + 训练任务追踪，这是 GPT 做不到的 |

### 3.3 功能整合建议

| 借鉴功能 | 来源 | 整合方式 | 优先级 |
|---------|------|---------|--------|
| 流式输出 UI | NovelAI | 实时显示 AI 回复，打字机效果 | P0 |
| 快捷操作按钮 | Sudowrite | 将常用动作（A001-A008）做成快捷按钮 | P1 |
| 知识库管理 | Custom GPT | 参考文件加载与管理界面 | P1 |
| 对话主题标签 | NovelAI | 自动根据对话内容生成标题 | P1 |
| 写作进度追踪 | Sudowrite | 训练任务完成度可视化 | P1 |
| 风格预设 | NovelAI | 态度档位（豆包/月笙如歌）的视觉化展示 | P0 |

### 3.4 竞争壁垒

| 壁垒 | 描述 | 竞品有无 |
|------|------|---------|
| **系统化教学方法论** | 8 种教学动作 + 7 种病症识别，基于真实教学记录 | 无 |
| **诊断书反馈** | 实时展示识别到的问题和改进方向 | 无 |
| **训练任务系统** | T001-T014 结构化训练任务 + 进度追踪 | 无 |
| **教练定位** | 不替用户写，帮用户看清问题 | 竞品多为"代写"定位 |
| **开源/本地化** | 用户自备 API，数据本地存储 | NovelAI 闭源，Sudowrite 闭源 |

---

## 4. 技术调研与模块选型

### 4.1 UI 框架选型

| 方案 | 优点 | 缺点 | 推荐度 |
|------|------|------|--------|
| **React + Tailwind CSS** | 生态丰富，组件库多，类型安全 | 需要自行组装 | ★★★★★ 推荐 |
| Vue 3 + Element Plus | 中文文档好，组件齐全 | Electron 生态不如 React | ★★★ |
| Svelte + shadcn | 体积小，性能好 | 生态相对较小 | ★★★ |

**选型**：React 18 + TypeScript + Tailwind CSS + shadcn/ui

### 4.2 状态管理

| 方案 | 适用场景 | 推荐度 |
|------|---------|--------|
| **Zustand** | 轻量级状态管理，适合中等规模应用 | ★★★★★ 推荐 |
| Redux Toolkit | 大型应用，需要严格状态流 | ★★★ |
| Jotai | 原子化状态，适合简单场景 | ★★★ |

**选型**：Zustand（轻量、API 简单、与 TypeScript 配合好）

### 4.3 Markdown 渲染

| 方案 | 特点 | 推荐度 |
|------|------|--------|
| **react-markdown + rehype** | 可定制性强，支持插件 | ★★★★★ 推荐 |
| marked-react | 简单直接 | ★★★ |

**选型**：react-markdown + rehype-highlight（代码高亮）

### 4.4 数据库

| 方案 | 特点 | 推荐度 |
|------|------|--------|
| **SQLite + better-sqlite3** | 零配置，本地文件，适合桌面应用 | ★★★★★ 推荐 |
| IndexedDB | 浏览器内建，但 Electron 中不如 SQLite | ★★ |
| LevelDB | Key-Value 存储，不适合关系查询 | ★★ |

**选型**：SQLite（对话记录、诊断历史、配置信息）

### 4.5 构建工具

| 方案 | 特点 | 推荐度 |
|------|------|--------|
| **electron-vite** | Vite 驱动，开发速度快，热更新 | ★★★★★ 推荐 |
| electron-forge | 官方推荐，配置复杂 | ★★★ |
| electron-builder 直接配置 | 需要手动配置 Webpack | ★★ |

**选型**：electron-vite

### 4.6 模块清单

| 模块 | 包名 | 版本 | 用途 |
|------|------|------|------|
| electron | electron | ^28.0.0 | 桌面应用框架 |
| react | react | ^18.2.0 | UI 框架 |
| typescript | typescript | ^5.3.0 | 类型系统 |
| vite | vite | ^5.0.0 | 构建工具 |
| tailwind | tailwindcss | ^3.4.0 | CSS 框架 |
| shadcn | @radix-ui/react-* | latest | UI 组件库 |
| zustand | zustand | ^4.5.0 | 状态管理 |
| markdown | react-markdown | ^9.0.0 | Markdown 渲染 |
| syntax highlight | rehype-highlight | ^7.0.0 | 代码高亮 |
| database | better-sqlite3 | ^9.4.0 | SQLite 驱动 |
| store | electron-store | ^9.0.0 | 配置持久化 |
| icons | lucide-react | ^0.300.0 | 图标库 |
| date | date-fns | ^3.0.0 | 日期处理 |
| uuid | uuid | ^9.0.0 | 唯一 ID 生成 |
| build | electron-builder | ^24.0.0 | 打包工具 |

---

## 5. 开发环境规范

### 5.1 完整技术栈

```
月笙写作教练 (Yue Sheng Writing Coach)
├── 运行时：Electron 28 + Node.js 20 LTS
├── 前端框架：React 18 + TypeScript 5.3
├── 构建工具：Vite 5 + electron-vite
├── 样式方案：Tailwind CSS 3.4 + shadcn/ui
├── 状态管理：Zustand 4.5
├── 数据库：SQLite + better-sqlite3
├── Markdown：react-markdown + rehype-highlight
├── 图标：Lucide React
├── 包管理：pnpm（推荐）或 npm
└── AI 模型：DPV4（用户自备 API Key）
```

### 5.2 环境要求

#### 操作系统

| 系统 | 支持情况 | 说明 |
|------|---------|------|
| Windows 10/11 | ✅ 主要支持 | 开发主力平台 |
| macOS 12+ | ✅ 支持 | 需要 macOS 开发者证书打包 |
| Ubuntu 20.04+ | ✅ 支持 | 需要 libwebkit2gtk 等依赖 |

#### 硬件要求

| 配置 | 最低 | 推荐 |
|------|------|------|
| CPU | 2 核 | 4 核+ |
| 内存 | 4 GB | 8 GB+ |
| 硬盘 | 2 GB 可用空间 | 5 GB+ |
| 网络 | 需要连接 AI API | 稳定网络 |

### 5.3 开发工具与技能

#### 必需技能

| 技能 | 要求 | 说明 |
|------|------|------|
| TypeScript | 熟练 | 核心开发语言 |
| React + Hooks | 熟练 | UI 开发 |
| Electron | 基础 | 了解主进程/渲染进程模型 |
| SQLite | 基础 | 数据持久化 |
| Tailwind CSS | 基础 | 样式开发 |

#### 推荐工具

| 工具 | 用途 | 获取方式 |
|------|------|---------|
| VS Code | 代码编辑器 | https://code.visualstudio.com/ |
| Node.js 20 LTS | JavaScript 运行时 | https://nodejs.org/ |
| pnpm | 包管理器 | `npm install -g pnpm` |
| Git | 版本控制 | https://git-scm.com/ |
| Electron Builder | 打包工具 | npm 包 |

### 5.4 环境安装步骤

#### 步骤 1：安装 Node.js

```powershell
# Windows PowerShell（管理员）
# 下载安装包
Invoke-WebRequest -Uri "https://nodejs.org/dist/v20.11.0/node-v20.11.0-x64.msi" -OutFile "node-v20.11.0-x64.msi"

# 安装
msiexec /i node-v20.11.0-x64.msi /quiet

# 验证
node --version   # 应输出 v20.11.0
npm --version    # 应输出 10.x.x
```

#### 步骤 2：安装 pnpm

```powershell
npm install -g pnpm
pnpm --version   # 验证安装
```

#### 步骤 3：初始化项目

```powershell
# 创建项目目录
cd d:\ai-teacher
mkdir yuesheng-app
cd yuesheng-app

# 初始化 pnpm 项目
pnpm init

# 安装开发依赖
pnpm add -D typescript@^5.3.0 vite@^5.0.0 @vitejs/plugin-react@^4.2.0 electron@^28.0.0 electron-builder@^24.0.0 electron-vite@^1.0.0 @electron-toolkit/tsconfig@^1.0.0 @electron-toolkit/utils@^3.0.0 cross-env@^7.0.0

# 安装生产依赖
pnpm add react@^18.2.0 react-dom@^18.2.0 @types/react@^18.2.0 @types/react-dom@^18.2.0 tailwindcss@^3.4.0 postcss@^8.4.0 autoprefixer@^10.4.0 zustand@^4.5.0 react-markdown@^9.0.0 rehype-highlight@^7.0.0 better-sqlite3@^9.4.0 electron-store@^9.0.0 lucide-react@^0.300.0 date-fns@^3.0.0 uuid@^9.0.0 @radix-ui/react-dialog@^1.0.0 @radix-ui/react-dropdown-menu@^2.0.0 @radix-ui/react-select@^2.0.0 @radix-ui/react-separator@^1.0.0 @radix-ui/react-tooltip@^1.0.0 @radix-ui/react-slot@^1.0.0 class-variance-authority@^0.7.0 clsx@^2.1.0 tailwind-merge@^2.2.0

# 安装类型定义
pnpm add -D @types/better-sqlite3 @types/uuid
```

#### 步骤 4：初始化 Tailwind CSS

```powershell
npx tailwindcss init -p
```

配置 `tailwind.config.js`：
```javascript
/** @type {import('tailwindcss').Config} */
module.exports = {
  darkMode: ['class'],
  content: ['./src/renderer/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        border: 'hsl(var(--border))',
        input: 'hsl(var(--input))',
        ring: 'hsl(var(--ring))',
        background: 'hsl(var(--background))',
        foreground: 'hsl(var(--foreground))',
      },
    },
  },
  plugins: [],
};
```

#### 步骤 5：配置 TypeScript

创建 `tsconfig.json`（内容见 2.3 节）。

#### 步骤 6：配置 Vite + Electron

创建 `electron.vite.config.ts`：
```typescript
import { resolve } from 'path';
import { defineConfig, externalizeDepsPlugin } from 'electron-vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  main: {
    plugins: [externalizeDepsPlugin()],
    build: {
      outDir: 'dist/main',
    },
  },
  preload: {
    plugins: [externalizeDepsPlugin()],
    build: {
      outDir: 'dist/preload',
    },
  },
  renderer: {
    resolve: {
      alias: {
        '@': resolve('src/renderer'),
        '@main': resolve('src/main'),
        '@shared': resolve('src/shared'),
      },
    },
    plugins: [react()],
    build: {
      outDir: 'dist/renderer',
    },
  },
});
```

#### 步骤 7：配置 package.json 脚本

```json
{
  "name": "yuesheng-writing-coach",
  "version": "1.0.0",
  "description": "月笙写作教练 - AI 驱动的写作辅导工具",
  "main": "./dist/main/index.js",
  "scripts": {
    "dev": "electron-vite dev",
    "build": "electron-vite build",
    "preview": "electron-vite preview",
    "package": "electron-builder --dir",
    "dist": "electron-builder",
    "typecheck": "tsc --noEmit"
  },
  "build": {
    "appId": "com.yuesheng.writing-coach",
    "productName": "月笙写作教练",
    "directories": {
      "output": "release"
    },
    "win": {
      "target": ["nsis"],
      "icon": "resources/icons/icon.ico"
    },
    "nsis": {
      "oneClick": false,
      "allowToChangeInstallationDirectory": true
    }
  }
}
```

#### 步骤 8：验证环境

```powershell
# 运行开发模式
pnpm dev

# 类型检查
pnpm typecheck

# 构建
pnpm build
```

如果 `pnpm dev` 能成功启动 Electron 窗口，则环境配置正确。

### 5.5 环境变量配置

创建 `.env.development`：
```
VITE_API_BASE_URL=https://api.deepseek.com/v1
VITE_DEFAULT_MODEL=deepseek-chat
VITE_APP_NAME=月笙写作教练
VITE_APP_VERSION=1.0.0
```

---

## 6. 产品架构

### 6.1 系统架构图

```
┌──────────────────────────────────────────────────────────────────┐
│                        用户界面层 (Renderer)                       │
├──────────────────────────────────────────────────────────────────┤
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────────────┐ │
│  │ 聊天页面  │  │ 诊断面板  │  │ 设置页面  │  │ 训练任务页面     │ │
│  │ ChatPage │  │Diagnosis │  │ Settings │  │  TasksPage       │ │
│  └────┬─────┘  └────┬─────  └────┬─────┘  └────────┬─────────┘ │
│       │             │             │                  │            │
│  ┌────┴─────────────┴─────────────┴──────────────────┴────────┐ │
│  │                      状态管理层 (Zustand)                    │ │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌────────────┐  │ │
│  │  │ chatStore│  │diagStore │  │configStore│  │taskStore   │  │ │
│  │  └──────────┘  └──────────┘  └──────────┘  └────────────┘  │ │
│  └──────────────────────────────┬────────────────────────────── │
├─────────────────────────────────┼────────────────────────────────┤
│                    IPC 安全桥 (Preload)                           │
├─────────────────────────────────┼────────────────────────────────┤
│                        主进程层 (Main)                            │
├─────────────────────────────────┼────────────────────────────────┤
│  ┌──────────┐  ┌──────────┐  ──────────┐  ┌──────────────────┐ │
│  │API Proxy │  │Session Mgr│  │Diagnosis │  │Reference Mgr     │ │
│  │          │  │          │  │ Engine   │  │                  │ │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────────┬─────────┘ │
│       │             │             │                  │            │
│  ┌────┴─────────────┴─────────────┴──────────────────┴────────┐ │
│  │                    SQLite 数据库                            │ │
│  │  (sessions, messages, diagnosis_history, tasks_progress)   │ │
│  └────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────┘
```

### 6.2 数据流

```
用户输入文本
    ↓
渲染进程: chatStore.sendMessage()
    ↓
IPC: chat:send → 主进程
    ↓
主进程: 构建消息列表 (System Prompt + 历史 + 新消息)
    ↓
主进程: ApiProxy.chatStream() → 流式调用 AI API
    ↓
IPC: chat:stream:data → 渲染进程 (实时显示)
    ↓
流结束 → 主进程: DiagnosisEngine.analyzeMessage()
    ↓
IPC: diagnosis:update → 渲染进程 (更新诊断面板)
    ↓
主进程: 保存到 SQLite
```

---

## 7. 功能模块设计

### 7.1 模块总览

| 模块 | 文件 | 职责 | 依赖 |
|------|------|------|------|
| API 配置 | `src/renderer/components/config/ApiConfigPanel.tsx` | API Key 管理、连接测试 | electron-store |
| 聊天界面 | `src/renderer/components/chat/ChatWindow.tsx` | 消息展示、输入、发送 | API Proxy |
| 诊断面板 | `src/renderer/components/diagnosis/DiagnosisPanel.tsx` | 病症展示、动作建议 | Diagnosis Engine |
| 会话管理 | `src/renderer/components/chat/SessionList.tsx` | 会话列表、新建、删除 | SQLite |
| 训练任务 | `src/renderer/pages/TasksPage.tsx` | 任务列表、进度追踪 | SQLite |
| 参考文件 | `src/renderer/components/reference/ReferenceBrowser.tsx` | 文件查看、搜索 | 本地文件系统 |
| 设置 | `src/renderer/pages/SettingsPage.tsx` | 应用设置、关于 | electron-store |

### 7.2 聊天界面详细设计

#### 组件结构

```
ChatPage
├── SessionList (左侧栏)
│   ├── NewSessionButton
│   ├── SessionItem[]
│   └── SessionDeleteModal
├── ChatWindow (中间主区域)
│   ├── ChatHeader (标题 + 态度档位选择)
│   ├── MessageList
│   │   ├── SystemMessage (月笙的回应)
│   │   │   ├── MarkdownRenderer
│   │   │   └── DiagnosisBadge (诊断标记)
│   │   ├── UserMessage (用户输入)
│   │   └── TypingIndicator (AI 思考中)
│   └── ChatInput
│       ├── TextArea
│       ├── SendButton
│       └── AttachFileButton (预留)
└── DiagnosisPanel (右侧栏)
    ├── SyndromeList (识别到的病症)
    │   └── SyndromeItem (名称 + 严重度 + 信号)
    ├── ActionSuggestions (建议动作)
    │   └── ActionItem (名称 + 描述)
    └── SeverityIndicator (整体严重度)
```

#### 态度档位 UI

```
┌─────────────────────────────────────┐
│  月笙写作教练                       │
│  ┌─────────┐  ┌─────────┐           │
│  │  豆包  │  │  月笙如歌│  (切换按钮) │
│  └─────────  └─────────┘           │
─────────────────────────────────────┘
```

### 7.3 诊断书面板详细设计

#### 显示内容

```
─── 诊断书 ───────────────────────────┐
│                                       │
│  📋 本轮诊断                           │
│                                       │
│  ┌─ 识别到的病症 ──────────────────┐  │
│  │ P001 世界观膨胀 [中度]            │  │
│  │ 触发信号: 世界观、主角未确定        │  │
│  │ 严重度: L2 (信号总分 4)            │  │
│  │                                  │  │
│  │ P004 信息硬塞 [轻度]              │  │
│  │ 触发信号: 说明句                   │  │
│  │ 严重度: L1 (信号总分 2)            │  │
│  └─────────────────────────────────┘  │
│                                       │
│  ┌─ 建议教学动作 ──────────────────┐  │
│  │ A001 缩小范围                     │  │
│  │ → 把用户从宏大设定拉回具体场景       │  │
│  │                                  │  │
│  │ A002 回归主角                     │  │
│  │ → 从上帝视角回到角色眼睛            │  │
│  └─────────────────────────────────┘  │
│                                       │
│  ┌─ 置信度 ────────────────────────┐  │
│  │ ████████░░ 80%                   │  │
│  └─────────────────────────────────┘  │
│                                       │
└───────────────────────────────────────┘
```

### 7.4 API 配置面板

```
┌─── API 配置 ─────────────────────────
│                                       │
│  API Key:                             │
│  [sk-xxxx...                          ]  │
│                                       │
│  Base URL:                            │
│  [https://api.deepseek.com/v1         ]  │
│                                       │
│  模型名称:                             │
│  [deepseek-chat                       ]  │
│                                       │
│  Temperature: 0.7  [◄───●───►]        │
│  Max Tokens:  4096  [◄───●───►]        │
│                                       │
│  [ 测试连接 ]  [ 保存配置 ]            │
│                                       │
│  状态: ✅ 连接成功                      │
│                                       │
└───────────────────────────────────────
```

### 7.5 训练任务页面

```
┌─── 训练任务 ─────────────────────────┐
│                                       │
│  筛选: [全部 ▼] [P003 情绪标签化 ▼]    │
│                                       │
│  ┌─ T001 ─────────────────────────┐  │
│  │ 情绪描写练习                     │  │
│  │ 对应病症: P003 情绪标签化          │  │
│  │ 难度: ⭐⭐                        │  │
│  │ 进度: ████████░░ 80%              │  │
│  │ 状态: 进行中                      │  │
│  │ [ 查看详情 ] [ 标记完成 ]          │  │
│  └────────────────────────────────┘  │
│                                       │
│  ┌─ T002 ─────────────────────────┐  │
│  │ 对话中的情绪表达                  │  │
│  │ 对应病症: P003 情绪标签化          │  │
│  │ 难度: ⭐⭐⭐                       │  │
│  │ 进度: ░░░░░░░░░░ 0%               │  │
│  │ 状态: 待开始                      │  │
│  │ [ 查看详情 ]                      │  │
│  └────────────────────────────────┘  │
│                                       │
└───────────────────────────────────────┘
```

---

## 8. 成功指标与验收标准

### 8.1 MVP 验收标准

| 验收项 | 标准 | 验证方法 |
|--------|------|---------|
| 应用启动 | 启动时间 ≤ 3 秒 | 计时测量 |
| API 配置 | 支持自定义 API Key / URL / 模型 | 手动测试 |
| 连接测试 | 能检测 API 连通性并给出反馈 | 输入错误 Key 测试 |
| 对话功能 | 能发送消息并收到 AI 回复 | 端到端测试 |
| 流式输出 | AI 回复实时显示，无卡顿 | 观察输出流畅度 |
| 诊断书 | 每轮对话后展示诊断结果 | 输入已知病症文本测试 |
| 会话管理 | 能创建、切换、删除会话 | 手动操作 |
| 数据持久化 | 关闭后重新打开，对话历史保留 | 重启验证 |
| 态度档位 | 能切换豆包/月笙如歌模式 | 切换后观察 AI 语气变化 |
| 训练任务 | 能查看任务列表和进度 | 手动操作 |

### 8.2 质量标准

| 指标 | 目标 | 测量方式 |
|------|------|---------|
| TypeScript 类型覆盖率 | 100% | `tsc --noEmit` 零错误 |
| 单元测试覆盖率 | ≥ 70%（诊断引擎 + API 代理） | Jest/Vitest |
| ESLint 规则 | 零警告 | `eslint .` |
| 首屏加载时间 | ≤ 2 秒 | Performance API |
| 内存占用 | ≤ 300 MB | 任务管理器 |
| 打包体积 | ≤ 100 MB | 构建产物大小 |

---

## 9. 里程碑与排期

### 9.1 开发里程碑

| 阶段 | 内容 | 交付物 | 优先级 |
|------|------|--------|--------|
| **M0: 环境搭建** | 项目初始化、技术栈配置、环境验证 | 可运行的空 Electron 窗口 | P0 |
| **M1: 核心对话** | API 配置面板 + 聊天界面 + 流式输出 | 能对话的基础应用 | P0 |
| **M2: 诊断引擎** | 后台诊断分析 + 诊断面板 UI | 带诊断功能的完整应用 | P0 |
| **M3: 数据持久化** | SQLite 集成 + 会话管理 | 支持历史记录的稳定版本 | P0 |
| **M4: 训练任务** | 任务列表 + 进度追踪 | 含训练系统的 MVP | P1 |
| **M5: 参考文件** | 参考文件管理 + 知识库加载 | 完整参考体系的版本 | P1 |
| **M6: 打包发布** | Electron Builder 配置 + 安装包 | Windows 安装包 | P1 |
| **M7: 盲测验证** | 执行 5 个盲测案例 | 验证报告 | P1.5 |
| **M8: Phase 2** | Sensei 模式 + 长期记忆 | 增强版 | P2 |

### 9.2 关键依赖

| 依赖项 | 状态 | 影响 |
|--------|------|------|
| Prompt V3.0 体系 | ✅ 已完成 | 无阻塞 |
| DPV4 API 可用性 | ️ 待验证 | M1 阶段需要 |
| 诊断引擎算法 | ✅ 已设计（见 2.3） | 无阻塞 |
| 训练任务库 T001-T014 | ✅ 已完成 | 无阻塞 |
| 参考文件内容 | ✅ 已完成 | 无阻塞 |

---

## 附录 A：Prompt V3.0 全文

见 `resources/prompts/yuesheng-prompt-v3.md`（从月笙本地化打包目录复制）

## 附录 B：病症信号完整映射表

见 `resources/prompts/syndrome-manual.md`（从月笙本地化打包目录复制）

## 附录 C：训练任务完整列表

见 `resources/prompts/training-tasks.md`（从月笙本地化打包目录复制）

---

> **文档维护**：本 PRD 为 MVP 阶段指导文档。Phase 2+ 功能将在本 PRD 基础上扩展新章节。
> **最后更新**：2026-05-31
