// ─────────────────────────────────────────────────────────────
// BootstrapService — 启动时问卷触发判定
// 复刻 yuesheng-android/src/hooks/useBootstrap.ts 的问卷触发逻辑
//
// 设计意图（批次1-8 波6）：
//   RN 真源 useBootstrap 原先检查 session 级 getOnboardingData(sessionId)，
//   会导致换会话时问卷重复弹出。波6 改为用户级 questionnaire_completed 优先：
//     1. app_state.questionnaire_completed == 'true' → 不弹（用户级已提交）
//     2. 向后兼容：session 级 onboarding_data → 不弹 + 迁移标记
//     2b. fallback：当前 session 无数据时全表扫描任意 session 的 onboarding_data
//         修复边界 A：老用户换新会话不应重复弹问卷
//     3. 都没有 → 弹问卷
// ─────────────────────────────────────────────────────────────

// 私有字段（_xxx）+ 公开命名参数（xxx）模式无法用 initializing formal
// ignore_for_file: prefer_initializing_formals

import '../data/repositories/app_state_repository.dart';
import '../data/repositories/student_model_repository.dart';

class BootstrapService {
  final AppStateRepository _appStateRepo;
  final StudentModelRepository _studentModelRepo;

  BootstrapService({
    required AppStateRepository appStateRepo,
    required StudentModelRepository studentModelRepo,
  }) : _appStateRepo = appStateRepo,
       _studentModelRepo = studentModelRepo;

  /// 判定是否需要显示写作偏好问卷
  ///
  /// 返回 true = 需要弹问卷；false = 不需要
  ///
  /// 检查顺序：
  /// 1. 用户级 questionnaire_completed（新机制，跨会话去重）
  /// 2. 当前 session 级 onboarding_data（向后兼容 + 迁移标记）
  /// 2b. fallback：全表扫描任意 session 的 onboarding_data
  ///     （修复边界 A：老用户换新会话场景）
  /// 3. 都没有 → 弹问卷
  Future<bool> shouldShowQuestionnaire(String? sessionId) async {
    // 1. 用户级检查（优先）
    final userCompleted = await _appStateRepo.getQuestionnaireCompleted();
    if (userCompleted) return false;

    // 2. 当前 session 级检查（老用户数据迁移）
    if (sessionId != null) {
      final sessionOnboarding = await _studentModelRepo.getOnboardingData(
        sessionId,
      );
      if (sessionOnboarding != null) {
        // session 级有数据但用户级标记缺失 → 补写迁移
        // 下次启动走第 1 步直接返回 false，不再查 session 级
        await _appStateRepo.setQuestionnaireCompleted(true);
        return false;
      }
    }

    // 2b. fallback：全表扫描任意 session 的 onboarding_data — 边界 A 修复
    //
    // 场景：老用户在 session A 填过问卷，本次启动进入新 session B。
    // 若只查 currentSession，会误判为"从未填过"而重复弹问卷。
    // 全表扫描拿到任意一条有效数据即认定老用户已填过。
    //
    // 性能：仅在用户级标记缺失时触发（一次性，迁移后不再走），
    // 且 SQL 层已 limit 1 + 过滤空串/'null' 字面量，开销可忽略。
    final anyOnboarding = await _studentModelRepo.hasAnyOnboardingData();
    if (anyOnboarding) {
      await _appStateRepo.setQuestionnaireCompleted(true);
      return false;
    }

    // 3. 都没有 → 弹问卷
    return true;
  }
}
