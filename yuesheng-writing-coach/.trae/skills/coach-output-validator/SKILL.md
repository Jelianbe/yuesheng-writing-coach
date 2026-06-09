---
name: "coach-output-validator"
description: "Validates coach AI output against 8 compliance rules (V-01~V-08): no ghost-writing, no decision-making, no internal ID leakage, tone consistency, length limits, suggestion limits, safety-word verification. Invoke after every AI response generation, before sending to user. Also invoke when reviewing/modifying prompt files or diagnosis/training logic."
---

# Coach Output Validator (教练输出合规性校验器)

## Purpose

月笙写作教练的 AI 输出必须遵守严格的教练定位约束。本 Skill 提供一套**基于规则的校验框架**，在每次 AI 回复生成后、发送给用户前进行自动检测，确保输出符合 R-025 教练定位和 System Prompt S6 输出验证清单。

## When to Invoke

- **每次 AI 对话回复生成后** — 在 `handleStreamResponse()` 的后处理阶段
- **修改 Prompt 文件时** — 验证新 Prompt 是否保留了校验约束
- **审查诊断/训练逻辑时** — 确保新增的 Agent 能力不违反教练铁律

## The 8 Validation Rules

### V-01 [P0] 禁止替用户写完整句子/段落

**Source**: R-025 §核心约束 — "不替用户写句子或做决定"

**Detection**: 检测连续非引用文本 > 50 字且包含改写式表达（如"可以改为"/"建议改成"/"这样写更好"）

**Pattern (regex)**:
```typescript
// 警告模式：大段改写文本（>50字连续非引用内容）
const GHOST_WRITE_PATTERN = /(?:可以改为|建议改成|这样写|不如改为|推荐写成)[^>\n]{50,}/;
```

**Action**: 🔴 **拦截** — 此类回复不得发送给用户。应重写为分析+提问形式。

### V-02 [P0] 禁止替用户做决定

**Source**: R-025 §核心约束 + R-009 用户主权

**Detection**: 决策句式检测

**Patterns**:
```typescript
const DECISION_PATTERNS = [
  /你应该(选择|采用|使用|写|改)/,
  /你可以(直接|这样|直接这样)/,
  /我建议你(一定要|务必|一定)/,
  /(这个|这|那)个方案(最好|肯定|绝对)/,
];
```

**Action**: 🔴 **拦截** — 替换为"你有两个方向可以考虑：A... B... 你觉得哪个更接近你想表达的？"

### V-03 [P1] 禁止暴露内部编号

**Source**: `diagnosis-agent-prompt-v1.md` S6 输出验证 — "隐性诊断铁律"

**Detection**: 内部编号泄露检测

**Pattern**:
```typescript
// 症候编号 P001-P010, 动作编号 A001-A012, 意图矛盾 I001-I006
const INTERNAL_ID_PATTERN = /\b(P0\d{2}|A0\d{2}|I0\d{2}|H0\d{2}|E00\d)\b/;
```

**Action**: 🟡 **警告 + 自动替换** — 将编号映射为人类可读名称后再发送。

### V-04 [P1] 语气档位一致性检测

**Source**: `TeachingStrategyService` 态度档位定义

**Detection Table**:

| 当前档位 | 禁止出现 | 示例 |
|---------|---------|------|
| `sensei` (L3) | 豆包风格表情/口语化 | "哈哈"、"哦哦"、"呢~"、"呀"、😊 |
| `yuesheng` (L2) | 过度亲昵/过度疏离 | "亲爱的"、"宝贝" 或 过于机械的学术腔 |
| `doubao` (L1) | sensei 式严厉 | 不应出现 |

**Action**: 🟡 **标记** — 记录到诊断日志，不拦截但统计漂移频率。

### V-05 [P2] 单次回复段落数限制

**Source**: `yuesheng-prompt-v3.md` S2.6 全局约束

**Rule**: 回复不超过 **4 个段落**（含问候语）

**Detection**: 统计 `\n\n` 分隔的文本块数量

**Action**: 🟢 **截断** — 超过 4 段时保留前 3 段核心内容 + 1 段引导性结尾。

### V-06 [P2] 建议堆叠限制

**Source**: `yuesheng-prompt-v3.md` S2.6 全局约束

**Rule**: 单次回复不超过 **3 个具体建议**

**Detection**: 统计有序列表/编号列表项数

**Action**: 🟢 **合并** — 将 >3 个建议按主题归类为 2-3 个方向。

### V-07 [P1] 安全词降档验证

**Source**: R-025 安全词机制 + `DisputeTrackerService`

**Rule**: 用户说"轻一点"后，当前回复必须比前一条回复**更温和**（档位已降低）

**Detection**: 比对当前 attitudeLevel 与 DisputeTracker 记录的上一次降档后的期望档位

**Action**: 🟡 **强制降档** — 若未降档，自动将 attitudeLevel 降低一级后重新生成。

### V-08 [P2] 引用格式规范

**Source**: REF-AUDIT 引用链路修复

**Rule**: 章节引用必须使用 `[[chapter:uuid:title]]` 格式，AI 回复中提及章节时必须保留原始引用标记

**Detection**: 正则匹配引用格式完整性

**Action**: 🟢 **修复** — 补全缺失的引用格式。

## Output Format

```typescript
interface ValidationResult {
  passed: boolean;           // true = 所有 P0 规则通过
  score: number;             // 0-100 合规分数
  violations: Array<{
    ruleId: string;          // "V-01" ~ "V-08"
    severity: 'P0' | 'P1' | 'P2';
    message: string;
    excerpt: string;         // 违规文本摘录（≤100字）
    suggestion: string;
    autoFixable: boolean;    // 是否可自动修复
  }>;
}
```

## Scoring Formula

```
score = 100
      - (P0 违规数 × 25)
      - (P1 违规数 × 10)
      - (P2 违规数 × 5)
score = max(0, score)
```

## Integration Point

在 `chat.handler.ts` 的 `handleStreamResponse()` 中，流结束后、IPC 发送前插入：

```typescript
// 在 CHAT_STREAM_END 之前
const validation = validateCoachOutput(aiResponseText, currentAttitude);
if (!validation.passed && validation.violations.some(v => v.severity === 'P0')) {
  writeDebugLog('Coach:OutputViolated', { violations: validation.violations });
  // 可选：触发重新生成或降级处理
}
```

## Notes

- 本 Skill 是**规则引擎**，不是 ML 分类器。优先保证确定性和速度。
- P0 规则必须 100% 通过才能发送；P1/P2 可记录但允许通过。
- 校验结果写入 `%APPDATA%/debug-coach.log` 用于后续分析。
