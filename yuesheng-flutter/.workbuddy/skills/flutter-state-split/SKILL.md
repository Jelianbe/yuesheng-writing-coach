---
name: flutter-state-split
description: Use when a Flutter + Riverpod StatefulWidget's State class OR a Service/Provider orchestrator class has grown huge (e.g. writing_page.dart _WritingPageState, writing_coach_panel.dart _WritingCoachPanelState, chat_service.dart ChatService in yuesheng-flutter) and needs physical decomposition without behavioral change. Provides the proven "part of + private extension on the host class" pattern, the anti-patterns that waste time (mixin-on-self-reference, mixin+getter bridge, missing ignore_for_file, private extension hiding a cross-file public method, and the P2-2 regression where moving a public instance method into an extension silently bypasses subclass @override — fix: keep a thin host stub delegating to a renamed private extension method), a copy-paste template, a generic extraction script, and the gate discipline (flutter works once FLUTTER_SKIP_UPDATE_CHECK=true is set).
agent_created: true
---

# Flutter 大 State 类拆分（part of + 私有扩展）

## Purpose

把一个膨胀的 `State` 类（几千行、几十个 handler / builder 方法）**物理拆分**成多个
`part` 文件，**逐字迁移、零行为变更**。适用于 `yuesheng-flutter` 这类
`Flutter + Riverpod + drift` 项目里 `ConsumerState<...>` 宿主类。

> 核心目标：可读性 + 可维护性，**不是**重构逻辑。拆完 `git diff` 除文件边界外不应有
> 任何语义差异。

## When to use

- 用户要"拆分 writing_page / 教练面板 / 某个 State 类""瘦身宿主""把 handler 抽到单独文件"。
- **也适用于膨胀的 Service / Provider 编排类**（如 `chat_service.dart` 的 `ChatService`，
  2617 行、含 1392 行单方法 `sendMessage`）——手法完全一致：把独立方法迁到 part 文件，
  宿主只留构造器 / 小方法 / 巨方法。扩展 `on ChatService`（非 State 类）同样能直访私有成员。
- 一个 `.dart` 文件超过 ~800 行、且方法按职责可自然分组（选区 AI、查找替换、章节导航、
  状态 builders、教学逻辑、诊断派生、实时观测…）。
- 注意：先确认是否应先做 #37 类"提取真正独立的 widget / 类"（见下）。

## 推荐模式（直接上，别犹豫）

```
宿主 writing_page.dart
  ├─ part 'writing_page_selection_ai.dart';
  ├─ part 'writing_page_find_replace.dart';
  ├─ part 'writing_page_chapter_nav.dart';
  └─ part 'writing_page_status_builders.dart';
  class _WritingPageState extends ConsumerState<WritingPage> {
    // 只留：字段、initState/dispose、build()，以及不想拆的小方法
  }

part writing_page_selection_ai.dart
  // ignore_for_file: invalid_use_of_protected_member
  part of 'writing_page.dart';
  extension _WritingPageSelectionAi on _WritingPageState {
    // 原方法体整段贴过来，_ 前缀和私有调用原样保留
  }
```

要点：
1. **用 `extension _Xxx on _HostState`**，不是 mixin。扩展与宿主在**同一 library**，
   因此能直接访问宿主的私有成员（`_controller`、`_syncEditorText`…），`setState` /
   `context` / `ref` / `mounted` / `widget` 本就是继承来的、合法可用。
2. **逐字迁移**：把原方法体整段（含 `_` 前缀方法名、私有字段调用）粘进扩展，不改名、
   不改逻辑。这样 `git diff` 几乎只剩"移动文件边界"，行为 100% 等价。
3. **State 类 part 文件顶部加** `// ignore_for_file: invalid_use_of_protected_member`。
   分析器会对"扩展调用继承的 protected 成员（setState/context/ref）"误报，文件级忽略
   干净消除，最终 `dart analyze` 0 issues。**纯 Service/Provider 类没有 @protected 成员，
   无需此 ignore**（加了也不报错，可省略）。
4. **跨文件公开方法必须用「公开 UpperCamelCase 扩展名」**：若被迁走的方法是**公开方法**
   （无 `_` 前缀，如 `commitDiagnosisFromContent`）且被**其他文件**调用，私有扩展
   （`_Xxx`）只在本 library 可见，外部调用会报 `isn't defined for the type` + 本库内
   `unused_element`。此时扩展名须改为公开：`extension ChatServiceDiagnosis on ChatService`。
   扩展公开**不影响**其内部的私有方法（仍保持库内私有）。纯库内调用的私有方法用
   私有扩展名即可（命名 lint `camel_case_extensions` 会提示，改名即可）。

5. **公开实例方法迁 extension 后必须留「薄实例桩」保 override 语义（P2-2 踩坑）**。
   扩展方法**不是 virtual**：当 `sendMessage` 从宿主实例方法迁到 `extension` 后，若
   宿主不再声明同名实例成员，静态类型 `ChatService` 上"没有实例成员"，Dart 会**静默
   解析到 extension 方法**，从而**绕过子类（如测试替身 `_FakeChatService extends
   ChatService`）的 `@override sendMessage`**。后果：9 个 `chat_page_test` 用例
   `pumpAndSettle timed out`（真实 `sendMessage` 含真 `streamChat` 流式永不结束）。
   **正确做法**：宿主保留一个**薄实例方法桩** `sendMessage(...)` 直接 `await
   _sendMessageCore(...)` 委派给改名后的私有扩展方法（保留 `this` 语义、无需把
   `this.` 改成 `self.`）。这样子类 override / 测试替身派发语义 100% 保住，扩展内
   仍是逐字原方法体。另：extension 内引用宿主 `static` 成员须加 `ChatService.`
   前缀（见反模式表）。

## Anti-patterns（已踩过，别再试）

| 尝试 | 结果 | 结论 |
|---|---|---|
| mixin `on ConsumerState<WritingPage>` + 宿主暴露公开 getter 桥接私有字段 | 19 条 info lint，且被迫把私有成员公开 | 否决 |
| mixin `on _HostState` | 编译错：`on` 自引用形成循环 | 否决 |
| 扩展 `on _HostState` 但**漏掉** `// ignore_for_file` | `invalid_use_of_protected_member` 报错 | State 类必须加文件级忽略 |
| 被迁方法是**公开且跨文件调用**，却用私有扩展名 `_Xxx` | 外部报 `isn't defined` + 本库 `unused_element` | 改公开 UpperCamelCase 扩展名 |
| 把 `static` 方法迁进扩展 | 编译错：extension 不能有 static 成员 | `static` 方法留宿主（或提成顶层函数） |
| 把**公开实例方法**（如 `sendMessage`）迁到 extension 后宿主留空、靠 Dart 解析到 extension | 静默绕过子类（测试替身 `_FakeChatService extends ChatService`）的 `@override` → 9 个 `pumpAndSettle timed out`（真实 `sendMessage` 含真 `streamChat` 流式永不结束） | 宿主保留**薄实例桩**委派给改名后的私有扩展方法 `_sendMessageCore`，维持 override/子类派发语义（见下「要点 5」） |
| 在 extension 内引用宿主 `static` 成员（如 `_kFullContentMaxLen`）未加 `ChatService.` 前缀 | 编译错：`unqualified_reference_to_static_member_of_extended_type` | extension 内访问宿主 static 须用 `ChatService._xxx` 全限定前缀（顶层 import const 不改） |

## 标准步骤

1. **先拆真正独立的类（#37 类）**：若一个方法/组件能脱离 State 独立存在（如
   `GoalDialog`、`ThinkingPlaceholder`、`FocusAwareEditingController`），先提成
   **公开类/独立文件**，宿主改调用点。这步独立于 part 拆分，优先做。
2. **按职责分组**：把剩余 handler / builder 按业务域分组（选区 AI、查找替换+全文搜索、
   章节导航、状态条 builders、教学逻辑、输入/列表 builders…），每组一个 part 文件。
3. **宿主加 `part` 声明**，删掉被迁走的方法体（保留字段/生命周期/build）。
4. **写 part 文件**：顶部 `// ignore_for_file: invalid_use_of_protected_member` →
   `part of '宿主.dart';` → `extension _Xxx on _HostState { ... 原方法 ... }`。
5. **逐组闸门**：每迁完一组就跑分析（见下），确认 0 issues 再下一组。降低回滚成本。
6. **一次性收口**：所有 part 完成后，建账（`docs/待办执行清单.md`）+ 单批 commit
   （遵循本项目"代码 + 台账同批一提交"惯例，参考 96-19 的 f00d727）。

## 闸门纪律（四闸）

- **理想四闸（本环境现已可用）**：`flutter analyze lib` 0 issues **且** 全量 `flutter test` 通过。
- **关键环境修正（重要）**：`flutter` 命令曾"挂死"（`--version` / `devices` / `test` /
  `analyze` 卡住无输出），**根因是更新检查的网络请求卡死**，不是命令不可用。设
  `FLUTTER_SKIP_UPDATE_CHECK=true` 后全部正常。每步用：
  `FLUTTER_SKIP_UPDATE_CHECK=true /d/flutter/bin/flutter analyze lib`
  （或 `flutter test`）作为静态 + 运行时四闸。
- **`dart analyze` 仍可作秒级静态闸门**：`/d/flutter/bin/cache/dart-sdk/bin/dart.exe
  analyze lib` 直接调同一分析引擎，适合逐组迁移时频繁跑；最终以 `flutter test` 闭环。
- 游离的 `flutter.bat` 进程若泄漏拖垮资源，必要时 `ps -W` 定位 + `kill -9` 清理。
- **沙箱跑命令的完整坑与绕过手法（`.bat` 被杀 / lockfile 死锁 / safe-delete 拦截 `rm` /
  快照直调 `flutter_tools.snapshot`）已单独立项**：见 skill **`flutter-sandbox-run`**。
  本工程在 WorkBuddy Bash 沙箱里跑 `analyze`/`test` 前，先按它走一遍可省大量试错。

## 参考

- `references/part_template.dart` — 可直接复制的宿主/part 双文件骨架。
- `references/extract_state_parts.py` — 通用提取脚本：按"方法签名锚点 + 大括号配平 +
  `///` 文档注释上提"逐字抽取多个方法到同一扩展的 part 文件，零行为变更。已用于 96-24
  的 `chat_service` 拆分。
- 真实样例：
  - **State 类（96-19，commit `f00d727`）**：宿主 `lib/widgets/writing_page.dart`
    （1896→1160 行）、`lib/widgets/writing_coach_panel.dart`（985→211 行）；part 含
    `writing_page_selection_ai.dart`(209) / `_find_replace.dart`(65) / `_chapter_nav.dart`(108)
    / `_status_builders.dart`(242) / `writing_coach_panel_teaching.dart`(501) / `_builders.dart`(301)。
  - **Service 编排类（96-24，commit `a8d4ef5`）**：`lib/services/chat_service.dart`
    （2617→1732 行）；`sendMessage` 巨方法(1392 行)留宿主，15 个独立 helper 迁到
    `chat_service_diagnosis.dart`(792) / `chat_service_observers.dart`(99)，扩展名用公开
    UpperCamelCase（`ChatServiceDiagnosis` / `ChatServiceObservers`）以暴露跨文件公开方法
    `commitDiagnosisFromContent`。
