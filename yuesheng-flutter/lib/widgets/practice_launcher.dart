// ─────────────────────────────────────────────────────────────
// practice_launcher — P1-6 自主练习选择器
//
// 恢复刻意练习的自我调节成分：学员自选 症候 × 类型 × 难度，
// 而不是只能接受 AI 建议的任务。反向漏斗：症候只列活跃问题
// （ActiveProblemView），不铺 38 个症候全表，避免 overwhelm。
//
// 使用：
//   PracticeLauncherSheet.show(context,
//     syndromes: [...],                 // 候选症候（活跃问题）
//     presetSyndromeId: ...,            // 建议卡预填
//     presetSyndromeName: ...,
//     onStart: (choice) { ... startPractice(...) },
//   );
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_palette.dart';
import '../config/app_theme.dart';
import '../theme/app_typography.dart';

/// 候选症候选项（id + 名称，来自活跃问题）
class PracticeSyndromeOption {
  final String id;
  final String name;

  const PracticeSyndromeOption({required this.id, required this.name});
}

/// 自选结果
class PracticeChoice {
  final String? syndromeId;
  final String? syndromeName;
  final String taskType; // rewrite / analyze / compare / generate
  final String difficulty; // easy / medium / hard

  const PracticeChoice({
    this.syndromeId,
    this.syndromeName,
    required this.taskType,
    required this.difficulty,
  });
}

/// 任务类型文案与默认任务描述
const Map<String, String> kPracticeTypeText = {
  'rewrite': '改写',
  'analyze': '分析',
  'compare': '对比',
  'generate': '生成',
};

/// 难度文案
const Map<String, String> kPracticeDifficultyText = {
  'easy': '入门',
  'medium': '进阶',
  'hard': '挑战',
};

/// 底部弹层：自选练习入口
class PracticeLauncherSheet {
  static Future<void> show(
    BuildContext context, {
    required List<PracticeSyndromeOption> syndromes,
    String? presetSyndromeId,
    String? presetSyndromeName,
    required void Function(PracticeChoice choice) onStart,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _PracticeLauncherBody(
        syndromes: syndromes,
        presetSyndromeId: presetSyndromeId,
        presetSyndromeName: presetSyndromeName,
        onStart: onStart,
      ),
    );
  }
}

/// 弹层主体（三步合一：症候 → 类型 → 难度）。
class _PracticeLauncherBody extends StatefulWidget {
  final List<PracticeSyndromeOption> syndromes;
  final String? presetSyndromeId;
  final String? presetSyndromeName;
  final void Function(PracticeChoice choice) onStart;

  const _PracticeLauncherBody({
    required this.syndromes,
    required this.presetSyndromeId,
    required this.presetSyndromeName,
    required this.onStart,
  });

  @override
  State<_PracticeLauncherBody> createState() => _PracticeLauncherBodyState();
}

class _PracticeLauncherBodyState extends State<_PracticeLauncherBody> {
  String? _syndromeId;
  String? _syndromeName;
  String _taskType = 'rewrite';
  String _difficulty = 'medium';

  @override
  void initState() {
    super.initState();
    // 预填：preset 优先，否则第一个候选；无候选则置空
    if (widget.syndromes.isNotEmpty) {
      PracticeSyndromeOption? match;
      if (widget.presetSyndromeId != null) {
        for (final s in widget.syndromes) {
          if (s.id == widget.presetSyndromeId) {
            match = s;
            break;
          }
        }
      }
      final picked = match ?? widget.syndromes.first;
      _syndromeId = picked.id;
      _syndromeName = picked.name;
    }
  }

  void _pickSyndrome(PracticeSyndromeOption s) {
    setState(() {
      _syndromeId = s.id;
      _syndromeName = s.name;
    });
  }

  void _start() {
    final choice = PracticeChoice(
      syndromeId: _syndromeId,
      syndromeName: _syndromeName,
      taskType: _taskType,
      difficulty: _difficulty,
    );
    Navigator.of(context).pop();
    widget.onStart(choice);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 16),
            _buildSyndromeSection(),
            const SizedBox(height: 16),
            _buildSection(
              title: '练习类型',
              options: kPracticeTypeText,
              selected: _taskType,
              onSelect: (v) => setState(() => _taskType = v),
            ),
            const SizedBox(height: 16),
            _buildSection(
              title: '难度',
              options: kPracticeDifficultyText,
              selected: _difficulty,
              onSelect: (v) => setState(() => _difficulty = v),
            ),
            const SizedBox(height: 16),
            _buildDescriptionPreview(),
            const SizedBox(height: 20),
            _buildStartButton(),
          ],
        ),
      ),
    );
  }

  /// 标题区。
  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('自主练习', style: context.text.titleLg),
        const SizedBox(height: 4),
        const Text(
          '选择要练的症候、练习类型和难度，练什么由你决定',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  /// 底部「开始练习」按钮（未选症候时禁用）。
  Widget _buildStartButton() {
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: FilledButton(
        onPressed: _syndromeId == null ? null : _start,
        style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
        child: const Text(
          '开始练习',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  /// 症候区：无候选时显示引导文案。
  Widget _buildSyndromeSection() {
    if (widget.syndromes.isEmpty) {
      return const Text(
        '暂时没有活跃的写作问题——先去写一段，诊断后这里会出现可选症候',
        style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
      );
    }
    return _buildSection(
      title: '症候',
      options: {for (final s in widget.syndromes) s.id: s.name},
      selected: _syndromeId ?? '',
      onSelect: (id) {
        for (final s in widget.syndromes) {
          if (s.id == id) {
            _pickSyndrome(s);
            break;
          }
        }
      },
    );
  }

  /// 通用 chip 选择区。
  Widget _buildSection({
    required String title,
    required Map<String, String> options,
    required String selected,
    required void Function(String) onSelect,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in options.entries)
              ChoiceChip(
                label: Text(e.value),
                selected: selected == e.key,
                onSelected: (_) => onSelect(e.key),
                selectedColor: AppColors.l1,
                labelStyle: TextStyle(
                  fontSize: 13,
                  color: selected == e.key
                      ? AppColors.primary
                      : AppColors.textSecondary,
                  fontWeight: selected == e.key
                      ? FontWeight.w600
                      : FontWeight.normal,
                ),
                backgroundColor: context.palette.background,
                side: BorderSide(
                  color: selected == e.key
                      ? AppColors.primary
                      : AppColors.border,
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// 任务描述预览：让学员开练前看到会练什么。
  String _description() {
    final syndrome = _syndromeName ?? '当前问题';
    switch (_taskType) {
      case 'analyze':
        return '分析范例文本，识别与「$syndrome」相关的写法，并说明其效果';
      case 'compare':
        return '对比好/差两种写法，指出「$syndrome」的差异与原因';
      case 'generate':
        return '基于「$syndrome」的改进要点，独立生成一段新的写作片段';
      default:
        return '针对「$syndrome」改写指定片段，消除问题写法';
    }
  }

  Widget _buildDescriptionPreview() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.palette.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        _description(),
        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
      ),
    );
  }
}
