// ─────────────────────────────────────────────────────────────
// CoachSettingsPage — 教练设置二级页（教练人格 + 教学方式）
//
// 从设置页主区收敛进来：设置页只放一个入口行，点进来才看/改。
// 内容 = CoachSelectorCard（选人卡 + 自定义人格 + 阈值 + 教学方式开关）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../../config/app_theme.dart';
import '../../config/app_palette.dart';
import 'coach_selector_card.dart';

class CoachSettingsPage extends StatelessWidget {
  const CoachSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.background,
      appBar: AppBar(
        title: const Text('教练设置'),
        backgroundColor: context.palette.background,
        foregroundColor: context.palette.textPrimary,
        toolbarHeight: 48,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 22),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: '返回',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: const [CoachSelectorCard()],
      ),
    );
  }
}
