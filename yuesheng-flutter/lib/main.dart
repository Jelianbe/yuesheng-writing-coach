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

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config/app_motion.dart';
import 'config/app_theme.dart';
import 'data/repositories/app_state_repository.dart';
import 'data/repositories/chapter_repository.dart';
import 'data/repositories/manuscript_repository.dart';
import 'data/repositories/volume_repository.dart';
import 'providers/app_providers.dart';
import 'router/app_router.dart';
import 'services/error_handler.dart';
import 'widgets/onboarding_flow.dart';

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
      runApp(const ProviderScope(child: YueshengApp()));
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

/// 应用主题（主壳与引导页共用，月色竹青令牌真源）
ThemeData buildAppTheme() {
  return ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      onPrimary: AppColors.onPrimary,
      surface: AppColors.background,
      onSurface: AppColors.textPrimary,
      error: AppColors.danger,
    ),
    useMaterial3: true,
    // 批次67：页面转场收敛——Android/桌面用自定义轻量过渡
    // （YueFadeSlidePageTransitionsBuilder：fade+轻微上滑 220ms easeOutCubic，
    // 替代 PredictiveBack/FadeForwards 的 450ms 长过渡与 Zoom 的缩放感）；
    // iOS/macOS 保留 Cupertino（滑动返回手势是平台核心交互，不能破坏）
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: YueFadeSlidePageTransitionsBuilder(),
        TargetPlatform.fuchsia: YueFadeSlidePageTransitionsBuilder(),
        TargetPlatform.linux: YueFadeSlidePageTransitionsBuilder(),
        TargetPlatform.windows: YueFadeSlidePageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      },
    ),
    scaffoldBackgroundColor: AppColors.background,
    textTheme: const TextTheme(
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      bodyMedium: TextStyle(fontSize: 15, color: AppColors.textPrimary),
      bodySmall: AppTextStyles.subBody,
    ),
  );
}

/// 暗夜主题（批次94-3：ThemeMode.system 跟随系统暗色，Material 层暗色）
///
/// 渐进说明：AppColors 为静态亮色令牌（76 文件 1668 处引用、含 147 处 const
/// 上下文），本轮仅做「系统级 ThemeData 暗色」——Dialog/Sheet/SnackBar/
/// TextField 光标等 Material 组件跟随系统暗色；自定义页面底色仍用亮色令牌，
/// 全量令牌化（AppColors 双 token）列入后续批次（见台账 94-3 执行记录）。
ThemeData buildDarkTheme() {
  const darkScaffold = Color(0xFF1E2126); // 深墨（略深于编辑器暗夜预设）
  const darkSurface = Color(0xFF26282B); // 对齐 editorBgDark
  const darkText = Color(0xFFE8EAED); // 对齐 editorBgDark 文字
  return ThemeData(
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.dark,
      primary: AppColors.primary,
      surface: darkSurface,
      onSurface: darkText,
      error: AppColors.l3Text,
    ),
    useMaterial3: true,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: YueFadeSlidePageTransitionsBuilder(),
        TargetPlatform.fuchsia: YueFadeSlidePageTransitionsBuilder(),
        TargetPlatform.linux: YueFadeSlidePageTransitionsBuilder(),
        TargetPlatform.windows: YueFadeSlidePageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      },
    ),
    scaffoldBackgroundColor: darkScaffold,
    dialogTheme: const DialogThemeData(backgroundColor: darkSurface),
    textTheme: const TextTheme(
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: darkText,
      ),
      bodyMedium: TextStyle(fontSize: 15, color: darkText),
      bodySmall: TextStyle(fontSize: 13, color: Color(0xFF9AA0A6)),
    ),
  );
}

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
  }

  Future<void> _checkIntro() async {
    try {
      final db = ref.read(appDatabaseProvider);
      final done = await AppStateRepository(db).getOnboardingCompleted();
      // 演示数据种子（SEED_DEMO）：仅演示模式注入，不阻塞 UI
      _seedDemoIfEmpty();
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
    } catch (_) {}
    if (!mounted) return;
    setState(() => _introDone = true);
  }

  @override
  Widget build(BuildContext context) {
    final done = _introDone;
    if (done == false) {
      // 批次63：首启功能引导页
      return MaterialApp(
        title: '月笙写作教练',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        darkTheme: buildDarkTheme(),
        themeMode: ThemeMode.system,
        home: OnboardingFlow(onComplete: _completeIntro),
      );
    }
    if (done == null) {
      // 引导标记读取中：空白页，避免主题闪烁
      return MaterialApp(
        title: '月笙写作教练',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        darkTheme: buildDarkTheme(),
        themeMode: ThemeMode.system,
        home: const Scaffold(
          backgroundColor: AppColors.background,
          body: SizedBox.shrink(),
        ),
      );
    }
    return MaterialApp.router(
      title: '月笙写作教练',
      theme: buildAppTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: ThemeMode.system,
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
    );
  }
}
