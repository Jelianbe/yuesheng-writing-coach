# T-018 Challenge-Unlock 反思门控设计

> **对应发现**：发现9 — AI 温和偏差  
> **优先级**：P1  
> **工作量**：2天  
> **依赖**：T-016（辩驳追踪）✅、T-017（态度统一）✅  
> **前端改动**：新增反思问题展示组件

---

## 一、问题

当前 AI 的响应流程是"诊断即给建议"：

```
用户发消息 → 诊断 → AI 直接给出建议
```

导致：
1. 用户没有反思机会，被动接收建议
2. AI 默认倾向温和引导（A001/A004 兜底）
3. 用户容易形成依赖，不会主动思考

## 二、目标

在"诊断"和"给出建议"之间插入一个"反思关卡"：

```
用户发消息 → 诊断 → 是否触发反思门控
  ├── 是 → AI 输出反思性问题 → 用户回答 → AI 结合回答给出建议
  └── 否 → AI 直接给出建议
```

## 三、设计

### 3.1 反思触发条件

```typescript
function shouldTriggerReflection(diagnosis: DiagnosisAnalysis): boolean {
  // 有症候发现时触发
  if (diagnosis.syndromeRef.length === 0) return false;
  
  // 只对主要症候触发（忽略纯信息型）
  const significantSyndromes = diagnosis.syndromeRef.filter(s => s.severity !== 'L1');
  return significantSyndromes.length > 0;
}
```

### 3.2 反思性问题生成

每种症候对应一个反思性问题，由 AI 根据上下文生成：

```typescript
// 反思问题模板（Prompt 层）
const REFLECTION_PROMPT = `
你发现用户的作品有以下问题：{syndromeList}

在给出建议前，先向用户提出一个诊断性的反思问题。
目标是让用户自己意识到问题所在。

要求：
1. 问题要具体，针对发现的问题
2. 不要暗示答案
3. 语气可以是引导式或挑战式，取决于当前教学态度

然后等待用户回答。
`;
```

**示例**：

| 症候 | 反思性问题 |
|------|-----------|
| P001 世界观膨胀 | "你的开场很精彩，但如果让主角先出场再做介绍，你觉得效果会有变化吗？" |
| P004 信息硬塞 | "读者第一次看到这个设定时，你认为他们最需要先知道什么？" |
| P009 角色动机缺失 | "你觉得这个角色为什么选择这么做？他的动机足够支撑后面的情节吗？" |

### 3.3 教学状态机扩展

新增 `S2_REFLECTION` 子阶段：

```
P2_PRACTICE_LOOP.S2_REFLECTION
  └── AI 输出反思性问题
  └── 等待用户回答
  └── 用户回答后 → AI 结合回答给出建议
  └── → S3_PRACTICE 或 S4_REVIEW
```

> **与 T-016 辩驳追踪的交互**：当教学状态机处于 `S2_REFLECTION` 阶段时，用户的回答**不纳入辩驳计数**。用户回答反思问题时说"你不对，我的角色就是这样的"不算辩驳——他们是在配合反思流程，不是在对抗教练。DisputeTracker 的 `getEffectiveAttitude()` 接收 `isReflectionPhase` 参数来排除反思阶段的消息。详见 dispute-tracking-escalation_V1.0.md §3.2.1 第 5 条。

### 3.4 前端展示

反思问题在聊天流中显示为普通消息，但带有特殊标记：

```typescript
interface ReflectionMessage {
  type: 'reflection';
  question: string;
  syndromeId: string;
  answered: boolean;
}

// 渲染时：
// - 如果 answered === false，显示反思问题卡片
// - 用户回复后自动附加到消息中
```

### 3.5 与挑战模板的集成

`challenge-templates.json` 中的模板可以作为反思性问题后的训练动作：

```
反思问题（用户回答）
  → AI 结合回答给出分析
  → 如果用户答案有偏差，触发 challenge-templates 中的微练
  → 如果用户答案正确，AI 确认并给出进阶建议
```

## 四、涉及文件

| 文件 | 改动类型 |
|------|---------|
| `src/main/services/reflection-gate.service.ts` | **新建** |
| `src/main/ipc/chat.handler.ts` | 在诊断和建议之间插入反思门控 |
| `src/main/services/teaching-state-machine.ts` | 扩展 `S2_REFLECTION` 子阶段 |
| `src/renderer/components/chat/ChatMessage.tsx` | 支持反思消息渲染 |
| `resources/config/challenge-templates.json` | 已有，接入反思门控 |

## 五、DoD

1. 症候发现时触发反思门控，输出反思性问题
2. 无症候时直接给建议（不触发）
3. 用户回答反思问题后，AI 结合回答给出建议
4. 反思问题根据教学态度调整语气（引导式/挑战式）
5. TypeScript 编译无错误
6. 5 个测试覆盖触发/不触发/不同语气场景

## 六、变更记录

| 版本 | 日期 | 变更内容 |
|------|------|---------|
| V1.0 | 2026-06-05 | 初始设计 |
