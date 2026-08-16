# B72 大纲层（AI 自主记忆沉淀）— 交付提交日志

**日期**：2026-08-09
**类型**：功能（诊断两层拆分·大纲层后端：实体/印象表 + 提取协议 + 匹配/合并/冲突逻辑）
**前置**：`41944a2`（批次 71，F02 对话标签过度）

---

## 背景与立项

用户提出**诊断两层拆分**设计：① **大纲层（事件/人物层）**——AI 自主提取剧情/人设/设定梗概沉淀入库；② **写作层（写法层）**——文字内容/写作手法诊断。两层分离后，F09 角色动态关系才有可信数据源（跨章节检测依赖大纲层数据）。

用户核心关切：**记忆可交互性 + 同人物两次入库导致印象混乱**。本批落地三件套：
**实体对齐（防重复入库）→ 增量合并（防印象覆盖）→ 用户确认（pending 态兜底）**。
经用户确认：AI 匹配 + 用户兜底、冲突标记待裁决、独立 OUTLINE 块、后端先行（UI 确认卡片下一批）。

## 改动内容

### 表结构（v18 迁移，2 张新表，17 → 19 张）
- [tables.dart](../lib/data/database/tables.dart) + [database.dart](../lib/data/database/database.dart)：
  - `outline_entity`：实体表——entity_type(character/setting/plot) + entity_key(规范名) + aliases(JSON 别名表) + status(pending/active/rejected)，UNIQUE(manuscript_id, entity_key)
  - `outline_impression`：印象表——单条梗概 + source_chapter_id(来源可追溯) + version + conflict_with(冲突标记) + status(pending/active/rejected/superseded)，UNIQUE(entity_id, impression) 防同文本重复

### 提取协议 + 解析器（独立 OUTLINE 块）
- [outline_parser.dart](../lib/services/outline_parser.dart)：`[YS_OUTLINE]...[/YS_OUTLINE]` 块 JSON 白名单校验（非法 → null 降级，不阻断主流程，仿 diagnosis_parser）

### 业务编排（匹配/合并/冲突）
- [outline_repository.dart](../lib/data/repositories/outline_repository.dart)：实体/印象 DAO（别名解析、同文本去重、别名合并）
- [outline_service.dart](../lib/services/outline_service.dart)：
  - `buildEntityIndexContext`：注入当前实体索引（名+别名+已确认印象），AI 匹配防重复的前提
  - `applyOutlineExtraction` 匹配优先级：① matched_entity_id（**必须存在于当前实体集合，防 AI 幻觉 id**）→ ② 别名交集规则匹配 → ③ 新建（pending）
  - 增量合并：命中已有实体 → 追加印象不覆盖；conflict_with 仅采信同实体已有印象 id（防幻觉）

### 诊断链路挂接
- [chat_service.dart](../lib/services/chat_service.dart)：5.1.8 注入实体索引（诊断 + 章节主引用 + 装配 outlineRepo）+ 步骤 9.1 解析 OUTLINE 块落库（失败不阻断）；OutlineRepository 可选参数（不装配则跳过）
- [session_providers.dart](../lib/providers/session_providers.dart)：装配 outlineRepo 启用

### 测试（净 +17）
- [outline_parser_test.dart](../test/services/outline_parser_test.dart)（+6）：无块/不完整/合法/非法/字段校验/matched_id 保留
- [outline_service_test.dart](../test/services/outline_service_test.dart)（+8）：索引构建/匹配命中/幻觉 id 回退/别名交集/新建 pending/去重/conflict 采信 vs 幻觉
- [chat_service_outline_test.dart](../test/services/chat_service_outline_test.dart)（+3）：落库端到端/索引注入/未装配跳过
- [widget_test.dart](../test/widget_test.dart)：schemaVersion 17→18、业务表 17→19 断言更新

## 关键设计

- **两层拆分落点**：大纲层（本批）= AI 记忆沉淀；写作层 = 现有症候/检测器诊断链路（不动）；F09 后续挂大纲层数据
- **防印象混乱三件套**：实体对齐（matched_id 存在性校验 + 别名交集，防「王叔/王建国」两次入库）→ 增量追加（不整体覆盖）→ pending 确认态（用户确认后才 active，满足 B58「自动提取→用户确认」约束，防 AVOID-02 回归）
- **防 AI 幻觉双闸**：matched_entity_id 必须存在于实体索引；conflict_with 必须指向同实体已有印象
- **来源可追溯**：每条印象带 source_chapter_id/No + version，印象混乱时可回溯纠正
- **零侵入写作层**：写作层诊断协议零改动；大纲块独立，解析失败不影响诊断

## 四闸验证

- `dart format`：全过（范围外历史存量文件已还原）
- `flutter analyze`：0 error 0 warning（32 info 全历史存量，本批 4 个新增 warning 已修，未留新账）
- `flutter test`：全量 **1007 全绿 + 4 skipped**（较批次 71 净 +17）
- 文档同步：本日志

## 提交

| Commit | 日期 | 标题 |
|--------|------|------|
| （本次） | 2026-08-09 | feat: 批次72 大纲层（B62j 后续：诊断两层拆分·AI 自主记忆沉淀——outline_entity/impression 表 v18 迁移 + [YS_OUTLINE] 提取协议 + 匹配/合并/冲突三件套 + 5.1.8/9.1 挂接 + 17 新用例）+ 本日志 |
