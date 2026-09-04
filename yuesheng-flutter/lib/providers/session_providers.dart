// ─────────────────────────────────────────────────────────────
// session_providers — session bootstrap 状态迁移到 Riverpod
//
// 设计背景：
//   原 ChatPage 用 setState 管理 sessionId/showOnboarding/initialized/initError，
//   导致状态管理与 Riverpod 双轨制。方案2 将 bootstrap 状态迁移到 Provider，
//   ChatPage 改为 ConsumerWidget。
//
// 状态结构（用户确认：单个 record）：
//   SessionBootstrapState = ({String sessionId, bool shouldShowOnboarding})
//
// Provider 类型（用户确认：AsyncNotifierProvider）：
//   - 支持 onboarding 完成后调 refresh() 重新执行 bootstrap
//   - 测试可 override bootstrapServiceProvider 注入 fake
// ─────────────────────────────────────────────────────────────

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/app_state_repository.dart';
import '../data/repositories/chapter_repository.dart';
import '../data/repositories/character_fact_repository.dart';
import '../data/repositories/event_fact_repository.dart';
import '../data/repositories/outline_repository.dart';
import '../data/repositories/subplot_fact_repository.dart';
import '../data/repositories/diagnosis_repository.dart';
import '../data/repositories/editor_observation_repository.dart';
import '../data/repositories/manuscript_repository.dart';
import '../data/repositories/session_repository.dart';
import '../data/repositories/student_model_repository.dart';
import '../data/repositories/teacher_suggestion_repository.dart';
import '../data/repositories/training_result_repository.dart';
import '../data/repositories/teaching_state_repository.dart';
import '../services/bootstrap_service.dart';
import '../services/chat_service.dart';
import '../services/diagnosis_committer.dart';
import '../services/diagnosis_service.dart';
import '../services/last_session_storage.dart';
import '../services/llm_client.dart';
import '../services/onboarding_service.dart';
import '../services/realtime_observation_service.dart';
import 'app_providers.dart';
import 'capability_providers.dart';

/// Session bootstrap 状态（record）
///
/// 包含 sessionId（取或建）+ shouldShowOnboarding（问卷触发判定）
typedef SessionBootstrapState = ({String sessionId, bool shouldShowOnboarding});

/// BootstrapService Provider
///
/// 生产环境依赖 appDatabaseProvider 构造；测试可 override 注入 fake
/// （如 _ThrowingBootstrapService 覆盖异常路径）
final bootstrapServiceProvider = Provider<BootstrapService>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return BootstrapService(
    appStateRepo: AppStateRepository(db),
    studentModelRepo: StudentModelRepository(db),
  );
});

/// 上次会话 ID 存储 Provider（批次 50：会话恢复对齐 RN）
///
/// 生产用 flutter_secure_storage；测试 override 注入内存 fake，
/// 避免触碰平台通道
final lastSessionStorageProvider = Provider<LastSessionStorage>((ref) {
  return SecureLastSessionStorage();
});

/// OnboardingService Provider
///
/// 用于问卷提交（submitOnboarding/skipOnboarding），
/// 提交后触发 sessionBootstrapProvider.refresh() 刷新 shouldShowOnboarding
final onboardingServiceProvider = Provider<OnboardingService>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return OnboardingService(
    studentModelRepo: StudentModelRepository(db),
    stateRepo: TeachingStateRepository(db),
    appStateRepo: AppStateRepository(db),
  );
});

/// 诊断服务 Provider（D5-B：诊断卡片确认/质疑闭环）
///
/// DiagnosisService 是诊断状态唯一 Owner（confirm/dispute/unlock）。
/// 供 DiagnosisCard 的确认栏调用；生产用真实 repo，测试可 override。
final diagnosisServiceProvider = Provider<DiagnosisService>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return DiagnosisService(
    diagnosisRepo: DiagnosisRepository(db),
    studentModelRepo: StudentModelRepository(db),
  );
});

/// LLM 客户端 Provider（单例）
///
/// ChatService 和 runProgressiveDiagnosis 共用同一实例
final llmClientProvider = Provider<LlmClient>((ref) {
  return LlmClient();
});

/// 诊断提交编排器 Provider（ADR-C74 K-1）
///
/// K-1 阶段仅供 chatServiceProvider 注入；ChatService 内暂不消费（行为零变化
/// 护栏）。K-2 ~ K-5 阶段随方法迁入时逐步收紧——届时 ChatService 内部开始
/// 委派到本 provider 实例。
final diagnosisCommitterProvider = Provider<DiagnosisCommitter>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return DiagnosisCommitter(
    sessionRepo: SessionRepository(db),
    stateRepo: TeachingStateRepository(db),
    diagnosisRepo: DiagnosisRepository(db),
    // 复用 D5-B 已落地的 DiagnosisService provider，与生产侧同一实例
    diagnosisService: ref.watch(diagnosisServiceProvider),
    genUi: ref.watch(genUiCapabilityProvider),
    material: ref.watch(materialCapabilityProvider),
    teaching: ref.watch(teachingCapabilityProvider),
    diagnosis: ref.watch(diagnosisCapabilityProvider),
    characterFactRepo: CharacterFactRepository(db),
    eventFactRepo: EventFactRepository(db),
    subplotFactRepo: SubplotFactRepository(db),
    outlineRepo: OutlineRepository(db),
  );
});

/// ChatService Provider
///
/// 生产环境依赖所有 Repository + LlmClient 构造；
/// 测试可 override 注入 fake（如 FakeChatService）
final chatServiceProvider = Provider<ChatService>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return ChatService(
    sessionRepo: SessionRepository(db),
    stateRepo: TeachingStateRepository(db),
    diagnosisRepo: DiagnosisRepository(db),
    studentModelRepo: StudentModelRepository(db),
    referenceRepo: ref.read(referenceCapabilityProvider),
    chapterRepo: ChapterRepository(db),
    manuscriptRepo: ManuscriptRepository(db),
    llmClient: ref.watch(llmClientProvider),
    teacherSuggestionRepo: TeacherSuggestionRepository(db),
    editorObservationRepo: EditorObservationRepository(db),
    // X-041c：训练结果持久化仓储装配，启用 training_results 落库
    trainingResultRepo: TrainingResultRepository(db),
    // 阶段 1（选项 B 依赖倒置）：四大纯能力经 capability provider 注入，
    // 生产侧走 DI 接缝；impl 为纯委托，行为与原顶层纯函数等价。
    genUi: ref.watch(genUiCapabilityProvider),
    material: ref.watch(materialCapabilityProvider),
    teaching: ref.watch(teachingCapabilityProvider),
    diagnosis: ref.watch(diagnosisCapabilityProvider),
    // 批次66（B62i）：人物知识仓储装配，启用时序矛盾观察
    characterFactRepo: CharacterFactRepository(db),
    // 批次67（B62j）：事件/支线知识仓储装配，启用 F07 因果链 + F11 情节闭环观察
    eventFactRepo: EventFactRepository(db),
    subplotFactRepo: SubplotFactRepository(db),
    // 批次72（大纲层）：大纲记忆仓储装配，启用实体索引注入 + AI 提取落库
    outlineRepo: OutlineRepository(db),
    // ADR-C74 K-1：诊断提交编排器装配；ChatService 暂不消费，K-2 ~ K-5
    // 阶段随方法迁入时收紧
    diagnosisCommitter: ref.watch(diagnosisCommitterProvider),
  );
});

/// 实时通道观察服务（批次68 B62j A7 双模型分级·实时通道）
///
/// 轻 prompt：只跑 Editor 观察（editor-observation skill + 轻量约束），
/// 低延迟反馈，不接 Reviewer/Teacher/全量诊断。复盘通道保持 ChatService 全量。
final realtimeObservationServiceProvider = Provider<RealtimeObservationService>(
  (ref) {
    final db = ref.watch(appDatabaseProvider);
    return RealtimeObservationService(
      llmClient: ref.watch(llmClientProvider),
      sessionRepo: SessionRepository(db),
      editorObservationRepo: EditorObservationRepository(db),
    );
  },
);

/// Session bootstrap AsyncNotifier
///
/// build() 执行 bootstrap 逻辑：
///   1. 取或建默认会话（优先级：显式目标 > 上次会话 > updated_at 最新 > 新建）
///      选定后持久化 LAST_SESSION_KEY（批次 50 对齐 RN initSession）
///   2. 判定是否需要弹问卷（BootstrapService.shouldShowQuestionnaire）
///
/// onboarding 完成后调用 refresh() 重新执行 build，刷新 shouldShowOnboarding
class SessionBootstrapNotifier extends AsyncNotifier<SessionBootstrapState> {
  /// 显式会话目标（drawer 切换/新建后设置；null 表示走默认解析）
  /// 重启后 Notifier 重建，回到「上次会话」恢复行为（批次 50）
  String? _targetSessionId;

  @override
  Future<SessionBootstrapState> build() async {
    final db = ref.watch(appDatabaseProvider);
    final bootstrapService = ref.watch(bootstrapServiceProvider);
    final lastStorage = ref.watch(lastSessionStorageProvider);
    final sessionRepo = SessionRepository(db);

    // 1. 取或建默认会话（复刻 useBootstrap L26-39 + 批次 50 会话恢复）：
    //    显式目标（drawer 切换/新建）> LAST_SESSION_KEY（SecureStore 恢复）>
    //    updated_at 最新会话 > 新建空白会话
    final sessions = await sessionRepo.listSessions();
    final String sessionId;
    if (_targetSessionId != null) {
      sessionId = _targetSessionId!;
    } else {
      final lastId = await lastStorage.getLastSessionId();
      if (lastId != null && lastId.isNotEmpty) {
        sessionId = lastId;
      } else if (sessions.isNotEmpty) {
        sessionId = sessions.first.id;
      } else {
        sessionId = await sessionRepo.createBlankSession();
      }
    }

    // 对齐 RN initSession（chat-store.ts L79）：选定会话后持久化 LAST_SESSION_KEY
    await lastStorage.setLastSessionId(sessionId);

    // 2. 判定是否需要弹问卷
    final shouldShow = await bootstrapService.shouldShowQuestionnaire(
      sessionId,
    );

    return (sessionId: sessionId, shouldShowOnboarding: shouldShow);
  }

  /// 切换会话（对齐 RN switchSession）：设置目标后重新 bootstrap
  Future<void> switchTo(String sessionId) async {
    _targetSessionId = sessionId;
    await refresh();
  }

  /// 新建会话并切换（对齐 RN createAndSwitchSession）
  Future<void> createNew() async {
    final db = ref.read(appDatabaseProvider);
    final sessionRepo = SessionRepository(db);
    final id = await sessionRepo.createBlankSession();
    _targetSessionId = id;
    await refresh();
  }

  /// 刷新 bootstrap 状态
  ///
  /// onboarding 完成后调用：questionnaire_completed 已写入，
  /// 重新执行 build 后 shouldShowOnboarding 应为 false
  Future<void> refresh() async {
    ref.invalidateSelf();
    // 等待新的 build 完成（future 在 invalidateSelf 后会指向新的 computation）
    await future;
  }
}

final sessionBootstrapProvider =
    AsyncNotifierProvider<SessionBootstrapNotifier, SessionBootstrapState>(
      SessionBootstrapNotifier.new,
    );
