# B66 时序矛盾冲突检测地基（B62i / A6 首步）— 交付提交日志

**日期**：2026-08-09
**类型**：功能地基（A6 人物一致性首步：只记不改码）
**前置**：`2b2c0f3`（批次 65，B62e 回退 + B62h 复发率）

---

## 背景与立项

B62i「时序矛盾检测」（规格权威来源：docs/2026-08-09-b58-research-audit.md）：
- 人物表带 `first_seen_chapter` + 属性断言列表；同属性不同值 → 时序矛盾观察项（挂 F05 补充，行为偏离已建立模式 / P018 人设崩塌症）
- 表结构必须带章节/时间双维度（TKG 区别于 KV 存储的根本）
- L120 约束：「本期只记不改码」——只搭地基，不接 LLM 自动提取

## 执行决策（用户确认）

1. **Flutter 先行**：RN 端（yuesheng-android）可废弃仅作参考，dao 目录无人物/伏笔表、数据结构无法对齐，本次全部在 Flutter 端落地
2. **只搭地基**：纯规则精确比较（字符串相等），不接 LLM 语义提取；注入层零 token 成本（无数据不注入）
3. **软引导非硬拦截**：观察项作为上下文注入诊断（挂 F05 补充），由 AI 自主判断是否提及，不强制改码

## 改动内容

### 数据层（TKG 双维度）
- [character_types.dart](../lib/types/character_types.dart)（新）：`CharacterAssertion` 数据类（attribute / value / chapter / timestamp）+ toJson + 宽松 tryFromJson（非法字段保守跳过）
- [tables.dart](../lib/data/database/tables.dart)：`CharacterFacts` 表（第 15 张，`character_fact`）——id / manuscriptId(FK cascade) / name / firstSeenChapter(可空) / firstSeenAt(可空) / assertions(JSON) / createdAt / updatedAt；`UNIQUE(manuscript_id, name)`
- [database.dart](../lib/data/database/database.dart)：`schemaVersion => 16`；守卫 `if (from >= 16) return;`；v16 迁移建表 + 索引（幂等 IF NOT EXISTS）；`@DriftDatabase` 注册 `CharacterFacts`

### 检测器（纯函数，无 IO）
- [conflict_detector.dart](../lib/services/conflict_detector.dart)（新）：`detectCharacterConflicts`——按 (人物, 属性) 分组 → 组内按 章节(null 排最后)→时间戳 升序 → 去重后不同值 ≥2 构成观察项（取最早两个）→ 输出按 (人物名, 属性) 字典序稳定排序

### 仓储
- [character_fact_repository.dart](../lib/data/repositories/character_fact_repository.dart)（新）：`upsertCharacter`（同作品按 name 唯一，事务内 upsert）/ `listCharacters` / `getCharacter` / `parseAssertions`（JSON 非法/脏条目保守跳过）

### 注入层（5.1.3，与 5.1.2 声线漂移同构）
- [chat_context_builder.dart](../lib/services/chat_context_builder.dart)：`buildConflictObservationsContext`——空返回 null；非空注入「## 时序矛盾观察（F05 补充）」：措辞「只定位，不代改正文」「结合 P018 人设崩塌症」
- [chat_service.dart](../lib/services/chat_service.dart)：可选字段 `_characterFactRepo`；5.1.3 区块（声线漂移 5.1.2 之后）——触发条件 = 诊断标记 + 章节主引用 + 仓储已装配；流程 = getChapter → listCharacters → parseAssertions → detectCharacterConflicts → 非空注入 system 消息；catch 吞错不阻断主流程
- [session_providers.dart](../lib/providers/session_providers.dart)：`chatServiceProvider` 装配 `characterFactRepo`

### 测试（净 +16）
- [conflict_detector_test.dart](../test/services/conflict_detector_test.dart)（新，9 用例）：空输入 / 同属性不同值 / 同值不误报 / 乱序→时间序 / 章节 null 排最后 / 多人物字典序 / 取最早两个 / 空上下文→null / 非空上下文含观察与措辞
- [character_fact_repository_test.dart](../test/data/repositories/character_fact_repository_test.dart)（新，4 用例）：upsert→list/get 往返 / 重复 upsert 更新断言 / 多人排序 / parseAssertions 宽松跳过
- [chat_service_conflict_injection_test.dart](../test/services/chat_service_conflict_injection_test.dart)（新，3 用例）：有冲突→注入 / 无人物数据→不注入 / 非诊断消息门控
- [widget_test.dart](../test/widget_test.dart)（更新）：预期表数 14→15、user_version 15→16

## 关键设计

- **TKG 时间维度**：人物断言带 章节 + 时间戳 双维度，是时序矛盾检测区别于 KV 存储的根本；null 章节视为「早期」排最后
- **与漂移检测同构挂接**：5.1.3（A6 冲突）与 5.1.2（L3 漂移）同一模式——诊断标记 + 章节主引用 + 各自仓储装配，均 catch 吞错不阻断主流程
- **防污染由隔离达成**：人物事实表本期无任何写入路径（不接 LLM 提取、写作端不写），天然不进入知识链路
- **AI 自主判断优先**：观察项仅作诊断上下文补充（F05），措辞限定「只定位，不代改正文」，不硬拦截
- **零 token 成本**：无人物数据 / 无冲突时不注入任何内容，空运行不改变既有诊断行为

## 四闸验证

- `dart format`：全过（批次文件 0 changed；范围外文件格式化后已还原）
- `flutter analyze`：0 error 0 warning（32 info 全历史存量，未新增）
- `flutter test`：全量 **929 全绿 + 4 skipped**（净 +16：检测 9 + 仓储 4 + 注入 3）
- 文档同步：本日志

## 提交

| Commit | 日期 | 标题 |
|--------|------|------|
| （本次） | 2026-08-09 | feat: 批次66 时序矛盾冲突检测地基（B62i/A6 首步：character_fact 表 + v16 迁移 + 纯规则检测器 + 诊断上下文 5.1.3 挂接，本期只记不改码） |
