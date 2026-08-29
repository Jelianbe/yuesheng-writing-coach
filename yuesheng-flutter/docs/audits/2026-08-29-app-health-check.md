# 应用体检报告（2026-08-29）

> **范围**：`D:\ai-teacher\yuesheng-flutter` 全量（`lib/` + `test/`）
> **方法**：规则符合性扫描 + 历史提交回溯 + 关键路径代码核查
> **性质**：问题清单与排期建议，**不含实现**。P0 建议优先处理。
> 数据基准：2026-08-29 00:30–00:50 实测。

---

## 结论速览

| 优先级 | 问题 | 规模 | 成本 | 建议 |
|:--:|:--|:--:|:--:|:--|
| **P0** | 数据损坏静默化（空 catch 无日志） | 17 处 | 低 | **建议做** |
| **P1** | 注释与代码脱节 | 已确认 3 例 | 极低 | 顺手修 |
| P2 | 文件超 R-019 行数上限 | 76 个文件 | 高 | 择机 |
| P3 | UI 样式字面量散落 | 803 处 | 中 | 舰长已定：暂缓 |
| — | 知识层未决项 | 2 项 | 中 | 待决 |

---

## P0 · 数据损坏静默化（17 处空 catch）— ✅ 已修复（2026-08-29）

> **修复记录**：新增 `lib/services/decode_guard.dart` 统一降级守卫，17 处空 catch
> 全部改为「保留降级 + 补可观测性」。其中 `error_log_repository` 刻意不走守卫
> （该文件即日志写入方，调用会递归）。零行为变更，四道门禁全绿。

### 证据

`grep -rnE "catch\s*\(\s*\w*\s*\)\s*\{\s*\}" lib/` → **17 处**，分布：

| 文件 | 处数 |
|:--|--:|
| `data/repositories/student_model_repository.dart` | 6 |
| `data/repositories/app_state_repository.dart` | 3 |
| `services/archive_export_service.dart` | 2 |
| `widgets/bookshelf_create.dart` | 1 |
| `services/progressive_diagnosis.dart` | 1 |
| `main.dart` | 1 |
| `data/repositories/session_repository.dart` | 1 |
| `data/repositories/error_log_repository.dart` | 1 |

### 典型形态（`student_model_repository.dart:57-60`）

```dart
try {
  final decoded = jsonDecode(model.teachingHistory);
  if (decoded is List) history = decoded;
} catch (_) {}        // 解析失败 → 静默走默认值
```

六处模式一致：JSON 解析失败 → 返回 `[]` / `null` / 空历史。

### 影响（产品视角，非架构视角）

降级行为本身**是合理的**——不应因一条脏数据让整个页面崩溃。真正的问题在**静默**：

- 用户的 `teachingHistory` / `writingStyleProfile` / `styleFingerprint` 一旦损坏，
  表现为**「学习记录凭空消失」「文笔画像没了」**，用户无从判断是数据丢了还是自己记错。
- 日志中无任何痕迹，**事后无法追溯原因**（写入截断？旧版本格式？迁移残留？）。
- 当前项目已具备日志基础设施（`error_log_repository`），缺的只是调用。

### 修法（零行为变更）

保留降级逻辑，仅在 catch 内补一行日志：

```dart
} catch (e, st) {
  logError('teachingHistory JSON 解析失败，按空历史降级', e, st);
}
```

- **行为不变**：降级结果完全一致，锚点/快照不漂移
- **成本**：17 处，每处 1–3 行
- **收益**：数据损坏从"不可见"变为"可追溯"

### 风险点

- `error_log_repository.dart` 自身有 1 处空 catch → **若日志写入失败会产生递归风险**，
  需单独设计（建议该处改为 `stderr` 直写或保持静默，避免递归）。
- `archive_export_service.dart` 的 2 处需单独确认语义：导出失败静默是否会导致
  用户以为导出成功（影响大于其他处，建议优先核这一处）。

---

## P1 · 注释与代码脱节（已确认 3 例）— ✅ 已修复（2026-08-29）

> **修复记录**：三处均已更正，**零字节变更**（prompt 内容一字未动）。
> 第 2 例（coaching-rhythm 自述「loadWhen: P0-P4 全程加载」）位于 content
> 字符串内部，更正会改变注入字节、触发行为锚点漂移，故**刻意不改正文**，
> 仅在 dart 注释层标注差异，并注明后续更正须连同锚点快照一并更新。
> 四道门禁全绿，2035 用例通过。

| 位置 | 注释内容 | 实际情况 |
|:--|:--|:--|
| `capability_providers.dart:8-11` | 四个能力「已落地但**尚无调用方**」 | 四个 provider 均已被 `session_providers.dart:121-124` 消费，且 `chatServiceProvider` 被 5 处 widget 使用 |
| `skills_beginner_p3.dart:13`（coaching-rhythm 头） | `loadWhen: P0-P4 全程加载` | `resolveL2Mode` 仅在 beginner(P0/P1/P2) 与 diagnosis(P2) 加载，**P3/P4 不加载** |
| `style_technique_router.dart:100` | `TODO：症候级 mastered → 技法集合的派生接入后启用` | **已完成**：`chat_service.dart:1487` 已传 `deriveMasteredTechniqueIds(activeProblems)`，且有 `style_technique_router_test.dart:217` 专项测试覆盖 |

### 影响

注释误导决策。本轮 Phase 3 执行中，`capability_providers.dart` 的过时注释曾导致
对「dispatcher 是否在生产链路」产生误判，需额外追到 widget 层才确认。
第三例更危险：TODO 会让人以为功能缺失而重复实现。

### 修法

更新三处注释。**零行为变更**，成本极低。

### 已实施（2026-08-29，提交 130e6b8b）

1. `capability_providers.dart` — 更正为「四个 provider 均已接入生产链路」，
   保留原错误表述的更正说明（含误判记录），避免后人重蹈。
2. `style_technique_router.dart` — 移除已完成 TODO，改为指向
   `chat_service.dart:1487` 的接入点与专项测试位置。
3. `skills_beginner_p3.dart` — **不改 content**，在 dart 注释层标注：
   实际加载以 `resolveL2Mode` 代码为准（P3/P4 不加载），并说明更正正文
   需连同行为锚点快照一并更新。

---

## P2 · R-019 超限

### P2-A · 文件超 300 行（76 个）

⚠️ **本节初版建议「只处理 `chat_service.dart`，按用例拆分」已撤回**——该建议
基于对 R-019 的误读，见 §P2-C 修正。以下仅为客观统计。

`find lib -name "*.dart" | xargs wc -l | awk '$1>300'` → **76 个文件**（上限 300 行）

目录分布：

| 目录 | 文件数 |
|:--|--:|
| `widgets/` | **44** |
| `services/` | 20 |
| `data/repositories/` | 5 |
| `data/database/` | 3（含 `database.g.dart` 24191 行，生成文件，不计） |
| `providers/` | 2 |
| `types/` | 1 |

超限最多者：

| 文件 | 行数 | 倍数 |
|:--|--:|--:|
| `services/chat_service.dart` | 3004 | **10.0×** |
| `widgets/manuscript_detail_page.dart` | 1252 | 4.2× |
| `widgets/writing_page.dart` | 1181 | 3.9× |
| `widgets/chapter_tree_drawer.dart` | 870 | 2.9× |
| `widgets/bookshelf_page.dart` | 867 | 2.9× |
| `widgets/diagnosis_card.dart` | 865 | 2.9× |

### 说明

- `database.g.dart` 为 drift 生成文件，不应计入债务。
- 其余多为 UI 页面文件，影响局限在页面内部。
- ⚠️ 初版写的「建议只处理 `chat_service.dart`，按用例拆分」**已撤回**，理由见 §P2-C。

### P2-B · 函数超 50 行（`chat_service.dart` 实测）

R-019 的**硬上限是函数 ≤50 行**，这才是真正超标处：

| 行数 | 方法 | 倍数 |
|--:|:--|--:|
| 293 | `_sendMessageCore` | 5.9× |
| 278 | `_preloadReferenceDetails` | 5.6× |
| 271 | `_injectDiagnosisLock` | 5.4× |
| 243 | `_injectChapterObservations` | 4.9× |
| 232 | `_handleTrainingResult` | 4.6× |
| 177 | `_applyPhaseMigration` | 3.5× |
| 175 | `commitDiagnosisFromContent` | 3.5× |
| 150 | `_commitDiagnosisAndSuggestions` | 3.0× |
| 140 | `_injectProfileAndIntents` | 2.8× |
| 128 | `_applyFactExtractionFromContent` | 2.6× |
| 88 / 86 | `_injectOutlineFactsAndFiles` / `_applyOutlineEntitiesFromContent` | 1.8× / 1.7× |

### P2-C · ⚠️ 对 R-019 的理解修正（2026-08-29 深夜，初版误读）

初版把 R-019 简化为「单文件 ≤300 行」并据此提出拆分方案，**该理解错误**。
据 `待办执行清单.md` 批次 **X-025-ARCH（2026-08-22）** 的既有决策：

1. **R-019 的硬上限是「函数 ≤50 行」**；「文件 ≤300 行」对服务层并非硬约束。
2. **服务层超限需走 ADR 决策**，不是直接动手拆。
3. **禁止用 `part`/`extension` 机械搬运凑行数**——项目曾将 12 个服务拆成 41 个
   part，被定性为**伪拆分**并全部回退（13 个 commit）。实证代价：
   `ChatService.sendMessage` 迁至 extension 后，测试替身 `_FakeChatService`
   的 `@override` 失效（契约断裂），调用真实 LLM API 触发 9 例
   `pumpAndSettle` 超时。
4. **真分解** = 独立类 / 显式接口 / 依赖注入 / 职责级重构。
5. **A 类纯常量知识库豁免**：part 拆分可保留（边界与内容领域边界一致，
   无逻辑耦合、无 override 契约）。

**结论**：`chat_service.dart` 的 3004 行是 X-025-ARCH 回退后的**有意单体**，
不是疏漏。若要处理，正道是缩短那 12 个超长函数（真分解），或走 ADR 登记
为已知债务——**不得**再用 part/extension 拆文件。

---

## P3 · UI 样式字面量散落（803 处）

| 项 | 处数 | 分布文件 |
|:--|--:|--:|
| `fontSize:` | 485 | 82 |
| `fontWeight:` | 318 | 76 |
| `Color(0x...)` | **0** | 颜色层已 100% 令牌化 ✅ |
| 已用 `AppTextStyles.` | 186 | 约 19% 收编率 |

字号取值高度集中：`14(125) 13(93) 12(93) 15(63) 16(33)`，**前 5 值覆盖 84%**。

**状态：舰长已明确本阶段不做**（扩展性方向，优先级低于产品问题）。

---

## 知识层 / 应用层未决项

| 项 | 现状 | 状态 |
|:--|:--|:--|
| 知识注入驱动模型 | Phase 3 已收口：A 组两块落地（advanced-phases / coaching-rhythm），B 组四块不索引化。已 ADR 化 | ✅ 已决 |
| `feedback-cognition` 与 `coaching-rhythm §五` 内容重叠 | 清单 §4.3 注：两者存在重复，需明确分工避免重复注入 | **未决** |
| Phase 4（14 个本体知识/动作拆分） | 经核查，收益已从「消除多点改动」缩水为「内容不必放 dart 文件」 | **建议暂缓** |

---

## 健康检查补充数据

| 检查项 | 结果 |
|:--|:--|
| 循环依赖 | **0**（288 modules，`check_circular.py` 全绿） |
| 测试 | 2035 用例全绿 |
| `TODO` / `FIXME` / `HACK` | 2 / 0 / 0（其中 2 处 TODO 已确认是过时注释，非真待办） |
| Skill 体系位置下标依赖 | **0**（全 Map 键控） |
| 全局可变状态 | 38 处均为 Riverpod Provider（不可变、可 override、依赖显式） |

**整体判断**：工程健康度良好（无循环依赖、测试全绿、规则体系完整）。
主要风险集中在**可观测性**（P0）与**文档准确性**（P1），而非结构耦合。

---

*记录时间：2026-08-29。本报告为问题清单，不含实现；P0 若决定处理，建议先单独确认
`archive_export_service.dart` 那 2 处的语义（影响大于其他处）。*
