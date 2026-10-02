// ─────────────────────────────────────────────────────────────
// OnboardingService — 新手模式落库服务（状态迁移编排器）
// 复刻 yuesheng-android/src/services/onboarding-service.ts（RN 真源规划中的文件）
//
// 设计意图（批次1-8 波6；ADR-C122：问卷 UI 已退役，由纯新手模式取代）：
//   新手模式落库不再直接调 DAO，而是走本 service 一次性触发三处状态迁移：
//     1. student_model.onboarding_data ← buildNoviceOnboardingData 解析的
//        三字段（proficiency / focusAreas / cognitiveStyle；writingGoal 恒空）
//     2. teaching_state.beginner_level ← 由 proficiency 映射 N0/N1/N2/N3
//     3. app_state.questionnaire_completed ← 'true'（用户级，跨会话去重）
//
//   调用方：chat_page 新手流程 _commitNoviceData
//   （➕面板 → 固定弹窗对话 → buildNoviceOnboardingData(text) → 本 service）。
//   C122 后无 onSkip 路径（skipOnboarding 已随问卷 UI 一并移除）。
// ─────────────────────────────────────────────────────────────

// 私有字段（_xxx）+ 公开命名参数（xxx）模式无法用 initializing formal
// ignore_for_file: prefer_initializing_formals

import '../data/repositories/app_state_repository.dart';
import '../data/repositories/student_model_repository.dart';
import '../data/repositories/teaching_state_repository.dart';
import '../types/teaching_types.dart';
import 'onboarding_flow.dart';

class OnboardingService {
  final StudentModelRepository _studentModelRepo;
  final TeachingStateRepository _stateRepo;
  final AppStateRepository _appStateRepo;

  OnboardingService({
    required StudentModelRepository studentModelRepo,
    required TeachingStateRepository stateRepo,
    required AppStateRepository appStateRepo,
  }) : _studentModelRepo = studentModelRepo,
       _stateRepo = stateRepo,
       _appStateRepo = appStateRepo;

  /// 提交问卷（正式完成）
  ///
  /// 三步状态迁移：
  /// 1. 写入 onboarding_data（student_model，session 级）
  /// 2. 映射 proficiency → BeginnerLevel，写入 teaching_state.beginner_level
  /// 3. 标记 questionnaire_completed = true（app_state，用户级）
  Future<void> submitOnboarding(String sessionId, OnboardingData data) async {
    // 1. 持久化问卷原始数据
    await _studentModelRepo.updateOnboardingData(sessionId, data.toJson());

    // 2. proficiency → BeginnerLevel 映射并写入
    //    跳过问卷时 proficiency 默认 beginner → N0_ENGAGE
    final beginnerLevel = proficiencyToBeginnerLevel(data.proficiency);
    await _stateRepo.updateBeginnerLevel(sessionId, beginnerLevel.value);

    // 3. 标记用户级问卷已完成（跨会话去重）
    await _appStateRepo.setQuestionnaireCompleted(true);
  }
}
