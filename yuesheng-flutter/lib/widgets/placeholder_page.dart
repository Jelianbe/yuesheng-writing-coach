// ─────────────────────────────────────────────────────────────
// 占位页面 — MVP 阶段 1 Tab 占位
//
// bookshelf / writing / growth 三个 Tab 在 MVP 阶段先用占位，
// 实际功能在后续阶段实现。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../theme/app_typography.dart';
import '../config/app_palette.dart';

class PlaceholderPage extends StatelessWidget {
  final String title;
  final String subtitle;

  const PlaceholderPage({
    super.key,
    required this.title,
    this.subtitle = '待后续阶段实现',
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: context.palette.primary,
        foregroundColor: context.palette.onPrimary,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.construction,
              size: 48,
              color: context.palette.textTertiary,
            ),
            const SizedBox(height: 16),
            Text(title, style: context.text.titleLg),
            const SizedBox(height: 8),
            Text(subtitle, style: context.text.body),
          ],
        ),
      ),
    );
  }
}
