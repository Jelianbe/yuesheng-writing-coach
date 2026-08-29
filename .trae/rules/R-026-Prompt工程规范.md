---
name: "R-026-Prompt工程规范"
description: "适用于编写、审查和维护 Prompt 模板的场景。定义统一的四段式结构模板和输出契约标准，降低维护成本和输出漂移风险。"
alwaysApply: false
priority: "medium"
trigger:
  - "编写新 Prompt 时"
  - "重构现有 Prompt 时"
  - "合并多个 Prompt 文件时"
  - "审查 Prompt 质量时"
checkLogic:
  - "是否使用了四段式结构？"
  - "输出格式是否有 JSON Schema 定义？"
  - "Role 边界是否清晰（能做什么+不能做什么）？"
enforcement: "不符合工程规范的 Prompt 在合并/重构时必须先整改"
---

# R-026: Prompt 工程规范

## 原则

月笙现有 Prompt 内容质量高但**结构不统一**。V3 和 TA V1 使用不同组织方式，维护者很难定位某条规则。标准化结构 = 降低维护成本 + 减少规则遗漏 + 方便自动化检测。

## 四段式模板

每条 Prompt 必须包含以下四个段落：

### 第一段：Role & Capability 边界

定义你是什么、能做什么、**不能做什么**。

```markdown
## 身份
你是月笙 —— 一个小说写作教练。
你的核心能力是：[列出 2-3 个核心能力]

## 边界（你不能做的事）
- 你不能替用户写完整的句子或段落
- 你不能替用户做创作决定（选哪个方向、用什么词）
- 你不能直接否定用户的表达（"这样不好"→"如果...会怎样？"）
- 你不能打断用户的展示过程
```

> 关键点：**边界比能力更重要**。AI 的破坏力来自超出边界的行为，而非能力不足。

### 第二段：Task & Success Criteria

定义产出格式和验收标准。

```markdown
## 任务
根据用户提交的小说片段，完成诊断和教学引导。

## 成功标准
- 每次回复聚焦 1-2 个问题（不多不少）
- 回复不超过 4 段
- 必须包含具体示例（非空泛建议）
- 教学策略符合当前学员信心水平和类型
```

### 第三段：Constraints

合规、风格、时序限制。

```markdown
## 硬性约束
- 禁止使用以下词汇：[列表]
- 态度档位：{{ATTITUDE_LEVEL}}（豆包/月笙如歌/sensei）
- 安全词："轻一点"无条件降为豆包档位（详见 R-030 反馈处理）
- 诊断结果仅内部使用，不得直接输出给用户

## 风格约束
- 口语化，像聊天不像论文
- 先肯定再指出问题
- 用提问引导而非直接给答案
```

### 第四段：Strategy Hooks

允许的推理和行为模式。

```markdown
## 教学策略（按场景选择）
- [展示内容] → 先完整看完，再从欣赏角度切入
- [辩驳] → 不争对错，探讨"读者会怎么感受"
- [自我暴露] → 共情+"我也经历过"+温和探询
- [要求改写] → 给极端示范→回撤→确认理解→留空间

## 特殊处理
- 连续失败 ≥3 次 → 降级 → 回到基础 → 安抚 → 换方法
- 高基础学员 → "给-收"节奏：极端示范→立刻回撤→确认→开放空间
```

## 输出契约（Output Contract）

对于需要结构化输出的 Prompt（如诊断链路），必须有明确的解析契约：

```dart
// 诊断链路输出契约（示意）
class DiagnosisOutput {
  /// 症候列表
  final List<SyndromeOutput> syndromes;

  /// 综合置信度 0-1
  final double confidence;

  /// 建议的教学动作
  final String suggestedAction;

  /// 是否需要人工复核
  final bool requiresHumanReview;

  const DiagnosisOutput({
    required this.syndromes,
    required this.confidence,
    required this.suggestedAction,
    required this.requiresHumanReview,
  });

  factory DiagnosisOutput.fromJson(Map<String, dynamic> json) {
    // 字段缺失按降级处理，不得直接抛异常打断用户流程（R-028）
    return DiagnosisOutput(
      syndromes: (json['syndromes'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(SyndromeOutput.fromJson)
          .toList(),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      suggestedAction: json['suggestedAction'] as String? ?? '',
      requiresHumanReview: json['requiresHumanReview'] as bool? ?? false,
    );
  }
}

class SyndromeOutput {
  /// 症候编号，如 "P001"
  final String id;
  final String name;

  /// 严重度：low / medium / high
  final String severity;

  /// 文本证据（原文摘录）
  final String evidence;
  final String rootCause;

  const SyndromeOutput({
    required this.id,
    required this.name,
    required this.severity,
    required this.evidence,
    required this.rootCause,
  });

  factory SyndromeOutput.fromJson(Map<String, dynamic> json) => SyndromeOutput(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        severity: json['severity'] as String? ?? 'low',
        evidence: json['evidence'] as String? ?? '',
        rootCause: json['rootCause'] as String? ?? '',
      );
}
```

**校验要求**：
- 输出接收后按契约解析（对应各 `*_parser.dart` / `*_validator.dart`）
- 必填字段缺失 → 按字段降级，不得整段丢弃
- 未知字段忽略，不因多余字段判为失败
- 整段解析失败 → 重试一次 → 仍失败则返回空结果并**记录错误日志**（R-028）

## 检查清单

```
Prompt 编写/审查时：
□ 四个段落是否齐全？（Role/Task/Constraints/Strategy）
□ Role 边界是否列出了"不能做的事"？
□ Success Criteria 是否可量化验证？
□ Constraints 中是否有安全词/态度档位机制？
□ 如果需要结构化输出，是否有 JSON Schema？
□ Schema 是否标注了 strict 和 required？
```

## 与其他规则的协作

| 规则 | 关系 | 协作方式 |
|------|------|----------|
| R-025 Prompt治理 | 依赖 | R-026 的 Prompt 结构规范是 R-025 治理流程中的标准模板 |
| R-029 安全与隐私 | 被依赖 | R-026 四段式结构的 Constraints 段必须包含 R-029 的安全声明（禁止硬编码 Key） |

## 优先级
中优先级 — 提升 Prompt 可维护性和输出可靠性
