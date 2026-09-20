// ─────────────────────────────────────────────────────────────
// main — 应用入口
// 复刻 yuesheng-android/src/app/_layout.tsx
//
// 接入：
//   - ProviderScope（Riverpod 状态管理）
//   - go_router（StatefulShellRoute 3 Tab + /chat 顶层）
//   - 批次2（2.1）：全局错误钩子（runZonedGuarded / FlutterError / PlatformDispatcher）
//     → error_logs；DB ready 前入内存队列，appDatabaseProvider 首读时 flush
// ─────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config/app_theme.dart';
import 'data/repositories/app_state_repository.dart';
import 'data/repositories/chapter_repository.dart';
import 'data/repositories/manuscript_repository.dart';
import 'data/repositories/volume_repository.dart';
import 'providers/app_error_observer.dart';
import 'providers/app_providers.dart';
import 'router/app_router.dart';
import 'services/error_handler.dart';
import 'theme/theme_controller.dart';
import 'widgets/onboarding_flow.dart';
import 'widgets/privacy_notice_dialog.dart';
import 'package:writingcoach/widgets/ui_overlay_host.dart';

/// 演示数据种子开关（默认关闭；`flutter run --dart-define=SEED_DEMO=true`
/// 开启——批次89 卷分组效果演示用，正常打包运行不受影响）
const _seedDemo = bool.fromEnvironment('SEED_DEMO');

void main() {
  // 批次55：冷启动基线观测——main 到首帧耗时（仅 debug 留痕，建基线待真实设备采集）
  final coldStartWatch = Stopwatch()..start();
  WidgetsFlutterBinding.ensureInitialized();
  // 批次2（2.1）：错误钩子先行注册——早于 DB ready 的错误先入内存队列
  ErrorHandler.instance.installErrorHandlers();
  runZonedGuarded(
    () {
      runApp(
        const ProviderScope(
          // 入档批次：ProviderObserver 全局拦截（provider 失败 → error_logs）
          observers: [AppErrorObserver()],
          child: YueshengApp(),
        ),
      );
      // 首帧构建/绘制完成后记录耗时
      WidgetsBinding.instance.addPostFrameCallback((_) {
        coldStartWatch.stop();
        debugPrint(
          '[批次55 冷启动] main→首帧 ${coldStartWatch.elapsedMilliseconds}ms（仅观测）',
        );
      });
    },
    (error, stack) {
      ErrorHandler.instance.captureError(
        level: 'error',
        category: 'uncaught',
        message: error.toString(),
        stack: stack.toString(),
      );
    },
  );
}

// buildAppTheme / buildDarkTheme 已迁至 lib/theme/app_theme.dart（2026-09-20 主题架构）。
// 主题选择经 lib/theme/theme_registry.dart + theme_controller.dart 单一真源驱动。

/// 应用根组件（批次63：首启功能引导门）
///
/// 启动时读 AppStateRepository.getOnboardingCompleted()：
///   - null（加载中）：空白页（避免闪烁）
///   - false（未看过引导）：全屏 OnboardingFlow，完成后写标记进主壳
///   - true（已看过）：直接进主壳（MaterialApp.router）
/// DB 异常静默放行进主壳（引导不阻断核心使用）
class YueshengApp extends ConsumerStatefulWidget {
  const YueshengApp({super.key});

  @override
  ConsumerState<YueshengApp> createState() => _YueshengAppState();
}

class _YueshengAppState extends ConsumerState<YueshengApp> {
  bool? _introDone;

  @override
  void initState() {
    super.initState();
    _checkIntro();
    // 主题：首帧后从 app_state 水合（幂等，读失败保持 light）
    unawaited(ref.read(themeControllerProvider.notifier).hydrate());
  }

  Future<void> _checkIntro() async {
    try {
      final db = ref.read(appDatabaseProvider);
      final done = await AppStateRepository(db).getOnboardingCompleted();
      // 演示数据种子（SEED_DEMO）：仅演示模式注入，不阻塞 UI
      unawaited(_seedDemoIfEmpty());
      if (!mounted) return;
      setState(() => _introDone = done);
    } catch (_) {
      // DB 初始化失败：静默放行进主壳，引导不阻断核心使用
      if (!mounted) return;
      setState(() => _introDone = true);
    }
  }

  /// 演示数据注入（仅 `--dart-define=SEED_DEMO=true` 时生效）：
  ///   - 空库：预置作品「山月记」+ 卷「第一卷/第二卷」+ 章节（第一卷 2 章 + 未分卷 1 章）；
  ///   - 已有作品（无卷）：自动补「第一卷」（现有章节移入）+ 空「第二卷」；
  /// 并标记引导已完成——打开即见卷分组效果，无需手动造数。
  Future<void> _seedDemoIfEmpty() async {
    if (!_seedDemo) return;
    try {
      final db = ref.read(appDatabaseProvider);
      await AppStateRepository(db).setOnboardingCompleted(true);
      final msRepo = ManuscriptRepository(db);
      final volRepo = VolumeRepository(db);
      final chRepo = ChapterRepository(db);
      final manuscripts = await msRepo.listManuscripts();
      if (manuscripts.isEmpty) {
        final msId = await msRepo.createManuscript(title: '山月记');
        final v1 = await volRepo.createVolume(msId, title: '第一卷');
        await volRepo.createVolume(msId, title: '第二卷');
        await chRepo.createChapter(
          msId,
          title: '第一章：晨雾',
          content: '晨雾里，他推开了窗。\n\u3000\u3000山脊在雾中若隐若现。',
          volumeId: v1,
        );
        await chRepo.createChapter(
          msId,
          title: '第二章：夜行',
          content: '夜行的人，影子被月光拉得很长。',
          volumeId: v1,
        );
        await chRepo.createChapter(msId, title: '散章', content: '一段尚未分卷的随想。');
        debugPrint('[SEED_DEMO] 演示数据已注入（山月记 + 2 卷 + 3 章）');
      } else {
        // 已有作品无卷 → 补卷让分组效果立即可见
        for (final ms in manuscripts) {
          final vols = await volRepo.listVolumes(ms.id);
          if (vols.isNotEmpty) continue;
          final v1 = await volRepo.createVolume(ms.id, title: '第一卷');
          for (final c in await chRepo.listChapters(ms.id)) {
            await volRepo.setChapterVolume(c.id, v1);
          }
          await volRepo.createVolume(ms.id, title: '第二卷');
          debugPrint('[SEED_DEMO] 已为作品「${ms.title}」补卷（第一卷 + 第二卷）');
        }
      }
    } catch (e) {
      debugPrint('[SEED_DEMO] 注入失败: $e');
    }
  }

  Future<void> _completeIntro() async {
    try {
      final db = ref.read(appDatabaseProvider);
      await AppStateRepository(db).setOnboardingCompleted(true);
    } catch (e, st) {
      // 降级行为保留：标记写入失败也继续进入主页（否则用户会卡在引导页）。
      // 代价是下次启动仍会看到引导页——此前静默吞掉，无从追溯。
      debugPrint('[Intro] 引导完成标记写入失败，下次启动将重复引导: $e');
      ErrorHandler.instance.captureError(
        level: 'warn',
        category: 'database',
        message: '引导完成标记写入失败，下次启动将重复引导',
        context: {'error': '$e'},
        stack: '$st',
      );
    }
    if (!mounted) return;
    setState(() => _introDone = true);
    // v0.1 发布批：轮播是问卷之前的第一级首启，「跳过」也走这里。
    // 跳过轮播的用户可能不再经过问卷直接开聊，隐私告知须在此兜底触发（一次性）。
    await _maybeShowPrivacyNotice();
  }

  /// 轮播结束后的一次性隐私与费用告知（与问卷路径共用同一 flag，先到先弹）。
  Future<void> _maybeShowPrivacyNotice() async {
    if (!mounted) return;
    // 主界面 MaterialApp.router 在下一帧才挂载，先等帧再取 Navigator context
    await WidgetsBinding.instance.endOfFrame;
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    final appState = AppStateRepository(ref.read(appDatabaseProvider));
    await maybeShowPrivacyNoticeOnce(ctx, appState);
  }

  @override
  Widget build(BuildContext context) {
    final done = _introDone;
    // 主题单一真源：注册表按当前 ThemeId 出 ThemeData；themeMode 恒 light
    // ⇒ 强制使用 `theme`（即所选主题），不跟随系统（系统深色在 ColorOS 上不可控）。
    final theme = themeDataFor(ref.watch(themeControllerProvider));
    if (done == false) {
      // 批次63：首启功能引导页
      return MaterialApp(
        title: '月笙写作教练',
        debugShowCheckedModeBanner: false,
        theme: theme,
        themeMode: ThemeMode.light,
        home: OnboardingFlow(onComplete: _completeIntro),
      );
    }
    if (done == null) {
      // 引导标记读取中：空白页，避免主题闪烁
      return MaterialApp(
        title: '月笙写作教练',
        debugShowCheckedModeBanner: false,
        theme: theme,
        themeMode: ThemeMode.light,
        home: const Scaffold(
          backgroundColor: AppColors.background,
          body: SizedBox.shrink(),
        ),
      );
    }
    return MaterialApp.router(
      title: '月笙写作教练',
      theme: theme,
      themeMode: ThemeMode.light,
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
      // 入档批次：全局 Toast/Dialog 覆盖层（纯增量能力）
      builder: (context, child) =>
          Stack(children: [?child, const UiOverlayHost()]),
    );
  }
}
