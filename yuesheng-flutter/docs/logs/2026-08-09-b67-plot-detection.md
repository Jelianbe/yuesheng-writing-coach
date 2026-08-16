# B67 A6 第二迭代：F07 因果链断裂 + F11 情节闭环（B62j）— 交付提交日志

**日期**：2026-08-09
**类型**：功能地基（A6 第二迭代：只记不改码）
**前置**：`792bd8b`（批次 66，时序矛盾冲突检测地基 B62i / A6 首步）

---

## 背景与立项

B62j「A6 预留项」（规格权威来源：docs/2026-08-09-b58-research-audit.md L135 + V2.0 §3.3）：
- **F07 因果链断裂**（Lv4）：TKG 事件节点因果边缺失检测。反馈范式「主角为什么突然决定去那个城市？缺少一个触发事件」；映射 P021 跳跃叙事 / P016 情节巧合
- **F11 情节闭环**（Lv4）：子线是否自然收束。反馈范式「第2卷引出了3条支线，目前只回收了1条」；映射 P014 结尾仓促 / P017 伏笔不回收
- L120 约束：「本期只记不改码」——只搭地基，不接 LLM 自动提取、不预填数据

用户确认批次 67 = A6 第二迭代 F07/F11（延续批次 66「Flutter 先行 + 只搭地基」决策）。

## 改动内容

### 数据层（TKG 双维度，schemaVersion 16 → 17，共 17 张表）
- [tables.dart](../lib/data/database/tables.dart)：
  - `EventFacts` 表（第 16 张，`event_fact`）——id / manuscriptId(FK cascade) / name / chapter(可空) / eventType（决定/转折/突发/冲突/日常）/ causeEventId(可空，因果前驱) / effectEventId(可空，因果后继) / participants(JSON) / description / createdAt / updatedAt；`UNIQUE(manuscript_id, name)`
  - `SubplotFacts` 表（第 17 张，`subplot_fact`）——id / manuscriptId(FK cascade) / name / introducedChapter(可空) / resolvedChapter(可空，null=未回收) / resolvedAt(可空) / description / createdAt / updatedAt；`UNIQUE(manuscript_id, name)`
- [database.dart](../lib/data/database/database.dart)：`schemaVersion => 17`；守卫 `if (from >= 17) return;`；v17 迁移建两表 + 索引（幂等 IF NOT EXISTS）；`@DriftDatabase` 注册 `EventFacts, SubplotFacts`；onCreate 索引 `idx_event_fact_manuscript` / `idx_subplot_fact_manuscript`

### 检测器（纯函数，无 IO）
- [event_causality_detector.dart](../lib/services/event_causality_detector.dart)（新）：`detectCausalityBreaks`——关键事件类型集合 `{决定, 转折, 突发}`（报告「突然…/为什么…」范式），因果前驱 causeEventId 为空 → 因果链断裂观察项；输出按 章节(null 排最后)→事件名 排序
- [subplot_closure_detector.dart](../lib/services/subplot_closure_detector.dart)（新）：`detectUnclosedSubplots`——resolvedChapter 为 null 且 当前章节 - 引入章节 ≥ 3（`kSubplotGraceChapterCount`，给作者回收留空间避免误报）→ 收束滞后观察项；无引入章节的支线保守跳过；输出按引入章节升序

### 仓储
- [event_fact_repository.dart](../lib/data/repositories/event_fact_repository.dart)（新）：`upsertEvent`（同作品按 name 唯一，事务内 upsert）/ `listEvents`（章节排序，null 排最后）/ `getEvent` / `parseParticipants`（JSON 非法/脏条目保守跳过）
- [subplot_fact_repository.dart](../lib/data/repositories/subplot_fact_repository.dart)（新）：`upsertSubplot` / `listSubplots` / `getSubplot`

### 注入层（5.1.4 / 5.1.5，与 5.1.2/5.1.3 同构）
- [chat_context_builder.dart](../lib/services/chat_context_builder.dart)：`buildCausalityBreakContext`（「## 因果链断裂观察（F07 补充）」+ P021/P016）+ `buildSubplotClosureContext`（「## 情节闭环观察（F11 补充）」+ P014/P017，≥2 条附「共 N 条支线收束滞后」汇总）；空输入均返回 null（零 token 成本）
- [chat_service.dart](../lib/services/chat_service.dart)：可选字段 `_eventFactRepo` / `_subplotFactRepo`；5.1.4（F07）/ 5.1.5（F11）区块——触发条件 = 诊断标记 + 章节主引用 + 仓储已装配；F11 当前章节取主引用章节 `sortOrder`；catch 吞错不阻断主流程
- [session_providers.dart](../lib/providers/session_providers.dart)：`chatServiceProvider` 装配 `eventFactRepo` / `subplotFactRepo`

### 测试（净 +28）
- [event_causality_detector_test.dart](../test/services/event_causality_detector_test.dart)（新，8 用例）：空输入 / 决定类缺前因 / 有前因不误报 / 非关键类型不误报 / 乱序按章节 / null 排最后 / 空上下文→null / 非空上下文含观察与措辞
- [subplot_closure_detector_test.dart](../test/services/subplot_closure_detector_test.dart)（新，8 用例）：空输入 / 超阈值未回收 / 已回收不误报 / 未到阈值不报 / 无锚点跳过 / 多条按引入排序 / 空上下文→null / 非空上下文含汇总
- [event_fact_repository_test.dart](../test/data/repositories/event_fact_repository_test.dart)（新，4 用例）：upsert→list/get 往返 / 重复 upsert 更新 / 章节排序 / parseParticipants 宽松跳过
- [subplot_fact_repository_test.dart](../test/data/repositories/subplot_fact_repository_test.dart)（新，4 用例）：upsert→list/get 往返 / 重复 upsert 更新 / 引入章节排序 / 回收字段往返
- [chat_service_plot_injection_test.dart](../test/services/chat_service_plot_injection_test.dart)（新，4 用例）：F07 有数据→注入 / F11 有数据→注入 / 无数据→不注入 / 非诊断消息门控
- [widget_test.dart](../test/widget_test.dart)（更新）：预期表数 15→17、user_version 16→17

## 关键设计

- **TKG 时间维度**：事件节点带 章节 + 因果边（cause/effect），支线节点带 引入/回收 双章节，均区别于 KV 存储
- **保守检测规则**：F07 仅检测关键事件类型（决定/转折/突发）缺前因，非关键事件不检测避免误报；F11 引入 ≥3 章未回收才提示（给作者回收留空间），无时间锚点的支线不检测
- **与既有检测同构挂接**：5.1.4/5.1.5 与 5.1.2（L3 漂移）/ 5.1.3（A6 时序矛盾）同一模式——诊断标记 + 章节主引用 + 各自仓储装配，均 catch 吞错不阻断主流程
- **防污染由隔离达成**：事件/支线表本期无任何写入路径（不接 LLM 提取、不预填），天然不进入知识链路（L120「只记不改码」）
- **AI 自主判断优先**：观察项仅作诊断上下文补充（F07/F11），措辞限定「只定位，不代改正文」，不硬拦截
- **零 token 成本**：无事件/支线数据、无观察项时不注入任何内容，空运行不改变既有诊断行为

## 四闸验证

- `dart format`：全过（批次文件 0 changed；范围外文件格式化后已还原）
- `flutter analyze`：0 error 0 warning（32 info 全历史存量，未新增）
- `flutter test`：全量 **957 全绿 + 4 skipped**（较批次 66 净 +28：检测器 16 + 仓储 8 + 注入 4）
- 文档同步：本日志

## 提交

| Commit | 日期 | 标题 |
|--------|------|------|
| （本次） | 2026-08-09 | feat: 批次67 A6 第二迭代 因果链断裂+情节闭环（B62j：event_fact/subplot_fact 表 + v17 迁移 + F07/F11 纯规则检测器 + 诊断上下文 5.1.4/5.1.5 挂接，只记不改码） |
