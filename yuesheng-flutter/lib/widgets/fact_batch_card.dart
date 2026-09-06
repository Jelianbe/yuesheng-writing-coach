// ─────────────────────────────────────────────────────────────
// FactBatchCard — FR-10 批次沉淀提示卡（C78 批次3）
//
// 渲染位置：诊断消息（assistant）尾部，由**系统**渲染（非 AI 协议输出，
// D-7 静默沉淀 + 批次视图）。数据 = 内存态注册表（fact_batch_provider），
// 重启后卡片消失——「最近批次」语义本就是 transient，角色页横幅如实标注。
//
// 点入：go_router 深链 /characters（extra 携 manuscriptId + since），
// 角色列表页按断言落库时间过滤，进入「最近批次」过滤视图。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../config/app_theme.dart';
import '../providers/fact_batch_providers.dart';
import '../router/app_routes.dart';

class FactBatchCard extends StatelessWidget {
  final FactBatchRecord record;

  const FactBatchCard({super.key, required this.record});

  @override
  Widget build(BuildContext context) {
    final canOpen =
        record.manuscriptId != null && record.manuscriptId!.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Material(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          onTap: canOpen ? () => _open(context) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xsm,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.inventory_2_outlined,
                  size: 14,
                  color: AppColors.l1Text,
                ),
                const SizedBox(width: AppSpacing.xsm),
                Text(
                  '本次沉淀 ${record.count} 条人物事实',
                  style: AppTextStyles.noteCaption.copyWith(
                    color: AppColors.l1Text,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                const Text(
                  '查看 ›',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _open(BuildContext context) {
    context.push(
      AppRoutes.characters,
      extra: <String, dynamic>{
        'manuscriptId': record.manuscriptId,
        'since': record.at,
      },
    );
  }
}
