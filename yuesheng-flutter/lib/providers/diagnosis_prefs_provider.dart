// ─────────────────────────────────────────────────────────────
// diagnosis_prefs_provider — 诊断偏好的**单一真源**（Riverpod）
//
// ★ B6-N（2026-10-06）：解决「状态有两个主人但只有一个真源」。
//
// ── 原缺陷 ──
//   `GrowthDiagnosisPrefsCard` 在**成长页**（折叠态 `embedded=false`）与
//   **设置页**（编辑态 `embedded=true`）是两个**独立 widget 实例**，各自
//   `initState` 里 `getDiagnosisPrefs()` 读一次 DB 就把结果冻结进本地 State。
//   ⇒ 在设置页改偏好只改到设置页那个实例；成长页那个实例的
//   `_prefs` 仍是旧值 ⇒ **后缀词「教学设置 · 完整故事」不变**。
//   根因不是缓存失效，而是**缺通知机制 + 实例状态各自冻结**
//   （`AppStateRepository` 既无 ChangeNotifier 也无 Stream）。
//
// ── 为什么用 provider 而不是「返回时强制 reload」──
//   后者只治成长页这一条路径：设置页 → 其他页面仍会踩；且同一成长页里
//   打印了**两个**折叠态卡片（`growth_page.dart:266` 与 `:455`），
//   两者也会各自冻结。provider 化让「偏好」只有一个主人，
//   任何处写入 → 所有 `ref.watch` 的地方同步更新。
//
// ── 数据源不变 ──
//   仍是 `AppStateRepository.getDiagnosisPrefs()`（SQLite `app_state`），
//   本provider 只是**加一层缓存 + 失效入口**，不引入第二真源、不加 schema。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/app_state_repository.dart';
import 'app_providers.dart';

/// 诊断偏好（`null` = 未设置 = 全启用，走默认）。
///
/// 用 `FutureProvider` 而非 `StateProvider`：数据源是异步 DB，
/// 由 provider 统一管理 loading / error，避免每个调用点各写一遍
/// 「loading 时先不渲染、失败时静默」（卡片原有逻辑正是这么做的）。
final diagnosisPrefsProvider = FutureProvider<DiagnosisPrefs?>(
  (ref) =>
      AppStateRepository(ref.watch(appDatabaseProvider)).getDiagnosisPrefs(),
);
