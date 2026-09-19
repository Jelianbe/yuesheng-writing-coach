// ─────────────────────────────────────────────────────────────
// focus_card — 教学线 P1-4「当前焦点 + 下一步」卡
//
// 一卡三段（竖屏克制）：停滞条（可选）→ 当前焦点 → 下一步建议。
// 纯展示组件：数据由 buildFocusCardData 组装（services 层），
// 本文件只渲染。R-009：全部文案为系统建议，不强制。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../services/focus_card_builder.dart';

/// 当前焦点卡。data == null 时调用方不应渲染本组件。
class FocusCard extends StatelessWidget {
  final FocusCardData data;

  const FocusCard({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (data.stagnated) _StagnationBanner(reason: data.stagnationReason),
        _Card(child: _CardBody(data: data)),
      ],
    );
  }
}

/// 卡体（焦点 + 为什么 + 下一步，R-019 拆出）。
class _CardBody extends StatelessWidget {
  final FocusCardData data;

  const _CardBody({required this.data});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '当前焦点',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '建议先关注：${data.focusName}',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            data.progressNarrative,
            style: const TextStyle(fontSize: 12, color: AppColors.primary),
          ),
          const SizedBox(height: 6),
          Text(
            data.reason,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '下一步：可练「${data.focusName}」的 ${data.skillLevel.value} '
            '${data.skillLevel.label} · ${data.intervention.value}'
            '（${data.intervention.label}）',
            style: const TextStyle(fontSize: 13, color: AppColors.primary),
          ),
        ],
      ),
    );
  }
}

/// 停滞提示条（仅当 detectStagnation 命中）。
class _StagnationBanner extends StatelessWidget {
  final String? reason;

  const _StagnationBanner({this.reason});

  @override
  Widget build(BuildContext context) {
    final text = reason == null || reason!.isEmpty
        ? '最近多次诊断未见改善信号，建议调整练习方式'
        : '最近多次诊断未见改善信号（$reason），建议调整练习方式';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.warningBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, color: AppColors.warning),
      ),
    );
  }
}

/// 通用卡片（左侧 4dp 竹青色条，与成长页 _Card 视觉一致）。
class _Card extends StatelessWidget {
  final Widget child;

  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: const BoxDecoration(color: AppColors.surface),
        child: child,
      ),
    );
  }
}
