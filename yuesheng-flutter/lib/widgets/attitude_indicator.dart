// ─────────────────────────────────────────────────────────────
// AttitudeIndicator — 态度档位切换器
// 复刻 yuesheng-android/src/components/chat/AttitudeIndicator.tsx
// （attitude-rhythm.json 的 label / toneDescription / color）
//
// 结构：
//   1. 顶部指示器：色点 + 当前档位 label（点击弹底部选择面板）
//   2. 底部面板：标题 + 3 档选项（色点 + 名称 + 语气说明 + 当前档位勾选）
//
// 档位与配色（月色竹青矿物色体系，对齐 RN green/yellow/red）：
//   doubao  → 温和、鼓励、先肯定（竹青绿 l1Text）
//   yuesheng → 直接、精准、理性（矿物黄 l2Text）
//   sensei  → 一针见血、刺痛但不侮辱（矿物红 l3Text）
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import 'yue_sheet.dart';
import '../types/teaching_types.dart';

/// 档位展示配置（对齐 attitude-rhythm.json）
class _AttitudeMeta {
  final String label;
  final String description;
  final Color color;

  const _AttitudeMeta({
    required this.label,
    required this.description,
    required this.color,
  });
}

const Map<AttitudeLevel, _AttitudeMeta> _attitudeMeta = {
  AttitudeLevel.doubao: _AttitudeMeta(
    label: '豆包',
    description: '温和、鼓励、先肯定',
    color: AppColors.l1Text,
  ),
  AttitudeLevel.yuesheng: _AttitudeMeta(
    label: '月笙如歌',
    description: '直接、精准、理性',
    color: AppColors.l2Text,
  ),
  AttitudeLevel.sensei: _AttitudeMeta(
    label: 'sensei',
    description: '一针见血、刺痛但不侮辱',
    color: AppColors.l3Text,
  ),
};

const List<AttitudeLevel> _attitudeOrder = [
  AttitudeLevel.doubao,
  AttitudeLevel.yuesheng,
  AttitudeLevel.sensei,
];

class AttitudeIndicator extends StatelessWidget {
  final AttitudeLevel currentAttitude;

  /// 选择回调（切换态度）
  final void Function(AttitudeLevel attitude) onSelect;

  const AttitudeIndicator({
    super.key,
    required this.currentAttitude,
    required this.onSelect,
  });

  /// 弹出底部选择面板
  Future<void> _showSheet(BuildContext context) async {
    final selected = await showYueModalBottomSheet<AttitudeLevel>(
      context: context,
      backgroundColor: AppColors.background,
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.xl,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Center(
                  child: Text(
                    '选择态度档位',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                for (final attitude in _attitudeOrder)
                  _AttitudeOption(
                    attitude: attitude,
                    meta: _attitudeMeta[attitude]!,
                    isActive: attitude == currentAttitude,
                    onTap: () => Navigator.pop(sheetCtx, attitude),
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (selected != null) {
      onSelect(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final meta = _attitudeMeta[currentAttitude]!;

    return InkWell(
      onTap: () => _showSheet(context),
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.smx, vertical: AppSpacing.xsm),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: meta.color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              meta.label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 2),
            const Icon(
              Icons.expand_more,
              size: 16,
              color: AppColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

/// 面板中的单个档位选项
class _AttitudeOption extends StatelessWidget {
  final AttitudeLevel attitude;
  final _AttitudeMeta meta;
  final bool isActive;
  final VoidCallback onTap;

  const _AttitudeOption({
    required this.attitude,
    required this.meta,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: AppSpacing.md),
        decoration: BoxDecoration(
          color: isActive ? AppColors.l1 : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: isActive
              ? Border.all(color: meta.color)
              : Border.all(color: AppColors.borderLight),
        ),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: meta.color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    meta.label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    meta.description,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            if (isActive) Icon(Icons.check, size: 18, color: meta.color),
          ],
        ),
      ),
    );
  }
}
