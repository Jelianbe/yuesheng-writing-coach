// ─────────────────────────────────────────────────────────────
// growth_detail_nav — 成长详情页导航动作（从 State extension 真分解）
//
// 从 growth_nav.dart（原 part）真分解而来（R-019：原 part 伪拆分根除）。
//
// 原 `extension _GrowthNav on _GrowthDetailPageState` 的两个方法被
// 提取为独立类 [GrowthDetailNavigator]，显式持有 [WidgetRef]，
// BuildContext 由调用方传入——不再隐式寄生在 State 上。
//
//   - openProgressDetail  学习进度入口（批次77，传最新 sessionId）
//   - openStyleCorrection 打开风格纠正底部弹层（批次57）
//
// 无宿主私有状态依赖：仅经 ref 读取 provider。
// ─────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../config/app_palette.dart';
import '../data/repositories/session_repository.dart';
import '../providers/app_providers.dart';
import '../providers/growth_providers.dart';
import '../router/app_routes.dart';
import '../services/decode_guard.dart';
import 'growth_detail_style_sheet.dart';
import 'yue_sheet.dart';

/// 学习进度入口的**唯一实现**（交互批 #6：原 growth_page._openProgressDetail 与
/// 本类方法是逐字重复的两份 copy ⇒ 收敛；「改一处漏一处」正是 V-5 表重复同款根因）。
///
/// [context] 调用方页面 context；[ref] 宿主 Widget/State 的 WidgetRef。
/// 语义 = 查最新会话（updated_at DESC）→ 传 sessionId 进详情页；
/// 空态给引导 SnackBar，查询失败**留痕 + 告知**（P0-2 同纪律：点了没反应
/// 与死按钮不可分；静默 catch 违反 R-028）。
Future<void> openLatestSessionProgressDetail(
  BuildContext context,
  WidgetRef ref,
) async {
  try {
    final sessionRepo = SessionRepository(ref.read(appDatabaseProvider));
    final sessions = await sessionRepo.listSessions(); // updated_at DESC
    if (sessions.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('还没有写作会话，先写一章吧')));
      }
      return;
    }
    if (!context.mounted) return;
    unawaited(
      context.push(
        AppRoutes.progressDetail,
        extra: <String, dynamic>{'sessionId': sessions.first.id},
      ),
    );
  } catch (e, st) {
    // 失败不进入死页，但必须留痕 + 告知（原两处 copy 皆静默 catch）
    logSilentDegrade(
      operation: 'openLatestSessionProgressDetail',
      error: e,
      stack: st,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('学习进度加载失败，请稍后重试')));
    }
  }
}

/// 成长详情页的导航动作集合（显式持有 [WidgetRef]）
class GrowthDetailNavigator {
  final WidgetRef ref;

  const GrowthDetailNavigator(this.ref);

  /// 批次77：学习进度入口——委托文件顶部的唯一实现（交互批 #6 收敛两份 copy）。
  /// 修复旧实现 `context.go(progressDetail)` 不传参 → 落入「未提供会话 ID」占位死页。
  Future<void> openProgressDetail(BuildContext context) =>
      openLatestSessionProgressDetail(context, ref);

  /// 批次57：打开风格纠正底部弹层（纠错非重写——仅纠正五维坐标）
  Future<void> openStyleCorrection(BuildContext context) async {
    final profile = ref.read(growthStoreProvider).styleProfile;
    if (profile == null) return;
    await showYueModalBottomSheet<void>(
      context: context,
      backgroundColor: context.palette.background,
      isScrollControlled: true,
      builder: (_) => GrowthStyleCorrectionSheet(
        profile: profile,
        onSave: (updated) async {
          await ref
              .read(growthStoreProvider.notifier)
              .correctStyleProfile(updated);
          if (context.mounted) Navigator.of(context).pop();
        },
      ),
    );
  }
}
