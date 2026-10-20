# ADR-C98 · 编辑器文本模型与搜索定位坐标系（FIX-6 / FIX-5 同批裁定）

- **日期**：2026-09-23
- **性质**：**文本模型口径裁定 + 实施形状裁定**；本 ADR 定模型与坐标系，FIX-5 据此实施；FIX-6 的「段落虚拟化」经证据核验**不立项**（详见 §1/§2）
- **触发**：用户实锤「全文搜索找到章节找不到文字 + 编辑器滑动卡顿」（09-23）→ 批次 A 编辑器簇（FIX-6 → FIX-5）
- **硬约束**：R-009（用户主权）· R-019（函数 ≤50 行）· R-020（循环依赖零容忍）· R-027（Prompt 改动需确认）· AGENTS.md §7（涉核心模块先写 ADR）·「数字口径以脚本实测为准，不写死」
- **上游（**本 ADR 不得与之冲突**）**：
  - `.ai/STATE.md §6`（2026-09-23 编辑器三缺陷登记行：⑤⑥⑦）
  - `.ai/logs/2026-09-23.md §6.1/§6.2`（两缺陷侦查：链路、根因、修复方向）
  - `.ai/logs/2026-09-21.md:57` · `.ai/logs/2026-09-22.md §14.6/§15.4/§15.8`（PERF-EDITOR 序列：**段落虚拟化三处明确「未立项」**）
  - `docs/ADR-C96-fact-chapter-identity.md`（ADR 落点与镜像纪律先例：docs/ 被 `.gitignore:105` 排除 ⇒ 裁定必须镜像进 `.ai/DECISIONS.md §2`）
- **标注纪律**：【事实】= 有 file:line 或实测佐证；【推断】= 我方推导，显式标注。

---

## §0 一句话结论

**编辑器文本坐标系 = 唯一真源 `controller.text`（`FocusAwareEditingController`）；DB `chapters.content` 只是持久化快照、不是定位坐标系。**
FIX-5 据此把搜索定位源收敛到编辑器文本快照 + 补 focus / scroll-to-caret / 失败可重试；
**FIX-6 的「段落虚拟化」（段落列表 + 各自 TextField）不立项** —— 它是**替换编辑器内核**（破坏跨段选区 / 跨段 undo / 全文搜索定位 / 光标跨段 / 坐标反查 5 类功能），
且项目自测（PERF-EDITOR-1）**不支持「滚动与文本量相关」**；
FIX-6 改立「**真机取证 + 低成本项**」：先钉死卡顿路径（滚动 / 击键 / 重排 / 输入），取证后再决定是否重新立项虚拟化。

---

## §1 证据链（为什么不能照任务书字面「落地片段虚拟化」）

### 1.1 任务书措辞与日志事实不符（★★ 本 ADR 的立档动因）

任务书（监督侧移交）写：**「FIX-6 … 落地片段虚拟化（PERF-EDITOR-0/1 立项，09-21/22 登记）」**。

实测日志原文（三处）：
| 来源 | 原文 | 含义 |
|:--|:--|:--|
| `.ai/logs/2026-09-21.md:57` | 「结构性解法『段落虚拟化』**未立项**」 | 09-21 即未立项 |
| `.ai/logs/2026-09-22.md` §14.6 | 「段落虚拟化**仍未立项**；本批**只出基线**」 | PERF-EDITOR-0 只是基线取证 |
| `.ai/logs/2026-09-22.md` §15.8 | 「**段落虚拟化仍未立项**」 | PERF-EDITOR-1 后仍否 |

⇒ 任务书的「PERF-EDITOR-0/1 立项」是**对「PERF-EDITOR-0/1 侦查批」的误读**：PERF-EDITOR-0/1 是**滚动基线取证批**（不写产品代码、只测），从未立项「段落虚拟化」。**本 ADR 以日志实测为准，予以订正。**

### 1.2 「段落虚拟化 = 替换编辑器内核」的代价（09-22 §13.2，可靠结论）

【事实】全仓依赖 `RenderEditable`/`TextSelection` 的文件 **= 10 个**（实测 `git grep -l`）。
Flutter 的 `RenderEditable` 是**整体式**（一个 `EditableText` 管全文）⇒ 「段落列表 + 各自 TextField」会**同时打破**：
1. **跨段选区**（选 3 段文字 = 跨 3 个 TextField，Selection 语义不存在）
2. **跨段 undo**（undo 栈按段分裂）
3. **查找替换全文定位**（全书偏移需跨段换算）
4. **光标跨段**（光标无法在段间自然流动）
5. **`editorStackKey` 坐标反查**（划词菜单位置定位段内坐标系）

⇒ 不是「加一层懒加载」，是**替换编辑器内核**。**任务书字面的「落地片段虚拟化」若按段落列表理解，代价 = 重写编辑器，且收益未被自测证实。**

### 1.3 项目自测不支持「滚动卡顿 ⇐ 文本量」（PERF-EDITOR-1，模拟器实测）

【事实】`.ai/logs/2026-09-22.md` §15.3，三档负载（段落结构刻意同构，唯一自变量 = 总字数）：

| 档 | 字数 | p50 中位 | p90 中位 | 尾部 p90−p50 |
|:--|--:|--:|--:|--:|
| S | 3,000 | **12.85** | 21.58 | 8.58 |
| M | 12,000 | **13.75** | 20.67 | 6.92 |
| L | 49,903 | **14.41** | 17.10 | 2.71 |

- **p50**：档内极差 **3.58 ms > 档间差 1.56 ms** ⇒ **无可靠规律**（滚动中位帧与文本量无关）
- **p90 / 尾部**：**严格单调递减**，L 与 S/M 完全不重叠 ⇒ **短文本抖动更大，与「长文档更卡」直觉相反**
- 同档参照系（L 连跑 4 块极差 p50 0.75 / p90 1.67）⇒ 两处差异均超噪声底 2 倍以上 = **真信号**

**⇒ 结论（PERF-EDITOR-1 §15.3）：「滚动『中位帧』代价与文本量无关；『慢帧严重程度』随文本量单调递减。」**

### 1.4 但本批不能据此断言「无卡顿」——证据边界必须诚实

PERF-EDITOR-1 自述边界（§15.4/§15.8，【事实】）：
1. **只测滚动**，**未测击键 / 重排**（`markNeedsLayout + 全量重绘` 路径完全不同）
2. **模拟器软渲染**，`drawParagraph` 的 **GPU 侧代价被完全改变** ⇒ 绝对帧率不可外推真机
3. 视口高度恒为 1599 ⇒ **进出视口的行数在几何上一样**，「文档大小」不是正确自变量

⇒ **「段落虚拟化收益」既未证实、也未否决**（PERF-EDITOR-1 原话：「其立项依据须另行取证」）。
用户 09-23 实锤「滑动也很卡顿」是**真机主观反馈**（模拟器测不到的路径可能才是卡顿源）——**优先级提升成立，但落地形态须先取证。**

### 1.5 FIX-5 的坐标系错位（09-23 §6.1，机制已定位）

【事实】当前链路：
`SearchReplaceSheet._searchAllBook`（`search_replace_sheet.dart:252-294`）用 **DB 原文 `ch.content`** 算 `firstOffset`（`:287`）→ 点击当前章结果 `onLocate(r.firstOffset, …)`（`:565`）→ `locateCursor(offset)`（`writing_page.dart:275-280`）。

- **缺陷 A（坐标系错位）**：全书搜索偏移基于 **DB 原文**；定位目标是**编辑器 `controller.text`**。二者不一致的现实路径：① 300ms debounce 窗口内未落库的编辑；② 草稿恢复（controller.text = 草稿 ≠ DB）；③ `syncEditorFromState` 只同步 `localContent` 非空且 controller 空的情况。后果：offset 落在错误位置，越界时 `locateCursor` 的守卫**静默 return** 且 `searchCursorLocated` 已置 true ⇒ **一次失败永不重试**。
- **缺陷 B（无滚动补偿，核心）**：`locateCursor` 全文 6 行，**只设 selection，不请求 focus、不滚动视口**；Flutter 程序化设 `controller.selection` **不触发 scroll-to-caret** ⇒ 长文下光标在屏幕外，用户「跳到章节但看不到匹配文字」。

【事实】对照：**当前章查找替换**（非全书）已经是编辑器坐标系 —— `writing_page_find_replace_controller.dart:25/39` 打开 sheet 时 `initialText: _host.editorController.text`，`_runSearch`/`_locate` 走 `onLocate(start, end)` 是编辑器文本偏移。**错位只存在于全书搜索 `_searchAllBook` 的当前章结果点击路径。**

### 1.6 FIX-5 不依赖段落虚拟化（与任务书「强耦合」判断的订正）

任务书称「FIX-5 修复必须基于 FIX-6 新文本模型」——成立的前提是「段落虚拟化改变了文本模型」。本 ADR 裁定：**文本模型保持单一 `controller.text`（坐标系不变），虚拟化不落地** ⇒
**FIX-5 的「定位源 = 编辑器坐标系」直接基于现文本模型即可实现，无需等待虚拟化。**
两者解耦：FIX-5 立即可实施；FIX-6 走取证路径。

---

## §2 裁定

### 裁定 1（文本模型：单一 `controller.text` 为唯一坐标系真源）

> **编辑器文本坐标系 = `FocusAwareEditingController.text`（单一 controller，不拆分）。**
> **DB `chapters.content` 是持久化快照，不是定位坐标系。**
> 任何跨层定位（搜索 / 跨章跳转 / 版本恢复 / 草稿恢复）都必须**以定位时刻的编辑器文本为准**（当前章用 `controller.text` 快照；未打开章用 DB 原文，加载后**以实际 controller.text 校验**）。

**理由**：① 维持现状即满足（controller 已是真源，`store.localContent` 与之双向同步）；② 拆分 controller = §1.2 的内核替换，代价无收益；③ FIX-5 的缺陷 A 正是「DB 原文当坐标系」造成的，裁定 1 直接消灭它。

### 裁定 2（FIX-5：搜索定位收敛，本批实施）

> ① 全书搜索**当前章结果**点击时，偏移用**编辑器文本快照**重算（sheet 的 `_text` 已是打开时快照，与 `controller.text` 一致），不用 DB `ch.content`；
> ② `locateCursor(offset)` 补 **`focusNode.requestFocus()` + scroll-to-caret**（`RenderEditable.getOffsetForCaret` + `Scrollable.ensureVisible`，或 TextField 外层 ScrollController 计算）——**先设 selection 后请求 focus**（focus 变化路径触发 `_showCaretOnScreen`）；
> ③ **失败可重试**：`locateCursor` 越界 / 定位失败时**不置** `searchCursorLocated = true`（或提供重试入口），跨章跳转 `maybeLocateSearchCursor` 在内容就绪后**校验 offset 合法性**，非法则按新文本重算或放弃；
> ④ 跨章跳转的 `initialCursorOffset` 在新页 `syncEditorFromState` 后**以实际 controller.text 重新校验**（草稿恢复场景 offset 已失效）。

**验收**：长文（≥4 万字章）全书搜索点击当前章 / 跨章结果 ⇒ 匹配文字**可见**（focus + 滚动到位）；草稿恢复后搜索定位不越界、不静默失败。

### 裁定 3（FIX-6：段落虚拟化不立项，改立「真机取证 + 低成本项」）

> **段落虚拟化（段落列表 + 各自 TextField）不立项。** 依据：§1.2（内核替换代价）+ §1.3（滚动收益未被自测支持）+ §1.4（真机 GPU 路径未测，**不得在未取证时宣称收益**）。
> FIX-6 落地形状 = **两段式**：
> - **第一段（本批可做）**：**真机取证** —— 模拟器重开（`-gpu swiftshader_indirect -no-snapshot-load`，STATE §7）+ 真机/模拟器负载敏感性复测（区分滚动 / 击键 / 重排 / 输入路径，`atrace` 若不稳定则不引用），**钉死卡顿路径**；同时落地零架构低成本项（若适用）：关闭光标动画等 TextField 内部降载（**不推荐**，仅作备选，09-23 §6.2 已注明「治标」）。
> - **第二段（取证后）**：若真机证实「滚动/重排与文本量相关」⇒ **另立批次 + 新 ADR** 立项虚拟化（届时 §1.2 的 5 类破坏面须有对应方案）；若证实「与文本量无关」⇒ 虚拟化正式否决，卡顿源在别处（格式化器 / 保存链路 / 布局），对症修。

**理由**：R-009 用户主权（不替舰长决定）+ 纪律「数字口径以实测为准」——**不能在自测不支持、真机未测的情况下，为「落地虚拟化」而重写编辑器内核。**

### 裁定 4（不新增 Prompt 约束，本期不动协议）

> FIX-5/FIX-6 **不触发 R-027**（不构成 Skill / Prompt 变更）。
> 若后续对「划词诊断 / 保存提示」等文案有改动需求 ⇒ 另立批次 + R-027 人工确认。

---

## §3 被否方案（防复现）

| 案 | 内容 | 否因 |
|:--:|:--|:--|
| **V1** | 按任务书字面落地「段落虚拟化」（段落列表 + 各自 TextField） | §1.2：替换编辑器内核，破坏 5 类核心编辑功能；§1.3：自测不支持滚动收益；§1.4：真机未测，收益未证 |
| **V2** | 保持现状（只修 FIX-5，FIX-6 不动） | ❌ 用户实锤「滑动卡顿」是**真机主观反馈**，优先级提升成立；完全不动 = 不回应真实用户问题 |
| **V3** | 直接上「关闭光标动画」等降载项作为 FIX-6 交付 | 09-23 §6.2 自述「不推荐，治标」——未取证就选治标项 = 假交付；应取证后对症 |
| **V4** | 全书搜索偏移继续用 DB 原文（只补 scroll-to-caret） | ❌ 只修缺陷 B 不修缺陷 A ⇒ 草稿 / 未保存场景 offset 仍错位，越界静默失败依旧 |

---

## §4 落地改动清单（FIX-5 本批实施；FIX-6 取证）

| # | 文件 | 改动 | 风险 |
|:--:|:--|:--|:--|
| 1 | `lib/widgets/writing_page.dart:275-280` | `locateCursor` 补 focus + scroll-to-caret + 失败返回 bool（**≤50 行约束内**） | 中（Flutter scroll-to-caret 实现细节需在真机验证） |
| 2 | `lib/widgets/writing/controllers/writing_page_store_sync_controller.dart:115-123` | `maybeLocateSearchCursor`：offset 校验 + 失败不置位 / 重试 | 中（草稿恢复场景） |
| 3 | `lib/widgets/search_replace_sheet.dart:252-294` | `_searchAllBook` 当前章用编辑器快照重算偏移（sheet 已有 `_text`） | 低 |
| 4 | `lib/widgets/writing/controllers/writing_page_find_replace_controller.dart` | 若 `_text` 快照与 controller 不一致的场景核对（打开时已一致，防御性核对） | 低 |
| 5 | `lib/widgets/editing/focus_aware_editing_controller.dart` | （视取证）无改动则不动 | — |
| 6 | 测试 | 新增：全书搜索当前章结果点击 ⇒ 编辑器定位偏移正确（含未保存编辑场景）；越界 ⇒ 不静默、可重试；scroll-to-caret 触发 | 中（widget test 需 mock focus/scroll） |
| 7 | `.ai/STATE.md §6` | ⑤ 登记行改「已修」（收尾时）+ FIX-6 取证结果登记 | — |
| 8 | `.ai/DECISIONS.md §2` | 镜像本 ADR 裁定（§2 表格加行） | — |

**不在本批**：段落虚拟化立项/实施（裁定 3）· 编辑器内核重写 · 任何 Prompt/Skill 改动。

---

## §5 验收判据

1. **正例（当前章）**：长文（≥4 万字）打开，编辑若干字（未保存），全书搜索关键词命中当前章 ⇒ 点击结果 ⇒ **编辑器滚动到匹配处、文字可见**（focus + scroll-to-caret 生效）。
2. **正例（跨章）**：全书搜索点击非当前章结果 ⇒ 跳转后新页加载完成 ⇒ 定位到命中处、文字可见。
3. **反例（草稿恢复）**：某章有较新草稿，用户选择恢复 ⇒ 全书搜索该章命中 ⇒ 定位 offset 以恢复后文本为准（不越界、不静默失败）。
4. **反例（越界可重试）**：人为构造 offset > 文本长度 ⇒ 不静默 return、`searchCursorLocated` 不置位（或触发重试），不出现「一次失败永不重试」。
5. **行为不变**：既有端到端测试网（含 `#96-11` 全文搜索 5 例、`#83` 章节树、`#85-2` 行段聚焦）**未改写仍全绿**。
6. **门禁**：`bash scripts/gate.sh` 12/12 全绿；R-019 **无新增**超限；T1/T2 达标。
7. **FIX-6 取证交付**：真机/模拟器负载敏感性复测记录（区分滚动/击键/重排路径），结论明确「卡顿路径 = X」或「尚未钉死 + 下一步」。
8. **负向验证**：至少 1 组「退回旧写法 ⇒ 精确转红」，且产物必须落在断言行（`DECISIONS §4-18`）。

---

## §6 高风险面（实施前必读）

1. **scroll-to-caret 的实现细节**：Flutter `EditableText` 的 `_showCaretOnScreen` 只在 **focus 变化 / 用户交互**路径触发；程序化设 selection 不触发。正确顺序 = **先设 selection，再 `requestFocus()`**（若已 focus，需确认是否仍触发）；若不可靠，改用 `RenderEditable.getOffsetForCaret` + `Scrollable.ensureVisible`。**必须在真机/模拟器实测确认，不能只靠 widget test。**
2. **`locateCursor` 行数**：现 6 行，补 focus + scroll + 失败返回后可能逼近 50 行上限（R-019）——若超限，把 scroll-to-caret 抽独立方法（真分解，非 part 伪拆分）。
3. **`_searchAllBook` 快照一致性**：全书搜索 sheet 打开时 `_text` = 打开瞬间的编辑器快照；模态期间正文不可编辑 ⇒ 打开即一致。但若未来允许模态期编辑，须改为定位时实时取 `controller.text`（本批按现状，注释留痕）。
4. **跨章 offset 生命周期**：`initialCursorOffset` 随路由 extra 传递，新页 `loadChapter` 是异步 ⇒ `maybeLocateSearchCursor` 依赖「内容就绪后 controller.text 非空」——校验 offset ≤ 文本长度，**非法则按新文本重算首处命中或放弃并留痕**（不静默）。
5. **FIX-6 取证不能外推**：模拟器软渲染 ≠ 真机 GPU；`atrace` 输出不稳定（09-22 §14.2 实测两臂差 100×）**不得引用其内容作判据**；「卡顿已解决」只有在**真机 + 用户确认**后才可声称。

---

## §7 记录（防复现）

- **任务书「PERF-EDITOR-0/1 立项」系误读**：PERF-EDITOR-0/1 = 滚动基线取证批（不写产品代码），**段落虚拟化三处日志明确未立项**（09-21:57 / 09-22 §14.6/§15.8）。**引用「段落虚拟化已立项」必须连带引用本订正。**
- **PERF-EDITOR-1 实测推翻「长文滚动更卡」直觉**（p90 随文本量单调递减）；但其边界（未测击键/重排、模拟器软渲染）意味着**不能据此断言无卡顿** —— 正确姿势 = 真机取证后定。
- ★ **ADR 落点 `yuesheng-flutter/docs/` 被 `.gitignore:105` 整体忽略** ⇒ 本裁定**已在 `.ai/DECISIONS.md §2` 留受控副本**（`DECISIONS §4-19`）。只写在 `docs/` 里的裁定等于没有写。
- **FIX-5 与 FIX-6 的「强耦合」判断已订正**：文本模型不变（单一 controller），FIX-5 无需等待虚拟化即可实施；虚拟化若未来立项，届时 FIX-5 的坐标系语义**不变**（仍是 controller.text），无返工。
