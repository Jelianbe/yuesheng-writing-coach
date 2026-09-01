// ─────────────────────────────────────────────────────────────
// chat_service 阶段迁移校验测试 — 批次5 M4-B / M4-C
//
// 覆盖：
//   M4-B: validatePhaseTransition 在 AI 驱动迁移路径的拦截
//     #1 非法跳级 P2→P4 被拦截
//     #2 合法递进 P2→P3 被放行
//   M4-C: phasePassRate 在自动迁移路径（M4-A）的达标率校验
//     #3 达标率 ≥ 0.7 → 自动迁移放行
//     #4 达标率 < 0.7 → 自动迁移拦截
// ─────────────────────────────────────────────────────────────

// ignore_for_file: prefer_initializing_formals, unnecessary_underscores

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/editor_observation_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/outline_repository.dart';
import 'package:writingcoach/data/repositories/reference_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/data/repositories/student_model_repository.dart';
import 'package:writingcoach/data/repositories/teacher_suggestion_repository.dart';
import 'package:writingcoach/data/repositories/teaching_state_repository.dart';
import 'package:writingcoach/services/chat_service.dart';
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/types/teaching_types.dart';

class FakeLlmClient extends LlmClient {
  final String _fullResponse;
  final int _chunkSize;

  /// 第二次及后续调用（如 Teacher 触发）返回的响应；null 则复用 [_fullResponse]
  final String? _subsequentResponse;

  /// 记录每次 streamChat 收到的 messages（批次6 M2 断言用）
  final List<List<ChatMessage>> calls = [];

  FakeLlmClient(
    this._fullResponse, {
    int chunkSize = 10,
    String? subsequentResponse,
  }) : _chunkSize = chunkSize,
       _subsequentResponse = subsequentResponse;

  @override
  Future<void> streamChat(
    List<ChatMessage> messages,
    void Function(LlmStreamResponse response) callback, {
    CancelToken? cancelToken,
  }) async {
    calls.add(messages);
    final body = calls.length == 1
        ? _fullResponse
        : (_subsequentResponse ?? _fullResponse);
    for (int i = 0; i < body.length; i += _chunkSize) {
      final end = i + _chunkSize < body.length ? _chunkSize : body.length - i;
      callback(
        LlmStreamResponse(content: body.substring(i, i + end), isDone: false),
      );
    }
    callback(const LlmStreamResponse(content: '', isDone: true));
  }
}

void main() {
  late AppDatabase db;
  late SessionRepository sessionRepo;
  late TeachingStateRepository stateRepo;
  late DiagnosisRepository diagnosisRepo;
  late StudentModelRepository studentModelRepo;
  late String sessionId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sessionRepo = SessionRepository(db);
    stateRepo = TeachingStateRepository(db);
    diagnosisRepo = DiagnosisRepository(db);
    studentModelRepo = StudentModelRepository(db);
    sessionId = await sessionRepo.createBlankSession();
  });

  tearDown(() async => db.close());

  /// 构造 ChatService
  ChatService buildChatService(LlmClient llmClient) {
    return ChatService(
      sessionRepo: sessionRepo,
      stateRepo: stateRepo,
      diagnosisRepo: diagnosisRepo,
      studentModelRepo: studentModelRepo,
      referenceRepo: ReferenceRepository(db),
      chapterRepo: ChapterRepository(db),
      manuscriptRepo: ManuscriptRepository(db),
      llmClient: llmClient,
      teacherSuggestionRepo: TeacherSuggestionRepository(db),
      editorObservationRepo: EditorObservationRepository(db),
    );
  }

  /// 设置教学状态：phase + beginnerLevel
  Future<void> setTeachingState({
    required TeachingPhase phase,
    required BeginnerLevel level,
  }) async {
    await stateRepo.updatePhase(sessionId, phase.value);
    await stateRepo.updateBeginnerLevel(sessionId, level.value);
  }

  /// 构造诊断 LLM 响应（含 suggestedPhase 可选）
  String buildDiagnosisResponse({
    String? suggestedPhase,
    String syndromeId = 's1',
    String severity = 'L2',
  }) {
    final phaseField = suggestedPhase != null
        ? ',"suggested_phase":"$suggestedPhase"'
        : '';
    return '诊断完成。'
        '\n[YS_DIAGNOSIS]'
        '\n{"syndromes":[{"syndrome_id":"$syndromeId","name":"叙事含糊","severity":"$severity","evidence":[],"explanation":"测试"}],"suggested_actions":[],"confidence":0.8$phaseField}'
        '\n[/YS_DIAGNOSIS]';
  }

  /// 种子一条诊断 + 活跃症候，然后手动 resolve
  Future<void> seedAndResolveProblem({String syndromeId = 's1'}) async {
    final msgId = await sessionRepo.addMessage(
      sessionId,
      'assistant',
      '诊断内容',
      messageType: 'diagnosis_result',
    );
    await diagnosisRepo.commitDiagnosis(
      DiagnosisInput(
        sessionId: sessionId,
        messageId: msgId,
        syndromes: [
          {'syndrome_id': syndromeId, 'name': '叙事含糊', 'severity': 'L2'},
        ],
        suggestedActions: const [],
        confidence: 0.8,
      ),
    );
    // 手动 resolve（模拟学员标记完成或 FSM mastered 路径）
    await diagnosisRepo.resolveProblem(sessionId, syndromeId);
  }

  /// 追加 confirmation 历史记录
  Future<void> addConfirmation({
    required String action,
    String syndromeId = 's1',
  }) async {
    await studentModelRepo.appendTeachingHistory(sessionId, {
      'type': 'confirmation',
      'syndromes': [syndromeId],
      'action': action,
      'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'sessionId': sessionId,
    });
  }

  const p2Options = SendMessageOptions(
    phase: TeachingPhase.p2PracticeLoop,
    attitude: AttitudeLevel.doubao,
  );

  // ── M4-B：AI 驱动迁移路径合法性校验 ──

  group('M4-B validatePhaseTransition', () {
    test('#1 非法跳级 P2→P4 被拦截，phase 保持 P2', () async {
      await setTeachingState(
        phase: TeachingPhase.p2PracticeLoop,
        level: BeginnerLevel.n3Diagnose,
      );

      final chatService = buildChatService(
        FakeLlmClient(buildDiagnosisResponse(suggestedPhase: 'P4_REVIEW')),
      );

      await chatService.sendMessage(
        sessionId,
        '帮我诊断',
        SendMessageCallbacks(
          onStream: (_) {},
          onComplete: (_, __) {},
          onError: (_) {},
        ),
        p2Options,
      );

      final ts = await stateRepo.getTeachingState(sessionId);
      expect(
        ts?.currentPhase,
        TeachingPhase.p2PracticeLoop.value,
        reason: 'P2→P4 跳级非法，应被 validatePhaseTransition 拦截',
      );
    });

    test('#2 合法递进 P2→P3 被放行，phase 变为 P3', () async {
      await setTeachingState(
        phase: TeachingPhase.p2PracticeLoop,
        level: BeginnerLevel.n3Diagnose,
      );

      final chatService = buildChatService(
        FakeLlmClient(buildDiagnosisResponse(suggestedPhase: 'P3_TRAINING')),
      );

      await chatService.sendMessage(
        sessionId,
        '帮我诊断',
        SendMessageCallbacks(
          onStream: (_) {},
          onComplete: (_, __) {},
          onError: (_) {},
        ),
        p2Options,
      );

      final ts = await stateRepo.getTeachingState(sessionId);
      expect(
        ts?.currentPhase,
        TeachingPhase.p3Training.value,
        reason: 'P2→P3 相邻递进合法，应被放行',
      );
    });

    test('#3 非法回退 P2→P0 被拦截，phase 保持 P2', () async {
      await setTeachingState(
        phase: TeachingPhase.p2PracticeLoop,
        level: BeginnerLevel.n3Diagnose,
      );

      final chatService = buildChatService(
        FakeLlmClient(buildDiagnosisResponse(suggestedPhase: 'P0_ENGAGE')),
      );

      await chatService.sendMessage(
        sessionId,
        '帮我诊断',
        SendMessageCallbacks(
          onStream: (_) {},
          onComplete: (_, __) {},
          onError: (_) {},
        ),
        p2Options,
      );

      final ts = await stateRepo.getTeachingState(sessionId);
      expect(
        ts?.currentPhase,
        TeachingPhase.p2PracticeLoop.value,
        reason: 'P2→P0 回退非法，应被拦截',
      );
    });
  });

  // ── C54 方案 C：首诊双信号确定性降级（ADR-C54 §7.3）──
  //
  // 背景：首诊（首次展示文本 + 首次诊断出症候）时 P0→P1 与 P1→P2 信号
  // 同时成立，suggested_phase 单值只能填一个——4 个模型实例实测证明
  // 采样决定教学路径。方案 C 让代码确定性降级，无论 AI 填哪个，
  // P0 首诊落库恒为 P1_WORLD。

  group('C54 方案 C：首诊双信号', () {
    test('#C1 P0 + N3 + suggested_phase=P2 → 降级落库 P1（C-2 clamp）', () async {
      await setTeachingState(
        phase: TeachingPhase.p0Engage,
        level: BeginnerLevel.n3Diagnose,
      );

      final chatService = buildChatService(
        FakeLlmClient(
          buildDiagnosisResponse(suggestedPhase: 'P2_PRACTICE_LOOP'),
        ),
      );

      await chatService.sendMessage(
        sessionId,
        '帮我诊断',
        SendMessageCallbacks(
          onStream: (_) {},
          onComplete: (_, __) {},
          onError: (_) {},
        ),
        const SendMessageOptions(
          phase: TeachingPhase.p0Engage,
          attitude: AttitudeLevel.doubao,
        ),
      );

      final ts = await stateRepo.getTeachingState(sessionId);
      expect(
        ts?.currentPhase,
        TeachingPhase.p1World.value,
        reason: 'C-2：P0→P2 跨一格应确定性降级为 P0→P1，而非整轮丢弃',
      );
    });

    test('#C2 P0 + N3 + suggested_phase=P1 → 透传落库 P1（C-3 收窄）', () async {
      await setTeachingState(
        phase: TeachingPhase.p0Engage,
        level: BeginnerLevel.n3Diagnose,
      );

      final chatService = buildChatService(
        FakeLlmClient(buildDiagnosisResponse(suggestedPhase: 'P1_WORLD')),
      );

      await chatService.sendMessage(
        sessionId,
        '帮我诊断',
        SendMessageCallbacks(
          onStream: (_) {},
          onComplete: (_, __) {},
          onError: (_) {},
        ),
        const SendMessageOptions(
          phase: TeachingPhase.p0Engage,
          attitude: AttitudeLevel.doubao,
        ),
      );

      final ts = await stateRepo.getTeachingState(sessionId);
      expect(
        ts?.currentPhase,
        TeachingPhase.p1World.value,
        reason:
            'C-3：current 未越过 P1 时 N3+P1 不提升——'
            '修复前会被规则 3 改写成 P2 再被拦截，P0 学员整轮不动',
      );
    });

    test('#C3 P0 + N0 + 任意 suggested_phase → 保持 P0（规则1 挂起，既有设计）', () async {
      await setTeachingState(
        phase: TeachingPhase.p0Engage,
        level: BeginnerLevel.n0Engage,
      );

      final chatService = buildChatService(
        FakeLlmClient(
          buildDiagnosisResponse(suggestedPhase: 'P2_PRACTICE_LOOP'),
        ),
      );

      await chatService.sendMessage(
        sessionId,
        '帮我诊断',
        SendMessageCallbacks(
          onStream: (_) {},
          onComplete: (_, __) {},
          onError: (_) {},
        ),
        const SendMessageOptions(
          phase: TeachingPhase.p0Engage,
          attitude: AttitudeLevel.doubao,
        ),
      );

      final ts = await stateRepo.getTeachingState(sessionId);
      expect(
        ts?.currentPhase,
        TeachingPhase.p0Engage.value,
        reason: '规则1（N0-N2 P 系虚拟挂起）是刻意设计，C54 不得误改',
      );
    });

    test('#C4 回归守卫：P2 + N3 + P4 → 保持 P2（收窄条件不得放宽到 P2+）', () async {
      await setTeachingState(
        phase: TeachingPhase.p2PracticeLoop,
        level: BeginnerLevel.n3Diagnose,
      );

      final chatService = buildChatService(
        FakeLlmClient(buildDiagnosisResponse(suggestedPhase: 'P4_REVIEW')),
      );

      await chatService.sendMessage(
        sessionId,
        '帮我诊断',
        SendMessageCallbacks(
          onStream: (_) {},
          onComplete: (_, __) {},
          onError: (_) {},
        ),
        p2Options,
      );

      final ts = await stateRepo.getTeachingState(sessionId);
      expect(
        ts?.currentPhase,
        TeachingPhase.p2PracticeLoop.value,
        reason:
            'clampEarlyPhaseSkip 仅覆盖 P0/P1；P2→P4 跨级维持拦截'
            '（与 #1 双重锁定）',
      );
    });
  });

  // ── M4-C：自动迁移达标率校验 ──

  group('M4-C phasePassRate', () {
    test('#4 达标率 ≥ 0.7 → 自动迁移 P2→P3 放行', () async {
      await setTeachingState(
        phase: TeachingPhase.p2PracticeLoop,
        level: BeginnerLevel.n3Diagnose,
      );
      // 种子症候并 resolve（让 remaining.isEmpty）
      await seedAndResolveProblem();
      // 3 条 confirmed（≥ minPhaseMigrationSamples=3）→ passRate = 1.0 ≥ 0.7
      await addConfirmation(action: 'confirmed');
      await addConfirmation(action: 'confirmed');
      await addConfirmation(action: 'confirmed');

      final chatService = buildChatService(
        FakeLlmClient(buildDiagnosisResponse()),
      );

      await chatService.sendMessage(
        sessionId,
        '帮我诊断',
        SendMessageCallbacks(
          onStream: (_) {},
          onComplete: (_, __) {},
          onError: (_) {},
        ),
        p2Options,
      );

      final ts = await stateRepo.getTeachingState(sessionId);
      expect(
        ts?.currentPhase,
        TeachingPhase.p3Training.value,
        reason: '达标率 1.0 ≥ 0.7，所有症候已 resolved，应自动迁移到 P3',
      );
    });

    test('#5 达标率 < 0.7 → 自动迁移拦截，phase 保持 P2', () async {
      await setTeachingState(
        phase: TeachingPhase.p2PracticeLoop,
        level: BeginnerLevel.n3Diagnose,
      );
      await seedAndResolveProblem();
      // 1 confirmed + 2 disputed → passRate ≈ 0.33 < 0.7
      await addConfirmation(action: 'confirmed');
      await addConfirmation(action: 'disputed');
      await addConfirmation(action: 'disputed');

      final chatService = buildChatService(
        FakeLlmClient(buildDiagnosisResponse()),
      );

      await chatService.sendMessage(
        sessionId,
        '帮我诊断',
        SendMessageCallbacks(
          onStream: (_) {},
          onComplete: (_, __) {},
          onError: (_) {},
        ),
        p2Options,
      );

      final ts = await stateRepo.getTeachingState(sessionId);
      expect(
        ts?.currentPhase,
        TeachingPhase.p2PracticeLoop.value,
        reason: '达标率 0.33 < 0.7，即使所有症候已 resolved 也不应迁移',
      );
    });

    test('#6 无 confirmation 记录 → 中性值 0.5 < 0.7，迁移拦截', () async {
      await setTeachingState(
        phase: TeachingPhase.p2PracticeLoop,
        level: BeginnerLevel.n3Diagnose,
      );
      await seedAndResolveProblem();
      // 无 confirmation 记录 → passRate = 0.5

      final chatService = buildChatService(
        FakeLlmClient(buildDiagnosisResponse()),
      );

      await chatService.sendMessage(
        sessionId,
        '帮我诊断',
        SendMessageCallbacks(
          onStream: (_) {},
          onComplete: (_, __) {},
          onError: (_) {},
        ),
        p2Options,
      );

      final ts = await stateRepo.getTeachingState(sessionId);
      expect(
        ts?.currentPhase,
        TeachingPhase.p2PracticeLoop.value,
        reason: '无训练确认记录 passRate=0.5 < 0.7，不应迁移',
      );
    });
  });

  // ── 批次1 C5/H3：阶段迁移双路径互斥 ──
  //
  // 修复前：路径1（AI 驱动）迁移后路径2（M4-A 自动）无条件继续，
  // 同轮可链式双跳（P1→P2→P3）。修复后：路径1 成功迁移即 return。

  group('C5/H3 双路径互斥（批次1）', () {
    test('#A1 路径1 AI 迁移命中后路径2 不执行（P1→P2，不链式双跳到 P3）', () async {
      await setTeachingState(
        phase: TeachingPhase.p1World,
        level: BeginnerLevel.n3Diagnose,
      );
      // remaining.isEmpty + passRate 1.0（3 条确认 ≥ 最小样本）→ 路径2 具备放行条件
      await seedAndResolveProblem();
      await addConfirmation(action: 'confirmed');
      await addConfirmation(action: 'confirmed');
      await addConfirmation(action: 'confirmed');

      final chatService = buildChatService(
        FakeLlmClient(
          buildDiagnosisResponse(suggestedPhase: 'P2_PRACTICE_LOOP'),
        ),
      );

      await chatService.sendMessage(
        sessionId,
        '帮我诊断',
        SendMessageCallbacks(
          onStream: (_) {},
          onComplete: (_, __) {},
          onError: (_) {},
        ),
        const SendMessageOptions(
          phase: TeachingPhase.p1World,
          attitude: AttitudeLevel.doubao,
        ),
      );

      final ts = await stateRepo.getTeachingState(sessionId);
      expect(
        ts?.currentPhase,
        TeachingPhase.p2PracticeLoop.value,
        reason: '路径1 已迁移 P1→P2，路径2 不应再链式双跳（P2→P3）',
      );
    });

    test('#A2 路径1 未产生迁移（suggested=当前阶段）→ 路径2 仍可评估推进', () async {
      await setTeachingState(
        phase: TeachingPhase.p2PracticeLoop,
        level: BeginnerLevel.n3Diagnose,
      );
      await seedAndResolveProblem();
      await addConfirmation(action: 'confirmed');
      await addConfirmation(action: 'confirmed');
      await addConfirmation(action: 'confirmed');

      final chatService = buildChatService(
        FakeLlmClient(
          buildDiagnosisResponse(suggestedPhase: 'P2_PRACTICE_LOOP'),
        ),
      );

      await chatService.sendMessage(
        sessionId,
        '帮我诊断',
        SendMessageCallbacks(
          onStream: (_) {},
          onComplete: (_, __) {},
          onError: (_) {},
        ),
        p2Options,
      );

      final ts = await stateRepo.getTeachingState(sessionId);
      expect(
        ts?.currentPhase,
        TeachingPhase.p3Training.value,
        reason: '路径1 同阶段不迁移（suggested=P2, current=P2），路径2 应正常推进 P2→P3',
      );
    });
  });

  // ── 批次6 D1：commitDiagnosisFromContent 复用阶段迁移 ──

  group('D1 commitDiagnosisFromContent 阶段推进（批次6）', () {
    test('#7 分块诊断路径：AI suggestedPhase 合法 → 阶段推进', () async {
      await setTeachingState(
        phase: TeachingPhase.p2PracticeLoop,
        level: BeginnerLevel.n3Diagnose,
      );

      final chatService = buildChatService(
        FakeLlmClient(buildDiagnosisResponse(suggestedPhase: 'P3_TRAINING')),
      );

      // 直接调用 commitDiagnosisFromContent（模拟超长章节分块诊断完成后的落库）
      await chatService.commitDiagnosisFromContent(
        sessionId: sessionId,
        fullContent: buildDiagnosisResponse(suggestedPhase: 'P3_TRAINING'),
      );

      final ts = await stateRepo.getTeachingState(sessionId);
      expect(
        ts?.currentPhase,
        TeachingPhase.p3Training.value,
        reason: 'D1: 分块诊断路径也应触发 resolver 阶段推进（P2→P3）',
      );
    });

    test('#8 分块诊断路径：非法跳级 suggestedPhase → 阶段保持', () async {
      await setTeachingState(
        phase: TeachingPhase.p2PracticeLoop,
        level: BeginnerLevel.n3Diagnose,
      );

      final chatService = buildChatService(
        FakeLlmClient(buildDiagnosisResponse(suggestedPhase: 'P4_REVIEW')),
      );

      await chatService.commitDiagnosisFromContent(
        sessionId: sessionId,
        fullContent: buildDiagnosisResponse(suggestedPhase: 'P4_REVIEW'),
      );

      final ts = await stateRepo.getTeachingState(sessionId);
      expect(
        ts?.currentPhase,
        TeachingPhase.p2PracticeLoop.value,
        reason: 'D1: 分块诊断路径同样受 M4-B 校验拦截（P2→P4 跳级）',
      );
    });

    test('#9 分块诊断路径：所有症候 resolved + 达标率达标 → 自动迁移', () async {
      await setTeachingState(
        phase: TeachingPhase.p2PracticeLoop,
        level: BeginnerLevel.n3Diagnose,
      );
      await seedAndResolveProblem();
      await addConfirmation(action: 'confirmed');
      await addConfirmation(action: 'confirmed');
      await addConfirmation(action: 'confirmed');

      final chatService = buildChatService(
        FakeLlmClient(buildDiagnosisResponse()),
      );

      await chatService.commitDiagnosisFromContent(
        sessionId: sessionId,
        fullContent: buildDiagnosisResponse(),
      );

      final ts = await stateRepo.getTeachingState(sessionId);
      expect(
        ts?.currentPhase,
        TeachingPhase.p3Training.value,
        reason: 'D1: 分块诊断路径也应触发 M4-A 自动迁移（达标率 1.0 ≥ 0.7）',
      );
    });
  });

  // ── 批次6 M2：sendMessage 阶段上下文取 DB currentPhase ──

  group('M2 阶段上下文以 DB 为准（批次6）', () {
    test('#10 DB phase=P3 + N4 → system prompt 用进阶阶段（非硬编码 P0）', () async {
      await setTeachingState(
        phase: TeachingPhase.p3Training,
        level: BeginnerLevel.n4Independent,
      );

      final fake = FakeLlmClient(buildDiagnosisResponse());
      final chatService = buildChatService(fake);

      // options.phase 硬编码 P0（模拟 chat_page 现状），DB 为 P3
      await chatService.sendMessage(
        sessionId,
        '帮我诊断',
        SendMessageCallbacks(
          onStream: (_) {},
          onComplete: (_, __) {},
          onError: (_) {},
        ),
        const SendMessageOptions(
          phase: TeachingPhase.p0Engage,
          attitude: AttitudeLevel.doubao,
        ),
      );

      // system message 应含 advanced-phases skill（P3/P4 专属，标志文本）
      final systemPrompt = fake.calls.first
          .where((m) => m.role == 'system')
          .map((m) => m.content)
          .join('\n');
      expect(
        systemPrompt,
        contains('进阶阶段指引'),
        reason: 'M2: system prompt 阶段上下文应取 DB currentPhase=P3，而非硬编码 P0',
      );
    });

    test('#11 DB 无 teaching_state → 回退 options.phase（P0，不加载 L2 进阶）', () async {
      // 不设置 teaching state（保持空）
      final fake = FakeLlmClient(buildDiagnosisResponse());
      final chatService = buildChatService(fake);

      await chatService.sendMessage(
        sessionId,
        '你好',
        SendMessageCallbacks(
          onStream: (_) {},
          onComplete: (_, __) {},
          onError: (_) {},
        ),
        const SendMessageOptions(
          phase: TeachingPhase.p0Engage,
          attitude: AttitudeLevel.doubao,
        ),
      );

      final systemPrompt = fake.calls.first
          .where((m) => m.role == 'system')
          .map((m) => m.content)
          .join('\n');
      expect(
        systemPrompt,
        isNot(contains('进阶阶段指引')),
        reason: 'M2: 无 DB 状态时回退 options.phase=P0，不应加载进阶阶段',
      );
    });
  });

  // ── O2：outline 沉淀解除装配依赖（批次7）──
  //
  // 改造前：OutlineService 在 ChatService 构造时 eager 构建，
  //        装配依赖作为「静默条件」——装配了 repo 但服务却可能不可用。
  // 改造后：保留 outlineRepo 引用，服务首次使用时懒加载（_ensureOutlineService），
  //        只要装配了 repo，大纲注入 + 提取落库必然可用。
  // 本组验证懒加载路径端到端可用（未使用真实 API，FakeLlmClient 返回协议块）。

  group('O2 outline 懒加载（批次7）', () {
    test('#12 装配 outlineRepo → 懒加载服务仍能完成大纲提取落库', () async {
      final outlineRepo = OutlineRepository(db);
      final chapterRepo = ChapterRepository(db);
      final msRepo = ManuscriptRepository(db);
      final refRepo = ReferenceRepository(db);

      final manuscriptId = await msRepo.createManuscript(title: 'O2 测试手稿');
      final chapterId = await chapterRepo.createChapter(
        manuscriptId,
        title: '第一章',
        content: '正文内容',
      );
      await refRepo.addReference(
        sessionId,
        'chapter',
        chapterId,
        isPrimary: true,
      );

      // 响应同时携带 [YS_DIAGNOSIS] 与 [YS_ENTITY] 块（对齐真实 AI 输出）
      final response =
          '诊断完成。'
          '\n[YS_DIAGNOSIS]'
          '\n{"syndromes":[{"syndrome_id":"s1","name":"叙事含糊","severity":"L2","evidence":[],"explanation":"测试"}],"suggested_actions":[],"confidence":0.8}'
          '\n[/YS_DIAGNOSIS]'
          '\n[YS_ENTITY]'
          '\n{"entities":[{"type":"character","key":"王建国","aliases":[],"impressions":[{"text":"巷口守夜人"}]}]}'
          '\n[/YS_ENTITY]';

      final fake = FakeLlmClient(
        response,
        subsequentResponse: '建议：先练一段聚焦动作的短句。',
      );
      final service = ChatService(
        sessionRepo: sessionRepo,
        stateRepo: stateRepo,
        diagnosisRepo: diagnosisRepo,
        studentModelRepo: studentModelRepo,
        referenceRepo: refRepo,
        chapterRepo: chapterRepo,
        manuscriptRepo: msRepo,
        llmClient: fake,
        teacherSuggestionRepo: TeacherSuggestionRepository(db),
        editorObservationRepo: EditorObservationRepository(db),
        outlineRepo: outlineRepo,
      );

      String? finalDisplay;
      await service.sendMessage(
        sessionId,
        '帮我诊断',
        SendMessageCallbacks(
          onStream: (_) {},
          onComplete: (display, _) => finalDisplay = display,
          onError: (e) => throw Exception('onError: $e'),
        ),
        const SendMessageOptions(
          phase: TeachingPhase.p1World,
          attitude: AttitudeLevel.doubao,
        ),
      );

      // 大纲实体 + 印象落库（懒加载服务走通即证明装配即可用）
      final entities = await outlineRepo.listEntities(manuscriptId);
      expect(entities, isNotEmpty, reason: 'O2: 懒加载服务下大纲提取应正常落库');
      final imps = await outlineRepo.listImpressions(entities.first.id);
      expect(imps, isNotEmpty, reason: 'O2: 实体印象应一并落库');
      // 展示层不含协议原文（[YS_ENTITY] 块已剥离）
      expect(finalDisplay, isNot(contains('[YS_ENTITY]')));
      expect(finalDisplay, isNot(contains('[/YS_ENTITY]')));
    });

    test('#13 未装配 outlineRepo → 懒加载返回 null，静默跳过不抛异常', () async {
      final msRepo = ManuscriptRepository(db);
      final chapterRepo = ChapterRepository(db);
      final refRepo = ReferenceRepository(db);

      final manuscriptId = await msRepo.createManuscript(title: 'O2 无装配手稿');
      final chapterId = await chapterRepo.createChapter(
        manuscriptId,
        title: '第一章',
        content: '正文内容',
      );
      await refRepo.addReference(
        sessionId,
        'chapter',
        chapterId,
        isPrimary: true,
      );

      // 与 #12 相同的协议响应，但 ChatService 不装配 outlineRepo
      final response =
          '诊断完成。'
          '\n[YS_DIAGNOSIS]'
          '\n{"syndromes":[{"syndrome_id":"s1","name":"叙事含糊","severity":"L2","evidence":[],"explanation":"测试"}],"suggested_actions":[],"confidence":0.8}'
          '\n[/YS_DIAGNOSIS]'
          '\n[YS_ENTITY]'
          '\n{"entities":[{"type":"character","key":"王建国","aliases":[],"impressions":[{"text":"巷口守夜人"}]}]}'
          '\n[/YS_ENTITY]';

      final fake = FakeLlmClient(
        response,
        subsequentResponse: '建议：先练一段聚焦动作的短句。',
      );
      final service = ChatService(
        sessionRepo: sessionRepo,
        stateRepo: stateRepo,
        diagnosisRepo: diagnosisRepo,
        studentModelRepo: studentModelRepo,
        referenceRepo: refRepo,
        chapterRepo: chapterRepo,
        manuscriptRepo: msRepo,
        llmClient: fake,
        teacherSuggestionRepo: TeacherSuggestionRepository(db),
        editorObservationRepo: EditorObservationRepository(db),
        // outlineRepo 不传 → 懒加载返回 null → 提取静默跳过
      );

      String? finalDisplay;
      await service.sendMessage(
        sessionId,
        '帮我诊断',
        SendMessageCallbacks(
          onStream: (_) {},
          onComplete: (display, _) => finalDisplay = display,
          onError: (e) => throw Exception('onError: $e'),
        ),
        const SendMessageOptions(
          phase: TeachingPhase.p1World,
          attitude: AttitudeLevel.doubao,
        ),
      );

      // 未装配时实体不应落库（静默跳过），主流程不受影响
      final entities = await OutlineRepository(db).listEntities(manuscriptId);
      expect(entities, isEmpty, reason: 'O2: 未装配 outlineRepo 时应静默跳过提取');
      expect(finalDisplay, isNotNull);
    });
  });
}
