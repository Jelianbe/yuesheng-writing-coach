// ─────────────────────────────────────────────────────────────
// GrowthStore — 成长页状态管理（用户级全局聚合）
// 复刻 yuesheng-android 成长页状态管理逻辑
//
// 职责：
//   - loadGrowthData：并行加载全局能力画像 + 跨 session 活跃问题 + 最近诊断
//   - 状态：isLoading / profile / activeProblems / diagnosisHistory / error
//
// 全局单例（非 family）：成长页是用户级视图，不需按 ID 隔离
// ─────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database/database.dart';
import '../data/repositories/diagnosis_repository.dart';
import '../data/repositories/session_repository.dart';
import '../data/repositories/student_model_repository.dart';
import '../services/growth_service.dart';
import '../services/student_profile.dart';
import '../types/teaching_types.dart';
import 'app_providers.dart';

/// 成长数据服务（用户级全局聚合，批次 51a）
final growthServiceProvider = Provider<GrowthService>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return GrowthService(db);
});

/// 成长页状态（不可变）
class GrowthState {
  final bool isLoading;
  final StudentProfile? profile;
  final List<ActiveProblemView> activeProblems;
  final List<DiagnosisRow> diagnosisHistory;
  // 批次 51c：RN growth-detail 页面四数据源
  final GrowthOverview? overview;
  final List<AbilityScore> abilityScores;
  final List<WritingDataPoint> writingCurve;
  final List<SyndromeHistoryEvent> syndromeHistory;
  final WritingStyleProfile? styleProfile; // 批次53c：最新写作风格画像
  final List<SyndromeRecurrence> syndromeRecurrences; // 批次65 B62h：同类症候复发率
  final String? error;

  const GrowthState({
    this.isLoading = true,
    this.profile,
    this.activeProblems = const [],
    this.diagnosisHistory = const [],
    this.overview,
    this.abilityScores = const [],
    this.writingCurve = const [],
    this.syndromeHistory = const [],
    this.styleProfile,
    this.syndromeRecurrences = const [],
    this.error,
  });

  GrowthState copyWith({
    bool? isLoading,
    StudentProfile? profile,
    List<ActiveProblemView>? activeProblems,
    List<DiagnosisRow>? diagnosisHistory,
    GrowthOverview? overview,
    List<AbilityScore>? abilityScores,
    List<WritingDataPoint>? writingCurve,
    List<SyndromeHistoryEvent>? syndromeHistory,
    WritingStyleProfile? styleProfile,
    List<SyndromeRecurrence>? syndromeRecurrences,
    String? error,
    bool clearError = false,
  }) {
    return GrowthState(
      isLoading: isLoading ?? this.isLoading,
      profile: profile ?? this.profile,
      activeProblems: activeProblems ?? this.activeProblems,
      diagnosisHistory: diagnosisHistory ?? this.diagnosisHistory,
      overview: overview ?? this.overview,
      abilityScores: abilityScores ?? this.abilityScores,
      writingCurve: writingCurve ?? this.writingCurve,
      syndromeHistory: syndromeHistory ?? this.syndromeHistory,
      styleProfile: styleProfile ?? this.styleProfile,
      syndromeRecurrences: syndromeRecurrences ?? this.syndromeRecurrences,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// 成长页状态管理器 — 全局聚合（sessionId: null）
class GrowthStore extends StateNotifier<GrowthState> {
  final AppDatabase _db;

  GrowthStore(this._db) : super(const GrowthState());

  /// 加载成长数据（全局聚合）
  ///
  /// 并行加载九项（批次 51c 对齐 RN growth-detail 四数据源 + 批次65 B62h）：
  ///   1. 能力画像（buildStudentContext(sessionId: null) 全局聚合）
  ///   2. 跨 session 活跃问题（listAllActiveProblems）
  ///   3. 最近 10 条诊断历史（跨 session，按 timestamp DESC）
  ///   4. 成长总览（GrowthService.getGrowthOverview）
  ///   5. 能力评分（GrowthService.getAbilityScores）
  ///   6. 写作曲线（GrowthService.getWritingCurve，14 天）
  ///   7. 症候历史（GrowthService.getSyndromeHistory，30 天）
  ///   8. 最新写作风格画像（GrowthService.getLatestStyleProfile）
  ///   9. 同类症候复发率（GrowthService.getSyndromeRecurrences）
  Future<void> loadGrowthData() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final diagRepo = DiagnosisRepository(_db);
      final sessionRepo = SessionRepository(_db);
      final studentModelRepo = StudentModelRepository(_db);
      final growthService = GrowthService(_db);

      // 并行加载九项数据
      final results = await Future.wait([
        // 1. 能力画像（全局聚合，sessionId: null）
        buildStudentContext(
          diagnosisRepo: diagRepo,
          studentModelRepo: studentModelRepo,
          sessionRepo: sessionRepo,
          sessionId: null, // 全局聚合
        ),
        // 2. 跨 session 活跃问题
        diagRepo.listAllActiveProblems(),
        // 3. 最近 10 条诊断历史（跨 session，走 Repository 方法）
        diagRepo.listRecentDiagnoses(limit: 10),
        // 4. 成长总览
        growthService.getGrowthOverview(),
        // 5. 六大能力评分
        growthService.getAbilityScores(),
        // 6. 写作曲线（近 14 天）
        growthService.getWritingCurve(),
        // 7. 症候历史（近 30 天）
        growthService.getSyndromeHistory(),
        // 8. 最新写作风格画像（批次53c）
        growthService.getLatestStyleProfile(),
        // 9. 同类症候复发率（批次65 B62h）
        growthService.getSyndromeRecurrences(),
      ]);

      final profileResult = results[0] as ProfileTextResult;
      final activeProblems = results[1] as List<ActiveProblemView>;
      final history = results[2] as List<DiagnosisRow>;
      final overview = results[3] as GrowthOverview;
      final abilityScores = results[4] as List<AbilityScore>;
      final writingCurve = results[5] as List<WritingDataPoint>;
      final syndromeHistory = results[6] as List<SyndromeHistoryEvent>;
      final styleProfile = results[7] as WritingStyleProfile?;
      final syndromeRecurrences = results[8] as List<SyndromeRecurrence>;

      state = GrowthState(
        isLoading: false,
        profile: profileResult.profile,
        activeProblems: activeProblems,
        diagnosisHistory: history,
        overview: overview,
        abilityScores: abilityScores,
        writingCurve: writingCurve,
        syndromeHistory: syndromeHistory,
        styleProfile: styleProfile,
        syndromeRecurrences: syndromeRecurrences,
      );
    } catch (e) {
      debugPrint('[GrowthStore] loadGrowthData 失败: $e');
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// 批次57：学员纠正最新风格画像（纠错非重写）
  ///
  /// 更新最新一条有 style_profile 的记录后重新加载成长数据。
  Future<void> correctStyleProfile(WritingStyleProfile updated) async {
    await StudentModelRepository(_db).updateLatestStyleProfile(updated);
    await loadGrowthData();
  }
}

/// 全局单例 provider（成长页是用户级视图，不需 family）
final growthStoreProvider = StateNotifierProvider<GrowthStore, GrowthState>((
  ref,
) {
  final db = ref.watch(appDatabaseProvider);
  return GrowthStore(db);
});
