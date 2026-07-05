# 月笙写作教练 — 架构图 / 数据流 / 用户流程

> 三个 Mermaid 图，GitHub 原生渲染。
> 嵌入位置：README.md `## 架构概览` 和 `## 用户流程` 章节。

---

## 1. 系统架构图

```mermaid
graph TB
    subgraph Renderer["Renderer Process (Electron)"]
        direction TB
        LP["Left Panel<br/>ToolGrid / 工具网格"]
        CP["Center Panel<br/>ChatView · TrainingWorkshop<br/>FiveStepFlow · RetroSummary"]
        RP["Right Panel<br/>7 Workspaces<br/>技法目录 · 教学进度 · 学习日志<br/>作品 · 教学笔记 · 设置 · 发展路径"]
        ZS["Zustand Stores<br/>training.store · session.store<br/>right-tools.store · chat.store"]
        LP --> ZS
        CP --> ZS
        RP --> ZS
    end

    subgraph Preload["preload.ts"]
        IPC["typed IPC channels<br/>invoke / on"]
    end

    subgraph Main["Main Process (Electron)"]
        direction TB
        subgraph Handlers["IPC Handlers"]
            H1["training:*<br/>generateFlow · catalog<br/>getChallenge · evaluate"]
            H2["session:*<br/>list · create · delete"]
            H3["diagnosis:*<br/>analyze · getHistory"]
            H4["prescription:*<br/>getStages · getProgress"]
        end

        subgraph Services["Services"]
            TFS["TrainingFlowService<br/>fillTemplate · getFlowCategory"]
            DS["DiagnosisService<br/>NLP analysis · syndrome matching"]
            TS["TeachingStateMachine<br/>5 phases · attitude control"]
            EA["EvaluatorAgent<br/>score · feedback"]
            AG["AbilityGraphService<br/>atlas · highlights"]
        end

        DB["SQLite<br/>diagnosis_results · sessions<br/>training_records · student_model"]
    end

    subgraph External["External"]
        LLM["DeepSeek Chat API"]
        FILE["technique-library.json<br/>training-flow-mapping.json"]
    end

    Renderer -->|invoke| IPC
    IPC -->|ipcMain.handle| Handlers
    Handlers --> Services
    Services --> DB
    Services -->|HTTP| LLM
    TFS --> FILE
```

---

## 2. 数据传输依赖图

```mermaid
flowchart LR
    U["用户输入<br/>写作片段"] --> D["诊断引擎<br/>DiagnosisService"]
    D -->|P001-P007 症候| TSM["教学状态机<br/>TeachingStateMachine"]
    
    TSM -->|phase = training| TR["训练推荐<br/>TrainingRecommendation"]
    TR -->|filtered list| FSF["五步训练流<br/>FiveStepFlow"]
    
    subgraph FiveStep["五步流内部"]
        S1["Step 1: 解说<br/>InstructionPanel"]
        S2["Step 2: 例证<br/>ExamplePanel"]
        S3["Step 3: 确认<br/>VerifyPanel<br/>≥30字解锁"]
        S4["Step 4: 尝试<br/>PracticePanel<br/>有草稿可提交"]
        S5["Step 5: 反馈<br/>FeedbackPanel<br/>AI评估+修订"]
    end
    
    FSF --> FiveStep
    FSF -->|填充技法内容| TL["技法库<br/>technique-library.json"]
    TL -->|fillTemplate| FSF
    
    S4 -->|提交改写| EA["评估Agent<br/>EvaluatorAgent"]
    EA -->|评分+建议| S5
    EA -->|效果数据| TSM
    
    TSM -->|phase = retro| AG["能力图谱<br/>AbilityGraphService"]
    AG -->|update highlights| DB[("SQLite<br/>persist")]
```

---

## 3. 用户流程图

```mermaid
flowchart TB
    START(["打开应用"]) --> FIRST{"首次使用?"}
    FIRST -->|是| ONBOARD["配置 API Key<br/>设置学生模型"]
    FIRST -->|否| HOME["主界面<br/>左侧工具网格 · 中央对话 · 右侧面板"]
    ONBOARD --> HOME

    HOME --> CHOICE{"选择操作"}
    
    CHOICE -->|诊断会话| CHAT["ChatView<br/>粘贴写作片段 → AI 诊断"]
    CHAT --> DIAG["AI 分析症候<br/>P001-P007 排序 + 严重级别"]
    DIAG --> TEACH["教学对话<br/>状态机驱动五阶段"]
    TEACH -->|推荐训练| RECO["训练推荐列表"]
    
    CHOICE -->|开始训练| RECO
    RECO --> START_TRAIN["点击推荐项"]
    START_TRAIN -->|B-02 检查| READ{"阅读决策<br/>required?"}
    READ -->|是| READ_REQ["先阅读教材"]
    READ_REQ --> READ_DONE["阅读完成"]
    READ -->|否 / 已完成| FIVE_STEP["五步训练流<br/>解说 → 例证 → 确认 → 尝试 → 反馈"]
    READ_DONE --> FIVE_STEP
    
    FIVE_STEP -->|Step 3 确认| CONFIRM{"输入 ≥30字?"}
    CONFIRM -->|否| CONFIRM_DISABLED["「下一步」禁用"]
    CONFIRM_DISABLED --> CONFIRM
    CONFIRM -->|是| CONFIRM_OK["可继续"]
    
    CONFIRM_OK -->|Step 4 尝试| PRACTICE{"有草稿?"}
    PRACTICE -->|否| NO_DRAFT["「提交」禁用"]
    NO_DRAFT --> PRACTICE
    PRACTICE -->|是| SUBMIT["提交改写"]
    SUBMIT --> EVAL["AI 评估 → 分数 + 建议"]
    EVAL -->|Step 5 反馈| FEEDBACK["查看评估<br/>修订稿 → 写回编辑器"]
    
    FIVE_STEP -->|完成| DONE["训练完成"]
    DONE --> UPDATE["能力图谱更新<br/>症候 severity 降级"]
    UPDATE --> HOME

    CHOICE -->|浏览右侧栏| BROWSE["工具面板<br/>(默认关闭-网格入口)"]
    BROWSE --> TOOL{"选择工具"}
    TOOL -->|技法目录| CATALOG["浏览核心组 → 技法卡片<br/>查看详情 → 直接训练"]
    TOOL -->|教学进度| PROGRESS["查看阶段进度<br/>诊断/教学/验证/复盘"]
    TOOL -->|学习日志| LOG["记录学习心得"]
    TOOL -->|作品管理| WORKS["管理章节稿"]
    TOOL -->|教学笔记| NOTE["教学备注"]
    TOOL -->|设置| SETTINGS["API 配置<br/>态度档位切换"]
    TOOL -->|发展路径| STAGE["能力成长总览"]
    
    CATALOG -->|选技法训练| RECO
    SETTINGS -->|态度切换| ATTITUDE{"豆包/月笙/sensei?"}
    ATTITUDE -->|豆包| DOUBAO["温和鼓励"]
    ATTITUDE -->|月笙| YUESHENG["中性专业<br/>(默认)"]
    ATTITUDE -->|sensei| SENSEI["严格·删鼓励话术"]
    
    PROGRESS --> HOME
    LOG --> HOME
    WORKS --> HOME
    NOTE --> HOME
    STAGE --> HOME
```

---

## Mermaid 嵌入 README 用法

复制以下代码块到 `README.md` 对应章节即可：

### 架构图 — 放 `## 架构概览`

```markdown
\`\`\`mermaid
graph TB
    ...（上面图 1 的内容）...
\`\`\`
```

### 数据流 — 放 `## 数据流`

```markdown
\`\`\`mermaid
flowchart LR
    ...（上面图 2 的内容）...
\`\`\`
```

### 用户流程 — 放 `## 用户流程`

```markdown
\`\`\`mermaid
flowchart TB
    ...（上面图 3 的内容）...
\`\`\`
```
