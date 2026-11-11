// ─────────────────────────────────────────────────────────────
// web_landing_page.dart — web 站点门面（发版 + 试用同一个 web · `§4-498`）
//
// 舰长 2026-11-11 21:5x：「发版和试用我期待挂到同一个 web 下」；21:59 裁「留」。
// 本页 = 那条路径的第一段：**看见 → 试用 → 想要完整版（下载 Android）**。
//
// 【为什么是独立页而不是给 `OnboardingFlow` 加一页】
//   1. 职责不同：`OnboardingFlow` 是**应用内**首启引导（讲功能），本页是**站点门面**
//      （讲「现在就能试 / 完整版在哪」）。混在一串横滑里，用户要滑 3 屏才见到 CTA。
//   2. 顺带修掉一条死路：`OnboardingFlow` 第 5 页在教用户去 DeepSeek 官网拿 Key →
//      设置 → API 填 Key，而 **web 上那张卡是掩码的**（`settings_page.dart:419` 的
//      `if (!kIsWeb)`，根因 `flutter_secure_storage_web` 替身读 null / 写抛
//      `UnsupportedError`，`§4-238②`）。web 首访改走本页后，那条死路**不再可达**，
//      因此**不需要改 `OnboardingFlow` 一个字**（零 R-027）。
//
// 【为什么必须明示「示例模式」】
//   web 上没有任何真实 LLM 调用通道：不存 key（替身）、平台垫付未接
//   （`lib/` 内 `workbuddy` / `垫付` / `publicConfig` 零命中）⇒ 未配 key 的用户
//   落到「免费测试模式」，其固定文案是「本次未进行诊断——没有调用真实模型」。
//   把这件事写在按钮旁边，而不是等用户点进去自己发现 —— 否则门面就是在承诺
//   一个不存在的能力。**「不承诺」比「转化率」重要。**
//
// 【下载地址为什么是编译期常量、且为空时不渲染】
//   Android 发版件（`ROADMAP §3.4 M-ε`）目前未定稿 ⇒ 地址不存在。
//   若渲染一个点不动的按钮，等于在门面上再造一条死路（本案正是在修死路）。
//   故：`--dart-define=ANDROID_DOWNLOAD_URL=<url>` 传了才渲染。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../../config/app_palette.dart';
import '../../config/app_theme.dart';
// 条件导入：web 走 js_interop 真跳转，非 web 走空实现（不引入 url_launcher）。
import 'url_opener_stub.dart'
    if (dart.library.js_interop) 'url_opener_web.dart';

/// Android 版下载地址（构建期注入；空 = 未发版，不渲染下载入口）。
const String _downloadUrl = String.fromEnvironment('ANDROID_DOWNLOAD_URL');

/// web 站点门面：一个主 CTA（试用）+ 一个可选次 CTA（下载 Android）。
class WebLandingPage extends StatelessWidget {
  const WebLandingPage({super.key, required this.onStart});

  /// 进入应用（写 onboarding 完成标记 + 进主壳）。由 `main.dart` 注入，
  /// 与 `OnboardingFlow.onComplete` 同一个回调 —— 两条首访路径共用一套状态机。
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.background,
      body: SafeArea(
        child: Center(
          // 小高度（如 360×560 横屏笔记本分屏）下可滚动 ⇒ 不溢出；
          // 大宽度下 `ConstrainedBox` 限宽 ⇒ 桌面端不会被拉成一条长条。
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.page,
              vertical: AppSpacing.xxl,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildBrand(context),
                  const SizedBox(height: AppSpacing.xxl),
                  _buildTryButton(context),
                  const SizedBox(height: AppSpacing.sm),
                  _buildTryNote(context),
                  if (_downloadUrl.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xl),
                    _buildDownload(context),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 品牌区：图标 + 名称 + 一句话定位。
  Widget _buildBrand(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: context.palette.primarySoft,
            borderRadius: BorderRadius.circular(AppRadius.xl),
          ),
          child: Icon(
            Icons.auto_stories,
            size: 36,
            color: context.palette.primary,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          '月笙写作教练',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            height: 1.3,
            color: context.palette.textPrimary,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          '把稿子交给我，我告诉你问题在哪、以及怎么改',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            height: 1.6,
            color: context.palette.textSecondary,
          ),
        ),
      ],
    );
  }

  /// 主 CTA：立即试用。触控高度 52（>48 下限，门面页是首次触达点，不省这两 dp）。
  Widget _buildTryButton(BuildContext context) {
    return FilledButton(
      onPressed: onStart,
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        backgroundColor: context.palette.primary,
        foregroundColor: context.palette.onPrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      child: const Text(
        '立即试用',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    );
  }

  /// 主 CTA 下的两行说明：门槛 + **示例模式明示**（不可省，见文件头）。
  Widget _buildTryNote(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '无需注册 · 无需 API Key',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            height: 1.5,
            color: context.palette.textTertiary,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline,
              size: 14,
              color: context.palette.textTertiary,
            ),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                '试用为示例模式：不调用真实模型，用于查看诊断与教学的组织方式',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: context.palette.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 次 CTA：下载 Android 版（未配置地址时整个不渲染，见文件头第 3 段）。
  Widget _buildDownload(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        OutlinedButton(
          onPressed: () => _openDownload(context),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            foregroundColor: context.palette.primary,
            side: BorderSide(color: context.palette.border),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
          ),
          child: const Text(
            '下载 Android 版',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          '完整诊断需自备 AI 服务商 API Key，在 Android 版中配置',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            height: 1.5,
            color: context.palette.textTertiary,
          ),
        ),
      ],
    );
  }

  /// 打开下载地址：web 用新标签页（不把用户从当前页带走）。
  ///
  /// 跳转走条件导入的 [openExternalUrl]（web = `dart:js_interop`，wasm 兼容；
  /// 非 web = 空实现）。**不引入 `url_launcher`**：新依赖须单独报批。
  /// 按钮是否出现由 [_downloadUrl] 控制 ⇒ 未发版时用户看不到此按钮，
  /// 因此不存在「按钮在但点了没反应」的死路。
  void _openDownload(BuildContext context) {
    openExternalUrl(_downloadUrl);
  }
}
