# C2 路由重构变更说明

**日期**：2026-08-05
**批次**：C2（Tab2 改为对话）
**关联计划**：[2026-08-05-writing-page-redesign.md](../plans/2026-08-05-writing-page-redesign.md)

---

## 变更概述

将 Tab2 从"写作占位页"改为"对话页"（ChatPage），默认 Tab 从 Tab2 调整为书架，`/chat` 顶层路由改为重定向到 Tab2。写作入口改走「书架→作品详情→章节」链路。

## 改动文件

| 文件 | 改动类型 |
|------|---------|
| `lib/router/app_router.dart` | 修改（5 处） |
| `test/router/c2_tab2_chat_route_test.dart` | 新增（4 测试） |
| `test/router/app_router_test.dart` | 修改（#1 + #6 断言同步更新） |

## 改动点

### 1. 默认 Tab 调整
- `initialLocation`：`/`（Tab2 写作）→ `/bookshelf`（Tab1 书架）
- **理由**：打开 App 先看作品列表，符合"先选作品再写作/对话"流程

### 2. Tab2 内容替换
- Branch B：`PlaceholderPage('写作')` → `ChatPage()`
- 导航项：`edit_outlined` + '写作' → `chat_outlined` + '对话'

### 3. `/chat` 顶层路由重定向
- 原：独立渲染 `ChatPage`（顶层路由，无 Tab 容器）
- 现：`redirect: AppRoutes.writing`（落到 Tab2，保留深链入口）
- **理由**：通知/外部链接点击 `/chat` 时仍能落到对话页，且带 Tab 导航

## 影响分析

### 用户视角
| 场景 | 改造前 | 改造后 |
|------|--------|--------|
| 打开 App | 落到写作占位页 | 落到书架（作品列表） |
| 进入对话 | 无入口（/chat 死路由） | 点 Tab2"对话" |
| 进入写作 | 无入口 | 书架→作品→章节 |
| /chat 深链 | 渲染对话页（无 Tab） | 重定向到 Tab2（有 Tab） |

### 开发者视角
- **会话模型不变**：Tab2 ChatPage 仍用 `sessionBootstrapProvider` 取全局第一个 session（非章节隔离）
- **WritingCoachPanel 不受影响**：章节级会话隔离逻辑独立，与 Tab2 对话页互不干扰
- **写作入口链路**：书架→`/manuscript-detail`→`/writing/:chapterId`（C1 已通，未改动）

## 验证结果

- **C2 路由测试**：4/4 通过（[c2_tab2_chat_route_test.dart](../../test/router/c2_tab2_chat_route_test.dart)）
- **pre-existing 路由测试**：6/6 通过（#1 + #6 断言已同步更新）
- **全量测试**：272 通过 / 1 失败（pre-existing `persistAttitude`，与 C2 无关）
- **无新增回归**

## 回滚方式

如需回滚到 C2 改造前的状态：
1. `initialLocation` 改回 `AppRoutes.writing`
2. Tab2 分支改回 `PlaceholderPage(title: '写作', subtitle: '...')`
3. Tab2 导航项改回 `edit_outlined` + '写作'
4. `/chat` 路由改回 `builder: (context, state) => const ChatPage()`
5. 同步还原 `app_router_test.dart` 的 #1 + #6 断言

## 后续衔接

- **C3**：书架页 + 作品详情页再设计（默认 Tab 已是书架，UI 待美化）
- **C6**：Tab2 独立对话页百灵风格再设计（当前 ChatPage 为 MVP 版本）
