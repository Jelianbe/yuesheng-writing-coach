# ADR-C81：章节会话懒创建——教练面板打开不再落库空会话

- 状态：**舰长裁决采纳（方案 C）**；教学链路核心改动，按 AGENTS.md 先立 ADR
- 日期：2026-09-06
- 关联：R-010 最小化范围、R-019、R-027 六道门禁、R-028；v0.1 发布准备批
  （ed152b94/5d6f5136）真机走查发现；ADR-C80（同为诊断链路小批）
- 影响模块：`lib/widgets/writing_coach_panel.dart`（+teaching part）、
  `lib/data/repositories/session_repository.dart`（+_test）
- 舰长报告原话：「书架里的项目相关对话那边……为什么会关联到一个只是发起过的内容？」

---

## 1. 背景与实证

### 1.1 现象（模拟器真机走查，2026-09-06）

书架 → 作品详情 →「相关对话」Tab 出现零消息会话（「新建会话 / 暂无消息」）——
用户只是**打开过章节写作页的教练面板**，一句话没说，会话即已落库并与作品建立
三路关联。

### 1.2 机制链（代码证据）

1. `writing_coach_panel.dart:107-109` → `initState` 即调 `_initSession()` →
   `:140-142` `getOrCreateSessionForChapter(manuscriptId, chapterId)`——**查不到就建**：
   新建 sessions + teaching_state + 写 `sessions.chapter_id/manuscript_id` 冗余缓存 +
   `session_reference` 主引用，整体事务（`session_repository.dart:99-146`）。
2. 「相关对话」`listRelatedSessions` 三路并集（章节归属 + 引用表 + 冗余缓存，
   `session_repository.dart:293-322`），**不过滤零消息会话**。
3. 叠加观感：发起过 = 永久挂在作品相关对话里。

该 getOrCreate 语义复刻自 RN 真源（「每个章节拥有独立会话，诊断/对话互不污染」
的隔离设计），隔离本身正确，**错在「打开面板」这个无代价动作触发了有代价的落库**。

### 1.3 与现有语义的自洽性（关键佐证）

`deleteOrphanSessions`（设置页「清除缓存」）的判据就是**零消息即删**
（`session_repository.dart:479`，不管是否有关联）——空会话在本应用语义里
本来就是可清理的垃圾数据。懒创建与此完全自洽：不产生垃圾，而非产生后过滤。

## 2. 候选方案与裁决

| 方案 | 内容 | 结论 |
|:--|:--|:--|
| A 展示层过滤 | 相关对话 Tab 隐藏零消息会话 | 治标：垃圾仍落库，抽屉/导出仍可见；**不采** |
| B 导出补强 | 导出跳过空会话 / 确认框显示标题 | 同为下游止血；**不采**（C 落地后空会话不再产生） |
| **C 懒创建** | **打开不建，首次发送/诊断/观察时才建** | **舰长裁决采纳** |

存量空会话：由现成的「清除缓存」入口一次性清掉（零消息即删，级联引用/教学状态），
无需新增清理逻辑。

## 3. 方案设计

### 3.1 repository：公开只查方法

`_findChapterSession`（私有，`session_repository.dart:161`）公开为
`findSessionForChapter(chapterId)`（语义不变：chapter_id 精确匹配 +
updated_at DESC limit 1）；`getOrCreateSessionForChapter` 内部改调它（一行）。
**getOrCreate 本身不动**——懒创建改变的是**调用时机**，不是创建语义。

### 3.2 panel：init 只查，三入口 ensure

- `_initSession()`：`getOrCreate` → `findSessionForChapter`。查到 → 绑定
  store + 加载消息 + `restoreForSession`（原路径原样）；查不到 → **什么都不建**，
  仅关 loading。UI 落到现有空态（无消息即空态，`#1` 用例既有路径）。
- 新增 `_ensureSession()`：`_sessionId != null` 直接返回；否则 getOrCreate +
  绑定 store + `restoreForSession`（评估报告恢复随会话真正建立触发）。
- **三处「产生内容」入口**改走 ensure（原 `await _initFuture; final sid =
  _sessionId; if (sid == null) return;` → `final sid = await _ensureSession();
  if (sid == null) return;`）：
  1. `_handleSend`（发送 / 部分认同 / 教原理 / 练习提交，全部复用此链路）
  2. `_handleDiagnoseWithText`（诊断本章 / 划词诊断）
  3. `_handleRealtimeObserve`（快速观察）
- **两处纯消费点保持不动**（现有 null 防御即正确行为）：
  `_confirmDeleteMessage`、`_buildEvaluationReportForLastMessage`——两者只在
  已有消息后才可能触发，无会话时 null-return 是语义正确的空操作。

### 3.3 影响面逐点核对

| 消费点 | 现状 | 懒创建下 |
|:--|:--|:--|
| `_handleSend` :124-126 | await init + null 防御 | 改 ensure：发送时建会话 |
| `_handleDiagnoseWithText` :310-312 | 同上 | 改 ensure：诊断时建会话 |
| `_handleRealtimeObserve` :240-242 | 同上 | 改 ensure：观察时建会话 |
| `_confirmDeleteMessage` :100-102 | null 防御 | 不动：无消息即无删除入口 |
| `_buildEvaluationReportForLastMessage` :217-218 | null 防御 | 不动：报告只随训练产生 |
| builders :177 流式占位 `sessionId: _sessionId ?? ''` | 空串兜底 | 不动：isStreaming 必发生在 ensure 之后，仅内存构造不落库 |
| `didUpdateWidget`（chapterId 变化） | 置 null + 重 init | 结构不变：新章节同样只查 |
| 评估报告 `restoreForSession`（防跨会话串写） | 打开即 restore | 改为**会话建立时** restore；报告构建/展示都发生在 ensure 之后，`_currentSessionId` 与操作 sid 恒一致，串写面不扩大 |
| 导出会话记录（本批 `collectLatestSessionExport` 取最新会话） | 可能导到空会话 | 空会话不再产生；存量由「清除缓存」清掉 |

### 3.4 不做的事（R-010）

- 相关对话 Tab / 会话抽屉不加零消息过滤（根因已除，过滤反而是对「发起过未聊」
  真实会话的误伤面）；
- 不动 `getOrCreateSessionForManuscript`（lib 内无生产调用点，仅 test；
  懒创建语义天然覆盖——若未来接线，按同一时机纪律）；
- 不动 Tab2 自由对话的会话创建链路（bootstrap 域，另一套语义）。

## 4. 测试计划

新增（`writing_coach_panel_test.dart`，L 组）：
- L1 打开面板（无已有会话）→ sessions 无新行、session_reference 无新行；
- L2 打开后发送 → 会话创建（chapter_id 关联）+ 消息落库；
- L3 打开后整章诊断 → 会话创建（真链路同 D1-2 装置）；
- L4 已有会话（预创建）→ 面板复用，不新建（sessions 总数不变）。

回归：该文件既有 26 例 + 全量（重点是 E1-1 报告恢复 / B3 划词 / B74 删除 /
D1-4 会话隔离）。六道门禁全绿后 pathspec 提交。

## 5. 回退

单 commit，`git revert` 即回；无 schema 变更、无数据迁移——旧版本创建的
空会话在新版本下行为不变（仍被「清除缓存」覆盖）。
