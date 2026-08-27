// ─────────────────────────────────────────────────────────────
// StyleProfileSheet — 当前文风弹层（批次85-4 当前文风展示）
// 教学特色增补：风格画像数据层已有（student_model.style_profile，
// 批次53 五维坐标 + 批次64 定量指纹），补写作页内查看入口。
//
// 展示：
//   - summary 一句话风格描述
//   - 五维坐标（感官/节奏/叙事距离/语气质地/结构本能，中文标签）
//   - 置信度 + 更新时间（有则显示）
// 无画像时显示空态引导（完成一次诊断后生成）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_theme.dart';
import '../data/repositories/student_model_repository.dart';
import '../providers/app_providers.dart';
import '../types/teaching_types.dart';
import 'yue_sheet.dart';

/// 维度值 → 中文标签（注释语义，用于展示）
String _sensoryLabel(SensoryPreference v) => switch (v) {
  SensoryPreference.visual => '视觉型',
  SensoryPreference.auditory => '听觉型',
  SensoryPreference.kinesthetic => '体感型',
  SensoryPreference.balanced => '均衡型',
};
String _rhythmLabel(RhythmPreference v) => switch (v) {
  RhythmPreference.long => '长句型',
  RhythmPreference.short => '短句型',
  RhythmPreference.alternating => '错落型',
  RhythmPreference.repetitive => '重复型',
};
String _distanceLabel(NarrativeDistance v) => switch (v) {
  NarrativeDistance.intimate => '贴身型',
  NarrativeDistance.observational => '观察型',
  NarrativeDistance.editorial => '评述型',
  NarrativeDistance.fluid => '游移型',
};
String _toneLabel(ToneTexture v) => switch (v) {
  ToneTexture.poetic => '诗意型',
  ToneTexture.spare => '冷峻型',
  ToneTexture.colloquial => '口语型',
  ToneTexture.elegant => '文雅型',
};
String _structureLabel(StructureInstinct v) => switch (v) {
  StructureInstinct.linear => '线性型',
  StructureInstinct.fragmented => '碎片型',
  StructureInstinct.circular => '回环型',
  StructureInstinct.divergent => '发散型',
};

class StyleProfileSheet extends ConsumerStatefulWidget {
  const StyleProfileSheet({super.key});

  /// 打开当前文风弹层（批次85-4）
  static Future<void> show(BuildContext context) {
    return showYueModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => const StyleProfileSheet(),
    );
  }

  @override
  ConsumerState<StyleProfileSheet> createState() => _StyleProfileSheetState();
}

class _StyleProfileSheetState extends ConsumerState<StyleProfileSheet> {
  /// null = 加载中
  WritingStyleProfile? _profile;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profile = await StudentModelRepository(
      ref.read(appDatabaseProvider),
    ).getLatestStyleProfile();
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _loaded = true;
    });
  }

  String _formatTime(int unixSec) {
    final t = DateTime.fromMillisecondsSinceEpoch(unixSec * 1000);
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    final dd = t.day.toString().padLeft(2, '0');
    final mo = t.month.toString().padLeft(2, '0');
    return '$mo-$dd $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.section,
        AppSpacing.md,
        AppSpacing.section,
        AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text(
                '当前文风',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textInk,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(
                  Icons.close,
                  size: 20,
                  color: AppColors.textTertiary,
                ),
                tooltip: '关闭',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(height: 380, child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (!_loaded) {
      return const Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppColors.primary,
        ),
      );
    }
    final p = _profile;
    if (p == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.brush_outlined, size: 40, color: AppColors.placeholder),
            SizedBox(height: 10),
            Text(
              '还没有文风画像\n完成一次「诊断本章」后，就能看到你的写作风格',
              textAlign: TextAlign.center,
              style: AppTextStyles.subCaption,
            ),
          ],
        ),
      );
    }
    return ListView(
      children: [
        // 一句话风格
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.primarySoft,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Text(
            p.summary,
            style: const TextStyle(
              fontSize: 14,
              height: 1.5,
              color: AppColors.primaryDeep,
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          '你的文风五维',
          style: AppTextStyles.noteCaption,
        ),
        const SizedBox(height: 6),
        _dimensionRow('感官偏好', _sensoryLabel(p.sensory)),
        _dimensionRow('句子节奏', _rhythmLabel(p.rhythm)),
        _dimensionRow('叙事距离', _distanceLabel(p.narrativeDistance)),
        _dimensionRow('语气质地', _toneLabel(p.toneTexture)),
        _dimensionRow('结构本能', _structureLabel(p.structure)),
        if (p.confidence != null || p.updatedAt != null) ...[
          const SizedBox(height: 10),
          Text(
            [
              if (p.confidence != null)
                '识别置信度 ${(p.confidence! * 100).round()}%',
              if (p.updatedAt != null) '更新于 ${_formatTime(p.updatedAt!)}',
            ].join(' · '),
            style: const TextStyle(fontSize: 11, color: AppColors.textTertiary),
          ),
        ],
      ],
    );
  }

  Widget _dimensionRow(String name, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xsm),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              name,
              style: AppTextStyles.subBody,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.surfaceWhite,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.borderSoft),
            ),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textInk,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
