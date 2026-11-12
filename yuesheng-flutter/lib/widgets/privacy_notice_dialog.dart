// ─────────────────────────────────────────────────────────────
// privacy_notice_dialog — 隐私与费用告知（v0.1 首次分发）
//
// 双落点（发布准备批任务 2）：
//   1. 首启一次性：问卷完成/跳过后弹出（maybeShowPrivacyNoticeOnce，
//      flag 存 app_state KV，key = privacy_notice_acknowledged）；
//   2. 设置页常驻入口：主动查看，复用同一对话框。
// 文案为拟稿，发布前需舰长过目（台账登记）。
//
// ─────────────────────────────────────────────────────────────
// ★ 2026-11-11 按平台分支（舰长「按你推荐做」· `§4-500`）
//
// 【为什么必须分两套话】原文三句是**为 BYOK 用户写的**，在 web 上逐句不成立：
//   ①「发送至**你所选的** AI 服务商 API」—— web 试用者没有服务商（无 Key）
//   ②「全部数据仅存储在**你的设备**本地」—— 方向对，但 web 的落盘是浏览器
//      IndexedDB（`WasmDatabase` + `drift_worker.js`），说「设备」含糊
//   ③「API 费用由你对应的**服务商账户**承担」—— web 试用者没有账户
//   ⇒ 对 web 用户弹出这三句 = **虚假告知**。它比「不告知」更坏：用户会据此
//     以为自己的稿子已经被发给了某个第三方。
//
// 【web 三句的事实依据（逐句可核，不凭印象）】
//   ★ 此处**刻意不写行号**（2026-11-12 实测：`settings_page.dart` 的 `!kIsWeb`
//     守卫在我加一行 import 后从 419 漂到 420，`llm_client.dart` 的免费分支从
//     437 漂到 439）。行号会随任何无关改动漂移 ⇒ 写行号 = 造一条会变假的引用。
//     改为按**符号**定位，grep 即可命中，不会过期：
//   ① 不调模型：`llm_client.dart` 未配 Key 时直接 `return` `_kFreeTestReply`，
//      而 web 无法配 Key（`settings_page.dart` 的 `if (!kIsWeb)` 掩码了 API 配置区，
//      且 `flutter_secure_storage_web` 写 Key 抛 `UnsupportedError`）
//   ② 数据在浏览器本地：`database_web.dart` 的 `WasmDatabase.open(...)`，
//      drift 的 wasm 后端经 `drift_worker.js` 落 IndexedDB
//   ③ 无 Key ⇒ 无调用 ⇒ 无费用；设置页 API 区在 web 不可达
//
// 【为什么 `isWeb` 是 `required` 而不是默认 `kIsWeb`】
//   `kIsWeb` 在 VM 测试里恒 `false` ⇒ 带默认值的写法下 web 分支**永远测不到**
//   = 写了一条不可能变红的判据（`.ai/PRACTICES.md A3c`）。
//   做成必传后：① 两个分支都能被 widget 测试直接喂值断言；
//   ② 漏传是**编译错误**，不会被静默默认成「非 web」而给 web 用户看错话；
//   ③ 判定点仍只有一处 —— 三处调用方统一传 `isWebSurface()`（`landing_gate.dart`），
//      本文件不 import 它（`widgets/` 反依赖 `features/` 属分层倒挂）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../data/repositories/app_state_repository.dart';
import '../theme/app_typography.dart';
import '../config/app_palette.dart';

/// app_state KV key：隐私告知是否已确认（'1' = 已确认）
const String kPrivacyNoticeAckKey = 'privacy_notice_acknowledged';

/// 隐私告知正文（**纯函数** ⇒ 两分支都能断言，不依赖真实平台）。
///
/// `isWeb` 的含义与 `landing_gate.isWebSurface()` 一致；此处**不重复实现**平台判定，
/// 只接收结果 —— 判定点保持唯一。
List<String> privacyNoticeLines({required bool isWeb}) {
  if (isWeb) {
    return const [
      '· 当前为示例模式：不调用任何 AI 服务商，你的作品文本不会被发送出去。',
      '· 数据保存在你的浏览器本地，本应用无任何遥测与数据上报。',
      '· 因此无需填写 API Key，也不产生任何 API 费用。',
    ];
  }
  // ★ 以下三句**逐字保持原样**：Android 已分发用户看到的文案不变（零行为变化）。
  return const [
    '· 你的作品文本会发送至你所选的 AI 服务商 API，用于生成诊断与教学反馈。',
    '· 全部数据仅存储在你的设备本地，本应用无任何遥测与数据上报。',
    '· API 费用由你对应的服务商账户按用量承担，本应用不代收任何费用。',
  ];
}

/// 首启一次性告知：未确认过则弹对话框，用户确认后落 flag。
///
/// flag 未落（如确认前杀进程）时下次仍会尝试，设置页入口为兜底。
Future<void> maybeShowPrivacyNoticeOnce(
  BuildContext context,
  AppStateRepository appState, {
  required bool isWeb,
}) async {
  final acked = await appState.getValue(kPrivacyNoticeAckKey);
  if (acked == '1') return;
  if (!context.mounted) return;
  await showPrivacyNoticeDialog(context, isWeb: isWeb);
  await appState.setValue(kPrivacyNoticeAckKey, '1');
}

/// 隐私与费用告知对话框（不可点外部关闭，须按「我知道了」）
Future<void> showPrivacyNoticeDialog(
  BuildContext context, {
  required bool isWeb,
}) {
  final lines = privacyNoticeLines(isWeb: isWeb);
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: Text('开始之前，请了解', style: context.text.titleLg),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < lines.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            Text(lines[i], style: context.text.body),
          ],
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          style: FilledButton.styleFrom(
            backgroundColor: context.palette.primary,
            foregroundColor: context.palette.onPrimary,
          ),
          child: const Text('我知道了'),
        ),
      ],
    ),
  );
}
