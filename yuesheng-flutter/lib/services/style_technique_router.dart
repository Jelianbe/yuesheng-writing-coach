// ─────────────────────────────────────────────────────────────
// 文笔画像 → 技法旁路路由器（2026-08-18 批次）
// 设计：docs/2026-08-18-style-technique-bypass-routing-design.md
//
// 背景：诊断链路有两层产出（feedbackSummary 内容总结层 + styleProfile 文笔
// 分析层），但技法路由纯症候驱动，styleProfile 五维发现落库后不参与技法
// 召回——文笔精修阶段无技法支撑。本路由器补一条旁路：五维坐标的非健康值
// 映射到文笔层技法候选，供 LLM 按需取用。
//
// 约束（教练哲学不破）：
//   - 一次只聚焦一个技法：旁路只补充候选，不并行教学
//   - 症候主路由优先：内容层问题活跃时不抢占焦点
//   - 全本地纯 Dart 判定，零 LLM 调用
// ─────────────────────────────────────────────────────────────

import 'package:writingcoach/services/chat_context_builder.dart'
    show ActiveSyndromeView;
import 'package:writingcoach/services/technique_knowledge_base.dart';
import 'package:writingcoach/types/teaching_types.dart';

/// 单条旁路候选
class StyleTechniqueCandidate {
  final String techniqueId;
  final String techniqueName;
  final String dimensionLabel;

  /// 一句提升理由
  final String reason;

  /// 跨层调用（候选技法非 prose 层）显式标注
  final bool crossLayer;

  const StyleTechniqueCandidate({
    required this.techniqueId,
    required this.techniqueName,
    required this.dimensionLabel,
    required this.reason,
    this.crossLayer = false,
  });
}

/// 路由结果
class StyleTechniqueSuggestion {
  /// 候选技法（0–2 条）
  final List<StyleTechniqueCandidate> candidates;

  /// 被哪条门控拦下（空串=未被拦/有候选；供单测与调试，不注入 LLM）
  final String gatedBy;

  const StyleTechniqueSuggestion({
    this.candidates = const [],
    this.gatedBy = '',
  });

  bool get isEmpty => candidates.isEmpty;
}

/// 判定症候是否「文笔层主导」：其映射技法中 prose 层占多数。
///
/// 例：P007（T019 content / T023 prose / T025 prose）→ 2/3 prose → 文笔主导；
/// P006（T008/T017/T018/T022 全 content）→ 内容主导。
/// 无映射技法的症候视为非文笔主导（保守，不抢占）。
bool _isProseDominantSyndrome(String syndromeId) {
  final techniques = kTechniquesBySyndrome[syndromeId];
  if (techniques == null || techniques.isEmpty) return false;
  var proseCount = 0;
  for (final t in techniques) {
    if (kTechniqueLayers[t] == TechniqueLayer.prose) proseCount++;
  }
  return proseCount * 2 > techniques.length;
}

/// 文笔画像 → 技法旁路路由
///
/// 门控（按优先级短路）：
/// 1. styleProfile 为 null → 空（画像未沉淀）
/// 2. 存在 L2/L3 严重度、且非文笔层主导的活跃症候 → 空（内容层问题优先，不抢占）
/// 3. 焦点症候的技法已含 prose 层 → 空（主路由已覆盖，不重复）
/// 4. 通过 → 五维非健康值映射候选，排除已 mastered，去重后取前 2 条
///
/// [masteredTechniqueIds] 技法掌握集合。当前 schema 无按技法粒度的掌握表
/// （teaching_state 按症候粒度），首版调用方传空集跳过过滤（TODO：症候级
/// mastered → 技法集合的派生接入后启用）。
StyleTechniqueSuggestion routeStyleTechniques({
  required WritingStyleProfile? styleProfile,
  List<ActiveSyndromeView> activeProblems = const [],
  Set<String> masteredTechniqueIds = const {},
  String? focusSyndromeId,
}) {
  // 门控 1：画像未沉淀
  if (styleProfile == null) {
    return const StyleTechniqueSuggestion(gatedBy: 'no_profile');
  }

  // 门控 2：内容层问题优先（L2/L3 且非文笔层主导的症候活跃 → 不抢占）
  const severityRank = {Severity.l3: 3, Severity.l2: 2, Severity.l1: 1};
  final hasContentPriority = activeProblems.any(
    (p) =>
        (severityRank[p.severity] ?? 0) >= 2 && !_isProseDominantSyndrome(p.syndromeId),
  );
  if (hasContentPriority) {
    return const StyleTechniqueSuggestion(gatedBy: 'content_priority');
  }

  // 门控 3：焦点症候技法已含 prose 层（主路由已覆盖，不重复注入）
  if (focusSyndromeId != null) {
    final focusTechniques = kTechniquesBySyndrome[focusSyndromeId] ?? const [];
    final focusHasProse = focusTechniques.any(
      (t) => kTechniqueLayers[t] == TechniqueLayer.prose,
    );
    if (focusHasProse) {
      return const StyleTechniqueSuggestion(gatedBy: 'focus_covers_prose');
    }
  }

  // 门控 4：五维非健康值 → 候选映射（固定维度顺序保证确定性）
  final dimensionKeys = <String>[
    'rhythm:${styleProfile.rhythm.value}',
    'sensory:${styleProfile.sensory.value}',
    'toneTexture:${styleProfile.toneTexture.value}',
    'narrativeDistance:${styleProfile.narrativeDistance.value}',
    'structure:${styleProfile.structure.value}',
  ];
  final byKey = {
    for (final m in kStyleDimensionTechniques) m.dimensionKey: m,
  };

  final candidates = <StyleTechniqueCandidate>[];
  final seen = <String>{};
  for (final key in dimensionKeys) {
    final mapping = byKey[key];
    if (mapping == null) continue; // 健康/中性值不进映射
    for (final tid in mapping.techniqueIds) {
      if (seen.contains(tid)) continue;
      if (masteredTechniqueIds.contains(tid)) continue;
      seen.add(tid);
      candidates.add(
        StyleTechniqueCandidate(
          techniqueId: tid,
          techniqueName: techniqueNameOf(tid) ?? tid,
          dimensionLabel: mapping.dimensionLabel,
          reason: mapping.reason,
          crossLayer: mapping.crossLayer,
        ),
      );
      if (candidates.length >= 2) {
        return StyleTechniqueSuggestion(candidates: candidates);
      }
    }
  }
  return StyleTechniqueSuggestion(candidates: candidates);
}

/// 旁路段格式化：注入 system prompt 的「✒️ 文笔精修候选」条件段。
///
/// 措辞约束：明确「按需提及，不与当前焦点并行教学」；对学员引用技法时
/// 说技法名称不暴露编号（编号仅注入给 LLM，同症候技法段的现有用法）。
/// 无候选 → 返回 null（调用方不注入，零 token 成本）。
String? formatStyleTechniqueSection(StyleTechniqueSuggestion suggestion) {
  if (suggestion.isEmpty) return null;

  final lines = suggestion.candidates
      .map(
        (c) =>
            '- ${c.techniqueId} ${c.techniqueName}：'
            '画像显示${c.dimensionLabel}——${c.reason}'
            '${c.crossLayer ? '（跨层候选：该技法偏结构层）' : ''}',
      )
      .join('\n');

  return '### ✒️ 文笔精修候选（画像旁路）\n'
      '以下候选来自学员文笔画像（五维坐标），不是当前教学焦点。按需提及——'
      '仅在学员主动谈及文笔/语言问题、或当前焦点症候已巩固时引入，'
      '不与当前教学焦点并行教学。对学员引用技法时说技法名称，不暴露编号。\n'
      '$lines';
}
