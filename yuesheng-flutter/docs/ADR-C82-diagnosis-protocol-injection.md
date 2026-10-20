# ADR-C82：诊断块协议一致性修复与 user 侧动态注入

> 状态：实施中 | 日期：2026-09-07 | 关联：ADR-C74（诊断提交拆分）、ADR-C63（解析拒绝原因）
> 触发：用户全流程实测（2026-09-07）发现结构化诊断卡（DiagnosisCard）不触发

---

## 1. 问题

用户明确请求诊断（「diagnose it / 请诊断这段文字」）时，AI 只输出对话式点评，
**不附加 `[YS_DIAGNOSIS]` 结构化块** → DiagnosisCard 不渲染、diagnosis_results
不落库（实测 0 行）、画像/教学进度/症候跟踪链路全部停摆。

## 2. 证据链（已查证）

| # | 证据 | 结论 |
|:--|:--|:--|
| 1 | 协议真源 skills_l1_core_p2.dart：`[YS_DIAGNOSIS]` 块格式 + 「用户主动请求诊断 → 必附加」；解析器 diagnosis_parser.dart 用同标记（`indexOf(kDiagnosisStart)`） | 协议与解析器标记一致 |
| 2 | skill_dispatcher buildSystemPromptV2：L1 9 skill（含 teaching-strategy）+ 态度 + L2 + 位置引导；无 contentForPhase 裁剪 | 协议段完整注入 system prompt（30231 字符） |
| 3 | **对照实验 A**：仅用协议段 + 简单原则调 DeepSeek（deepseek-v4-flash）→ ✅ 输出完整块 | 模型有能力遵循协议 |
| 4 | **对照实验 B**：真实完整 30231 字符 prompt → ❌ 不输出（回复为 P0 引导式） | 长 prompt 中协议被 P0 指引淹没 |
| 5 | **对照实验 C**：完整 prompt + 末尾追加「输出协议（最高优先级）」强调 → ❌ 仍不输出 | 非位置可见性问题，是指令冲突 + 长上下文遵循度 |
| 6 | **对照实验 D**：完整 prompt + **user 消息侧注入协议** → ✅ 输出完整块（症候+evidence+画像五维） | user 侧注入可绕过淹没 |
| 7 | **纪律冲突**：chat_service `_appendDisciplineReminder` 第 6 条「诊断块用 ```diagnosis``` 包裹」（全仓唯一）与 `[YS_DIAGNOSIS]` 协议/解析器冲突——模型遵循纪律输出 markdown 包裹 → parser 找不到标记 | 即使模型输出结构化诊断也会解析失败 |

## 3. 根因（双叠加）

1. **纪律冲突（确定性缺陷）**：发送链末尾「回复纪律」第 6 条要求 ```` ```diagnosis```` 包裹，
   与协议（`[YS_DIAGNOSIS]`）和解析器（只认 `[YS_DIAGNOSIS]`）**互相矛盾**。
   模型按纪律输出 → 诊断块永不解析。
2. **P0 指引淹没（遵循率问题）**：诊断协议埋藏在 3 万字符 system prompt 中段，
   与 P0「建立投入」指引并存时被主导，用户明确请求诊断也不附加块。
   末尾强调无效（实验 C）；user 侧注入有效（实验 D）。

## 4. 修复方案（最小范围）

### 4.1 纪律第 6 条对齐协议（chat_service.dart `_appendDisciplineReminder`）

把 `6. 诊断块用 ```diagnosis``` 包裹，卡片块用对应标签，不裸露 JSON。`
改为与协议一致的表述：`6. 诊断块按 [YS_DIAGNOSIS]...[/YS_DIAGNOSIS] 标记输出，卡片块用对应标签，不裸露 JSON。`

### 4.2 诊断意图检测（intent_classifier.dart 新增纯函数）

```dart
/// 诊断请求信号：明确请求评价/诊断的措辞
bool isDiagnosisRequest(String text) {
  final t = text.trim();
  if (t.isEmpty) return false;
  return _diagnosisSignals.any(t.contains);
}
```

信号词（保守集合，避免误触发改变模型行为）：
中文：诊断、评价、点评、看看这段、怎么改、哪里不好、怎么改进、帮我分析、分析一下、提提意见
英文：diagnose、diagnosis、analyze、analysis、review、improve、feedback、comment

### 4.3 user 侧动态注入（chat_service extension 新增 helper）

在 `_sendMessageCore` 的 `_assembleSendContext` 之后、`_streamLlm` 之前：

```dart
/// 诊断意图 → user 消息侧注入诊断协议（ADR-C82；绕过长 prompt 指令淹没）
void _maybeInjectDiagnosisProtocol(List<ChatMessage> messages, String content) {
  if (!isDiagnosisRequest(content)) return;
  // 定位最后一条 user 消息（末尾追加协议，贴近输出）
  final lastUser = messages.lastIndexWhere((m) => m.role == 'user');
  if (lastUser < 0) return;
  final m = messages[lastUser];
  messages[lastUser] = ChatMessage(role: m.role, content: '${m.content}\n\n$kDiagnosisProtocolSuffix');
}
```

协议后缀常量（实验 D 验证有效）：

```
【输出要求】
请按系统协议在回复最末尾附加结构化诊断块：
[YS_DIAGNOSIS]
{ "syndromes": ["症候"], "suggested_actions": ["动作"], "confidence": 0.0-1.0 }
[/YS_DIAGNOSIS]
```

## 5. 验证计划

1. **API 复现验证**：真实完整 prompt + 修改后纪律 + user 侧注入 → 应输出 `[YS_DIAGNOSIS]` 块
2. **单测**：
   - `isDiagnosisRequest` 正/负样本（诊断词命中；闲聊/普通创作不命中）
   - `_maybeInjectDiagnosisProtocol`：诊断请求注入到 user 消息；非诊断请求不注入；无 user 消息不崩溃
   - 纪律第 6 条文本契约（不再含 ```` ```diagnosis````）
3. **模拟器回归**：发送「diagnose」→ DiagnosisCard 渲染 + diagnosis_results 落库
4. **全量测试 + 六道门禁**

## 6. 风险与边界

- **误触发风险**：信号词保守；「怎么改」等词在 compose 语境也可能触发注入——注入只是要求模型附加块，模型仍可按 P0 判断是否给出低置信块（协议支持 confidence 低标），不改变对话行为本身
- **token 成本**：注入 ~80 字符，可忽略
- **不改变**：解析器、诊断提交链（ADR-C74）、协议真源（skills_l1_core_p2）均不动

## 7. 回退

单 commit 可回退；纪律文本与注入 helper 各自独立。
