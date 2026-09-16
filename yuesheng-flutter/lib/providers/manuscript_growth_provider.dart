// ─────────────────────────────────────────────────────────────
// manuscript_growth_provider — 书籍级成长数据（教学线 P0-2）
//
// 三层成长叙事的中间层（章节级 / 书籍级 / 全库级）唯一缺口出前台。
// 数据源 = 批次 A 已交付的 3 个书籍级 DAO + buildStudentContext
// （sessionIds 收敛到本书，同一套推理不新造语义）。
//
// 书籍级会话范围 = collectManuscriptSessionIds 并集（与详情页
// 「相关对话」Tab 同一真源），见 manuscript_scope.dart。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/diagnosis_repository.dart';
import '../data/repositories/session_repository.dart';
import '../data/repositories/student_model_repository.dart';
import '../services/manuscript_scope.dart';
import '../services/student_profile.dart';
import '../services/syndrome_recurrence.dart';
import '../types/teaching_types.dart';
import '../data/database/database.dart';
import 'app_providers.dart';

/// 书籍级成长聚合结果。
class ManuscriptGrowthData {
  final StudentProfile? profile;
  final List<ActiveProblemView> activeProblems;
  final List<SyndromeRecurrence> recurrences;
  final int diagnosisCount;

  const ManuscriptGrowthData({
    required this.profile,
    required this.activeProblems,
    required this.recurrences,
    required this.diagnosisCount,
  });

  bool get hasData => diagnosisCount > 0 || activeProblems.isNotEmpty;
}

/// 书籍级成长数据（按 manuscriptId 并行加载 4 项）。
///
/// 无本书会话 / 无诊断时返回空数据（hasData = false），不抛异常。
final manuscriptGrowthProvider =
    FutureProvider.family<ManuscriptGrowthData, String>((
      ref,
      manuscriptId,
    ) async {
      final db = ref.watch(appDatabaseProvider);
      final diagRepo = DiagnosisRepository(db);
      final sessionRepo = SessionRepository(db);
      final studentModelRepo = StudentModelRepository(db);

      final ids = await collectManuscriptSessionIds(db, manuscriptId);

      final results = await Future.wait<Object>([
        buildStudentContext(
          diagnosisRepo: diagRepo,
          studentModelRepo: studentModelRepo,
          sessionRepo: sessionRepo,
          sessionIds: ids,
        ),
        diagRepo.listActiveProblemsForManuscript(manuscriptId),
        diagRepo.getSyndromeRecurrencesForManuscript(manuscriptId),
        diagRepo.listDiagnosesForManuscript(manuscriptId),
      ]);

      final profile = (results[0] as ProfileTextResult).profile;
      final activeProblems = results[1] as List<ActiveProblemView>;
      final recurrences = results[2] as List<SyndromeRecurrence>;
      final diagnoses = results[3] as List<DiagnosisRow>;

      return ManuscriptGrowthData(
        profile: profile,
        activeProblems: activeProblems,
        recurrences: recurrences,
        diagnosisCount: diagnoses.length,
      );
    });
