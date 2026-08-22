// ─────────────────────────────────────────────────────────────
// growth_service — 用户级写作成长数据服务（跨会话全局聚合）
// 真源：yuesheng-android/src/services/growth-service.ts
//
// 职责（对齐 RN growth-detail 页面四数据源）：
//   - getGrowthOverview：成长总览（总字数/诊断次数/已解决/待改进/阶段/写作天数/首末写作）
//   - getAbilityScores：六大能力维度评分（0-100 + 趋势）
//   - getWritingCurve：最近 N 天写作曲线（每日字数 + 诊断次数）
//   - getSyndromeHistory：症候历史事件流（发现/解决时间线）
//
// 批次 51a：Flutter GrowthDetailPage 对齐 RN growth-detail.tsx 的数据层落地。
// 数据源均为现有 drift 表（chapters / diagnosis_results / active_problem /
// teaching_state），采用 customSelect 原生 SQL 复刻 RN SQL 语义。
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:drift/drift.dart';

import '../data/database/database.dart';
import '../types/teaching_types.dart';

part 'growth_service_dto.dart';
part 'growth_service_stats.dart';
part 'growth_service_ability.dart';

/// 成长数据服务（用户级，无 sessionId 维度）
class GrowthService {
  final AppDatabase _db;

  GrowthService(this._db);

  /// 六大能力维度（复刻 RN ABILITY_DIMENSIONS）
  static const List<({String key, String label, String description})>
  abilityDimensions = [
    (key: 'plot', label: '情节构建', description: '故事结构、节奏与冲突'),
    (key: 'character', label: '人物塑造', description: '角色立体度与动机'),
    (key: 'language', label: '语言表达', description: '用词、句式与节奏'),
    (key: 'logic', label: '逻辑连贯', description: '因果关系与衔接'),
    (key: 'emotion', label: '情感共鸣', description: '代入感与情绪传递'),
    (key: 'theme', label: '主题深度', description: '思想性与立意'),
  ];

  // ─────────────────────────────────────────────
  // 内部工具（复刻 RN classifyDimension / 评分公式）
  // ─────────────────────────────────────────────

  /// 症候名关键词归类到 6 大维度（复刻 RN classifyDimension）
  String _classifyDimension(String syndromeName) {
    if (RegExp(r'情节|结构|节奏|冲突|大纲').hasMatch(syndromeName)) return 'plot';
    if (RegExp(r'人物|角色|动机|心理').hasMatch(syndromeName)) return 'character';
    if (RegExp(r'语言|用词|句式|描写|文风').hasMatch(syndromeName)) {
      return 'language';
    }
    if (RegExp(r'逻辑|因果|衔接|跳跃').hasMatch(syndromeName)) return 'logic';
    if (RegExp(r'情感|情绪|代入|共鸣').hasMatch(syndromeName)) return 'emotion';
    if (RegExp(r'主题|立意|深度|思想').hasMatch(syndromeName)) return 'theme';
    // 默认归入语言表达
    return 'language';
  }

  /// 评分 + 趋势（复刻 RN 公式）
  AbilityScore _buildAbilityScore({
    required String dimension,
    required String description,
    required ({int detected, int resolved}) stats,
  }) {
    var score = 80 - stats.detected * 5 + stats.resolved * 3;
    score = score.clamp(30, 95);
    // 若无数据，给 70 分基线
    if (stats.detected == 0) score = 70;

    final Trend trend;
    if (stats.resolved > 0 && stats.resolved >= stats.detected * 0.5) {
      trend = Trend.improving;
    } else if (stats.detected > stats.resolved) {
      trend = Trend.worsening;
    } else {
      trend = Trend.stable;
    }

    return AbilityScore(
      dimension: dimension,
      score: score.round(),
      trend: trend,
      description: description,
    );
  }
}
