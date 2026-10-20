# ADR-C83：扩展 OpenAI 兼容多模型供应商

- 状态：已实施（commit 87f87d4c，2026-09-08）
- 范围：LLM 客户端 / 设置页 / 隐私文案
- 决策人：舰长（用户）确认方向后实施

## 背景

当前仅支持 DeepSeek（默认 `https://api.deepseek.com` + `deepseek-v4-flash`）。
用户要求扩展适配 OpenAI 及其他大模型。

## 现状调研（已查证）

| 层 | 结论 |
|:--|:--|
| 协议层（llm_client.dart） | 已 100% OpenAI Chat Completions 兼容：`{baseUrl}/chat/completions` + Bearer + `messages`，SSE 按 `data: ` 行解析 + `[DONE]` |
| 配置层（llm_config_storage.dart） | 三字段（apiKey/baseUrl/model）+ fallbacks 备选端点链，无供应商绑定 |
| 唯一 DeepSeek 硬编码 | 设置页 UI：默认值、重置按钮、Key 引导对话框、隐私弹窗文案 |

## 决策

### P0：模型参数差异适配（核心）

- 新增 `classifyLlmModel(model)` 纯函数：按前缀识别 OpenAI **o 系列推理模型**（`o1/o3/o4/gpt-5` 及 `-mini/-preview` 变体）。
- 推理模型请求体：**去 `temperature`**（o 系列不支持，会 400）、`max_tokens` → **`max_completion_tokens`**。
- DeepSeek 系与其他 OpenAI 兼容端点：保持 `max_tokens` + `temperature` 现状，**零行为变化**。

### P1：供应商预设（设置页）

- 新增 `_llmPresets` 常量表（6 家：DeepSeek/OpenAI/Kimi/通义/智谱/豆包），Model 字段下渲染 ActionChip 行。
- 点选自动填 Base URL + Model 默认值；**API Key 不预设**（各供应商独立，R-029 零硬编码）。

### P2：文案泛化

- 「如何获取 DeepSeek Key」→「如何获取 API Key」，引导内容泛化为多服务商通用步骤。
- 隐私弹窗：「发送至 DeepSeek API」→「发送至你所选的 AI 服务商 API」；费用句「你的 DeepSeek 账户」→「你对应的服务商账户」。

### 明确不做

- 协议层、SSE 解析、重试/降级链、配置存储结构：无需改动。
- temperature/max_tokens 高级参数 UI：未开放（默认值保持）。

## 风险与后续

- 不同模型指令遵循能力差异大（ADR-C82 已证 deepseek-v4-flash 需 user 侧注入才稳定输出诊断协议）——**切换模型后需复测诊断块触发率**（`[YS_DIAGNOSIS]`）。
- OpenAI o 系列为推理模型，首字延迟更高，流式连接超时（60s）已留足。
- o 系列响应可能带 `reasoning_content` 字段——当前解析只取 `delta.content`，自动忽略，无影响。

## 验证

- 新增 `classifyLlmModel` 5 用例（o 系列/DeepSeek/其他/大小写/空串边界）。
- 设置页/隐私测试适配新文案与滚动（视口外按钮 dragUntilVisible）。
- 全量 `+2577 All tests passed`；六道门禁 6/6。
