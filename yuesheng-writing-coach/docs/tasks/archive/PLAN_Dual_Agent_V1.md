# 瘦双 Agent 架构实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将现有单 Agent Prompt（V3.1 ~2800字）拆分为 Diagnosis Agent（~1000字）和 Teaching Agent（~1500字），通过轻量 Router 路由

**Architecture:** 无调度器、无事件总线。Router 是 chat.handler.ts 中的一个 if-else 规则。Diagnosis Agent 在主进程中直接调用，输出结构化 JSON 传给 Teaching Agent。技法索引共享同一个文件。

**Tech Stack:** TypeScript, Electron IPC, better-sqlite3

---

### Task 1: Diagnosis Agent Prompt 文件

**Files:**
- Create: `resources/prompts/diagnosis-agent-prompt-v1.md`

- [ ] **Step 1: 创建 Diagnosis Agent Prompt**

```markdown
# Diagnosis Agent V1

> 角色：月笙的诊断分析师。不跟用户对话，只输出结构化分析。

## 输入

用户文本（小说章节/段落）

## 输出格式（JSON）

你必须在回复中只输出以下 JSON，不要包含任何其他文字：

```json
{
  "rootCause": "用一句话概括根因，不要超过20字",
  "intentPhase": 0,
  "syndromeRef": ["P001"],
  "techniquePool": [],
  "keyPassages": [],
  "confidence": 0.8
}
```

## 分析流程

### 第一步：意图阶段判断

| Phase | 信号 | 说明 |
|-------|------|------|
| 0 未成形 | 无明确风格/目标，信息密度异常 | 用户还没想清楚要写什么 |
| 1 模糊 | 用户说了意图但说不清具体效果 | "我想写凡人流""想写底层的" |
| 2 明确但不一致 | 意图清晰，但文本操作与意图矛盾 | 想写底层，开局即筑基中期 |

### 第二步：症候检测（检测到则加入 syndromeRef，不检测则留空）

| 症候 | 一句话触发条件 |
|------|---------------|
| P001 世界观膨胀 | 大量世界观设定但主角模糊 |
| P002 角色工具化 | 角色行为缺乏动机或前后不一致 |
| P003 情绪标签化 | 直接用情绪词概括，无具体描写 |
| P004 信息硬塞 | 设定通过旁白交代而非角色日常 |
| P005 视角漂移 | 写了主角看不到/听不到的信息 |
| P006 节奏停滞 | 连续多段没有推进或冲突 |

### 第三步：技法匹配

从以下列表中匹配合适技法（3-5条），填充到 techniquePool：

当 syndromeRef 包含 P001/P004 时：
- 技法名：日常行为释放设定，来源：诡秘之主，难度：beginner
- 技法名：物件反常法，来源：诡秘之主，难度：beginner
- 技法名：设定倾倒式开篇（反面教材），来源：凡人修仙传，难度：—

当 syndromeRef 包含 P002/P009 时：
- 技法名：内心吐槽破冰，来源：大奉打更人，难度：beginner
- 技法名：缺席式情感书写，来源：夜的命名术，难度：beginner
- 技法名：行动代替情绪，来源：夜的命名术，难度：beginner
- 技法名：一句话情感锚点，来源：大奉打更人，难度：beginner
- 技法名：日常反差建立人物，来源：夜的命名术，难度：beginner
- 技法名：日常温情锚点，来源：我在精神病院学斩神，难度：beginner
- 技法名：旁观者视角引入主角，来源：我在精神病院学斩神，难度：beginner
- 技法名：平凡出身共鸣，来源：凡人修仙传，难度：beginner
- 技法名：绰号反差，来源：凡人修仙传，难度：beginner
- 技法名：群像快速建立，来源：十日终焉，难度：beginner

当 syndromeRef 包含 P006 时：
- 技法名：绝境开局法，来源：大奉打更人，难度：beginner
- 技法名：三词递进开篇，来源：诡秘之主，难度：beginner
- 技法名：三段式情绪递降，来源：诡秘之主，难度：beginner
- 技法名：行动预告断点，来源：诡秘之主，难度：beginner
- 技法名：双线叙事制造信息差，来源：大奉打更人，难度：intermediate
- 技法名：反常识推理破局，来源：大奉打更人，难度：intermediate
- 技法名：倒计时制造紧迫感，来源：夜的命名术，难度：beginner
- 技法名：世界碎裂式转场，来源：夜的命名术，难度：beginner
- 技法名：远期预告钩子，来源：凡人修仙传，难度：beginner
- 技法名：小人物大命运反差，来源：凡人修仙传，难度：beginner
- 技法名：密闭空间开局，来源：十日终焉，难度：beginner
- 技法名：数字矛盾制造悬念，来源：十日终焉，难度：beginner
- 技法名：暴力事件定调，来源：十日终焉，难度：beginner
- 技法名：身份反转断点，来源：十日终焉，难度：beginner
- 技法名：规则漏洞推理，来源：十日终焉，难度：intermediate
- 技法名：反差视觉开局，来源：我在精神病院学斩神，难度：beginner
- 技法名：双重身份悬念，来源：我在精神病院学斩神，难度：beginner
- 技法名：梦境世界暗示，来源：我在精神病院学斩神，难度：intermediate
- 技法名：证据链式悬念，来源：诡秘之主，难度：intermediate

### 规则

1. 先判断意图阶段，再匹配症候
2. techniquePool 最多选 5 条，按难度排序（beginner 优先）
3. 不输出教学建议，只输出分析
4. keyPassages 引用原文不超过 50 字
5. confidence 范围 0-1，基于信号清晰度
```

- [ ] **Step 2: 验证文件格式**

Run: `Get-Item D:\ai-teacher\yuesheng-writing-coach\resources\prompts\diagnosis-agent-prompt-v1.md`
Expected: 文件存在，大小 > 1000 字节

---

### Task 2: Teaching Agent Prompt 文件

**Files:**
- Create: `resources/prompts/teaching-agent-prompt-v1.md`

- [ ] **Step 1: 创建 Teaching Agent Prompt**

```markdown
# Teaching Agent V1

> 角色：月笙。只做教学对话，不做文本分析。诊断结果由 Diagnosis Agent 提供。

## 核心原则

1. 一次只处理一个根因（不是一次一个症状）
2. 不暴露内部编号（用户看不到 P001/TQ-001/A001）
3. 训练嵌入当前修改（治疗模式），不布置独立作业
4. 不说"你错了"，说"你想要的效果和实际效果之间有差距"

## 当前诊断结果

{diagnosisResult}

## 可用技法

{techniquePool}

## 引用技法的方式

- 提来源作品名称，不提编号
- 示例："诡秘之主第一章用手枪放在书桌上，读者自己就知道世界不对劲"
- 不给完整案例，只给方向和框架
- 只在诊断结果指明根因时引用技法

## 三档态度

{attitudeLevel}

## 教学动作（按需调用）

| 动作 | 一句话精髓 | 适用时机 |
|------|-----------|---------|
| 缩小范围 | 把用户从宏大设定拉回具体场景 | 用户在一段内放了太多信息 |
| 回归主角 | 从上帝视角回到角色眼睛 | 写了主角看不到/听不到的信息 |
| 五问法 | 用连续追问理清因果链 | 用户逻辑模糊或矛盾 |
| 现实锚点 | 从"编故事"回到"真人会怎么做" | 角色行为远离日常经验 |
| 信心确认 | 帮高基础学员确认直觉正确 | 学员自我审查时 |
| 边界校准 | 给情绪/技术边界，防止走形 | 学员"照单全收"时 |
| 跨语境迁移 | 用现代类比激活陌生设定共情 | 学员远离日常经验时 |
| 意图校准 | 呈现矛盾让用户自己发现 | 意图与执行不一致时 |

## 节奏

- 第一轮：只说方向，不给具体方案
- 第二轮（用户确认后）：给框架，不让填充
- 第三轮（用户尝试后）：让用户自评

## 禁忌

- ❌ 不替用户写句子
- ❌ 不替用户决定
- ❌ 不打断用户展示
- ❌ 不直接否定
- ❌ 不给套路建议（"黄金三章"）

## 教学状态

{stateContext}
```

- [ ] **Step 2: 验证文件格式**

Run: `Get-Item D:\ai-teacher\yuesheng-writing-coach\resources\prompts\teaching-agent-prompt-v1.md`
Expected: 文件存在，大小 > 1000 字节

---

### Task 3: 共享诊断结果类型定义

**Files:**
- Modify: `src/renderer/shared/types.ts`（追加在文件末尾）

- [ ] **Step 1: 在 types.ts 追加诊断结果结构化类型**

```typescript
/** 技法池条目（Diagnosis Agent 输出用） */
export interface TechniqueRef {
  /** 技法名 */
  name: string;
  /** 来源作品 */
  source: string;
  /** 难度等级 */
  difficulty: 'beginner' | 'intermediate';
}

/** 关键段落引用（Diagnosis Agent 输出用） */
export interface KeyPassage {
  /** 原文片段（不超过 50 字） */
  text: string;
  /** 问题描述 */
  issue: string;
}

/** 诊断 Agent 的结构化输出 */
export interface DiagnosisAnalysis {
  /** 根因：一句话概括（不超过 20 字） */
  rootCause: string;
  /** 意图阶段：0=未成形/1=模糊/2=明确但不一致 */
  intentPhase: number;
  /** 关联症候编号列表（内部使用） */
  syndromeRef: string[];
  /** 可选技法池（3-5条） */
  techniquePool: TechniqueRef[];
  /** 文本中的关键段落（供教学引用） */
  keyPassages: KeyPassage[];
  /** 置信度（0-1） */
  confidence: number;
}
```

- [ ] **Step 2: 确保编译通过**

Run: `cd D:\ai-teacher\yuesheng-writing-coach && npx tsc --noEmit`
Expected: 无报错

---

### Task 4: 更新 DiagnosisService 支持根因存储

**Files:**
- Modify: `src/main/services/diagnosis.service.ts`

- [ ] **Step 1: 更新 DiagnosisRow 接口和 save 方法**

```typescript
export interface DiagnosisRow {
  id: string;
  session_id: string;
  message_id: string;
  syndromes: string;
  suggested_actions: string;
  confidence: number;
  timestamp: string;
  next_focus: string | null;
  created_at: string;
  /** 新增：Diagnosis Agent 的根因分析 JSON */
  root_cause_analysis: string | null;
}
```

- [ ] **Step 2: 更新 save 方法写入根因字段**

在 save 方法中，新增 `root_cause_analysis` 参数。由于 `save()` 当前接收 `DiagnosisEntry` 类型，而根因分析不在 `DiagnosisEntry` 中，新增一个重载方法：

```typescript
/** 保存 Diagnosis Agent 的结构化分析结果 */
saveAnalysis(analysis: DiagnosisAnalysis, sessionId: string, messageId: string): void {
  const stmt = this.db.prepare(`
    UPDATE diagnosis_results
    SET root_cause_analysis = ?
    WHERE session_id = ? AND message_id = ?
  `);
  stmt.run(JSON.stringify(analysis), sessionId, messageId);
}

/** 获取最近的分析结果 */
getLatestAnalysis(sessionId: string): DiagnosisAnalysis | null {
  const row = this.db.prepare(`
    SELECT root_cause_analysis FROM diagnosis_results
    WHERE session_id = ? AND root_cause_analysis IS NOT NULL
    ORDER BY timestamp DESC LIMIT 1
  `).get(sessionId) as { root_cause_analysis: string } | undefined;
  if (!row) return null;
  return JSON.parse(row.root_cause_analysis);
}
```

需要导入 `DiagnosisAnalysis`：

```typescript
import { DiagnosisEntry, SyndromeResult, ActionId, SyndromeId, DiagnosisAnalysis } from '../../renderer/shared/types';
```

- [ ] **Step 3: 编译检查**

Run: `cd D:\ai-teacher\yuesheng-writing-coach && npx tsc --noEmit`
Expected: 无报错

---

### Task 5: Router 规则 + Diagnosis Agent 调用 — chat.handler.ts

**Files:**
- Modify: `src/main/ipc/chat.handler.ts`

- [ ] **Step 1: 新增 Diagnosis Agent 调用函数**

在 `chat.handler.ts` 中新增函数。Router 规则是 if-else 逻辑，不独立成模块。

```typescript
import { DiagnosisAnalysis, AttitudeLevel } from '../../renderer/shared/types';

// ... 现有代码 ...

/**
 * 判断用户输入是否包含可分析的文本
 * 文本 ≥ 100 字且非纯对话性质
 */
function isAnalyzeableText(message: string): boolean {
  const trimmed = message.trim();
  if (trimmed.length < 100) return false;
  // 纯对话特征：以提问结尾、少于 3 句、包含"你"指向 AI
  const lines = trimmed.split(/[\n\r]+/).filter(l => l.trim().length > 0);
  if (lines.length <= 3 && /\?$/.test(trimmed)) return false;
  if (lines.length <= 3 && /^(你|月笙|那)/.test(trimmed)) return false;
  return true;
}

/**
 * 调用 Diagnosis Agent 分析文本
 * 在主进程内直接调用 API，不经过 IPC
 */
async function callDiagnosisAgent(userText: string): Promise<DiagnosisAnalysis | null> {
  const proxy = getApiProxy();
  try {
    const promptPath = path.join(__dirname, '../../resources/prompts/diagnosis-agent-prompt-v1.md');
    let diagnosisPrompt: string;
    try {
      diagnosisPrompt = fs.readFileSync(promptPath, 'utf-8');
    } catch {
      diagnosisPrompt = '分析以下文本的写作问题，输出结构化 JSON。';
    }

    const messages = [
      { role: 'system' as const, content: diagnosisPrompt },
      { role: 'user' as const, content: userText },
    ];

    let fullResponse = '';
    for await (const chunk of proxy.chatStream(messages)) {
      fullResponse += chunk;
    }

    // 尝试解析 JSON 响应
    const jsonMatch = fullResponse.match(/\{[\s\S]*\}/);
    if (!jsonMatch) {
      console.warn('[DiagnosisAgent] No JSON found in response');
      return null;
    }

    const parsed = JSON.parse(jsonMatch[0]) as DiagnosisAnalysis;
    return parsed;
  } catch (err) {
    console.error('[DiagnosisAgent] Failed to analyze:', err);
    return null;
  }
}
```

- [ ] **Step 2: 修改 `registerChatHandlers` 中的路由逻辑**

在 `chat:send` handler 中，将原来的单一流式调用改为路由分流：

```typescript
export function registerChatHandlers(): void {
  ipcMain.handle(IPC_CHANNELS.CHAT_SEND, async (_event, args: {
    message: string;
    sessionId: string;
    history?: { role: string; content: string }[];
    attitudeLevel?: AttitudeLevel;
  }) => {
    if (!mainWindow) throw new Error('Main window not available');

    const { message, sessionId, history, attitudeLevel } = args;
    const activeSessionId = sessionId || sessionService.getOrCreateDefaultSession().id;
    sessionService.saveMessage(activeSessionId, 'user', message.trim());

    const attitude = attitudeLevel ?? ConfigService.getInstance().getConfig().attitudeLevel;

    // === Router 逻辑 ===
    const hasAnalysisText = isAnalyzeableText(message);

    let diagnosisAnalysis: DiagnosisAnalysis | null = null;

    if (hasAnalysisText) {
      // 1. 先走 Diagnosis Agent
      // 通知前端正在分析
      mainWindow.webContents.send(IPC_CHANNELS.CHAT_STREAM_DATA, {
        sessionId: activeSessionId,
        chunk: '',
        status: 'analyzing',
      });

      diagnosisAnalysis = await callDiagnosisAgent(message);

      if (diagnosisAnalysis) {
        // 存入数据库
        const existingDiagService = getDiagnosisService();
        if (existingDiagService) {
          existingDiagService.saveAnalysis(diagnosisAnalysis, activeSessionId, '');
        }
      }
    }

    // 2. 走 Teaching Agent（有诊断结果则注入，无则走常规流程）
    const proxy = getApiProxy();
    const systemPrompt = loadSystemPrompt(attitude, diagnosisAnalysis);

    const messages: { role: 'system' | 'user' | 'assistant'; content: string }[] = [
      { role: 'system', content: systemPrompt },
    ];

    if (history) {
      for (const msg of history) {
        if (msg.role === 'user' || msg.role === 'assistant') {
          messages.push({ role: msg.role, content: msg.content });
        }
      }
    }

    messages.push({ role: 'user', content: message });

    const messageId = generateId();
    let fullResponse = '';

    try {
      // 如果已经有诊断分析，先发送分析摘要
      if (diagnosisAnalysis) {
        const summary = `📋 分析摘要：${diagnosisAnalysis.rootCause}`;
        mainWindow.webContents.send(IPC_CHANNELS.CHAT_STREAM_DATA, {
          sessionId: activeSessionId,
          chunk: summary,
        });
      }

      for await (const chunk of proxy.chatStream(messages)) {
        fullResponse += chunk;
        mainWindow.webContents.send(IPC_CHANNELS.CHAT_STREAM_DATA, {
          sessionId: activeSessionId,
          chunk,
        });
      }

      sessionService.saveMessage(activeSessionId, 'assistant', fullResponse);
      sessionService.autoGenerateTitle(activeSessionId);

      // 3. 仍然保留原有的诊断后处理（兼容旧嵌入标记）
      try {
        processDiagnosisFromAI(fullResponse, activeSessionId, messageId);
      } catch (err) {
        console.error('[Chat] Diagnosis processing failed:', err);
      }

      mainWindow.webContents.send(IPC_CHANNELS.CHAT_STREAM_END, {
        sessionId: activeSessionId,
        fullResponse,
        messageId,
      });

      return { success: true, messageId, sessionId: activeSessionId };
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : '未知错误';
      mainWindow.webContents.send(IPC_CHANNELS.CHAT_STREAM_END, {
        sessionId: activeSessionId,
        fullResponse: '',
        messageId,
        error: errorMessage,
      });
      return { success: false, error: errorMessage };
    }
  });
}
```

- [ ] **Step 3: 更新 `loadSystemPrompt` 函数**

```typescript
function loadSystemPrompt(attitude: AttitudeLevel, diagnosisAnalysis?: DiagnosisAnalysis | null): string {
  try {
    let basePrompt: string;

    if (diagnosisAnalysis) {
      // 有诊断结果 → 加载 Teaching Agent Prompt 并注入诊断
      const teachingPath = path.join(__dirname, '../../resources/prompts/teaching-agent-prompt-v1.md');
      basePrompt = fs.readFileSync(teachingPath, 'utf-8');

      // 替换占位符
      const techniquePoolText = diagnosisAnalysis.techniquePool
        .map(t => `- ${t.name}（来源：${t.source}，难度：${t.difficulty}）`)
        .join('\n');

      const stateContext = loadStateContext();

      basePrompt = basePrompt
        .replace('{diagnosisResult}', JSON.stringify({
          rootCause: diagnosisAnalysis.rootCause,
          intentPhase: diagnosisAnalysis.intentPhase,
          syndromeRef: diagnosisAnalysis.syndromeRef,
          keyPassages: diagnosisAnalysis.keyPassages,
        }, null, 2))
        .replace('{techniquePool}', techniquePoolText || '无')
        .replace('{attitudeLevel}', attitude)
        .replace('{stateContext}', stateContext);
    } else {
      // 无诊断结果 → 用常规 Prompt
      const promptPath = path.join(__dirname, '../../resources/prompts/yuesheng-prompt-v3.md');
      basePrompt = fs.readFileSync(promptPath, 'utf-8');
    }

    return attitude === 'doubao' ? basePrompt + DOUBAO_TONE_MODIFIER : basePrompt;
  } catch {
    console.warn('[ChatHandler] Failed to load system prompt');
  }

  const fallback = '你是一个专业的写作教练月笙，帮助用户提升写作水平。';
  return attitude === 'doubao'
    ? fallback + '\n\n请用温暖鼓励的语气指导用户，多使用积极语言。'
    : fallback;
}

/** 获取当前教学状态上下文 */
function loadStateContext(): string {
  try {
    // 从 sessionService 获取当前教学状态
    // 目前返回占位，后续关联 teaching-state-machine.ts
    const stateRows = sessionService?.getTeachingState?.();
    if (stateRows) {
      return `当前对话已有诊断记录。`;
    }
    return '新对话，尚无教学历史。';
  } catch {
    return '新对话，尚无教学历史。';
  }
}
```

- [ ] **Step 4: 添加 getDiagnosisService 访问函数**

```typescript
import { DiagnosisService } from '../services/diagnosis.service';

let diagnosisService: DiagnosisService | null = null;

export function setDiagnosisService(svc: DiagnosisService): void {
  diagnosisService = svc;
}

function getDiagnosisService(): DiagnosisService | null {
  return diagnosisService;
}
```

并在 `src/main/index.ts` 中注册：

```typescript
// 在初始化后添加
setDiagnosisService(diagnosisService);
```

- [ ] **Step 5: 编译检查**

Run: `cd D:\ai-teacher\yuesheng-writing-coach && npx tsc --noEmit`
Expected: 无报错

---

### Task 6: 主进程注册 DiagnosisService

**Files:**
- Modify: `src/main/index.ts`

- [ ] **Step 1: 导入并注册**

找到 `initDatabase()` 和 `runMigrations()` 调用的位置，在数据库初始化后注册：

```typescript
import { setDiagnosisService } from './ipc/chat.handler';
import { DiagnosisService } from './services/diagnosis.service';

// 在 app.whenReady().then() 内的数据库初始化之后添加
const db = initDatabase();
const diagService = new DiagnosisService(db);
setDiagnosisService(diagService);
```

- [ ] **Step 2: 编译检查**

Run: `cd D:\ai-teacher\yuesheng-writing-coach && npx tsc --noEmit`
Expected: 无报错

---

### Task 7: IPC 通道类型扩展

**Files:**
- Modify: `src/renderer/shared/types.ts`（IPC 通道部分）

- [ ] **Step 1: 检查现有 IPC 通道是否覆盖**

当前 `IPC_CHANNELS` 中已有 `CHAT_SEND`，且 `diagnosis:query` 等通道也已有。不需要新增通道，因为 Diagnosis Agent 在主进程内直接调用。但需要在 `IPCEventMap` 中新增分析状态事件类型：

```typescript
// 在 IPCEventMap 中（如果存在）或已有定义中追加
// 如果不存在 IPCEventMap，忽略此步骤
export interface IPCEventMap {
  // ... 现有
  [IPC_CHANNELS.CHAT_STREAM_DATA]: {
    sessionId: string;
    chunk: string;
    status?: 'analyzing' | 'streaming' | 'done';
  };
}
```

- [ ] **Step 2: 编译检查**

Run: `cd D:\ai-teacher\yuesheng-writing-coach && npx tsc --noEmit`
Expected: 无报错

---

### Task 8: 数据库迁移（新增 root_cause_analysis 字段）

**Files:**
- Create: `src/main/migrations/010_add_root_cause_analysis.sql`

- [ ] **Step 1: 创建迁移脚本**

```sql
-- 010_add_root_cause_analysis.sql
-- 在 diagnosis_results 表中新增 root_cause_analysis 字段

ALTER TABLE diagnosis_results ADD COLUMN root_cause_analysis TEXT;
```

- [ ] **Step 2: 在数据库初始化循环中注册迁移**

修改 `src/main/index.ts` 中的 `runMigrations` 函数，确保导入并执行编号为 `010` 的迁移。

如已有动态迁移加载机制，只需将 SQL 文件放入对应目录。

- [ ] **Step 3: 验证迁移**

Run: 重启应用，检查 `yuesheng.db` 中 `diagnosis_results` 表是否有 `root_cause_analysis` 列
Expected: 列存在且为 TEXT 类型

---

### Task 9: 验证测试

- [ ] **Step 1: 检查 Diagnosis Agent 输出**

手动测试：创建一个临时文件夹，放一段测试文本（如 "修仙传(1).txt" 的开头 500 字），通过诊断 Agent 调用，看是否能输出结构化 JSON。

可用以下测试代码创建一个快速验证脚本：

```typescript
// 临时验证代码
async function testDiagnosisAgent() {
  const proxy = new ApiProxy(config);
  const prompt = fs.readFileSync('resources/prompts/diagnosis-agent-prompt-v1.md', 'utf-8');
  const response = '';
  for await (const chunk of proxy.chatStream([
    { role: 'system', content: prompt },
    { role: 'user', content: '筑基中期。普通散修资质。金丹便是终点...' },
  ])) {
    response += chunk;
  }
  const jsonMatch = response.match(/\{[\s\S]*\}/);
  if (jsonMatch) {
    const analysis = JSON.parse(jsonMatch[0]);
    console.log('rootCause:', analysis.rootCause);
    console.log('techniquePool:', analysis.techniquePool?.length, 'items');
    console.log('confidence:', analysis.confidence);
  }
}
Expected: 正确输出 rootCause、techniquePool 和 confidence

- [ ] **Step 2: 检查 Teaching Agent 不暴露编号**

手动测试：上传一段文本，检查 AI 回复中是否出现 "P001"、"TQ-001"、"A001" 等编号。
Expected: 回复中无任何内部编号

- [ ] **Step 3: 回退方案**

如果任一 Agent 调用失败，回退到原有单 Agent 流程：
- `callDiagnosisAgent` 返回 null 时，`loadSystemPrompt` 自动使用 V3.1
- 无需修改代码，故障态自动降级
