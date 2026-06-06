# 月笙写作教练 — 开发者手册

> **文档版本**：V1.0  
> **最后更新**：2026-06-02  
> **适用范围**：月笙写作教练 V1.0 开发周期  
> **关联规范**：[R-017 文档与报告管理规范](../../.trae/rules/R-017-文档与报告管理规范.md)、[R-018 变更溯源规范](../../.trae/rules/R-018-变更溯源规范.md)、[R-016 Git 提交规范](../../.trae/rules/R-016-Git提交规范.md)  
> **关联文档**：[ROADMAP_V1.md](../plans/ROADMAP_V1.md)、[SPEC_ThreeSpecs_Integration_V1.md](../specs/SPEC_ThreeSpecs_Integration_V1.md)

---

## 目录

1. [项目概述](#一项目概述)
2. [环境搭建](#二环境搭建)
3. [编码规范](#三编码规范)
4. [架构设计](#四架构设计)
5. [模块说明](#五模块说明)
6. [API 接口文档](#六api-接口文档)
7. [数据库设计](#七数据库设计)
8. [测试流程](#八测试流程)
9. [部署步骤](#九部署步骤)
10. [变更管理](#十变更管理)
11. [常见问题解决](#十一常见问题解决)
12. [附录](#十二附录)

---

## 一、项目概述

### 1.1 项目定位

**月笙写作教练**是一个专注于网络小说创作的 AI 写作指导系统。核心理念是：
- **不是小说分析系统，而是作者成长操作系统**
- **诊断对象是作者能力，不是小说本身**
- **系统知道什么时候把什么东西拿给 AI**

### 1.2 核心价值主张

```
用户上传小说 → AI 诊断写作问题 → 推荐训练任务 → 评估训练成果 → 记录成长轨迹
```

### 1.3 技术栈

| 层级 | 技术选型 | 版本要求 |
|------|---------|---------|
| 前端框架 | React 18 + TypeScript | ≥ 5.3 |
| 状态管理 | Zustand + Immer | ≥ 4.5 |
| UI 样式 | Tailwind CSS | ≥ 3.4 |
| 桌面容器 | Electron | ≥ 28.0 |
| 构建工具 | Vite | ≥ 5.0 |
| 数据库 | SQLite (better-sqlite3) | ≥ 9.4 |
| 主进程 | TypeScript (Node.js) | ≥ 18.0 |
| AI 接口 | DeepSeek API | 支持 1M tokens |
| 包管理 | npm | ≥ 10.0 |

### 1.4 项目结构

```
yuesheng-writing-coach/
├── src/
│   ├── main/                          # Electron 主进程
│   │   ├── index.ts                   # 入口文件（窗口、DB、IPC 注册）
│   │   ├── db/                        # 数据库迁移（001-009.sql）
│   │   ├── services/                  # 业务服务层
│   │   │   ├── evidence.service.ts    # 证据管理
│   │   │   ├── author-profile-v2.service.ts # 作者画像
│   │   │   ├── diagnosis.service.ts   # 诊断持久化
│   │   │   ├── teaching-state-machine.ts    # 教学状态机
│   │   │   └── ...                    # 其他服务
│   │   ├── ipc/                       # IPC 处理器
│   │   │   ├── chat.handler.ts        # 聊天流
│   │   │   ├── diagnosis.handler.ts   # 诊断链路
│   │   │   ├── evidence.handler.ts    # 证据查询
│   │   │   └── ...                    # 其他 handler
│   │   └── services/
│   │       ├── config.service.ts      # API 配置
│   │       └── api-proxy.ts           # AI 代理
│   ├── preload/                       # 预加载脚本
│   │   └── index.ts                   # IPC 白名单
│   └── renderer/                      # React 渲染进程
│       ├── components/                # React 组件
│       │   ├── DiagnosisPanel.tsx     # 诊断面板（三标签）
│       │   ├── AbilityRadarChart.tsx  # 能力雷达图
│       │   ├── GrowthTimeline.tsx     # 成长时间线
│       │   └── ...
│       ├── stores/                    # Zustand stores
│       │   ├── author-profile.store.ts
│       │   ├── teaching-state.store.ts
│       │   └── ...
│       ├── shared/
│       │   └── types.ts               # 全局类型定义
│       ├── App.tsx                    # 根组件
│       └── electron.d.ts              # 全局类型声明
├── resources/
│   ├── prompts/                       # AI Prompt 配置
│   │   ├── yuesheng-prompt-v3.md      # Agent Prompt V3.1
│   │   └── action-library.md          # 教学动作库 V3.1
│   └── config/                        # 配置文件
│       └── transition-prompts.json    # 过渡话术
├── docs/
│   ├── specs/                         # 技术规格
│   ├── tasks/                         # 任务文档
│   ├── plans/                         # 计划文档
│   └── cases/                         # 教学案例
└── package.json
```

### 1.5 核心设计原则

| 原则 | 说明 | 依据 |
|------|------|------|
| **三层数据架构** | Raw Novel → NovelProfile → AuthorProfile | SESSION-2026-06-02-summary.md |
| **四级认知追踪** | OBS（观察）→ DIAG（诊断）→ TRAIN（训练）→ EVAL（评估） | SPEC_AuthorProfile_V1.md |
| **四级证据层级** | 文本 → 模式 → 统计 → 对比 | SPEC_Evidence_V1.md |
| **六核心能力** | OBS / CHAR / PLOT / EMO / WORLD / STYLE，V1 冻结 | SPEC_Ability_Map_V1.md |
| **教学隔离** | Reader / Diagnosis / Training / Evaluation 关注点分离 | SPEC_ThreeSpecs_Integration_V1.md |
| **能力树稳定性** | V1 期间不新增/修改核心能力，只映射症候 | SPEC_Ability_Map_V1.md |
| **配置外置** | 所有静态配置外置，禁止硬编码业务映射表 | R-014 配置外置规范 |
| **原子化变更** | 每次变更只解决一个问题，只修改必要文件 | R-010 最小化范围 |

---

## 二、环境搭建

### 2.1 前置要求

- **Node.js** ≥ 18.0（推荐 20.x LTS）
- **npm** ≥ 10.0
- **Git** ≥ 2.40
- **Windows 10+ / macOS 12+ / Linux**

### 2.2 克隆与安装

```powershell
# 克隆仓库
git clone <repository-url>
cd yuesheng-writing-coach

# 安装依赖
npm install

# 验证安装
npm run typecheck    # 类型检查
npm test             # 运行测试
```

### 2.3 开发模式启动

```powershell
# 启动开发服务器（Electron + Vite）
npm run dev
```

**预期行为**：
- Vite 开发服务器在 `localhost:5173` 启动
- Electron 窗口自动打开
- 开发者工具自动开启

### 2.4 数据库初始化

数据库迁移在应用启动时自动执行（见 [src/main/index.ts](file:///d:/ai-teacher/yuesheng-writing-coach/src/main/index.ts#L39-L167)）：

```typescript
// 数据库路径：用户数据目录/yuesheng.db
const dbPath = path.join(app.getPath('userData'), 'yuesheng.db');

// 自动运行 001-009 迁移
// 支持开发/生产环境路径自动识别（app.isPackaged 判断）
```

**开发环境迁移路径**：`src/main/db/`  
**生产环境迁移路径**：`<resourcesPath>/db/`

### 2.5 API 配置

应用首次启动时会引导配置 DeepSeek API 密钥：

1. 打开应用 → 设置页面
2. 输入 DeepSeek API Key
3. 选择模型（默认 `deepseek-v4-pro`）
4. 测试连接

**配置文件位置**：electron-store（本地加密存储）

---

## 三、编码规范

### 3.1 TypeScript 规范

#### 3.1.1 类型定义集中化

**所有类型定义必须在 `src/renderer/shared/types.ts` 中集中管理**，禁止在组件中重复定义。

```typescript
// ✅ 正确：使用共享类型
import type { TeachingState, DiagnosisResult } from '../shared/types';

// ❌ 错误：组件内重复定义
interface TeachingState {
  currentPhase: string;
  // ...
}
```

#### 3.1.2 类型安全要求

- 禁止使用 `any`，使用 `unknown` 替代
- 所有函数必须有明确的返回类型
- IPC 通道类型必须在 `IPC_CHANNELS` 枚举中声明
- `window.electronAPI` 类型在 `electron.d.ts` 中全局声明

### 3.2 文件命名规范

| 类型 | 格式 | 示例 |
|------|------|------|
| Service | `kebab-case.service.ts` | `evidence.service.ts` |
| Handler | `kebab-case.handler.ts` | `diagnosis.handler.ts` |
| Component | `PascalCase.tsx` | `DiagnosisPanel.tsx` |
| Store | `kebab-case.store.ts` | `author-profile.store.ts` |
| 迁移 | `NNN_snake_case.sql` | `008_evidence.sql` |
| 规格文档 | `SPEC_Name_VN.md` | `SPEC_Evidence_V1.md` |
| 任务文档 | `T-NNN-description.md` | `T-004-diagnosis-persistence.md` |

### 3.3 状态管理规范

#### 3.3.1 Zustand Store 规范

```typescript
// ✅ 正确：使用 selector 函数
export const useProfileStore = create<ProfileState>((set, get) => ({
  // 状态定义
  currentTab: 'diagnosis',
  
  // 选择器
  getActiveTab: () => get().currentTab,
  
  // 动作
  setTab: (tab: ProfileTab) => set({ currentTab: tab }),
}));

// ✅ 使用方式
const activeTab = useProfileStore((s) => s.getActiveTab());
const setTab = useProfileStore((s) => s.setTab);
```

#### 3.3.2 数据变更同步

- 前端状态变更通过 IPC 同步到后端
- 后端数据变更通过 `mainWindow.webContents.send()` 推送到前端
- 遵循 **R-007 双向绑定规范**

### 3.4 IPC 通信规范

#### 3.4.1 通道命名

```typescript
// 格式：<domain>:<action>
enum IPC_CHANNELS {
  // 诊断
  'diagnosis:process' = 'diagnosis:process',
  'diagnosis:result' = 'diagnosis:result',
  
  // 证据
  'evidence:getByDisease' = 'evidence:getByDisease',
  'evidence:create' = 'evidence:create',
  
  // 画像
  'authorProfile:get' = 'authorProfile:get',
  'authorProfile:update' = 'authorProfile:update',
}
```

#### 3.4.2 白名单机制

所有新增 IPC 通道必须在 [src/preload/index.ts](file:///d:/ai-teacher/yuesheng-writing-coach/src/preload/index.ts) 的 `allowedChannels` 白名单中注册。

#### 3.4.3 安全要求

- 禁止使用 `nodeIntegration: true`
- 必须启用 `contextIsolation: true`
- 所有 IPC 通信必须通过 `window.electronAPI`（preload 暴露）

### 3.5 Git 提交规范

遵循 **R-016 Git 提交规范**：

```
<type>(<scope>): <subject>

<body>

<footer>
```

**示例**：
```
feat(evidence): 新增 Pattern Detector 服务

实现 Level 1→Level 2 证据聚合器，支持按症候/时间窗口/按章节聚合。

Closes #T-008
依据: docs/specs/SPEC_Evidence_V1.md
```

**Type 枚举**：`feat` / `fix` / `docs` / `style` / `refactor` / `perf` / `test` / `chore`

---

## 四、架构设计

### 4.1 整体架构

```
┌─────────────────────────────────────────────────────┐
│                    前端（Renderer）                  │
│  ┌──────────┐  ┌──────────┐  ┌──────────────────┐  │
│  │ ChatPage │  │ Diagnosis│  │ TeachingProgress │  │
│  │          │  │  Panel   │  │     Panel        │  │
│  └────┬─────┘  └────┬─────┘  └────────┬─────────┘  │
│       │             │                  │            │
│  ┌────┴─────────────┴──────────────────┴─────────┐  │
│  │              Zustand Stores                   │  │
│  └────────────────────┬──────────────────────────┘  │
│                       │ window.electronAPI          │
└───────────────────────┼─────────────────────────────┘
                        │ IPC（preload 白名单）
┌───────────────────────┼─────────────────────────────┐
│                    主进程（Main）                    │
│  ┌────────────────────┴──────────────────────────┐  │
│  │              IPC Handlers                      │  │
│  │  chat │ diagnosis │ evidence │ author-profile  │  │
│  └────────┬──────────┬──────────┬────────────────┘  │
│           │          │          │                    │
│  ┌────────┴──────────┴──────────┴─────────────────┐  │
│  │              Services                           │  │
│  │ Evidence │ AuthorProfile │ Diagnosis │ Teaching │  │
│  └────────┬──────────┬──────────┬────────────────┘  │
│           │          │          │                    │
│  ┌────────┴──────────┴──────────┴─────────────────┐  │
│  │           better-sqlite3 (SQLite)               │  │
│  │  10 张表（001-010 迁移）                        │  │
│  └────────────────────────────────────────────────┘  │
│                                                      │
│  ┌────────────────────────────────────────────────┐  │
│  │              AI API（DeepSeek）                 │  │
│  │  /api-proxy.ts → /api/chat/completions         │  │
│  └────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────┘
```

### 4.2 数据流架构

#### 4.2.1 完整链路（已打通）

```
用户发送消息
    ↓
[chat.handler.ts] AI 流式响应（DeepSeek API）
    ↓
流结束 → processDiagnosisFromAI()
    ↓
[step 1] parseDiagnosisFromAIResponse() → 解析诊断结果
    ↓
[step 2] DiagnosisService.save() → diagnosis_results 表
    ↓
[step 3] 按症候循环 → 提取 evidence[]
      ↓
   每条证据文本 → EvidenceService.save() → evidence 表
      ↓
   EvidenceService.linkToDiagnosis() → diagnosis_evidence 表
    ↓
[step 4] AuthorProfileServiceV2.updateAfterDiagnosis()
      ├── 能力评分加减（子能力基础算法）
      ├── 轨迹追加（时间点 + 分数）
      └── 成长链追加（DIAG 事件 + evidenceIds）
    ↓
[step 5] 合并到 TeachingState → 推送到前端
    ↓
前端三标签页展示（诊断 / 画像 / 成长记录）
```

#### 4.2.2 待建设链路

```
用户上传小说章节
    ↓
[待实现] Reader Agent → 提取 NovelProfile
    ↓
[待实现] NovelProfile → Level 1 Evidence
    ↓
[待实现] Pattern Detector → Level 2/3 Evidence
    ↓
[待实现] Training Agent → 推送训练任务
    ↓
[待实现] Evaluation Agent → 评估训练成果
    ↓
AuthorProfile 更新（TRAIN/EVAL 事件）
```

### 4.3 安全架构

- **Electron**：禁用 `nodeIntegration`，启用 `contextIsolation`
- **IPC 白名单**：所有通道必须在 preload 中显式声明
- **API 密钥**：使用 electron-store 加密存储
- **数据库**：WAL 模式 + 外键约束（应用层校验）
- **Prompt 注入防护**：系统提示与用户输入严格分离

---

## 五、模块说明

### 5.1 主进程模块

#### 5.1.1 入口文件 `src/main/index.ts`

**职责**：
- 窗口创建与管理
- 数据库初始化与迁移
- 服务实例化与注入
- IPC Handler 注册

**关键流程**：
1. `app.whenReady()` → 初始化数据库
2. 运行 001-009 迁移（环境感知路径）
3. 实例化各 Service（Session / Diagnosis / Evidence / AuthorProfile）
4. 通过 setter 注入到对应 Handler
5. 注册所有 IPC Handler
6. 创建窗口

#### 5.1.2 诊断处理器 `src/main/ipc/diagnosis.handler.ts`

**职责**：
- 接收 AI 响应并解析诊断结果
- 创建 Evidence 记录
- 更新 AuthorProfile
- 推送诊断结果到前端

**核心方法**：
- `processDiagnosisFromAI()` — 诊断→证据→画像 完整链路
- `parseDiagnosisFromAIResponse()` — AI 响应解析

**依赖注入**：
- `setDiagnosisService()` — 诊断持久化
- `setEvidenceService()` — 证据管理
- `setAuthorProfileV2Service()` — 画像更新
- `setMainWindow()` — 前端推送

#### 5.1.3 教学状态机 `src/main/services/teaching-state-machine.ts`

**职责**：
- 管理教学阶段流转（诊断→聚焦→训练→评估）
- 处理动作映射（A001-A011）
- 支持聚焦方向过滤（worldbuilding / character / general）
- 生成过渡邀请

**关键状态**：
- `currentPhase` — 当前教学阶段
- `focusArea` — 用户聚焦方向
- `currentSubphase` — 子阶段
- `transitionOffered` — 是否已提供过渡邀请

### 5.2 渲染进程模块

#### 5.2.1 诊断面板 `src/renderer/components/DiagnosisPanel.tsx`

**布局**：三标签页设计
- **本轮诊断**：展示当前会话的诊断结果
- **能力画像**：能力雷达图（六边形 SVG）
- **成长记录**：成长时间线 + 作品对比

**数据来源**：
- `author-profile.store.ts` — IPC 调用封装
- `diag.store.ts` — 诊断数据

#### 5.2.2 能力雷达图 `src/renderer/components/AbilityRadarChart.tsx`

**技术方案**：SVG 纯代码绘制，无第三方库
- 六边形网格（6 项核心能力）
- `polarToCartesian()` 坐标转换
- `buildPolygonPoints()` 网格构建
- 支持空数据/全0/满分三种状态

#### 5.2.3 成长时间线 `src/renderer/components/GrowthTimeline.tsx`

**功能**：
- 垂直事件序列展示
- 按症候分组
- 展示 DIAG / TRAIN / EVAL 事件类型

### 5.3 服务层模块

#### 5.3.1 EvidenceService `src/main/services/evidence.service.ts`

**职责**：证据的完整生命周期管理

**核心方法**：
- `save(evidence)` — 创建证据记录
- `getByDisease(syndromeId)` — 按症候查询
- `getByAbility(abilityId)` — 按能力查询
- `getChainForDiagnosis(diagnosisId)` — 获取诊断关联的证据链
- `linkToDiagnosis(diagnosisId, evidenceId)` — 关联诊断与证据

**数据表**：`evidence` + `diagnosis_evidence`（关联表）

#### 5.3.2 AuthorProfileServiceV2 `src/main/services/author-profile-v2.service.ts`

**职责**：作者画像的更新与查询

**核心方法**：
- `getProfile(authorId)` — 获取完整画像
- `updateAfterDiagnosis()` — 诊断后更新画像
  - 能力评分加减
  - 轨迹追加
  - 成长链追加（DIAG 事件）
- `recordTraining()` — 记录训练事件（TRAIN）
- `recordEvaluation()` — 记录评估事件（EVAL）
- `getGrowthVisualization()` — 获取成长可视化数据

**数据表**：`author_profiles` + `growth_chain_events`

### 5.4 共享资源

#### 5.4.1 Prompt 配置

**Agent Prompt**：`resources/prompts/yuesheng-prompt-v3.md`
- 学员分层（beginner / intermediate / advanced）
- 三档态度（🟢 / 🟡 / 🔴）
- 4 条新禁忌
- 高基础学员处理规则

**教学动作库**：`resources/prompts/action-library.md`
- A001-A011 完整定义
- 症候→动作映射表
- 组合规则

#### 5.4.2 过渡话术配置

**文件**：`resources/config/transition-prompts.json`
- 支持模板变量（`{userName}`、`{focusArea}` 等）
- 多版本轮询（防止话术重复）
- 按场景分类

---

## 六、API 接口文档

### 6.1 内部 API（Electron IPC）

#### 6.1.1 通道清单

| 通道 | 方向 | 请求参数 | 响应 | 说明 |
|------|------|---------|------|------|
| `chat:stream` | Renderer→Main | `{ message, sessionId }` | `stream:chunk` | AI 流式对话 |
| `diagnosis:process` | Main→Renderer | `DiagnosisResult` | — | 推送诊断结果 |
| `evidence:getByDisease` | Renderer→Main | `{ syndromeId }` | `EvidenceRecord[]` | 按症候查询证据 |
| `evidence:getByAbility` | Renderer→Main | `{ abilityId }` | `EvidenceRecord[]` | 按能力查询证据 |
| `evidence:getChain` | Renderer→Main | `{ diagnosisId }` | `EvidenceChain` | 获取证据链 |
| `evidence:create` | Renderer→Main | `EvidenceRecord` | `{ id }` | 创建证据 |
| `authorProfile:get` | Renderer→Main | `{ authorId }` | `AuthorProfileV2` | 获取作者画像 |
| `authorProfile:getAbility` | Renderer→Main | `{ authorId }` | `AbilityScores` | 获取能力评分 |
| `authorProfile:getTrajectory` | Renderer→Main | `{ authorId }` | `Trajectory[]` | 获取能力轨迹 |
| `authorProfile:getChain` | Renderer→Main | `{ authorId }` | `GrowthChain[]` | 获取成长链 |
| `authorProfile:getVisualization` | Renderer→Main | `{ authorId }` | `VisualizationData` | 获取可视化数据 |
| `teachingState:get` | Renderer→Main | `{ sessionId }` | `TeachingState` | 获取教学状态 |
| `teachingState:update` | Renderer→Main | `{ sessionId, state }` | `void` | 更新教学状态 |
| `teachingState:confirm` | Renderer→Main | `{ sessionId }` | `void` | 确认动作完成 |
| `ability:getProfile` | Renderer→Main | `{ sessionId }` | `AbilityProfile` | 获取旧版能力画像 |

#### 6.1.2 完整通道列表

参见 [src/renderer/shared/types.ts](file:///d:/ai-teacher/yuesheng-writing-coach/src/renderer/shared/types.ts) 中的 `IPC_CHANNELS` 枚举。

#### 6.1.3 新增 IPC 通道流程

```
1. 在 types.ts 中新增 IPC_CHANNELS 枚举值
2. 在 preload/index.ts 的 allowedChannels 白名单中注册
3. 创建对应的 handler 文件
4. 在 index.ts 中注册 handler
5. 更新 electron.d.ts 中的类型声明（如有新 API）
6. 编写测试用例
```

### 6.2 外部 API（DeepSeek）

#### 6.2.1 代理配置

**文件**：`src/main/api-proxy.ts`

| 参数 | 值 | 说明 |
|------|-----|------|
| 端点 | `https://api.deepseek.com/v1/chat/completions` | DeepSeek API |
| 模型 | `deepseek-v4-pro`（默认） | 支持 1M tokens |
| max_tokens | 8192 | 最大输出 tokens |
| 流式响应 | `true` | 支持实时输出 |

#### 6.2.2 配置管理

**文件**：`src/main/services/config.service.ts`
- API Key 存储：electron-store
- 模型配置：支持用户自定义
- 连接测试：`testConnection()` 方法

---

## 七、数据库设计

### 7.1 数据库概览

| 迁移号 | 文件名 | 表 | 说明 |
|--------|--------|-----|------|
| 001 | `001_initial.sql` | `sessions` | 会话主表 |
| 002 | `002_create_messages.sql` | `messages` | 消息表 |
| 003 | `003_create_teaching_state.sql` | `teaching_state` | 教学状态 |
| 004 | `004_create_chat.sql` | `chat_histories` | 聊天历史 |
| 005 | `005_diagnosis.sqlite` | `diagnosis_results` | 诊断结果 |
| 006 | `006_add_focus_area.sql` | `teaching_state` (ALTER) | 新增聚焦方向字段 |
| 007 | `007_user_training.sql` | `user_training_records` | 训练记录 |
| 008 | `008_evidence.sql` | `evidence` + `diagnosis_evidence` | 证据系统 |
| 009 | `009_author_profile.sql` | `author_profiles` + `growth_chain_events` | 作者画像 |
| 010 | `010_novel_profile.sql` | *(待实现)* | NovelProfile 持久化 |

### 7.2 核心表结构

#### 7.2.1 evidence（证据表）

| 列名 | 类型 | 约束 | 说明 |
|------|------|------|------|
| `id` | TEXT | PK | 证据 ID（EVD-xxxxxx） |
| `session_id` | TEXT | NOT NULL | 会话 ID |
| `novel_id` | TEXT | NULLABLE | 小说 ID（预留） |
| `syndrome_id` | TEXT | NOT NULL | 症候 ID（P001-P010） |
| `evidence_type` | TEXT | NOT NULL | LEVEL_1/LEVEL_2/LEVEL_3/LEVEL_4 |
| `content_json` | TEXT | NOT NULL | 证据内容（JSON 字符串） |
| `created_at` | TEXT | DEFAULT CURRENT_TIMESTAMP | 创建时间 |

**索引**：`idx_evidence_syndrome`、`idx_evidence_session`、`idx_evidence_type`、`idx_evidence_created`

#### 7.2.2 diagnosis_evidence（诊断-证据关联表）

| 列名 | 类型 | 约束 | 说明 |
|------|------|------|------|
| `id` | TEXT | PK | 关联 ID |
| `diagnosis_id` | TEXT | NOT NULL | 诊断 ID |
| `evidence_id` | TEXT | NOT NULL | 证据 ID |
| `created_at` | TEXT | DEFAULT CURRENT_TIMESTAMP | 创建时间 |

**索引**：`idx_diag_evidence_diagnosis`、`idx_diag_evidence_evidence`

#### 7.2.3 author_profiles（作者画像表）

| 列名 | 类型 | 约束 | 说明 |
|------|------|------|------|
| `id` | TEXT | PK | 画像 ID（AP-xxxxxx） |
| `author_id` | TEXT | NOT NULL UNIQUE | 作者 ID |
| `abilities_json` | TEXT | NOT NULL | 能力评分（JSON） |
| `trajectory_json` | TEXT | NOT NULL | 能力轨迹（JSON） |
| `growth_chain_json` | TEXT | NOT NULL | 成长证据链（JSON） |
| `student_profile_json` | TEXT | NOT NULL | 学员分层信息（JSON） |
| `updated_at` | TEXT | DEFAULT CURRENT_TIMESTAMP | 更新时间 |

#### 7.2.4 growth_chain_events（成长链事件表）

| 列名 | 类型 | 约束 | 说明 |
|------|------|------|------|
| `id` | TEXT | PK | 事件 ID（GCE-xxxxxx） |
| `author_id` | TEXT | NOT NULL | 作者 ID |
| `event_type` | TEXT | NOT NULL | DIAG/TRAIN/EVAL |
| `event_date` | TEXT | NOT NULL | 事件日期 |
| `detail_json` | TEXT | NOT NULL | 事件详情（JSON） |
| `evidence_ids_json` | TEXT | NULLABLE | 关联证据 ID 列表（JSON） |
| `created_at` | TEXT | DEFAULT CURRENT_TIMESTAMP | 创建时间 |

**索引**：`idx_growth_author`、`idx_growth_type`、`idx_growth_date`

### 7.3 数据迁移注意事项

#### 7.3.1 环境感知路径

```typescript
// ✅ 正确：支持开发/生产环境
const migrationPath = app.isPackaged
  ? path.join(process.resourcesPath, 'db/008_evidence.sql')
  : path.join(app.getAppPath(), 'src/main/db/008_evidence.sql');
```

#### 7.3.2 迁移幂等性

所有迁移必须使用 `CREATE TABLE IF NOT EXISTS` 或幂等语句：

```sql
-- ✅ 正确
CREATE TABLE IF NOT EXISTS evidence (...);

-- ❌ 错误
CREATE TABLE evidence (...);  -- 重复执行会报错
```

#### 7.3.3 外键处理

SQLite 不支持某些外键约束（如 JSON 字段的外键），需在应用层校验：

```typescript
// 应用层校验（替代数据库外键）
if (!await evidenceService.exists(evidenceId)) {
  throw new Error(`Evidence ${evidenceId} not found`);
}
```

---

## 八、测试流程

### 8.1 测试架构

```
src/
├── main/
│   ├── services/
│   │   └── __tests__/           # Service 单元测试
│   └── ipc/
│       └── __tests__/           # Handler 单元测试
└── renderer/
    └── stores/
        └── __tests__/           # Store 单元测试
```

### 8.2 测试命令

```powershell
# 运行全部测试
npm test

# 运行指定文件测试
npm test -- --testPathPattern="diagnosis"

# 运行测试并生成覆盖率报告
npm run test:coverage

# 监听模式（开发时自动重跑）
npm run test:watch
```

### 8.3 测试规范

#### 8.3.1 命名规范

```typescript
// ✅ 正确：describe + it 清晰描述行为
describe('EvidenceService', () => {
  describe('save', () => {
    it('应该成功创建 Level 1 证据记录', () => {
      // ...
    });
    
    it('当 syndrome_id 不存在时应抛出错误', () => {
      // ...
    });
  });
});
```

#### 8.3.2 测试数据工厂

```typescript
// ✅ 使用测试工厂创建测试数据
import { createMockEvidence, createMockDiagnosis } from './test-factories';

const evidence = createMockEvidence({ syndromeId: 'P001' });
```

#### 8.3.3 数据库测试

```typescript
// ✅ 使用内存数据库隔离测试
const db = new Database(':memory:');
db.pragma('foreign_keys = ON');

// 运行迁移
db.exec(fs.readFileSync('008_evidence.sql', 'utf-8'));

// 执行测试...
```

### 8.4 当前测试状态

| 指标 | 数据 |
|------|------|
| 总用例数 | 81 |
| 通过率 | 100% |
| 覆盖模块 | Service 层（诊断/状态/配置/证据/画像） |
| 待补充 | 组件测试、集成测试、Agent 测试 |

### 8.5 新增测试流程

```
1. 在对应 __tests__/ 目录创建测试文件
2. 使用 test-factories 创建测试数据
3. 编写测试用例（至少覆盖正常路径 + 异常路径）
4. 运行 npm test 验证
5. 确保不破坏现有 81 个测试
```

---

## 九、部署步骤

### 9.1 开发环境

```powershell
# 1. 克隆并安装
git clone <repo-url> && cd yuesheng-writing-coach && npm install

# 2. 运行测试
npm test

# 3. 启动开发模式
npm run dev
```

### 9.2 生产构建

```powershell
# 1. 运行全量测试
npm test

# 2. 类型检查
npm run typecheck

# 3. 构建生产包
npm run build

# 4. 打包应用（Electron Builder）
npm run package
```

### 9.3 构建产物

| 产物 | 路径 | 说明 |
|------|------|------|
| 前端静态文件 | `dist/renderer/` | Vite 构建输出 |
| 主进程代码 | `dist/main/` | TypeScript 编译输出 |
| 预加载脚本 | `dist/preload/` | preload 编译输出 |
| 数据库迁移 | `resources/db/` | 随包分发 |
| Prompt 配置 | `resources/prompts/` | 随包分发 |
| 安装包 | `release/` | electron-builder 输出 |

### 9.4 生产环境注意事项

#### 9.4.1 路径处理

```typescript
// ✅ 正确：环境感知路径
const dbPath = app.isPackaged
  ? path.join(process.resourcesPath, 'db/008_evidence.sql')
  : path.join(app.getAppPath(), 'src/main/db/008_evidence.sql');
```

#### 9.4.2 资源打包

在 `electron-builder.json` 中配置需要打包的资源：

```json
{
  "extraResources": [
    "resources/prompts/**/*",
    "resources/config/**/*",
    "resources/db/**/*"
  ]
}
```

#### 9.4.3 安全清单

- [ ] 不打包 `.env` 或配置文件
- [ ] 不打包测试文件（`__tests__/`）
- [ ] 不打包开发工具（devDependencies）
- [ ] 数据库文件不硬编码路径
- [ ] API Key 不在代码中出现

---

## 十、变更管理

### 10.1 变更溯源流程

遵循 **R-018 变更溯源规范**：

```
设计哲学（为什么）
    ↓
技术规格（怎么做）
    ↓
任务文档（做什么 + DoD）
    ↓
代码变更
    ↓
Git 提交 + CHANGELOG
```

### 10.2 变更检查清单

**变更前**：
- [ ] 是否有文档依据？（设计哲学 / 研究文档 / 技术规格）
- [ ] 是否明确了"为什么要改"？
- [ ] 是否明确了"怎么改"？
- [ ] 是否创建或更新了任务文档？
- [ ] 是否有回退方案？（依据 R-006）

**变更后**：
- [ ] 代码是否与设计哲学一致？
- [ ] 是否记录了变更摘要？
- [ ] 是否更新了相关文档的变更记录？
- [ ] Git 提交信息是否引用了依据文档？
- [ ] 追溯链条是否完整？

### 10.3 文档同步

遵循 **R-008 文档同步准则**：
- 代码变更后，相关规格文档必须同步更新
- 新增功能必须在对应 SPEC 中记录
- 接口变更必须更新 API 文档
- 数据库变更必须更新迁移清单

### 10.4 变更记录模板

在文档末尾添加：

```markdown
## 变更记录

| 版本 | 日期 | 变更内容 | 变更人 | 关联任务 |
|------|------|---------|--------|---------|
| V1.0 | 2026-06-02 | 初始版本 | AI+用户 | — |
```

---

## 十一、常见问题解决

### 11.1 开发环境问题

#### Q: `npm install` 失败，报 `better-sqlite3` 编译错误

**A**：需要安装编译工具：

```powershell
# Windows
npm install --global windows-build-tools
# 或单独安装
npm config set msvs_version 2022
```

#### Q: Electron 窗口打不开，控制台无报错

**A**：检查 Vite 开发服务器是否启动：

```powershell
# 确认端口 5173 是否被占用
netstat -ano | findstr :5173

# 如果被占用，杀掉进程或修改 Vite 端口
# 在 vite.config.ts 中设置：server: { port: 5174 }
```

#### Q: 数据库迁移报错 "table already exists"

**A**：检查迁移 SQL 是否使用 `CREATE TABLE IF NOT EXISTS`。如果是新增字段，使用 `ALTER TABLE` 并加检查：

```sql
-- 安全的新增字段迁移
ALTER TABLE teaching_state ADD COLUMN focus_area TEXT DEFAULT 'general';
-- 如果字段已存在，SQLite 会报错，但可忽略（幂等问题）
```

### 11.2 TypeScript 编译问题

#### Q: `window.electronAPI` 报类型错误

**A**：确保 `electron.d.ts` 存在且路径正确：

```typescript
// src/renderer/electron.d.ts
interface Window {
  electronAPI: {
    invoke: (channel: string, ...args: any[]) => Promise<any>;
    on: (channel: string, callback: (...args: any[]) => void) => void;
    // ... 其他 API
  };
}
```

如果仍有问题，重启 TypeScript 语言服务器（VSCode：Ctrl+Shift+P → TypeScript: Restart TS Server）。

#### Q: 新增 IPC 通道后类型不匹配

**A**：检查以下位置是否同步更新：
1. `types.ts` 中的 `IPC_CHANNELS` 枚举
2. `preload/index.ts` 的白名单
3. `electron.d.ts` 的类型声明
4. handler 中的注册

### 11.3 运行时问题

#### Q: 诊断结果不显示，前端无更新

**A**：按以下步骤排查：

```
1. 检查诊断 handler 是否注册（index.ts 中的 registerDiagnosisHandlers）
2. 检查 mainWindow 是否设置（setDiagnosisMainWindow）
3. 检查 IPC 通道是否在白名单中
4. 检查前端 store 是否监听对应事件
5. 查看 Electron 开发者工具控制台是否有 IPC 错误
```

#### Q: 数据库查询返回空

**A**：检查：

```
1. 数据库文件是否存在于正确路径
2. 迁移是否成功执行（查看启动日志中的 [Migration] 输出）
3. 数据是否已插入（使用 DB Browser for SQLite 打开 yuesheng.db 查看）
4. 查询条件是否正确（ID 格式是否匹配）
```

#### Q: AI 响应解析失败

**A**：检查：

```
1. Prompt 格式是否正确（resources/prompts/yuesheng-prompt-v3.md）
2. API Key 是否有效
3. 网络是否通畅
4. AI 返回的 JSON 格式是否合法（查看 chat.handler.ts 日志）
```

### 11.4 性能问题

#### Q: 应用启动慢

**A**：优化方向：

```
1. 减少启动时的数据库迁移数量（按需迁移）
2. 延迟加载非关键 Service
3. 使用 Web Workers 处理 AI 请求
4. 减少 preload 脚本体积
```

#### Q: 大文本处理内存溢出

**A**：使用长文本策略：

```
1. 文本 < 3000 字 → 直接分析
2. 3000-20000 字 → 战略抽样（开篇/中段/结尾）
3. > 20000 字 → 滑动窗口或让用户选择章节
```

---

## 十二、附录

### 12.1 术语表

| 术语 | 英文 | 说明 |
|------|------|------|
| 症候 | Syndrome | 写作问题的分类标识（P001-P010） |
| 证据 | Evidence | 支持诊断结果的文本证据，分四级 |
| 能力画像 | Author Profile | 作者能力的结构化记录 |
| 教学状态机 | Teaching State Machine | 管理教学阶段流转的状态机 |
| 聚焦方向 | Focus Area | 用户选择的学习重点（世界观/角色/通用） |
| 训练任务 | Training Task | 针对症候的练习任务（T001-T021） |
| 能力映射 | Ability Map | 症候→子能力→训练任务的映射关系 |
| 认知追踪 | Cognitive Tracking | OBS→DIAG→TRAIN→EVAL 四级事件流 |

### 12.2 能力体系

| 核心能力 | 子能力数量 | 症候映射 |
|---------|-----------|---------|
| **OBS**（观察力） | 3 | P003, P005 |
| **CHAR**（角色力） | 3 | P002, P009, P010 |
| **PLOT**（情节力） | 3 | P006 |
| **EMO**（情绪力） | 3 | P003 |
| **WORLD**（世界力） | 4 | P001, P004, P008 |
| **STYLE**（文笔力） | 3 | P004, P005 |

详见 [SPEC_Ability_Map_V1.md](../specs/SPEC_Ability_Map_V1.md)

### 12.3 症候列表

| ID | 名称 | 核心能力 | 说明 |
|----|------|---------|------|
| P001 | 设定倾倒症 | WORLD | 一次性倾倒大量设定 |
| P002 | 人物空心症 | CHAR | 角色缺乏内在动机 |
| P003 | 情绪标签症 | OBS+EMO | 用标签代替情绪描写 |
| P004 | 世界观说明书症 | WORLD+STYLE | 直接解释世界观 |
| P005 | 形容词依赖症 | STYLE | 过度使用形容词 |
| P006 | 节奏失衡症 | PLOT | 情节节奏不均衡 |
| P007 | 视角漂移症 | — | 视角不统一（不参与评分） |
| P008 | 世界观说明书症 | WORLD | 直接讲解世界观 |
| P009 | 角色工具化症 | CHAR | 角色沦为工具 |
| P010 | 对话空洞症 | CHAR | 对话缺乏潜台词 |

### 12.4 教学动作库

| ID | 名称 | 适用症候 | 说明 |
|----|------|---------|------|
| A001 | 缩小范围 | P001, P008 | 从宏大设定聚焦到具体场景 |
| A002 | 回到主角 | P002, P009 | 以主角视角重新讲述 |
| A003 | 现实锚定 | P001, P004 | 用日常经验类比 |
| A004 | 核心构建 | P001 | 从核心元素开始构建 |
| A005 | 展示不告知 | P003, P005 | 用行为展示替代标签 |
| A006 | 对话训练 | P010 | 对话潜台词训练 |
| A007 | 视角翻转 | P007 | 换一个视角重新叙述 |
| A008 | 阅读任务 | 全部 | 推荐阅读相关作品 |
| A009 | 信心确认 | 全部 | 确认用户理解 |
| A010 | 边界校准 | P002, P009 | 校准角色边界 |
| A011 | 跨语境迁移 | 全部 | 将设定迁移到其他语境 |

详见 [action-library.md](../../resources/prompts/action-library.md)

### 12.5 相关文档索引

| 文档类型 | 文件路径 |
|---------|---------|
| 项目计划 | [ROADMAP_V1.md](../plans/ROADMAP_V1.md) |
| 能力映射规格 | [SPEC_Ability_Map_V1.md](../specs/SPEC_Ability_Map_V1.md) |
| 证据规格 | [SPEC_Evidence_V1.md](../specs/SPEC_Evidence_V1.md) |
| 作者画像规格 | [SPEC_AuthorProfile_V1.md](../specs/SPEC_AuthorProfile_V1.md) |
| 三规范集成 | [SPEC_ThreeSpecs_Integration_V1.md](../specs/SPEC_ThreeSpecs_Integration_V1.md) |
| 聚焦方向规格 | [SPEC_focus-area-transition_V1.0.md](../specs/SPEC_focus-area-transition_V1.0.md) |
| 开发任务报表 | [REPORT-2026-06-02.md](../tasks/REPORT-2026-06-02.md) |
| Session 总结 | [SESSION-2026-06-02-summary.md](../tasks/SESSION-2026-06-02-summary.md) |
| 教学案例 | [case-ayuan-rebirth-ch1.md](../cases/case-ayuan-rebirth-ch1.md) |
| 项目规则汇总 | [月笙项目开发规则汇总.md](../../.trae/rules/月笙项目开发规则汇总.md) |

### 12.6 变更记录

| 版本 | 日期 | 变更内容 | 变更人 | 关联任务 |
|------|------|---------|--------|---------|
| V1.0 | 2026-06-02 | 初始版本，覆盖 12 个核心章节 | AI+用户 | ROADMAP_V1.md |

---

> **文档维护说明**：  
> - 本手册遵循 R-017 文档管理规范，每次重大变更后需更新版本号  
> - 新增功能/模块时，同步更新本手册对应章节  
> - 如有疑问，查看 [月笙项目开发规则汇总](../../.trae/rules/月笙项目开发规则汇总.md) 或提出 Issue
