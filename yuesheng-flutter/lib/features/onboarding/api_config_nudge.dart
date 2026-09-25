// ─────────────────────────────────────────────────────────────
// api_config_nudge — 首次使用 AI 功能时的「配置 API」一次性引导（C2）
//
// 背景：免费测试模式会在「未配置 API」时自动走离线示例（不报错、不提示），
// 导致新手实测时「看不见 API 配置教学」（ADR 2026-09-25 侦察结论）。
// 本 helper 在用户**首次**发起真实请求（对话 / 诊断）且未配 API 时弹一次，
// 指向「设置 → API」。已配或已看过则静默跳过。
//
// 单一真源判据（与免费测试模式同源，不新造）：
//   - LlmConfigStorage().getLlmConfig() == null  ⇔ 未完整配置
//   - app_state.api_config_hint_seen == 'true'   ⇔ 已展示过
// 持久化零 schema 迁移（app_state 为 KV 表，新 key 行即可）。
// 免费测试模式语义不变；本 helper 仅做 orientation，绝不阻断请求。
// ─────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/database/database.dart';
import '../../data/repositories/app_state_repository.dart';
import '../../router/app_routes.dart';
import '../../services/llm_config_storage.dart';

/// 首次在对话 / 诊断里发起真实请求、且未配 API 时弹一次性引导。
///
/// 判据（任一满足即不弹）：已展示过（api_config_hint_seen）或 已配置 API。
/// 行为：〔去设置〕→ 深链「设置 → API」并标记已看；〔稍后〕→ 仅标记已看。
Future<void> maybeShowApiConfigNudge(
  BuildContext context,
  AppDatabase db,
) async {
  final repo = AppStateRepository(db);
  if (await repo.getApiConfigHintSeen()) return;
  final configured = await LlmConfigStorage().getLlmConfig() != null;
  if (configured) {
    await repo.setApiConfigHintSeen(true); // 已配：静默标记，不再提示
    return;
  }
  // 先标记已展示（防快速重复发送叠弹），再弹。
  await repo.setApiConfigHintSeen(true);
  if (!context.mounted) return;
  final goSettings = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('还未配置 AI 服务商 API'),
      content: const Text(
        '本应用需接入你自己的 AI 服务商 API，才能做真实诊断与教学。\n\n'
        '当前会走「免费测试模式」（离线示例），结果仅供体验。\n\n'
        '去「设置 → API」填入 Key / Base URL / 模型，即可解锁完整功能。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('稍后'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('去设置'),
        ),
      ],
    ),
  );
  if (goSettings == true && context.mounted) {
    unawaited(context.push(AppRoutes.settings));
  }
}
