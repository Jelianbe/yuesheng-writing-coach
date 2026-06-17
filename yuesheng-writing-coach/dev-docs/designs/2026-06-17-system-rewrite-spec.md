# 月笙写作教练 — 前端系统重构规格文档

> 用途：为前端系统重构提供完整的设计规范、交互逻辑、数据模型变更和实施路径
> 生成日期：2026-06-17
> 基于：2026-06-16 四方批斗会 + 设计缺口讨论 + 教学案例分析

---

## 一、重构目标

**核心问题**：后端教学能力完整，前端未能正确消费。用户感知不到"教学感"，按键和入口杂乱，教学流程断裂。

**重构目标**：
1. 教学体验优先 — 用户完整走通"提交作品→对话教学→方法论文付→自主修改"循环
2. 入口收敛 — 三栏各司其职，不跨栏、不重叠、不嵌套
3. 后台可见 — 诊断表和用户画像作为服务系统，不裸露内部数据
4. 认知框架优先 — 训练以对话认知建立为基础，技能练习为辅助手段

---

## 二、布局模型

### 2.1 三栏独立窗口模型

```
┌──────────────────┬───────────────────────────┬───────────────────────────┐
│ 月笙[☰]      [⚙] │ [▼ 当前项目 ▾]    [+][⚙]  │   [⤢][─][□][✕]          │
├──────────────────┤  ─── 中间栏 header ───    │ ← 右侧栏 header          │
│ [训练]           │ （视觉隐形，无背景色        ├───────────────────────────┤
│ [对话] [项目]     │   无分割线）               │ 有工具 → 展示工具内容     │
│ ─────────────── │                           │ 无工具 → 展示工具网格     │
│ [🔍 搜索...]     │  聊天消息列表               │ （所有可用工具按钮）      │
│ 会话/项目列表     │                           │                          │
│（分隔线区分      │                           │                          │
│ 按键区与列表区） │                           │                          │
│                  │                           │                          │
├──────────────────┤  ┌─────────────────────┐  ├───────────────────────────┤
│                  │  │ [模板]    🟢🟡🔴🔒   │  │ ← 输入框上方工具栏      │
│                  │  └─────────────────────┘  │                           │
│                  │  ┌─────────────────────┐  │                           │
│                  │  │                     │  │                           │
│                  │  │   输入框（1/6屏高）  │  │                           │
│                  │  │            [发送]   │  │                           │
│                  │  └─────────────────────┘  │                           │
│                  │       ← 中间栏 body →      │                           │
└──────────────────┴───────────────────────────┴───────────────────────────┘
```

### 2.2 核心规则

| 规则 | 说明 |
|:-----|:------|
| 独立窗口模型 | 三栏不是叠加覆盖，共同挤占屏幕空间 |
| 中间栏 header 视觉隐形 | 无独立背景色、无底部深色分割线，仅承载左上项目选择器 + 右上[＋][⚙] |
| 输入框上方工具栏 | 独立于 header，包含左[模板] + 右🟢🟡🔴🔒，占一行 |
| 输入区高度 | 工具栏 + 输入框 + 发送 = 屏幕高度的 1/6 |
| 左侧栏 header | 月笙[☰] 左端 + [⚙] 右端 |
| 左侧栏分隔线 | 标签行与内容区之间的分隔线用于区分上方按键区和下方列表区，仅视觉功能，无独立 UI |
| 左侧栏三标签 | [训练]独立在上方行点击右侧栏展开技法列表；[对话][项目]并列在下方行切换左下内容视图 |
| 右侧栏 header | 有工具打开时展示对应标签（无固定标签）；无工具时仅保留[⤢][─][□][✕] |
| 右侧栏默认视图 | 无工具打开时，展示工具网格供用户选择 |
| 窗口四键 | 在右侧栏 header 右端自然排列，不使用 `position: fixed` |
| 拖拽调整 | 只设 min，不设 max 和 default，用户自由调整 |

### 2.3 三栏状态表

| 栏 | 展开态 | 收起态 |
|:--|:-------|:-------|
| 左侧栏 | 显示 header + 内容区，min=180px | 完全隐藏（宽度 0，中间栏自动扩展） |
| 中间栏 | 始终剩余空间，header 视觉隐形 | 始终剩余空间，接管全屏宽度 |
| 右侧栏 | 显示 header + 内容区，min=320px | header 保留，内容区隐藏 |
| 输入区 | 工具栏 + 输入框 + 发送（1/6屏高） | 宽度随中间栏扩展 |

### 2.4 响应式断点策略

| 窗口宽度 | 行为 |
|:---------|:------|
| ≥1280px | 三栏共存，正常拖拽调整 |
| 1024px ~ 1279px | 左侧栏自动收起（用户可手动展开但覆盖不挤占）；右侧栏保持常态 |
| <1024px | 右侧栏改为 overlay 浮层模式（覆盖在中间栏上方，不是挤占） |

### 2.4 按钮功能表

| 按钮 | 位置 | 功能 |
|:----:|:-----|:------|
| `[☰]` | 左侧栏 header 左端 | 左侧栏展开/收起（和 `[▶]` 二选一，配置决定） |
| `[⚙]` | 左侧栏 header 右端 | 全局设置 |
| `[▼ 当前项目 ▾]` | 中间栏 header 左上角 | 下拉选择项目，切换后当前会话切到该项目最后一次活跃会话 |
| `[＋]` | 中间栏 header 右上角 | 新建会话（归入当前项目） |
| `[⚙]` | 中间栏 header 右上角 | 设置 |
| `[模板]` | 输入框上方工具栏左侧 | 教学中AI自动汇总讨论要点，在对话末尾以预览形式展示，下方附带[记录到教学笔记]按钮。用户点击后右侧栏展开"教学笔记"标签，以树状结构记录讨论成果（如设定/大纲等），归入当前项目。同一项目初始共享一棵树，后续支持新建多棵树 |
| `🟢🟡🔴` | 输入框上方工具栏右侧 | 态度档位灯，点击切换，默认🟢 |
| `🔒` | 输入框上方工具栏最右 | 锁定态度档位，AI 不再自动切换 |
| `[训练]` | 左侧栏标签区上方独立行 | 点击后右侧栏展开技法分类列表，用户选技法后新建训练会话 |
| `[对话][项目]` | 左侧栏标签区下方行 | 切换左侧栏内容视图（会话列表/项目树） |
| `[⤢]` | 右侧栏 header 右端 | 右侧栏内容区展开/收起 |
| `[─][□][✕]` | 右侧栏 header 最右 | 窗口最小化/最大化/关闭 |
| 动态工具标签 | 右侧栏 header（仅工具有打开时出现） | 显示已打开的工具标签，用户可切换；标签右侧[＋]点击展示未打开工具供新建 |

### 2.5 动画规范

| 元素 | 动画 | 缓动 |
|:-----|:-----|:------|
| 左侧栏宽度 | `width 200ms ease` | `cubic-bezier(0.25, 1, 0.5, 1)` |
| 右侧栏宽度 | `width 200ms ease` | 同上 |
| 中间栏被推挤 | 无独立动画，CSS transition 被动触发 | 同上 |
| 🟢🟡🔴 灯切换 | `opacity 150ms ease, transform 150ms ease` | `ease` |

---

## 三、数据模型：项目容器

### 3.1 从属关系

```
用户
  └── 项目（作品集容器）
        ├── 基本信息（名称、创建时间、写作类型）
        ├── 章节（上传文件 → 待分章程序处理）
        ├── 会话列表（所有对话记录）
        │     ├── 会话 1："初稿诊断"
        │     └── 会话 2："修改讨论"
        ├── 诊断表（项目级汇总）
        │     └── 0/N 教学进度（跨会话累计）
        ├── 训练记录（项目级）
        └── 能力画像素描（项目级聚合）
```

### 3.2 默认项目

- 用户第一次完成 API Key 配置后，系统自动创建"我的作品"（默认项目名）
- 用户不需要手动建项目即可开始使用
- 新建第二个项目时才需手动操作

### 3.3 中间栏与项目的关系

- 中间栏 header 左上角 `[▼ 项目名 ▾]` → 切换项目
- 切换项目 → 自动切换到该项目最后一次活跃的会话
- 当前项目下的所有会话在左侧栏 `[对话]` 标签下展示
- 教学进度 0/N 是项目级的，跨会话累计

### 3.4 需新增的 IPC

```typescript
PROJECT_LIST: 'project:list',
PROJECT_CREATE: 'project:create',
PROJECT_GET: 'project:get',
PROJECT_SWITCH: 'project:switch',
PROJECT_GET_CURRENT: 'project:getCurrent',
```

---

## 四、教学体验设计

### 4.1 用户旅程

```
第一次打开（无作品）
  │
  ▼
[Onboarding] → 填写 API Key（一次性）
  │
  ▼
三岔路口 — 展示在中间栏（不是弹窗）：
  ┌─────────────────────────┐
  │ 📝 我有作品              │ → 直接进入聊天，AI 回复引导粘贴作品
  │ 🌱 从头学习              │ → AI 开始世界观/人物搭建引导
  │ 💬 先聊聊               │ → 正常聊天，AI 自然引导
  └─────────────────────────┘
  │
  ▼
进入诊断训练循环（提交作品后）
  用户粘贴/上传作品
    → AI 内部诊断（不暴露问题清单）
    → AI 回复开始教学对话（隐性诊断铁律：一次只处理一个根因）
    → 教学对话持续多轮，AI 引导用户理解问题
    → 自然收尾 → AI 布置作业（可选）
    → 用户修改 → 提交新版本 → 对比进步 → 下一轮
```

### 4.2 教学进度条

**位置**：右侧栏纵向时序视图（非中间栏）

```
┌── 右侧栏内容 ──┐
│ 提交作品       ✓ │
│ 诊断分析       ✓ │
│ ─────────────  │
│ 教学进度    3/7 │  ← 数字在诊断和教学之间
│ ─────────────  │
│ 教学中         ● │  ← 当前状态
│ 已收尾         ○ │
│ 等待修改      ○  │
└──────────────────┘
```

**核心规则**：

| 规则 | 说明 |
|:-----|:------|
| 按项目区分 | 每个项目有自己的进度，跨会话累计 |
| 分阶段展示 | 追加新问题时不累积到同一个分母，改为分阶段显示（"第一批 3/3 ✓ → 第二批 0/4"） |
| 追加动画 | 追加新问题时给一个 "+2 个新问题" 的短暂视觉过渡，避免用户突然看到进度变化 |
| 问题解决跳一次 | 一个问题的教学完成 + 精通确认 → 分子 +1 |
| 数字位置 | 每个阶段在诊断和教学之间，"3/7" = "诊断出的 7 个问题中已完成 3 个" |
| 点击数字 | 展开详细教学概览（问题解决什么、训练结果、当前阶段） |
| 可展开状态指示器 | 中间栏 header 左上角项目选择器旁，小标签显示当前系统状态（教学中、诊断中、梳理中等） |

### 4.3 诊断表增强

在现有 `DiagnosisEntry` + `SyndromeResult` 基础上增加字段：

```typescript
interface DiagnosisEntry {
  // ... 现有字段保留 ...
  
  /** 教学进度追踪 — 每个问题的当前状态 */
  teachingProgress: {
    /** 问题 ID（从 SyndromeResult 关联） */
    syndromeId: string;
    /** 当前状态 */
    status: 'pending' | 'teaching' | 'mastered' | 'relapsed';
    /** 认知阶段 — AI 在教学中自然判断并更新，不裸露给用户 */
    learningStage: 'unaware' | 'aware' | 'can_apply' | 'consistent';
    /** 开始教学时间 */
    teachingStartedAt?: number;
    /** 掌握确认时间 */
    masteredAt?: number;
    /** 此问题的教学方式记录 */
    teachingApproaches: Array<{
      actionId: string;        // A001-A012
      effectiveness: 'effective' | 'neutral' | 'ineffective';
      appliedAt: number;
    }>;
    /** 是否复发（精通后再次出现） */
    isRelapse: boolean;
    /** 复发次数 */
    relapseCount: number;
  }[];
}
```

**认知阶段说明**：

| 阶段 | 含义 | 对应的教学策略倾向 |
|:-----|:------|:------------------|
| `unaware` | 未意识到问题存在 | 先引导发现（GUIDE_DISCOVERY），不直接教方法 |
| `aware` | 知道有问题，但不知如何解决 | 给方法论 + 示范（DIRECT_TEACHING） |
| `can_apply` | 会解决，但有意识才能做到 | 多练形成内化（PRACTICE + REFLECTION） |
| `consistent` | 已内化，不自觉地就能正确写 | 触发精通门控，推进下一问题 |

**更新规则**：
- 纯 AI 判断 — 后端每次教学回复后根据学生反应推断，不做自评/手动调整
- 不裸露给用户 — user profile 不展示 `learningStage`，progress bar 也不展示
- `learningStage` 的变化本身就是进步信号——`unaware → aware` 已经是教学成果

### 4.4 用户画像增强

在现有 `StudentModelService` 基础上增强：

```typescript
interface TeachingHistory {
  /** 问题 ID */
  syndromeId: string;
  /** 使用的教学动作 */
  actionId: string;
  /** 效果评估 */
  effectiveness: 'effective' | 'neutral' | 'ineffective';
  /** 应用时间 */
  appliedAt: number;
  /** 所属项目 */
  projectId: string;
  /** 应用时的系统态度档位 */
  attitudeLevel: 'gentle' | 'balanced' | 'direct';
}

interface StudentModelExtended {
  // ... 现有字段保留 ...
  
  /** 教学历史（跨项目、跨会话） */
  teachingHistory: TeachingHistory[];
  
  /** 用户态度偏好（从 DisputeTracker 数据提炼） */
  attitudePreference: {
    preferredLevel: 'gentle' | 'balanced' | 'direct';
    locked: boolean;           // 用户是否手动锁定了档位
    lockedAt?: number;
    disputePattern: 'challenge' | 'accept' | 'silent';  // 辩驳反应类型
  };
  
  /** 进度叙事（供 AI 回复中引用） */
  progressNarrative: string[];
  // 示例: ["用户已攻克情绪标签化(P003)，可以挑战视角混乱(P005)"]
}
```

### 4.5 训练体系 — 三层设计

| 层级 | 名称 | 发生位置 | 形式上 | 触发条件 |
|:-----|:------|:---------|:-------|:---------|
| **L1** | 认知框架建立 | 聊天对话 | AI 用三重追问引导用户发现概念 | 诊断→教学自然过渡 |
| **L2** | 认知工具迁移 | 聊天对话 | AI 让用户用新框架诊断旧文 | L1 完成后 AI 自然引出 |
| **L3** | 技能练习 | 聊天内嵌 EditPanel / 右侧栏 ActiveTrainingView | 改写原文或完成结构化训练 | L2 完成后 / 用户主动要求 |

**关键规则**：
- 训练入口统一到聊天 — AI 在对话中自然引出，不是系统弹窗
- 右侧栏不主动弹训练面板 — 除非用户已经主动打开并显示训练内容
- 简单改写（L3 简单）用 EditPanel，结构化训练（L3 复杂）用 ActiveTrainingView
- 训练完成 → 更新诊断表 teachingProgress → 检查精通门控 → 进度跳动

### 4.6 生产训练内容

`TrainingRecommendationService` + `challenge-templates.json` 用于 L3 结构化训练的内容匹配。AI 在对话中判断：
- 问题具体、单一 → 简单改写（EditPanel）
- 问题有深层结构根因 → 结构化训练（ActiveTrainingView）
- 用户主动要求 → AI 根据当前上下文动态生成

### 4.7 训练反馈回路

```
训练完成
  │
  ├──→ 更新诊断表 teachingProgress[].status = 'mastered'
  │
  ├──→ 进度条分子 +1
  │
  ├──→ 检查精通门控（MasteryGate）：
  │     精通 → 解锁当前问题，AI 切换下一问题
  │     未精通 → 不跳，AI 换方式再教
  │
  ├──→ 用户画像记录 teachingHistory（教学方式 + 有效度）
  │
  └──→ 如果右侧栏已打开 → 切换到进步摘要卡片
       如果右侧栏未打开 → 不主动打开，AI 在聊天中告知
```

### 4.8 右侧栏"不主动打开"

右侧栏是查阅区，不是操作区。三条硬规则：

| 规则 | 行为 |
|:-----|:------|
| 从不主动打开 | 右侧栏的打开/关闭完全由用户控制 |
| AI 在聊天中"邀请" | AI 说"我准备了练习，去右侧看看？"→ 用户说"好"→ 用户手动打开 |
| 已打开时自动切内容 | 如果右侧栏已打开且对应工具已在标签栏中，自动切换到该工具（不打扰用户，仅切换内容） |

### 4.9 精通确认时刻

| 情况 | 行为 |
|:-----|:------|
| 右侧栏已打开且"进步摘要"工具已在标签栏中 | 自动切换到该工具，卡片短暂高亮 |
| 右侧栏已打开但"进步摘要"未在标签栏中 | 不自动打开，AI 在聊天中告知 |
| 右侧栏未打开 | AI 在聊天中告知，进度条跳 1/N |
| 后续用户主动打开右侧栏 | 进步记录持久化在"学习日志"工具中可查阅 |

### 4.10 成长趋势

**双通道设计**：

| 通道 | 消费者 | 展示形式 |
|:-----|:-------|:---------|
| 用户可见 | 用户本人 | 右侧栏"学习日志"工具（从工具网格打开），每天一条汇总记录 |
| 系统使用 | AI 教学决策 | 独立记录持久化到画像数据，按问题类型/时间/是否复发聚合 |

**进步记录的内容结构**：

```
✧ 6月16日
  新发现问题：铺垫过多、视角混乱
  已攻克：情绪标签化 —— 你学会了用动作代替情绪词

✧ 6月15日
  新发现问题：信息硬塞
  已攻克：对话节奏 —— 你学会了在对话中穿插动作描写
```

注意：文本措辞由 AI 在对话中自然生成，不硬编码。系统只提供数据结构触发点 + 数据字段。

**复发问题**：两笔记录都保留，不隐藏不特殊标记。AI 在教学中自然提及"这个问题又出现了"。

### 4.11 教学笔记系统（`[模板]` 按钮）

**定位**：教学产出物的可视化记录，不是创作工具，不是练习入口。

**完整交互流**：

```
聊天中 AI 判断某个教学话题已充分展开（3-5 轮无新信息）
  ↓
AI 在回复末尾以自然语言汇总讨论要点（预览），例如：
  "主角的背景我们聊得差不多了：
   ↘ 主线：成为剑仙
   ↘ 出身：普通山村少年
   ↘ 奇遇：遇到隐居剑仙"
  ↓
回复末尾附带非侵入式按钮：[记录到教学笔记]
  ↓
用户点击 → 右侧栏展开"教学笔记"标签
          → 预览内容写入树状结构
          → 后续聊天中 AI 继续更新同一棵树
  ↓
当树足够丰富时，AI 提示："基本信息够了，可以开始创作了"
```

**关键设计规则**：

| 规则 | 说明 |
|:-----|:------|
| **预览模式** | AI 在聊天中的总结是写入前的预览，用户点击[记录]后才正式写入 |
| **手动写入** | 用户确认后才展开右侧栏写入树，AI 不自动写入 |
| **不打断教学** | 按钮在回复末尾，用户不点击也不影响当前教学节奏 |
| **一项目多树** | 初始共享一棵树，后续支持用户新建多棵独立树（如不同的故事设定分支） |

**数据存储**：树结构归入项目级设定集，与章节平行。

```typescript
interface ProjectSettingTree {
  projectId: string;
  treeGroup: string;       // 默认值: 'main'，后续支持多树
  nodes: TreeNode[];
}

interface TreeNode {
  id: string;
  label: string;           // 节点标题（如"主角出身"）
  content: string;         // 节点详细内容
  parentId: string | null; // 父节点 ID
  order: number;           // 同级排序
  sourceSessionId: string; // 来源会话（可追踪到聊天记录）
  sourceMessageId: string; // 来源消息（可追踪到具体位置）
  createdAt: number;
  updatedAt: number;
}
```

---

### 4.12 教学状态膨胀预警

**架构原则**：TeachingState 只描述"现在在干什么"，不要描述"怎么干"。

| 正确（状态） | 错误（方法） |
|:------------|:------------|
| `PRACTICE_TEACHING` | `PRACTICE_TEACHING_COGNITIVE_CONFLICT` |
| `PRACTICE_GUIDE` | `PRACTICE_GUIDE_SOCRATIC` |
| `PRACTICE_REFLECTION` | `PRACTICE_REFLECTION_FREE_WRITE` |

教学方法（认知冲突法、反例法、苏格拉底式提问、自由写作……）属于 `TeachingSkill`，由 `StrategyRouter` 决定，**不进入状态机枚举**。未来状态机只扩展阶段（如 `PRACTICE_VERIFY`），不扩展方法变体。

**不需要单独的 paused 状态**：暂停场景只有两个——用户离开会话（session 自然不活跃）和用户锁档位（态度锁已覆盖）。现有的 `displayStatus: idle | diagnosing | teaching | reflecting | completed` 能够表达所有有效状态。加 paused 反而模糊状态机边界。

---

## 五、输入区域设计

### 5.1 布局

```
┌─────────────────────────────────────────────┐
│ [模板]                        🟢🟡🔴  🔒    │  ← 工具栏
├─────────────────────────────────────────────┤
│                                             │
│           输入框                              │
│           （高度 ≈ 屏幕的 1/6）               │
│                                             │
│                                 [发送]      │
│                                             │
└─────────────────────────────────────────────┘
```

### 5.2 态度档位灯行为

| 灯 | 态度 | 默认 | AI 自动切换 | 用户操作 |
|:--:|:-----|:----:|:-----------|:---------|
| 🟢 | 豆包（温和鼓励） | 默认亮 | 可 | 点击切换 |
| 🟡 | 月笙如歌（平衡） | 灭 | 可 | 点击切换 |
| 🔴 | sensei（直接） | 灭 | 可 | 点击切换 |
| 🔒 | 锁定档位 | 未锁 | 禁止切换 | 点击锁定 |

- 三灯点击切换：当前灯亮，其余灭
- 锁定后 AI 不再根据策略自动切换档位（即使检测到辩驳也不升级）
- 锁定后可手动解锁
- 🔒 视觉反馈：锁定后锁图标变为实心 + 颜色加深（`var(--color-attitude-{level})`），解锁后恢复空心 + 浅色
- 无 toast 提示，无"已切换档位"消息——灯亮/灭变化本身就是即时反馈
- 态度变化的效果在 AI 回复内容中自然体现，不在前端 UI 加额外过渡提示

### 5.3 Placeholder 随机轮换

输入框 placeholder 随机展示以下提示（用户输入后消失，下次使用随机抽选）：

```
"输入你的作品，或直接开始对话"
"试试粘贴一段文字，我可以帮你分析"
"你可以要求我出个练习"
"说说你在写作中遇到的问题"
```

### 5.4 输入框保持简单

- 输入框不随教学阶段改变 UI（始终一致）
- 教学阶段的变化体现在 AI 回复内容上，不是输入框上
- EditPanel 是独立的行内组件，不替换主输入框

---

## 六、左侧栏设计

### 6.1 结构

```
┌── 左侧栏 ──┐
│ 月笙[☰] [⚙]│  ← header
├─────────────┤
│ [训练]      │  ← 独立行，点击右侧栏展开技法列表
│ [对话] [项目]│  ← 并列行，切换左下列表
├─────────────┤（分隔线：区分上方按键区和下方列表区）
│ [🔍 搜索...]│  ← 搜索栏，筛选当前标签下的内容
│ [全部] [对话] [训练] │  ← 搜索筛选切换
├─────────────┤
│ 当前标签内容 │
│ - [对话]：当前项目下的会话列表（含训练会话，带靶心图标区分）
│ - [项目]：项目树（含章节，点击章节→右侧栏展开编辑器）
│             │
└─────────────┘
```

### 6.2 按键布局

| 按键 | 位置 | 行为 |
|:-----|:------|:------|
| `[训练]` | 左侧栏标签区上方独立行 | 点击后右侧栏展开技法分类列表，用户选技法后新建训练会话 |
| `[对话]` | 左侧栏标签区下方左侧 | 切换左侧栏内容为当前项目下的所有会话（含训练会话，带靶心图标） |
| `[项目]` | 左侧栏标签区下方右侧 | 切换左侧栏内容为项目树（含章节），点击章节→右侧栏展开作品编辑器 |
| `[🔍 搜索...]` | 列表区顶部搜索栏 | 筛选当前标签下的内容，支持[全部][对话][训练]筛选项 |

### 6.3 训练交互流

1. 用户点击 `[训练]` → 右侧栏展开，展示技法分类按钮（来自 technique-library.json）
2. 根据用户画像数据，匹配的技法分类上显示 `👍` 推荐标记（最多 2 个分类）
3. 用户选中分类 → 技法列表由易到难排列
4. 用户选中技法 → 系统创建新聊天会话：
   - 调用 IPC `training:createSession`（参数：`{ techniqueId: string, projectId: string }`）
   - 后端根据 techniqueId 匹配 challenge-templates.json，组装第一条消息内容
   - 会话命名：`"训练：{技法名}"`
   - 会话标记 `type: 'training'`
   - 归属当前项目
   - 新会话第一条消息是 AI 关于该技法的教学引导
5. 新会话出现在左侧栏 `[对话]` 列表中，带靶心图标区分
6. 训练结果持久化到项目级训练记录表 + 诊断表 teachingProgress

### 6.4 作品交互流

1. 用户点击 `[项目]` 标签 → 左侧栏展示项目树
2. 展开项目 → 显示章节列表
3. 点击某个章节 → 右侧栏展开"作品"标签，展示：
   - 作品名称（章节所属）
   - 章节名称
   - 文字内容编辑器
4. 当前已有的 `chapter.store` 和 `manuscript:*` IPC 通道提供数据支撑

---

## 七、空状态设计

每个面板在无数据时展示引导内容（不是空白）：

| 面板 | 空状态 |
|:-----|:--------|
| 中间栏 | 三岔路口卡片（我有作品/从头学习/先聊聊） |
| 诊断面板 | "还没有诊断记录 → 把你的作品发给我" |
| 训练面板 | "还没有训练任务 → 完成一次诊断后我来推荐" |
| 能力画像 | "持续学习后，这里会展示你的成长" |
| 学习日志 | "持续学习后，这里会积累你的进步记录" |
| 作品管理 | "还没有作品 → 上传文件或粘贴到聊天" |
| 左侧栏会话列表 | "当前没有会话 → 点击右上角[＋]新建" |

**文件上传提示**（针对大于 5000 字的长文档）：

```
📄 文件 "第一章.docx" 已读取
共 23,456 字，已自动分为 5 个章节

建议选择具体方向和范围：
┌─────────────────────┐
│ ○ 整体结构          │
│ ○ 角色塑造          │
│ ○ 指定章节：[第3章] │
└─────────────────────┘

[发送选定内容]    [全部发送（灰字弱化）]
```

**分章失败的兜底策略**：

| 失败原因 | 行为 |
|:---------|:------|
| 格式不兼容（非 .txt/.docx/.md） | 提示"暂不支持此格式，请转换为支持的格式" |
| 无章节标记（纯连续文本） | 按 5000 字自动分段，标注"按字数自动分章" |
| 总字数 < 5000 汉字 | 不触发分章流程，直接导入为单章 |
| 解析超时（文件 > 100MB） | 提示"文件过大，建议选择部分内容导入" |

### 7.1 文本片段引用系统

**核心问题**：用户选中右侧栏章节内容，引用到中间栏对话中与 AI 讨论。系统需要精确定位被引用的文本片段，且定位不因编辑操作（增删改）而失效。

**方案：文本片段锚定（Text Fragment Anchoring）**

不依赖行号（增删文字导致偏移），不依赖块 ID（无法精确到半句话），使用**选中文本本身作为定位依据**：

```typescript
interface TextFragmentRef {
  chapterId: string;
  /** 被选中的精确文本 */
  selectedText: string;
  /** 选中文本前 10 个字符（作为上下文校验） */
  contextPrefix: string;
  /** 选中文本后 10 个字符（作为上下文校验） */
  contextSuffix: string;
  /** 字符偏移量（仅作二次校验，不作主定位依据） */
  charOffset: number;
  /** 引用创建时的 aiSnapshot 版本（决定了查找目标版本） */
  snapshotVersion: number;
}
```

**定位流程**：

```
用户选中 "众人心中打气" → 浮动工具栏 [引用到对话]
  ↓
在 aiSnapshot 中搜索 selectedText：
  ├── 找到（用户没改这段）→ 精确命中，AI 知道原文位置
  └── 未找到（用户已改过）→ 但 selectedText + 前后文本身已是
      足够的上下文，AI 仍可理解用户引用的是什么
```

**为什么不依赖行号**：
- 写作场景频繁增删，行号不断变化
- 选中文本在右侧栏的分栏宽度不同时，视觉"行"不同
- 行号不是稳定标识符

**性能保障**：
| 章节大小 | `indexOf()` 一次搜索耗时 | 是否构成瓶颈 |
|:---------|:------------------------|:-------------|
| 1,000 字 | 微秒级 | 否 |
| 10,000 字 | < 0.1ms | 否 |
| 100,000 字 | ~0.5ms | 否 |
| 500,000 字 | ~2-3ms | 否 |

**快照方案（编辑器的引用稳定性）**：

章节表增加 `aiSnapshot` 字段，记录 AI 最后一次"知道"的内容版本：

```
chapters
  ├── id
  ├── content       ← 用户当前编辑的内容
  └── aiSnapshot    ← AI 上次讨论过的版本（新字段）
```

交互流程：

```
用户保存章节 → content 更新，aiSnapshot 不变
用户说"我改了一下" → 系统发现 content ≠ aiSnapshot
  → 将差异传给 AI → AI 知道用户改了第 N 段
  → AI 回应后，aiSnapshot 更新为当前 content
```

**编辑器方案**：初期使用纯 `<textarea>` + CSS Grid 行号（仅视觉辅助，不作定位），引用定位完全基于文本片段。未来如需富文本能力可升级到 CodeMirror 6。

**备用方案**（纯手动引用）：

```
用户在编辑器中选中文本 → 浮动工具栏 [引用到对话]
  → 引用以特殊格式插入聊天框：
      [引用：第3章] "众人心中打气"
  → 用户再输入追问，一起发送

混合方案 = 快照自动对比（被动） + 手动引用（主动）
```

---

## 八、教学决策记录层（Teaching Intelligence Layer）

### 8.1 为什么需要

当前教学链路的决策过程不透明：

```
诊断结果 → TeachingStrategyRouter → 决定策略 → 教学执行
                                            ↑
                                       为什么这么决定？不可回溯
```

半年后无人知道 Router 为什么选择特定策略，直接影响 Debug、蒸馏、Skill 优化。

### 8.2 数据结构

```typescript
interface TeachingDecisionLog {
  /** 所属会话 */
  sessionId: string;
  /** 针对的症候 */
  syndromeId: string;
  /** 选择的策略类型 */
  strategyChosen: 'GUIDE' | 'DIRECT_TEACHING' | 'GUIDE_DISCOVERY' | 'REFLECTION' | 'READING';
  /** 选择原因 */
  reason: string;
  /** 决策时的学生状态 */
  studentState: {
    confidence: 'high' | 'neutral' | 'low';
    relapseCount: number;
    currentStage: 'ENGAGE' | 'WORLD' | 'IDENTIFY' | 'GUIDE' | 'REFLECTION' | 'TEACHING' | 'ASSIGN' | 'REVIEW';
    attitudeLevel: 'gentle' | 'balanced' | 'direct';
  };
  /** 决策时间 */
  decidedAt: number;
}

interface TeachingOutcomeLog {
  /** 关联的决策 ID */
  decisionId: string;
  /** 结果 */
  outcome: 'success' | 'failure' | 'partial';
  /** 后续补救策略（失败后） */
  followUpStrategy?: string;
  /** 备注（AI 对效果的自然语言评估） */
  notes?: string;
  /** 评估时间 */
  evaluatedAt: number;
}
```

### 8.3 实施建议

| 阶段 | 动作 | 说明 |
|:-----|:------|:------|
| Phase 1 | 定义数据结构 + 写入 | Router 决策时记录，暂时不读 |
| Phase 2-3 | 积累数据 | 教学稳定运行，等待足够样本 |
| Phase 4+ | 数据回流 | 用积累的决策数据优化 Skill Router 和教学库 |
| 未来 | 失败库（TeachingFailureLog） | 当 TeachingOutcomeLog 产生足够"失败"样本时独立成库 |

### 8.4 与现有数据的关系

```
TeachingDecisionLog           TeachingOutcomeLog
     │                              │
     ├── 关联 DiagnosisEntry 症候    ├── 更新 teachingProgress[].teachingApproaches
     ├── 关联 StudentModelService    └── 输入 Skill 优化
     └── 输入 prompt 上下文
```

---

## 九、Store 变更

### 9.1 新增 progress.store

```typescript
interface SessionProgress {
  /** 所属会话 ID */
  sessionId: string;
  /** 当前会话的总问题数（识别到的症候数） */
  totalIssues: number;
  /** 已解决的分子 */
  resolvedIssues: number;
  /** 各问题的教学状态明细 */
  issues: Array<{
    syndromeId: string;
    status: 'identified' | 'teaching' | 'mastered' | 'relapsed';
    label: string;          // 人类可读的简短描述
  }>;
  /** 当前系统展示状态（给状态指示器用的） */
  displayStatus: 'idle' | 'diagnosing' | 'teaching' | 'reflecting' | 'completed';
}

interface ProgressState {
  currentProgress: SessionProgress | null;
  /** 按会话 ID 索引 */
  progressMap: Record<string, SessionProgress>;
  /** 
   * 清理策略：不自动清理历史进度数据
   * - 历史进度是用户画像的输入源（复发分析、成长趋势），清理反而丢信息
   * - 仅当用户主动删除项目时，级联删除该项目下所有会话的进度记录
   */
}

interface ProgressActions {
  /** 诊断完成时初始化进度 */
  initProgress: (sessionId: string, issues: Array<{ syndromeId: string; label: string }>) => void;
  /** 一个问题的教学完成 → 分子 +1 */
  markResolved: (sessionId: string, syndromeId: string) => void;
  /** 追加新问题（同一会话中上传新作品） */
  appendIssues: (sessionId: string, issues: Array<{ syndromeId: string; label: string }>) => void;
  /** 标记复发 */
  markRelapsed: (sessionId: string, syndromeId: string) => void;
  /** 更新展示状态 */
  setDisplayStatus: (sessionId: string, status: SessionProgress['displayStatus']) => void;
}
```

### 9.2 Store 架构调整

**原则**：保留三个独立 zustand store 实例，不合并为同一个。统一从 `src/renderer/stores/layout/` 目录导出，保持文件组织一致。

```typescript
// src/renderer/stores/layout/drawer.store.ts — 侧边栏开合状态
// src/renderer/stores/layout/ui-layout.store.ts — UI 布局状态（当前项目、教学展示状态）
// src/renderer/stores/layout/panel-session.store.ts — 右侧面板会话/标签

// 统一导出
// src/renderer/stores/layout/index.ts
export { useDrawerStore } from './drawer.store';
export { useUILayoutStore } from './ui-layout.store';
export { usePanelSessionStore } from './panel-session.store';
```

### 8.3 面板服务重构

编排逻辑改为 `useRightPanel()` hook：

```typescript
function useRightPanel() {
  const { setRightPanelOpen, setActiveTool } = useLayoutStore();
  
  return {
    openTool(toolId: string) {
      setActiveTool(toolId);
      setRightPanelOpen(true);
    },
    close() {
      setRightPanelOpen(false);
    },
    toggle() {
      // 暂不实现，统一交由 panel-session 管理
    },
  };
}
```

---

## 十、IPC 通道变更

### 10.1 新增

```typescript
// 项目
PROJECT_LIST: 'project:list',
PROJECT_CREATE: 'project:create',
PROJECT_GET: 'project:get',
PROJECT_SWITCH: 'project:switch',
PROJECT_GET_CURRENT: 'project:getCurrent',

// 教学进度
PROGRESS_GET: 'progress:get',
PROGRESS_UPDATE: 'progress:update',

// 文件上传
FILE_OPEN_DIALOG: 'file:openDialog',
FILE_READ: 'file:read',
FILE_PARSE_CHAPTERS: 'file:parseChapters',  // 分章处理

// 诊断表教学进度更新
TEACHING_PROGRESS_UPDATE: 'teachingProgress:update',
TEACHING_PROGRESS_GET: 'teachingProgress:get',

// 画像教学历史
TEACHING_HISTORY_ADD: 'teachingHistory:add',
ATTITUDE_PREFERENCE_SET: 'attitudePreference:set',
ATTITUDE_PREFERENCE_GET: 'attitudePreference:get',
ATTITUDE_PREFERENCE_LOCK: 'attitudePreference:lock',
```

### 10.2 需保留通道（不变）

- 所有诊断域通道 (`diagnosis:*`)
- 所有教学状态域通道 (`teachingState:*`)
- 所有训练域通道 (`training:*`)
- 所有聊天域通道 (`chat:*`)
- 所有会话域通道 (`session:*`)
- 所有证据域通道 (`evidence:*`)
- 所有配置域通道 (`config:*`)
- 所有作品域通道 (`manuscript:*`, `chapter:*`)

### 10.3 建议合并的通道

```typescript
// 证据域 5→1
// evidence:getBySyndrome, evidence:getByAbility, evidence:getChain,
// evidence:getBySyndrome → evidence:query (加 filter 参数)

// 训练域 9→7（保留 TRAINING_RECOMMEND, ASSIGN, COMPLETE, SUBMIT, EVALUATE, HISTORY, DERIVE_BEHAVIOR）
// 删除 TRAINING_SKIP（在教学对话中处理，不需要前端通道）
// 删除 TRAINING_DECIDE_READING（SKILL 内部逻辑）
```

---

## 十一、组件变更清单

### 11.1 新建组件

| 组件 | 文件路径 | 职责 |
|:-----|:---------|:------|
| `TeachingProgressBar` | `src/renderer/components/training/TeachingProgressBar.tsx` | 右侧栏纵向时序进度 + 0/N 数字，点击展开详细教学概览 |
| `ProgressTimeline` | `src/renderer/components/training/ProgressTimeline.tsx` | 进度时间轴（提交→诊断中→教学中→已收尾→等待修改） |
| `LearningLogPanel` | `src/renderer/components/growth/LearningLogPanel.tsx` | 右侧栏"学习日志"工具（从工具网格打开），展示每日进步记录 |
| `ProjectSelector` | `src/renderer/components/layout/ProjectSelector.tsx` | 中间栏 header 左上角项目下拉选择器 |
| `AttitudeIndicator` | `src/renderer/components/chat/AttitudeIndicator.tsx` | 输入框上方工具栏 🟢🟡🔴🔒 |
| `InputToolbar` | `src/renderer/components/chat/InputToolbar.tsx` | 输入框上方工具栏容器（左侧模板 + 右侧态度灯） |
| `TeachingTip` | `src/renderer/components/chat/TeachingTip.tsx` | 输入框 placeholder 随机轮换提示管理 |

### 11.2 需重构组件

| 组件 | 改动说明 |
|:-----|:---------|
| `AppShell` | 适应新布局模型，简化顶部栏逻辑 |
| `RightDrawer` | 移除 `[⤢]` 迁移逻辑，改为固定 header；重构内部结构适应新的右侧栏定位 |
| `SoloSidebar` | 改为[对话][项目][训练]三标签，适应项目容器模型 |
| `ChatView` | 集成 InputToolbar，简化诊断卡片，移除内部数据暴露 |
| `DiagnosisCard` | 重写为教学对话的"隐式诊断"风格，不展示系统内部数据 |
| `EditPanel` | 保留在聊天流中内嵌的简单训练改写入口 |
| `ActiveTrainingView` | 保留结构化训练面板，触发逻辑改为由 AI 在聊天中推荐后跳转 |
| `AbilityProfilePanel` | 改为展示学习日志和进步叙事，移除数字仪表盘风格 |
| `DiagnosisPanel` | 取消"战争迷雾"机制，改为教学概览风格 |
| `right-panel.service.ts` | 删除，功能合并到 layout.store + useRightPanel hook |

### 11.3 输入框设计

```tsx
// src/renderer/components/chat/ChatInput.tsx

interface ChatInputProps {
  onSend: (text: string) => void;
  placeholder?: string;  // 由 TeachingTip 提供
}

// 内部集成：
// - InputToolbar（模板按钮 + AttitudeIndicator）
// - 发送按钮在右下角
// - 输入框高度约占屏幕 1/6
```

---

## 十二、CSS Design Tokens 清理

### 12.1 需要删除的 Token

```css
/* 删除项 */
--header-height: 0px;        /* 无 header 层 — 改为轻量 header 功能区域，不用固定 height */
--icon-strip-width: 48px;    /* 已废弃的窄条 */
--statusbar-min-h: 26px;     /* 无状态栏 */
--sidebar-width: 240px;      /* 三栏不设默认宽度，只设 min */
--toolpanel-width: 380px;    /* 改名为 --right-panel-width 系列 */
--transition-bounce: 400ms cubic-bezier(0.34, 1.56, 0.64, 1);  /* 保留但不作为默认缓动，在按钮点击、小标签出现等微交互处使用 */
```

### 12.1a 需要保留的 Token

```css
/* 保留但改名：sidebar 相关 */
--sidebar-collapsed-w: 0px;  /* 保留，左侧栏收起态宽度 */
```

### 12.2 需要新增的 Token

```css
/* 布局 — 三栏最小值（不设默认宽度） */
--left-panel-min-w: 180px;                /* 左侧栏最小值 */
--right-panel-min-w: 320px;               /* 右侧栏最小值 */
--right-panel-width: var(--right-panel-min-w); /* 初始时使用最小值，用户拖拽后覆盖 */

/* 输入区域 */
--input-area-height: calc(100vh / 6);   /* 输入区总高 = 屏幕 1/6 */
--toolbar-height: 32px;                  /* 工具工具栏高度 */

/* 教学状态 */
--color-attitude-gentle: #3D6B48;        /* 🟢 豆包绿 */
--color-attitude-balanced: #7B5121;      /* 🟡 平衡黄棕 */
--color-attitude-direct: #A94444;        /* 🔴 直接红 */
--color-progress-resolved: var(--accent); /* 已解决问题高亮色 */

/* 缓动统一 */
--ease-default: cubic-bezier(0.25, 1, 0.5, 1);
```

### 12.3 需要修复的 Token

```css
/* 字号 — 从 8 级精简为 6 级，去掉 base/md 混乱 */
--text-xs: 0.75rem;      /* 12px — 修复低于浏览器最小可读字号问题 */
--text-sm: 0.8125rem;    /* 13px */
--text-base: 0.875rem;   /* 14px — 合并原来的 base 和 md */
--text-lg: 1rem;         /* 16px */
--text-xl: 1.25rem;      /* 20px */
--text-2xl: 1.5rem;      /* 24px */
--text-3xl: 2rem;        /* 32px */

/* 阴影 — 从 4+1 级精简为 3 级 */
--shadow-sm: 0 1px 3px rgba(44, 36, 22, 0.06);
--shadow-md: 0 4px 12px rgba(44, 36, 22, 0.08);
--shadow-lg: 0 12px 32px rgba(44, 36, 22, 0.10);
--shadow-input: 0 2px 12px rgba(0, 0, 0, 0.06);  /* 保留输入框阴影 */

/* 圆角 — 从 4 档精简为 6/10/16 */
--radius-sm: 6px;
--radius-md: 10px;
--radius-lg: 16px;

/* 语义色 — 保证对比度达标 */
--text-tertiary: #8A7A68;   /* 原 #736452 对比度 3.8:1 → 改为 4.5:1+ 安全值 */
```

---

## 十三、架构统一规范

### 13.1 基础组件策略

不封装独立的基础 UI 组件库（无 Button/Input/Card 抽象层），不引入外部 UI 库（如 shadcn/ui、radix-ui）。

**理由**：
- HoloGram 同类项目验证了"CSS 变量统一 + CSS Modules 隔离"模式足够
- 改风格只动 `variables.css` 一个文件即可覆盖全局
- 中间栏 header 视觉隐形 + 右侧栏工具网格 + 左侧栏三标签的布局决定了大多数"组件"是业务容器而非通用基础组件

### 13.2 目录规范

每个组件一个目录，统一 `index.tsx` 默认导出：

```
components/layout/ProjectSelector/
  ├── index.tsx          ← 组件定义 + 默认导出
  └── ProjectSelector.module.css

components/chat/AttitudeIndicator/
  ├── index.tsx
  └── AttitudeIndicator.module.css
```

**规则**：
- 已有单文件组件（如 `ChatView.tsx`）逐步迁移到目录格式，Phase 1 不动，Phase 4 清理
- CSS Modules 是唯一样式方案，禁止内联样式（style={}）和内联 `<style>` 标签
- 每个 CSS Module 只引用 `var(--xxx)`，不定义新变量值

### 13.3 TypeScript 规范

在 `.eslintrc` 中新增规则：

```json
{
  "rules": {
    "@typescript-eslint/consistent-type-assertions": ["error", {
      "assertionStyle": "as",
      "objectLiteralTypeAssertions": "never"
    }],
    "@typescript-eslint/ban-ts-comment": ["error", {
      "ts-ignore": "allow-with-description"
    }],
    "react/no-unknown-property": "error",
    "no-inline-styles": "off"  // 由 Code Review 而非 lint 检查
  }
}
```

关键规则：
- `as` 断言允许使用但限制 object literal 场景
- `@ts-ignore` 允许但必须附带说明（`// @ts-ignore — 原因: XXXX`）
- 内联样式由代码审查（HoloGram MCP + 人工）检查，不由 ESLint 阻塞

### 13.4 代码审查工具：HoloGram MCP

**用途**：作为 R-019 和其他代码规范的自动审查辅助。

**集成方式**：MCP 服务模式（不开桌面应用），在项目根目录配置 `.mcp.json`。

**安装（Phase 1 前置）**：

```
1. 从 GitHub Releases 下载 hologram-engine.exe
2. 放入 ~/.hologram/ 目录
3. 配置项目级 MCP
```

**配置**：
```json
{
  "mcpServers": {
    "hologram": {
      "command": "hologram-engine",
      "args": ["serve", "--project-root", "D:\\ai-teacher\\yuesheng-writing-coach"],
      "env": {}
    }
  }
}
```

**审查范围**：
- 耦合深度检测（模块间不当依赖）
- 循环依赖
- 架构违规（如渲染层直接导入 IPC handler）
- 死代码检测（未引用的导出）

> **注意**：HoloGram 是辅助审查，不替代人工 Code Review。ESLint 检查 + HoloGram 静态分析 + 人工 review 三层防护。

### 13.5 IPC 错误处理与加载态统一规则

**错误处理**（遵循 R-028 防御性编码）：

```
┌── IPC invoke 调用 ──────────────────────────────┐
│ try/catch 包裹所有 invoke 调用                    │
│   ├── 成功 → 正常渲染                            │
│   └── 失败 → 静默展示错误占位（非弹窗）：           │
│         ├── 左侧栏列表 → 列表区显示"加载失败"       │
│         ├── 右侧栏工具 → 工具内容区显示错误提示      │
│         ├── 中间栏消息发送 → 消息旁红色状态标记      │
│         └── 均不弹全局 error dialog               │
└──────────────────────────────────────────────────┘
```

- 不做全局 ErrorBoundary（React error boundary 拦截渲染错误，不拦截异步 invoke）
- IPC 调用失败后不自动重试（除非是网络抖动场景，由前端判断后手动重试）
- 用户可点击错误占位中的"重试"按钮重新 invoke

**加载态**：

| 场景 | 加载态 | 说明 |
|:-----|:-------|:-----|
| 左侧栏会话/项目列表 | 骨架屏 | 文本占位行 + 脉冲动画 |
| 右侧栏工具内容 | 骨架屏 | 根据工具类型展示对应骨架 |
| 中间栏历史消息 | 无 loading | SQLite 本地读取，足够快 |
| IPC 请求 < 300ms | 不展示 loading | 闪烁比等待更糟糕 |
| IPC 请求 ≥ 300ms | 展示骨架屏 | 用 setTimeout 延迟触发 |

### 13.6 设置面板（⚙）

**定位**：右侧栏工具页，不是独立的对话框/弹窗。

**内容**（最低可用版本）：
- API Key 配置（输入框 + 保存）
- 态度档位默认偏好（🟢🟡🔴单选，默认🟢）

**交互**：
- 点击左侧栏 `[⚙]` → 右侧栏打开"设置"工具
- 保存后立即生效，不重启
- API Key 配置仅在 main process 处理（R-029 安全规范）

---

## 十四、实施路线

### Phase 1：数据地基（优先级：最高）

| 任务 | 预估规模 | 说明 |
|:-----|:---------|:------|
| 数据模型扩展 | 3 文件 | 诊断表加 teachingProgress，画像加 teachingHistory |
| 新增 progress.store | 1 文件 | 教学进度追踪 |
| 调整 Store 导出路径 | 1 文件 | 三个独立 store 统一从 layout/ 目录导出 |
| 删除 rightPanelService | 1 文件删除 | 替换为 useRightPanel hook |
| 新增项目 IPC | 3 文件 | project:* 通道 + handler + contract |
| DB migration | 2 文件 | 新增项目表 + 诊断表扩展字段 + **数据迁移脚本（旧数据→新模型：我的作品集→默认项目，现有会话归入该项目，诊断数据保留）** |
| CSS Design Tokens 清理 | 1 文件 | variables.css |
| HoloGram MCP 配置 | 2 文件 | 下载引擎 + .mcp.json |
| ESLint 规范规则 | 1 文件 | .eslintrc 新增 TS 规则 |

### Phase 2：布局重建（优先级：高）

| 任务 | 预估规模 | 说明 |
|:-----|:---------|:------|
| AppShell 重写 | 2 文件 | 适应新的三栏独立布局模型 |
| SoloSidebar 三标签 | 2 文件 | [对话][项目][训练] |
| ProjectSelector | 1 文件 | 中间栏 header 项目选择 |
| InputToolbar + AttitudeIndicator | 2 文件 | 输入框上方工具栏 |
| 输入区 1/6 屏高 | 1 文件 | ChatInput 重构 |

### Phase 3：教学体验（优先级：高）

| 任务 | 预估规模 | 说明 |
|:-----|:---------|:------|
| TeachingProgressBar | 1 文件 | 右侧栏纵向时序 + 0/N |
| ProgressTimeline | 1 文件 | 提交→诊断中→教学中→已收尾 |
| 诊断表与进度联动 | 2 文件 | AI 完成教学 → 进度跳动 |
| 画像增强 | 2 文件 | teachingHistory + attitudePreference |
| LearningLogPanel | 1 文件 | 右侧栏学习日志 |
| 训练反馈回路 | 3 文件 | 训练完成 → 更新进度 → 检查精通门控 |

### Phase 4：收尾打磨（优先级：中）

| 任务 | 预估规模 | 说明 |
|:-----|:---------|:------|
| 空状态全覆盖 | 各面板 + 2 文件 | 为所有面板添加引导文字 |
| 文件上传 + 分章 | 2 文件 | file:* IPC + 上传交互 |
| 输入框 placeholder 轮换 | 1 文件 | TeachingTip 组件 |
| 右侧栏"进步摘要"卡片 | 1 文件 | 精通确认时的 UI |
| 纵向时序点击展开 | 1 文件 | 点击数字 → 教学概览 |
| TypeScript 清理 | 全局 | 消除 `as` 断言、`@ts-ignore` |

---

## 十五、验收标准

| 标准 | 验证方式 | 通过条件 |
|:-----|:---------|:---------|
| TypeScript | `npm run typecheck` | 0 errors |
| 单元测试 | `npm run test` | 全部通过 |
| Lint | `npm run lint` | 0 errors, max 300 warnings |
| 门禁 | `npm run gate` | 全部通过 |
| 教学闭环 | 手动测试 | 用户可完整走完"提交作品→对话教学→方法论文付→修改"链 |
| 进度跳动 | 手动测试 | 解决一个问题后 0/N 分子 +1 |
| 态度锁定 | 手动测试 | 锁定后 AI 不自动切换 |
| 项目切换 | 手动测试 | 切换项目后会话和进度随之切换 |
| 右侧栏不主动弹 | 手动测试 | 用户不操作时右侧栏不动 |
| 项目切换响应 | 手动测试 | 切换项目后会话列表 ≤ 500ms 出现 |
| 大会话滚动 | 手动测试 | 1000+ 条消息的会话滚动帧率 ≥ 30fps |
| 拖拽响应 | 手动测试 | 拖拽调整宽度延迟 ≤ 100ms |
| 教学进度一致性 | 自动测试 | 精通确认后 progressMap.resolvedIssues 正确 +1 |
| 数据迁移 | 自动测试 | 旧数据迁移至新模型后，会话数/项目数/配置全部保留 |
| IPC 失败降级 | 手动测试 | invoke 失败时对应面板展示错误占位，不崩溃 |
| 加载态覆盖 | 手动测试 | 左侧栏列表/右侧栏工具内容有骨架屏，历史消息无 loading |

---

## 附录：关键决策记录

| 决策时间 | 决策内容 | 来源 |
|:--------|:---------|:-----|
| 2026-06-16 | 教学环节不暴露诊断内部数据 | 隐性诊断铁律 |
| 2026-06-16 | 训练入口统一到聊天，面板不主动弹出 | 教学案例 + 讨论 |
| 2026-06-16 | 按会话区分进度 0/N，分母只增不减 | 用户确认 |
| 2026-06-16 | 中间栏 header 视觉隐形但仍承载功能 | 用户明确 |
| 2026-06-16 | 态度档位灯在输入框上方工具栏右侧，默认🟢 | 用户明确 |
| 2026-06-16 | 项目是容器，会话活在项目里 | 用户确认 |
| 2026-06-16 | 成长趋势双通道（用户看到每日摘要 + 系统持久化画像） | 用户确认 |
| 2026-06-16 | 右侧栏从不主动打开 | 用户确认 |
| 2026-06-16 | 证据不暴露为独立面板，AI 在聊天中自然引用 | 用户确认 |
| 2026-06-16 | 输入框保持简单一致，placeholder 随机轮换 | 用户确认 |
| 2026-06-16 | 左侧栏垂直分割为[对话][项目][训练]三标签 | 讨论结论 |
| 2026-06-16 | 训练覆盖中间栏时不丢失聊天记录 | 讨论结论 |
| 2026-06-16 | 仅设宽度最小值，不设默认值和最大值 | 用户明确 |
| 2026-06-16 | 底部栏不需要，删除 | 用户明确 |
| 2026-06-17 | AI 读写模块不原创，选成熟方案集成 | 用户明确 |
| 2026-06-17 | 树状图实现不原创，参考成熟前端方案 | 用户明确 |
| 2026-06-17 | paused 状态不需要，现有 displayStatus 覆盖 | AI 建议 + 用户确认 |
| 2026-06-17 | 档位切换无 toast 提示，灯变化本身就是反馈 | AI 建议 + 用户确认 |
| 2026-06-17 | progressMap 不自动清理，删项目时级联删除 | AI 建议 + 用户确认 |
| 2026-06-17 | IPC 错误静默展示错误占位，不弹全局 dialog | AI 建议 + 用户确认 |
| 2026-06-17 | 数据迁移用 Knex migration 自动迁移 | AI 建议 + 用户确认 |
| 2026-06-17 | 设置面板用右侧栏工具页，不做独立对话框 | AI 建议 + 用户确认 |

---

## 附录B：AI 读写模块 — 成熟技术方案参考

> 以下方案仅作为技术参考和设计思路借鉴，不承诺全部集成。重点评估与项目技术栈（Electron + React + TypeScript + SQLite）的兼容性。

### B.1 AI 写作（长篇小说/网文创作）

| 项目 | 技术栈 | Star | 核心价值 | 可借鉴的设计 |
|:-----|:-------|:----:|:---------|:-------------|
| **InkOS** | TypeScript / Node.js / CLI | 1.9k | 10-Agent 多智能体流水线 + 7 真相文件连续性保障 + 33 维审计 | 多 Agent 拆分架构、真相文件、审计-修订闭环、多模型路由 |
| **91Writing** | Vue 3 + Pinia + Vite | 1.2k | 完整小说创作工具链：世界观/角色/大纲/AI 续写/润色 | 提示词库系统、写作目标管理、分章管理、模板化世界观 |
| **InkOS Studio** | TypeScript / React (Web UI) | — | InkOS 的 Web 可视化管理界面，书籍管理、章节审查 | 后端 CLI + 前端 UI 分离模式 |
| **AI_NovelGenerator** | Python | 1.5k | 本地部署、向量数据库上下文记忆、多模型适配 | 上下文记忆系统、角色一致性检查 |
| **Novel Writer English** | npm / CLI | — | 8 步结构化创作流程：概念→规格→规划→起草→编辑→审查 | 步骤化工作流、13 项写前清单、编辑-审查分离 |
| **OpenWrite** | React 19 + Hono + D1(SQLite) + Drizzle | — | 完整 AI 写作平台，Codex 系统(角色/地点/设定)、项目级 AI 上下文 | 与月笙技术栈几乎同构(React+SQLite+TS)，Codex UI 布局可借鉴 |
| **SoloEnt AI** | Next.js (商业闭源) | — | 桌面写作工作台，SoloEnt.md "故事宪法"作为 AI 长期记忆 | 明文化状态文件设计思想，Rules/Workflows/Skills 三层管线 |

**InkOS 核心架构参考价值最高**（同为 TypeScript 项目）：

```
Radar(市场分析) → Planner(章节意图) → Composer(上下文选择)
→ Writer(正文生成) → Observer(事实提取) → Reflector(状态更新)
→ Normalizer(字数调整) → Auditor(33维审计) → Reviser(定点修复)
```

月笙项目的教学状态机（INIT → ENGAGE → WORLD → PRACTICE_LOOP → REVIEW）与 InkOS 的多 Agent 流水线在设计哲学上高度一致：**状态/阶段分离 + 独立审计/回退机制**。可借鉴其：
- 真相文件机制 → 对应月笙的 `TeachingDecisionLog` + `TeachingOutcomeLog`
- 审计-修订闭环 → 对应教学反馈回路 + 精通门控
- 多模型路由 → 教学 Agent 用强模型，辅助 Agent 用轻量模型

**OpenWrite — 技术栈最接近的参考项目**：

| 维度 | OpenWrite | 月笙 |
|:-----|:----------|:-----|
| 前端 | React 19 + TailwindCSS/shadcn-ui | React 18 + CSS Modules |
| 后端 | Hono + D1 (SQLite) + Drizzle | Electron + better-sqlite3 + Knex |
| 编辑器 | Tiptap (富文本) | textarea/纯文本 |
| AI 模式 | BYOK 聊天助手 | BYOK 教学状态机 |

可借鉴的设计：
- **Codex 系统** — 角色/地点/传说/情节点的结构化维基，以项目为容器 → 与月笙的 `ProjectSettingTree` 教学笔记树高度同构，其 UI 布局方式（左侧列表+右侧详情）可直接参考
- **AI 上下文感知** — AI 助手知晓当前项目的标题、类型、角色，生成建议时自动注入上下文 → 与月笙的"AI 知道当前在教什么"一致
- **项目级管理** — 项目带类型/状态/字数追踪 → 月笙的项目容器设计可参考其字段设计
- 技术栈几乎一致，但 OpenWrite 是 AGPL-3.0 许可，月笙是私有项目，**不能直接复制代码，仅借鉴设计思路**

**SoloEnt AI — 明文化状态文件设计思想**：

```
每个项目 → SoloEnt.md (故事宪法)
  ├── 世界观设定 (world lore)
  ├── 角色档案 (characters)
  ├── 叙事一致性 (narrative consistency)
  └── AI 长期记忆的唯一来源
```

SoloEnt 的"故事宪法"与月笙的 `TeachingDecisionLog` + `TeachingOutcomeLog` + 诊断表共享同一设计哲学：**将 AI 的隐性知识显性化为可读、可审计的文件**。区别在于 SoloEnt 面向创作（AI 记住角色设定），月笙面向教学（AI 记住教学决策历史）。

其 Rules/Workflows/Skills 三层管线对应月笙的：
- Rules → 教学策略规则（`StrategyRouter` 的条件判断）
- Workflows → 教学状态机（状态流转）
- Skills → 教学方法（`TeachingSkill`，如苏格拉底式提问）

> 注意：SoloEnt 是商业产品（\$9.9/月起），核心不开源。仅参考其公开设计文档和产品理念。

### B.2 AI 写作教学（写作教练/教育反馈）

| 项目 | 类型 | 核心设计 | 可借鉴的设计 |
|:-----|:-----|:---------|:-------------|
| **CoachGPT** (Delaware大学, SIGIR'25) | 学术论文 | Scaffolding 结构：教师指令→拆分子任务→实时反馈；AI 不代写 | 支架式教学的 Agent 化实现、不替写原则、分步反馈 |
| **Khan Academy Writing Coach** | 商业产品 | 高亮反馈 + 可交互修订 + 多轮草稿迭代；聚焦结构/论点/论据 | 反馈不替代写作、多稿追踪、教师面板（进步概览） |
| **Class Companion AI** | 商业产品 | Rubric 对齐反馈、迭代修订循环、班级共性弱项分析 | Rubric 驱动的精准反馈、教师数据面板 |
| **Prompts-for-edu** | 开源提示词库 | 7 大教育场景提示词模板（写作导师/测验/辩论教练/同伴教学） | Prompt 模板体系、场景化教学 Agent 设计 |
| **MagicSchool** | 商业产品 | 60+ 教师工具，含 rubric 生成、写作反馈、课堂设计 | 工具矩阵式产品架构 |

**CoachGPT 学术参考价值最高**：
- 明确提出现有 LLM 写作助手的根本问题：**generate essays without teaching**（生成但不教学）
- 采用 Scaffolding（支架式教学）理论：将教师指令转化为可执行的子任务序列
- 提供实时反馈而非替写 —— 与月笙"不替写"铁律完全一致

**Khan Academy Writing Coach 的产品设计参考价值**：
- 反馈覆盖结构/论点强度/论据使用/风格 — 不止语法层面
- 交互式修订：学生可追问可修改，多轮草稿
- 教师面板展示班级共性问题

---

## 附录C：树状图前端实现 — 成熟技术方案参考

### C.1 React 树形组件库对比

| 库 | Star | 许可证 | 拖拽 | 虚拟化 | 无障碍 | TypeScript | 维护状态 |
|:---|:----:|:------:|:----:|:------:|:------:|:----------:|:--------:|
| **react-arborist** | 3.4k | MIT | ✅ | ✅ | ✅ | ✅ | 活跃 |
| **@kingstack/dnd-tree** | 新 | MIT | ✅(dnd-kit) | ✅ | ✅ | ✅(泛型) | 活跃 |
| **MUI X Tree View (Community)** | — | MIT | ❌ | ❌ | ✅ | ✅ | 活跃 |
| **MUI X Tree View (Pro)** | — | 商业 | ✅ | ✅ | ✅ | ✅ | 活跃 |
| **react-dnd-treeview** | 1.2k | MIT | ✅(react-dnd) | ❌ | 部分 | ✅ | 低 |
| **react-accessible-treeview** | 322 | MIT | ❌ | ❌ | ✅(WAI-ARIA) | ✅ | 稳定 |

### C.2 推荐方案

**首选：`react-arborist`**（MIT 许可证，3.4k Star，活跃维护）

```
核心特性：
├── 拖拽排序（DnD）
├── 打开/关闭折叠
├── 行内重命名
├── 虚拟化渲染（大规模树必备）
├── 自定义样式
├── 键盘导航
├── Aria 属性
├── 树过滤
└── 选择管理
```

```tsx
// 与项目教学笔记树的数据结构高度匹配
interface TreeNode {
  id: string;
  label: string;
  content: string;
  parentId: string | null;
  order: number;
  children?: TreeNode[];
}

// react-arborist 可直接消费此结构
import { TreeView } from 'react-arborist';

function ProjectTree({ nodes }: { nodes: TreeNode[] }) {
  return (
    <TreeView
      data={nodes}
      openByDefault={false}
      onMove={handleMove}
      onRename={handleRename}
      selection={selectedId}
      onSelect={handleSelect}
    >
      {({ node, style, dragHandle }) => (
        <div style={style} ref={dragHandle}>
          {node.isLeaf ? '📄' : '📁'} {node.data.label}
        </div>
      )}
    </TreeView>
  );
}
```

**备选：`@kingstack/dnd-tree`**（更新，dnd-kit 驱动，Tailwind 友好）

适用于：
- 教学笔记树（`ProjectSettingTree.treeGroup`）
- 左侧栏项目树（`[项目]` 标签下的章节树）
- 技法分类列表的层次展示

### C.3 最终选择建议

| 使用场景 | 推荐方案 | 理由 |
|:---------|:---------|:------|
| 教学笔记树（右侧栏） | react-arborist | 需要拖拽重排 + 行内编辑 + 虚拟化（树可能很大） |
| 左侧栏项目章节树 | react-arborist 或 @kingstack/dnd-tree | 层级较浅，拖拽为副产品，可任一 |
| 技法分类列表 | 纯 CSS + 递归组件 | 无需拖拽，无需虚拟化，减少依赖 |

---

## 附录D：扩展功能（本重构不涉及）

以下功能已识别为潜在需求，但明确标注**不在本次重构范围内**。记录在此供 Phase 4 之后评估。

| 功能 | 说明 | 触发条件 |
|:-----|:------|:---------|
| 暗黑模式 | CSS Design Tokens 已为换色预留了变量架构，但本次不做 dark mode 实现 | Phase 4+ / 用户明确需求 |
| 节点快照对比 | 教学笔记树节点支持历史版本对比，需引入 diff 算法 | Phase 4+ / 用户需求 |
| 批量引用 | 用户一次选中多处文本，批量引用到对话 | Phase 4+ / 用户需求 |
| 用户自定义模板 | 除基础 5 模板外，用户可自定义保存自己的模板 | Phase 4+ / 用户需求 |
| 快捷键系统 | 键盘快捷操作（Ctrl+N 新建会话、Ctrl+[ 收起左侧栏等） | Phase 4+ / 用户需求 |
