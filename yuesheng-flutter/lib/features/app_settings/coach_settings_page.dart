// ─────────────────────────────────────────────────────────────
// CoachSettingsPage — 教练设置二级页
//
// 从设置页 + 成长页收敛进来：
//   - 教练人格选人卡（系统预设 + 自定义人格 + 阈值）
//   - 教学方式（疑问式 / 直接说）
//   - 诊断偏好（写作阶段 × 题材，原成长页"教练侧重"banner）
//
// 入口：
//   - 设置页「教练」卡片 → 「教练人格与教学方式」
//   - 成长页「教学设置」入口行
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../../config/app_theme.dart';
import '../../config/app_palette.dart';
import '../growth/growth_diagnosis_prefs_card.dart';
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
        children: const [
          CoachSelectorCard(),
          SizedBox(height: 12),
          GrowthDiagnosisPrefsCard(embedded: true),
        ],
      ),
    );
  }
}
