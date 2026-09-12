// ─────────────────────────────────────────────────────────────
// growth_detail_style_sheet — 写作风格纠正底部弹层（批次57）
//
// 从 growth_detail_page.dart 真分解而来（R-019：原 part 伪拆分根除）。
//   - GrowthStyleCorrectionSheet 纠错非重写——仅纠正五维坐标
//
// 行为与文案逐字保持不变：widget 测试 #D7/#D8 直接 tap ChoiceChip('发散型')
// 并断言弹层文本（'纠正风格画像' / 'AI 描述' / '保存纠正' / '感官偏好' /
// '结构本能'），任何文字或交互变更都会破坏测试。
//
// 状态全部在自身内部（仅靠 profile + onSave 构造注入）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../types/teaching_types.dart';
import 'growth_detail_labels.dart';

/// 批次57：风格纠正底部弹层（纠错非重写——仅纠正五维坐标，summary 保留 AI 描述只读）
class GrowthStyleCorrectionSheet extends StatefulWidget {
  final WritingStyleProfile profile;
  final Future<void> Function(WritingStyleProfile updated) onSave;

  const GrowthStyleCorrectionSheet({
    super.key,
    required this.profile,
    required this.onSave,
  });

  @override
  State<GrowthStyleCorrectionSheet> createState() =>
      _GrowthStyleCorrectionSheetState();
}

class _GrowthStyleCorrectionSheetState
    extends State<GrowthStyleCorrectionSheet> {
  late SensoryPreference _sensory;
  late RhythmPreference _rhythm;
  late NarrativeDistance _narrative;
  late ToneTexture _tone;
  late StructureInstinct _structure;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _sensory = p.sensory;
    _rhythm = p.rhythm;
    _narrative = p.narrativeDistance;
    _tone = p.toneTexture;
    _structure = p.structure;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.onSave(
        WritingStyleProfile(
          sensory: _sensory,
          rhythm: _rhythm,
          narrativeDistance: _narrative,
          toneTexture: _tone,
          structure: _structure,
          summary: widget.profile.summary,
          confidence: widget.profile.confidence,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _dimensionRow<T>({
    required String title,
    required List<T> options,
    required T selected,
    required String Function(T) label,
    required ValueChanged<T> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTextStyles.subBody.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final opt in options)
              ChoiceChip(
                label: Text(label(opt)),
                selected: opt == selected,
                onSelected: (_) => onChanged(opt),
                selectedColor: AppColors.primary,
                backgroundColor: AppColors.surface,
                side: BorderSide(color: AppColors.border),
                labelStyle: TextStyle(
                  fontSize: 12,
                  color: opt == selected
                      ? AppColors.onPrimary
                      : AppColors.textPrimary,
                ),
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.section,
            AppSpacing.lg,
            AppSpacing.section,
            AppSpacing.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 16),
              ..._buildDimensionRows(),
              const SizedBox(height: 20),
              _buildSaveButton(),
            ],
          ),
        ),
      ),
    );
  }

  /// 标题 + 说明 + AI 描述（只读）
  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '纠正风格画像',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '风格由 AI 从你的文本自动识别。如判断有误，可在此纠正坐标；'
          '下次诊断仍会按你的新文本重新识别。',
          style: AppTextStyles.noteCaption.copyWith(height: 1.5),
        ),
        const SizedBox(height: 12),
        const Text('AI 描述', style: AppTextStyles.caption),
        const SizedBox(height: 4),
        Text(
          widget.profile.summary,
          style: const TextStyle(
            fontSize: 13,
            height: 1.5,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  /// 五维选择行
  List<Widget> _buildDimensionRows() {
    return [
      _dimensionRow(
        title: '感官偏好',
        options: SensoryPreference.values,
        selected: _sensory,
        label: styleSensoryLabel,
        onChanged: (v) => setState(() => _sensory = v),
      ),
      const SizedBox(height: 12),
      _dimensionRow(
        title: '节奏偏好',
        options: RhythmPreference.values,
        selected: _rhythm,
        label: styleRhythmLabel,
        onChanged: (v) => setState(() => _rhythm = v),
      ),
      const SizedBox(height: 12),
      _dimensionRow(
        title: '叙事距离',
        options: NarrativeDistance.values,
        selected: _narrative,
        label: styleNarrativeLabel,
        onChanged: (v) => setState(() => _narrative = v),
      ),
      const SizedBox(height: 12),
      _dimensionRow(
        title: '语气质地',
        options: ToneTexture.values,
        selected: _tone,
        label: styleToneLabel,
        onChanged: (v) => setState(() => _tone = v),
      ),
      const SizedBox(height: 12),
      _dimensionRow(
        title: '结构本能',
        options: StructureInstinct.values,
        selected: _structure,
        label: styleStructureLabel,
        onChanged: (v) => setState(() => _structure = v),
      ),
    ];
  }

  /// 保存按钮
  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: _saving ? null : _save,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
        child: Text(_saving ? '保存中…' : '保存纠正'),
      ),
    );
  }
}
