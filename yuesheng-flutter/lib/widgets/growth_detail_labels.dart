// ─────────────────────────────────────────────────────────────
// growth_detail_labels — 成长详情页展示文案映射（顶层纯函数）
//
// 从 growth_detail_page.dart / growth_content.dart 真分解而来
// （R-019：原 part 伪拆分根除）。原先 5 个标签函数已是顶层函数，
// _cognitiveStyleLabel 原挂在 State extension 上，此处一并提为顶层纯函数。
//
//   - styleSensoryLabel / styleRhythmLabel / styleNarrativeLabel /
//     styleToneLabel / styleStructureLabel  写作风格五维中文标签（批次53c）
//   - growthCognitiveStyleLabel             认知风格中文标签
//
// 全部为纯查表函数，无副作用、无依赖。
// ─────────────────────────────────────────────────────────────

import '../types/teaching_types.dart';

/// 批次53c：感官偏好中文标签（对齐 writing-style.ts 五维坐标）
String styleSensoryLabel(SensoryPreference v) {
  switch (v) {
    case SensoryPreference.visual:
      return '视觉型';
    case SensoryPreference.auditory:
      return '听觉型';
    case SensoryPreference.kinesthetic:
      return '体感型';
    case SensoryPreference.balanced:
      return '均衡型';
  }
}

/// 批次53c：节奏偏好中文标签
String styleRhythmLabel(RhythmPreference v) {
  switch (v) {
    case RhythmPreference.long:
      return '长句型';
    case RhythmPreference.short:
      return '短句型';
    case RhythmPreference.alternating:
      return '错落型';
    case RhythmPreference.repetitive:
      return '重复型';
  }
}

/// 批次53c：叙事距离中文标签
String styleNarrativeLabel(NarrativeDistance v) {
  switch (v) {
    case NarrativeDistance.intimate:
      return '贴身型';
    case NarrativeDistance.observational:
      return '观察型';
    case NarrativeDistance.editorial:
      return '评述型';
    case NarrativeDistance.fluid:
      return '游移型';
  }
}

/// 批次53c：语气质地中文标签
String styleToneLabel(ToneTexture v) {
  switch (v) {
    case ToneTexture.poetic:
      return '诗意型';
    case ToneTexture.spare:
      return '冷峻型';
    case ToneTexture.colloquial:
      return '口语型';
    case ToneTexture.elegant:
      return '文雅型';
  }
}

/// 批次53c：结构本能中文标签
String styleStructureLabel(StructureInstinct v) {
  switch (v) {
    case StructureInstinct.linear:
      return '线性型';
    case StructureInstinct.fragmented:
      return '碎片型';
    case StructureInstinct.circular:
      return '回环型';
    case StructureInstinct.divergent:
      return '发散型';
  }
}

/// 认知风格中文标签
String growthCognitiveStyleLabel(CognitiveStyle style) {
  switch (style) {
    case CognitiveStyle.analytical:
      return '分析型';
    case CognitiveStyle.intuitive:
      return '直觉型';
    case CognitiveStyle.mixed:
      return '混合型';
  }
}
