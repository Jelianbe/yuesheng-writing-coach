// ─────────────────────────────────────────────────────────────
// GrowthDetailPage — 成长详情页（用户级能力画像详情）
//
// 视觉规范（月色竹青，对齐 GrowthPage）：
//   AppBar       #F7F8F6 + 48dp + 深字 #2D3142
//   Scaffold 背景 #F7F8F6
//   卡片         #F2F4F2 + 左侧 4dp 竹青色条
//   时间线       左侧 2dp 竹青竖线 + 8dp 圆点
//
// 布局：
//   1. 能力画像卡片：ProficiencyRing + 认知风格 + 总会话数
//   2. 症候分布列表：按教学状态分组（练习中/待诊断/巩固中/已掌握，批次 48 对齐 RN）
//   3. 诊断历史时间线：按 timestamp DESC
//
// 空状态：暂无诊断数据（图标 + 文本）
//
// 架构（R-019 真分解）：本文件仅保留页面宿主 [GrowthDetailPage] 与其
// State（生命周期 + 装配）。内容/导航/原子组件已拆为独立文件：
//   - growth_detail_content.dart       内容主体（纯渲染 StatelessWidget）
//   - growth_detail_nav.dart           导航动作（GrowthDetailNavigator）
//   - growth_detail_labels.dart        展示文案顶层纯函数
//   - growth_detail_overview.dart      写作总览组件
//   - growth_detail_timeline.dart      诊断历史时间线
//   - growth_detail_style_sheet.dart   风格纠正弹层
//   - growth_detail_widgets.dart       通用原子组件
//   - growth_detail_error_view.dart    错误态视图
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../config/app_theme.dart';
import '../providers/growth_providers.dart';
import 'growth_detail_content.dart';
import 'growth_detail_error_view.dart';
import 'growth_detail_nav.dart';

/// 成长详情页
class GrowthDetailPage extends ConsumerStatefulWidget {
  const GrowthDetailPage({super.key});

  @override
  ConsumerState<GrowthDetailPage> createState() => _GrowthDetailPageState();
}

class _GrowthDetailPageState extends ConsumerState<GrowthDetailPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(growthStoreProvider.notifier).loadGrowthData();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(growthStoreProvider);
    final navigator = GrowthDetailNavigator(ref);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('能力画像'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        toolbarHeight: 48,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 22),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/growth'),
          tooltip: '返回',
        ),
      ),
      body: state.isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : state.error != null
          ? GrowthErrorView(
              error: state.error!,
              onRetry: () =>
                  ref.read(growthStoreProvider.notifier).loadGrowthData(),
            )
          : GrowthDetailContent(
              state: state,
              onOpenProgressDetail: () => navigator.openProgressDetail(context),
              onOpenStyleCorrection: () =>
                  navigator.openStyleCorrection(context),
            ),
    );
  }
}
