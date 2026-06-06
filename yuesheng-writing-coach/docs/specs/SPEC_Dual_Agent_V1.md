# SPEC: 瘦双 Agent 架构（方案D）

> 版本：V1.0  
> 创建日期：2026-06-03  
> 核心原则：只拆必要的，不做不必要的  
> 关联：V3.1 Prompt → V3.2 拆分、SPEC_Technique_Invocation_V1.md、teaching-state-machine.ts

---

## 一、背景与目标

### 1.1 为什么需要拆

现有单 Agent 架构（V3.1 Prompt ~2800字）承担了五类职责：

| 职责 | 知识域 | 当前规模 |
|------|--------|---------|
| 文本分析 | 症候检测、模式识别 | P001-P010 规则映射 |
| 意图提取 | 三阶段诊断流程 | Phase 0/1/2 |
| 技法匹配 | 34 条技法池筛选 | 6 本小说蒸馏成果 |
| 教学对话 | 动作选择、档位控制 | A001-A012 |
| 训练嵌入 | 治疗模式发放 | T001-T021 |

单 Agent 的认知瓶颈：
- Prompt 超过 2800 字后，AI 对中后段规则的记忆衰减显著
- 诊断和教学需要的思维方式不同（分析 vs 引导），同一模型难同时达到最佳状态
- 技法库更新必须同步修改 Prompt，维护成本高

### 1.2 与原始 P4 的区别

| 维度 | 原始 P4（审计移出） | 方案D（本规格） |
|------|-------------------|----------------|
| Agent 数 | 4 | **2** |
| 调度器 | 独立服务 | **50字 if-else 规则，不独立** |
| 事件总线 | 独立组件 | **不需要** |
| Agent 间通讯 | 总线消息 | **结构化 JSON（文件/内存）** |
| 总工时 | 16h | **6-8h** |

### 1.3 不做的

- 不做 Agent 基础设施（没有 Agent 框架、运行时、注册中心）
- 不做事件总线
- 不做独立部署（两个 Agent 在主进程中运行）
- 不做实时双向通信（诊断→教学单向结构化输出即可）

---

## 二、架构总览

```
用户输入（文本 / 对话）
    │
    ▼
┌─────────────────────────────────────┐
│           Router（规则路由）          │
│  "检测到新文本？→ Diagnosis Agent   │
│   "检测到对话请求？→ Teaching Agent  │
│   "两者都有？→ 先诊断，再教学         │
└──────────────┬──────────────────────┘
               │
       ┌───────┴───────┐
       ▼               ▼
┌──────────────┐ ┌──────────────┐
│ Diagnosis    │ │ Teaching     │
│ Agent        │ │ Agent        │
│              │ │              │
│ Prompt:      │ │ Prompt:      │
│ ~1000字      │ │ ~1500字      │
│ 只分析不对话  │ │ 只对话不分析  │
│              │ │              │
│ 输出 JSON    │ │ 引用诊断结果  │
└──────┬───────┘ └──────┬───────┘
       │                │
       │  结构化根因     │
       │  {             │
       │    rootCause,  │
       │    syndromeRef,│
       │    techniquePool, │
       │    confidence  │
       │  }             │
       ▼                ▼
┌─────────────────────────────────────┐
│          Shared Technique Index      │
│  docs/teaching/technique-library/   │
│  (两个 Agent 共读，不复制)            │
└─────────────────────────────────────┘
```

---

## 三、Router（路由规则）

### 3.1 定位

Router **不是 Agent**，不是服务，不是一个独立模块。它是一个  50 字以内的判断规则，放在现有 `chat.handler.ts` 的入口处。

### 3.2 路由逻辑

```
用户输入到达 chat:send
  │
  ├── 输入包含新增文本 ≥ 100 字 → 路由到 Diagnosis Agent
  │     （文本分析优先，不混合教学）
  │
  ├── 输入是对话/提问/追问 → 路由到 Teaching Agent
  │     （纯教学对话，不触发诊断）
  │
  └── 两者都有 → 两轮处理：
        1. 先 Diagnosis Agent（输出结构化根因）
        2. 再 Teaching Agent（引用诊断结果进行教学）
```

### 3.3 实现位置

现有 `chat.handler.ts` 的 `chat:send` handler 中，在调用 `ApiProxy.chatStream()` 之前加路由判断。不在 `preload/index.ts` 中新增 IPC 通道。

---

## 四、Diagnosis Agent

### 4.1 定位

**不跟用户对话，只输出结构化分析。**

它接收用户文本，输出一个结构化的诊断结果 JSON。教学 Agent 消费这个 JSON。

### 4.2 Prompt 设计（~1000字）

```
# 角色
你是月笙的诊断分析师。你的任务只有一项：分析用户文本，输出结构化诊断结果。

# 输入
用户文本（小说章节/段落）

# 输出格式（JSON）
{
  "rootCause": "意图-执行不一致",    // 根因：一句话概括
  "intentPhase": 0 | 1 | 2,        // 意图阶段（0=未成形/1=模糊/2=明确但不一致）
  "syndromeRef": ["P006"],          // 关联症候编号（内部使用，不暴露给用户）
  "techniquePool": [                 // 可选技法池（3-5条）
    {
      "id": "TQ-001",
      "name": "三词递进开篇",
      "source": "诡秘之主",
      "difficulty": "beginner"
    }
  ],
  "keyPassages": [                   // 文本中的关键段落（供教学引用）
    {
      "text": "筑基中期...",
      "issue": "调用者直接旁白设定，与意图'底层挣扎'矛盾"
    }
  ],
  "confidence": 0.8                  // 置信度
}

# 规则
1. 先判断意图阶段（Phase 0/1/2），再匹配症候
2. 技法池从 technique-library/index_V1.md 中匹配
3. 不输出教学建议，只输出分析
4. 关键段落引用原文，不超过 50 字
```

### 4.3 调用位置

在现有 `processDiagnosisFromAI()` 流程中**插入**——先走 Diagnosis Agent 分析，再将结构化结果传给 Teaching Agent。旧有的 `---DIAGNOSIS_START---` 嵌入标记**暂时保留**，待 Diagnosis Agent 稳定运行后再移除。

### 4.4 输出流向

```
Diagnosis Agent
    ↓ 输出 JSON
诊断结果存入 diagnosis_results 表（复用现有 DiagnosisService）
    ↓
结构化根因传递给 Teaching Agent（作为 system message 的一部分）
    ↓
Teaching Agent 生成教学回复
```

---

## 五、Teaching Agent

### 5.1 定位

**只做教学对话，不做文本分析。**

它接收用户的对话输入 + Diagnosis Agent 的结构化输出，生成教学回复。

### 5.2 Prompt 设计（~1500字）

```
# 角色
你是月笙，一个网文写作教练。你的任务：引导作者改进写作，不替他们写。

# 核心原则
1. 一次只处理一个根因（不是一次一个症状）
2. 不暴露内部编号（用户看不到 P001/TQ-001/A001）
3. 训练嵌入当前修改（治疗模式），不布置独立作业
4. 不说"你错了"，说"你想要的效果和实际效果之间有差距"

# 当前诊断结果（由 Diagnosis Agent 提供）
{diagnosisResult}

# 可用技法（从诊断结果中获取）
{techniquePool}

# 引用技法的方式
- 提来源作品名称，不提编号
- "诡秘之主第一章用手枪放在书桌上，读者自己就知道世界不对劲"
- 不给完整案例，只给方向和框架

# 三档态度
{attitudeLevel}   // doubao / yuesheng / sensei，由 Router 传递

# 教学动作（按需调用，不暴露编号）
A001 缩小范围：把用户从宏大设定拉回具体场景
A002 回归主角：从上帝视角回到角色眼睛
A003 五问法：用连续追问理清因果链
A004 现实锚点：从"编故事"回到"真人会怎么做"
A009 信心确认：帮高基础学员确认直觉正确
A010 边界校准：给情绪/技术边界，防止走形
A011 跨语境迁移：用现代类比激活陌生设定共情
A012 意图校准：呈现矛盾，让用户自己发现

# 阶段控制
按教学状态机（teaching-state-machine.ts）控制当前阶段
P0_INIT → 引导用户表达意图
P1_WORLD → 诊断和教学
P2_PRACTICE_LOOP → 训练嵌入
P4_REVIEW → 回顾进步

# 节奏
- 第一轮：只说方向，不给具体方案
- 第二轮（用户确认后）：给框架，不让填充
- 第三轮（用户尝试后）：给反馈，让用户自评
```

### 5.3 与现有状态机的关系

Teaching Agent 的 Prompt 中 `{diagnosisResult}` 和状态机上下文是**拼接而非替代**关系：

```
最终 Prompt = Teaching Prompt（~1500字）
             + diagnosisResult（结构化 JSON）
             + stateContext（teaching-state-machine.ts 的 buildSystemPromptWithState() 输出）
             + techniqueRefs（从索引文件读取的技法详情）
```

### 5.4 引用技法时的规范

| 技法池 | 对外说法 | 案例引用方式 |
|--------|---------|------------|
| TQ-007 绝境开局法 | "让主角在第一章面临生死危机" | "大奉打更人第一章就是绝境" |
| TQ-005 三段式情绪递降 | "前三章的情绪要有起伏" | "诡秘之主的情绪曲线是恐惧→好奇→温情" |
| TC-001 日常行为释放设定 | "让角色动作带出设定" | "诡秘之主用投铜便士带出货币体系" |
| TN-001 设定倾倒式开篇 | "把设定直接讲出来是最亏的" | 不提反面教材，只说"这样做会怎样" |

---

## 六、共享技法索引

### 6.1 设计

两个 Agent 共读同一个索引文件，不复制数据。

- 文件：`docs/teaching/technique-library/index_V1.md`
- 读取时机：Agent 启动时 / 按需读取
- 更新方式：修改文件即可，不需要改动任何代码或 Prompt

### 6.2 Diagnosis Agent 如何使用

读取索引中的 `全部技法一览` 表，根据 `适用症候` 列匹配合适技法，填充到输出的 `techniquePool` 数组。

### 6.3 Teaching Agent 如何使用

读取 Diagnosis Agent 输出的 `techniquePool`（3-5条），从中选 1 条最贴合当前语境的技法引用。不需要读取完整索引。

---

## 七、与现有代码的集成

### 7.1 改动清单

| 文件 | 改动 | 预估工时 |
|------|------|---------|
| `src/main/ipc/chat.handler.ts` | Router 规则 + Diagnosis Agent 直接调用（~50行） | 2h |
| 新增：Diagnosis Agent Prompt | `resources/prompts/diagnosis-agent-prompt-v1.md` | 1h |
| 新增：Teaching Agent Prompt | `resources/prompts/teaching-agent-prompt-v1.md`（从 V3.1 拆分） | 2h |
| `src/main/services/diagnosis.service.ts` | 新增根因存储字段 | 0.5h |
| `src/renderer/shared/types.ts` | 新增诊断结果结构化类型 | 0.5h |
| **合计** | | **6h** |

### 7.2 不做改动

| 文件 | 理由 |
|------|------|
| `teaching-state-machine.ts` | 状态机保持不变，Teaching Agent 消费其输出 |
| `preload/index.ts` | Diagnosis Agent 在主进程内直接调用（chat.handler.ts），不经过 IPC |
| `technique-library/*.md` | 只是内容更新，结构不需要改 |
| `src/main/index.ts` | 注册逻辑不变 |

### 7.3 Prompt 文件存放

不把 Prompt 硬编码在 `.ts` 文件中，改为外部文件加载：

```
resources/prompts/
  ├── yuesheng-prompt-v3.md          ← 当前（保留，作为参考备份）
  ├── diagnosis-agent-prompt-v1.md   ← 新增：Diagnosis Agent
  └── teaching-agent-prompt-v1.md    ← 新增：Teaching Agent
```

`chat.handler.ts` 中的 `loadSystemPrompt()` 根据路由结果加载对应 Prompt。

---

## 八、前置依赖

### 8.1 必须在新 Prompt 拆分之完成

| 依赖 | 状态 | 影响 |
|------|------|------|
| A012 意图校准动作正式定义 | 已在 SPEC_Intent_Consistency 中定义，未写入 action-library.md | Teaching Agent Prompt 中引用了 A012，需补齐 |
| Diagnosis Agent Prompt 编写 | 不存在 | 需新写 |
| Teaching Agent Prompt 编写 | 不存在 | 需从 V3.1 拆分 + 新增技法引用层 |

### 8.2 非阻塞依赖

| 依赖 | 原因 |
|------|------|
| SPEC_Technique_Invocation_V1.md | 技法筛选规则可以在 Diagnosis Agent Prompt 中直接定义，不阻塞实施 |

---

## 九、操作流程示例

### 场景：用户上传第一章文本

```
step 1: Router 检测到文本 ≥ 100字
    → 路由到 Diagnosis Agent

step 2: Diagnosis Agent
    → 分析文本
    → 检测到 "筑基中期 + 神魂强 + 意图底层挣扎" 矛盾
    → Phase 2（意图明确但不一致）
    → 输出 JSON：
      {
        rootCause: "意图'底层挣扎'与执行'筑基中期开局'矛盾",
        intentPhase: 2,
        syndromeRef: ["P001", "P006"],
        techniquePool: [
          { id: "TQ-007", name: "绝境开局法", source: "大奉打更人", difficulty: "beginner" },
          { id: "TQ-016", name: "小人物大命运反差", source: "凡人修仙传", difficulty: "beginner" },
          { id: "TC-005", name: "平凡出身共鸣", source: "凡人修仙传", difficulty: "beginner" }
        ],
        keyPassages: [
          { text: "筑基中期...普通散修资质...金丹便是终点", issue: "旁白直接交代设定，削弱底层感" }
        ],
        confidence: 0.85
      }

step 3: Router 将 diagnosisResult 传给 Teaching Agent

step 4: Teaching Agent
    → 引用 diagnosisResult 的 rootCause 和 techniquePool
    → 生成教学回复：
      "你说想写底层挣扎的凡人，但我注意到开局是筑基中期——
       这个设定在你想要的效果之间有个小矛盾。
       大奉打更人第一章就用了'绝境开局'：主角一睁眼就在监狱，两天后流放。
       你觉得你的第一章，如果改成'炼气期散修站在秘境入口'，效果会有什么变化？"

step 5: 用户回复后
    → Router 检测到纯对话
    → 路由到 Teaching Agent（不重复诊断）
    → Teaching Agent 继续引导
```

---

## 十、DoD

| 标准 | 验证方式 |
|------|---------|
| Diagnosis Agent 能正确输出结构化 JSON | 单元测试：输入一段文本，检查 JSON 结构 |
| Teaching Agent 不暴露内部编号 | 手动测试：看回复中是否出现 "P001"/"TQ-001"/"A001" |
| Router 正确区分"文本"和"对话" | 单元测试：≥100字文本→诊断，纯对话→教学 |
| 诊断结果持久化到 diagnosis_results 表 | 测试：诊断后查询数据库 |
| 技法库更新不需要改代码 | 修改 index_V1.md 后重启，效果立即生效 |
| 总 Prompt 长度 ≤ 输出字数限制 | 双 Prompt ≤ 2500字（1000+1500） |
| 教学回复中至少引用 1 个技法案例 | 手动测试：检查回复中是否提到来源作品 |

---

## 十一、变更记录

| 版本 | 日期 | 变更内容 | 变更人 |
|------|------|---------|--------|
| V1.0 | 2026-06-03 | 初始版本：瘦双 Agent 架构设计与集成方案 | AI |
