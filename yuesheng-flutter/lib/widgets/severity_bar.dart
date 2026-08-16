// ─────────────────────────────────────────────────────────────
// SeverityBar — 症候严重度色块条（月色竹青矿物色）
// 用于成长页/详情页的症候分布可视化
//
// 视觉规范（月色竹青矿物色定型）：
//   L1 = #E8F0EE（浅竹青，轻微）
//   L2 = #F5E6B8（浅赭黄，中等）
//   L3 = #E8C5C5（浅赭红，严重）
//   空状态 = #E0E4E0（浅灰）
//
// 用 Expanded + flex 按比例填充，无第三方图表库
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_theme.dart';

/// 症候严重度计数
class SeverityCounts {
  final int l1;
  final int l2;
  final int l3;

  const SeverityCounts({required this.l1, required this.l2, required this.l3});

  int get total => l1 + l2 + l3;
  bool get isEmpty => total == 0;
}

/// 症候严重度色块条 — 极简横向比例条
class SeverityBar extends StatelessWidget {
  final SeverityCounts counts;
  final double height;

  const SeverityBar({super.key, required this.counts, this.height = 8});

  static const _l1Color = AppColors.l1;
  static const _l2Color = AppColors.l2;
  static const _l3Color = AppColors.l3;
  static const _emptyColor = AppColors.border;

  @override
  Widget build(BuildContext context) {
    if (counts.isEmpty) {
      return Container(
        height: height,
        decoration: BoxDecoration(
          color: _emptyColor,
          borderRadius: BorderRadius.circular(height / 2),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            if (counts.l1 > 0)
              Expanded(
                flex: counts.l1,
                child: Container(decoration: BoxDecoration(color: _l1Color)),
              ),
            if (counts.l2 > 0)
              Expanded(
                flex: counts.l2,
                child: Container(decoration: BoxDecoration(color: _l2Color)),
              ),
            if (counts.l3 > 0)
              Expanded(
                flex: counts.l3,
                child: Container(decoration: BoxDecoration(color: _l3Color)),
              ),
          ],
        ),
      ),
    );
  }
}
