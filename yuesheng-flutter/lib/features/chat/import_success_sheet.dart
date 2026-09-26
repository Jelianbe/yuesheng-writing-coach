// ─────────────────────────────────────────────────────────────
// ImportSuccessSheet — 导入成功反馈弹层（缺口清单 B 类）
// 真源：yuesheng-android/src/components/reference/ImportSuccessSheet.tsx
//
// 作品导入完成后引导：
//   - 立即诊断：触发自动诊断（RN startDiagnosis=true&chapterId=X 语义）
//   - 稍后再说：仅关闭，刷新引用/消息
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../../config/app_theme.dart';
import '../../config/app_palette.dart';

class ImportSuccessSheet extends StatelessWidget {
  /// 作品标题
  final String manuscriptTitle;

  /// 导入章节数
  final int chapterCount;

  /// 作品 ID（预留，对齐 RN manuscriptId）
  final String manuscriptId;

  /// 首章 ID（「立即诊断」诊断目标）
  final String? chapterId;

  /// 「稍后再说」/ 遮罩关闭（对齐 RN handleLater）
  final VoidCallback onClose;

  /// 「立即诊断」（对齐 RN handleDiagnosis：触发自动诊断）
  final VoidCallback onDiagnose;

  /// 是否启用「立即诊断」引导（批次78：追加章节场景不触发诊断，
  /// 关闭提问行与「稍后再说」副按钮，主按钮文案降级为「返回作品」，
  /// 避免「立即诊断」按钮名不副实）
  final bool diagnoseEnabled;

  const ImportSuccessSheet({
    super.key,
    required this.manuscriptTitle,
    required this.chapterCount,
    required this.manuscriptId,
    this.chapterId,
    required this.onClose,
    required this.onDiagnose,
    this.diagnoseEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.md,
          AppSpacing.xl,
          AppSpacing.section + AppSpacing.sm,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHandle(context),
            _buildSuccessIcon(context),
            _buildTitleText(context),
            const SizedBox(height: 8),
            _buildSubtitleText(context),
            const SizedBox(height: 16),
            if (diagnoseEnabled) ..._buildDiagnosePrompt(context),
            _buildPrimaryButton(context),
            if (diagnoseEnabled) ..._buildLaterButton(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHandle(BuildContext context) {
    return Container(
      width: 36,
      height: 4,
      margin: const EdgeInsets.only(bottom: AppSpacing.section),
      decoration: BoxDecoration(
        color: context.palette.border,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      alignment: Alignment.center,
    );
  }

  Widget _buildSuccessIcon(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      margin: const EdgeInsets.only(bottom: AppSpacing.lg),
      decoration: BoxDecoration(
        color: context.palette.primary,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Icon(Icons.check, size: 24, color: context.palette.onPrimary),
    );
  }

  Widget _buildTitleText(BuildContext context) {
    return Text(
      '导入成功！',
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: context.palette.textPrimary,
      ),
    );
  }

  Widget _buildSubtitleText(BuildContext context) {
    return Text(
      '已成功导入 $chapterCount 个章节到\n「$manuscriptTitle」',
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 14,
        height: 1.55,
        color: context.palette.textSecondary,
      ),
    );
  }

  List<Widget> _buildDiagnosePrompt(BuildContext context) {
    return [
      Text(
        '是否立即发送给月笙诊断？',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 14, color: context.palette.textTertiary),
      ),
      const SizedBox(height: 20),
    ];
  }

  Widget _buildPrimaryButton(BuildContext context) {
    return FilledButton(
      onPressed: () {
        Navigator.of(context).pop();
        onDiagnose();
      },
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(46),
        backgroundColor: context.palette.primary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      child: Text(
        diagnoseEnabled ? '立即诊断' : '返回作品',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: context.palette.onPrimary,
        ),
      ),
    );
  }

  List<Widget> _buildLaterButton(BuildContext context) {
    return [
      const SizedBox(height: 10),
      OutlinedButton(
        onPressed: () {
          Navigator.of(context).pop();
          onClose();
        },
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(46),
          side: BorderSide(color: context.palette.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
        child: Text(
          '稍后再说',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: context.palette.textSecondary,
          ),
        ),
      ),
    ];
  }
}
