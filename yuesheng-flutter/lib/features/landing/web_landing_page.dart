// ─────────────────────────────────────────────────────────────
// web_landing_page.dart — 试用介绍页（`§4-498` 首访 + `§4-499` header 入口）
//
// 舰长 2026-11-11 21:5x：「发版和试用我期待挂到同一个 web 下」；21:59 裁「留」；
// 22:24 再定形态：**试用做独立界面 · 点开先看介绍页 · header 加一个试用键切过去**。
//
// 【一页两态（同一份代码，不给入口各写一份）】
//   首访态：`onBack == null`，无返回键，CTA =「开始试用」→ 写标记进主壳。
//   入口态：`onBack != null`（从书架 header 推入），有返回键，CTA =「知道了，去试试」→ 出栈。
//   ⇒ 两态共用一个页面，避免「首访版本和入口版本各说一套」这种长期漂移；
//     两态差异**只有**返回键与 CTA 文案两处，都由此页面内判定，不散到调用方。
//
// 【为什么是独立页、而不是给 `OnboardingFlow` 加一页】
//   1. 职责不同：`OnboardingFlow` 是**应用内**首启引导（讲功能），本页讲
//      「现在就能试 / 怎么试 / 完整版在哪」。混在一串横滑里要滑 3 屏才见 CTA。
//   2. 顺带修掉一条死路：`OnboardingFlow` 第 5 页教用户去 DeepSeek 官网拿 Key →
//      设置 → API 填 Key，而 **web 上那张卡是掩码的**（`settings_page.dart:419`，
//      根因 `flutter_secure_storage_web` 替身读 null / 写抛 `UnsupportedError`）。
//      web 首访改走本页后那条死路不再可达 ⇒ **不需要改 `OnboardingFlow` 一个字**（零 R-027）。
//
// 【为什么正文写「怎么试」而不是「能看什么」】
//   实测 `llm_client.dart:254`：未配 Key 固定回一句「本次未进行诊断——没有调用真实模型」，
//   **试用者看不到任何诊断结果**。故正文只承诺流程走得通，不承诺有结果可看（见 `try_steps_section.dart`）。
//   ⚠️ 本文件旧版曾写「用于查看诊断与教学的组织方式」——那句不准确，已订正（`§4-499 ②`）。
//
// 【下载地址为什么是编译期常量、且为空时不渲染】
//   Android 发版件（`ROADMAP §3.4 M-ε`）未定稿 ⇒ 地址不存在。渲染一个点不动的按钮
//   等于再造一条死路。故 `--dart-define=ANDROID_DOWNLOAD_URL=<url>` 传了才渲染。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../../config/app_palette.dart';
import '../../config/app_theme.dart';
// 条件导入：web 走 js_interop 真跳转，非 web 走空实现（不引入 url_launcher）。
import 'try_steps_section.dart';
import 'url_opener_stub.dart'
    if (dart.library.js_interop) 'url_opener_web.dart';

/// Android 版下载地址（构建期注入；空 = 未发版，不渲染下载入口）。
const String _downloadUrl = String.fromEnvironment('ANDROID_DOWNLOAD_URL');

/// 试用介绍页：一页两态（首访 / header 入口），差异只有返回键与 CTA 文案。
class WebLandingPage extends StatelessWidget {
  const WebLandingPage({super.key, required this.onStart, this.onBack});

  /// 主 CTA 的动作。
  /// 首访态 = 写 onboarding 完成标记并进主壳（由 `main.dart` 注入 `_completeIntro`）；
  /// 入口态 = 出栈回书架（由 [TryEntryButton] 注入）。
  final VoidCallback onStart;

  /// 非空 = 从主壳推入的「入口态」：显示返回键，CTA 改为「知道了，去试试」。
  /// 为空 = 首访态：无返回键（此时无栈可回，给一个返回键就是假出口）。
  final VoidCallback? onBack;

  /// 入口态与否。两态差异全部由此布尔驱动，不在调用方分叉。
  bool get _fromEntry => onBack != null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.background,
      appBar: _buildAppBar(context),
      body: _buildBody(context),
    );
  }

  /// 顶栏：两态**都保留**（首访态透明、无 leading）⇒ 页面起始高度一致，进出不跳动。
  /// 只有入口态给返回键 —— 首访态无栈可回，给一个返回键就是假出口。
  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: context.palette.background,
      foregroundColor: context.palette.textPrimary,
      elevation: 0,
      toolbarHeight: 48,
      automaticallyImplyLeading: false,
      leading: _fromEntry
          ? IconButton(
              icon: const Icon(Icons.arrow_back, size: 22),
              onPressed: onBack,
              tooltip: '返回',
            )
          : null,
    );
  }

  Widget _buildBody(BuildContext context) {
    return SafeArea(
      top: false,
      child: Center(
        // 小高度（如 360×560 横屏笔记本分屏）下可滚动 ⇒ 不溢出；
        // 大宽度下 `ConstrainedBox` 限宽 ⇒ 桌面端不会被拉成一条长条。
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.page,
            vertical: AppSpacing.lg,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildBrand(context),
                const SizedBox(height: AppSpacing.xl),
                _buildStepsCard(context),
                const SizedBox(height: AppSpacing.xl),
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

  /// 三步区：白底卡片包住，与品牌区/CTA 拉开层级。
  Widget _buildStepsCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.palette.border),
      ),
      child: const TryStepsSection(),
    );
  }

  /// 主 CTA：文案随入口变（入口态用户已在主壳内，说「开始试用」会像让他再进一次）。
  /// 触控高度 52（>48 下限，本页是首次触达点，不省这两 dp）。
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
      child: Text(
        _fromEntry ? '知道了，去试试' : '开始试用',
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    );
  }

  /// 主 CTA 下的说明：门槛 + **边界声明**（不可省，见文件头）。
  ///
  /// 措辞按实测事实写（`llm_client.dart:254`）：走到诊断那一步会**明确说没做诊断**，
  /// 不会给假结果。**刻意不写「去设置填 Key」** —— web 上那张卡被掩码，那是一条死路。
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
                '试用不调用真实模型：走到诊断那一步，它会如实告诉你「本次未进行诊断」，'
                '不会给出假结果。完整诊断需在 Android 版配置你自己的 API Key。',
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
