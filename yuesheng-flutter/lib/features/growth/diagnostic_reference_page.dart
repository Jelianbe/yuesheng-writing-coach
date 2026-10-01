// ─────────────────────────────────────────────────────────────
// diagnostic_reference_page — 诊断资料区（ADR-C122 一期）
//
// 一期：症候学员解读库纯展示（P001–P034）。
//   - 列表页：DiagnosticReferenceListPage（编号+名称+一句解读）
//   - 详情页：SyndromeLearnerDetailPage（这是什么/为什么是问题/常见表现/对应训练）
//
// 视觉规范（月色竹青，对齐 growth_page）：
//   AppBar #F7F8F6 + 48dp；卡片 #F2F4F2 + 左侧 4dp 竹青条；主色锚点 #2D5A52
//
// 数据真源：syndrome_learner_notes.dart（独立展示数据，不进注入链）
// 编号+名称并用（幽灵键消歧纪律：不裸用编号）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../config/app_palette.dart';
import '../../services/syndrome_learner_notes.dart';

/// 诊断资料区列表页
class DiagnosticReferenceListPage extends StatelessWidget {
  const DiagnosticReferenceListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.background,
      appBar: AppBar(
        title: const Text('教学资料'),
        backgroundColor: context.palette.background,
        foregroundColor: context.palette.textPrimary,
        toolbarHeight: 48,
        elevation: 0,
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: kSyndromeLearnerNotes.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final note = kSyndromeLearnerNotes[index];
          return _SyndromeListTile(note: note);
        },
      ),
    );
  }
}

/// 症候条目卡片（左侧竹青条 + 编号名称 + 一句解读）
class _SyndromeListTile extends StatelessWidget {
  final SyndromeLearnerNote note;

  const _SyndromeListTile({required this.note});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Material(
        color: context.palette.surface,
        child: InkWell(
          onTap: () =>
              context.push('/syndrome-learner-detail/${note.id}', extra: note),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(width: 4, color: context.palette.primary),
              ),
            ),
            child: Row(
              children: [
                Text(
                  note.id,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: context.palette.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: _buildMainColumn(context)),
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: context.palette.disabledText,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 名称 + 一句解读（拆出守 R-019 函数 ≤50 行）
  Widget _buildMainColumn(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          note.name,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: context.palette.textPrimary,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          note.what,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, color: context.palette.textSecondary),
        ),
      ],
    );
  }
}

/// 症候详情页（这是什么 / 为什么是问题 / 常见表现 / 对应训练动作）
class SyndromeLearnerDetailPage extends StatelessWidget {
  final SyndromeLearnerNote note;

  const SyndromeLearnerDetailPage({super.key, required this.note});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.background,
      appBar: AppBar(
        title: Text(note.name),
        backgroundColor: context.palette.background,
        foregroundColor: context.palette.textPrimary,
        toolbarHeight: 48,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildTitleRow(context),
          const SizedBox(height: 16),
          _SectionCard(
            title: '这是什么',
            child: Text(
              note.what,
              style: TextStyle(
                fontSize: 14,
                height: 1.6,
                color: context.palette.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: '为什么是问题',
            child: Text(
              note.why,
              style: TextStyle(
                fontSize: 14,
                height: 1.6,
                color: context.palette.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 12),
          _SectionCard(title: '常见表现', child: _buildSigns(context)),
          const SizedBox(height: 12),
          _SectionCard(title: '对应训练动作', child: _buildActionRefs(context)),
          const SizedBox(height: 8),
          _buildFooterNote(context),
        ],
      ),
    );
  }

  /// 二期挂载说明（拆出守 R-019 函数 ≤50 行）
  Widget _buildFooterNote(BuildContext context) {
    return Text(
      '训练动作详情见后续版本（二期挂载训练资产）',
      style: TextStyle(fontSize: 11, color: context.palette.textTertiary),
    );
  }

  /// 编号 + 名称行（并用，不裸用编号）
  Widget _buildTitleRow(BuildContext context) {
    return Row(
      children: [
        Text(
          note.id,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: context.palette.primary,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          note.name,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: context.palette.textPrimary,
          ),
        ),
      ],
    );
  }

  /// 常见表现列表（拆出守 R-019 函数 ≤50 行）
  Widget _buildSigns(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < note.signs.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '· ',
                  style: TextStyle(
                    fontSize: 14,
                    color: context.palette.primary,
                  ),
                ),
                Expanded(
                  child: Text(
                    note.signs[i],
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: context.palette.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// 对应训练动作标签组（拆出守 R-019 函数 ≤50 行）
  Widget _buildActionRefs(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final ref in note.actionRefs)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: context.palette.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: context.palette.divider),
            ),
            child: Text(
              ref,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: context.palette.primary,
              ),
            ),
          ),
      ],
    );
  }
}

/// 详情区块卡片（对齐月色竹青：surface 底 + 左侧竹青条）
class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.palette.surface,
          border: Border.all(color: context.palette.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: context.palette.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}
