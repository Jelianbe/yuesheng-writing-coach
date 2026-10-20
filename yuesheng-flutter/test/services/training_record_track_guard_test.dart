// ─────────────────────────────────────────────────────────────
// training_record_track_guard_test — 训练记录轨读取链护栏（T-20261019-02 施工批）
//
// 依据：reports/2026-10-20-训练记录轨读取链改造方案.md §6.2
//   （DECISIONS §4-224 方案 / §4-225 施工落账；公仓 HEAD e8f4b731 复核）
// 给三处「定性」上机器执行点——改动即红：
//
//   T1 覆盖契约（§4.1 判据）：同一 session 任意次训练反馈后，
//      TH `type='training'` 记录数 ≥ TR 行数，且共享字段逐条一致。
//      锁「TH 先写、TR 后写」的写入顺序（顺序调换 ⇒ TR ⊋ TH 时可红）。
//   T2 双写一致（§3.2-4 风险）：_persistSelfAssessment 的仓储序列
//      （先 updateSelfAssessment 写 TR 四列，再 updateLatestTrainingRating
//      补 TH 副本）后两侧一致；并锁定「任一方写失败不阻断另一方」。
//   T3 门控语义锁（§4.3 判据）：mastered 软门控四种输入
//      （无自评 / repo null / 查询抛错 / 低分自评）输出逐字锁定。
//
// 边界（R-010）：纯测试层新增，不改任何 lib/ 产品代码；
// 不设任何数值阈值（方案 §3.3：误报率数据本地域零实例，禁拍）。
// ─────────────────────────────────────────────────────────────

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/reference_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/data/repositories/student_model_repository.dart';
import 'package:writingcoach/data/repositories/teacher_suggestion_repository.dart';
import 'package:writingcoach/data/repositories/teaching_state_repository.dart';
import 'package:writingcoach/data/repositories/training_result_repository.dart';
import 'package:writingcoach/services/chat_context_builder.dart'
    show MaterialCapabilityImpl;
import 'package:writingcoach/services/chat_message_types.dart'
    show SendMessageCallbacks;
import 'package:writingcoach/services/chat_training_parser.dart'
    show parseTrainingProtocol;
import 'package:writingcoach/services/diagnosis_committer.dart';
import 'package:writingcoach/services/diagnosis_flow_handler.dart';
import 'package:writingcoach/services/diagnosis_parser.dart'
    show DiagnosisCapabilityImpl;
import 'package:writingcoach/services/evaluation_service.dart';
import 'package:writingcoach/services/genui_parser.dart' show GenUiParser;
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/services/message_injector.dart';
import 'package:writingcoach/types/teaching_types.dart';

/// 训练反馈路径不应触达 LLM；一旦触达即 fail（而非静默发真实请求）。
class _UnusedLlmClient extends LlmClient {
  @override
  Future<void> streamChat(
    List<ChatMessage> messages,
    void Function(LlmStreamResponse response) callback, {
    CancelToken? cancelToken,
    Map<String, dynamic>? extraBody,
  }) async {
    fail('handleTrainingResult 不应发起 LLM 调用');
  }
}

/// T3-③：查询抛错仓储——锁定「检查失败不阻断教学」的放行路径。
class _ThrowingTrainingResultRepository extends TrainingResultRepository {
  _ThrowingTrainingResultRepository(AppDatabase db) : super(db);

  @override
  Future<List<TrainingResultRow>> queryBySyndrome(
    String syndromeId, {
    int limit = 50,
  }) async => throw StateError('T3-③ 模拟查询失败');
}

void main() {
  late AppDatabase db;
  late SessionRepository sessionRepo;
  late DiagnosisRepository diagnosisRepo;
  late StudentModelRepository studentModelRepo;
  late TrainingResultRepository trainingRepo;
  late String sessionId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sessionRepo = SessionRepository(db);
    diagnosisRepo = DiagnosisRepository(db);
    studentModelRepo = StudentModelRepository(db);
    trainingRepo = TrainingResultRepository(db);
    sessionId = await sessionRepo.createBlankSession();
  });

  tearDown(() async => db.close());

  /// 手工组装 DiagnosisFlowHandler（仅训练反馈路径所需依赖，
  /// 与 training_result_persistence_test 同一夹具）。
  DiagnosisFlowHandler buildHandler({required bool withTrainingResultRepo}) {
    DiagnosisCommitter committer() => DiagnosisCommitter(
      sessionRepo: sessionRepo,
      stateRepo: TeachingStateRepository(db),
      diagnosisRepo: DiagnosisRepository(db),
      studentModelRepo: StudentModelRepository(db),
      referenceRepo: ReferenceRepository(db),
      chapterRepo: ChapterRepository(db),
    );

    MessageInjector injector() => MessageInjector(
      sessionRepo: sessionRepo,
      diagnosisRepo: DiagnosisRepository(db),
      studentModelRepo: StudentModelRepository(db),
      referenceRepo: ReferenceRepository(db),
      chapterRepo: ChapterRepository(db),
      manuscriptRepo: ManuscriptRepository(db),
      diagnosisCommitter: committer(),
      material: const MaterialCapabilityImpl(),
    );

    return DiagnosisFlowHandler(
      sessionRepo: sessionRepo,
      stateRepo: TeachingStateRepository(db),
      diagnosisRepo: DiagnosisRepository(db),
      studentModelRepo: StudentModelRepository(db),
      referenceRepo: ReferenceRepository(db),
      chapterRepo: ChapterRepository(db),
      teacherSuggestionRepo: TeacherSuggestionRepository(db),
      llmClient: _UnusedLlmClient(),
      diagnosisCommitter: committer(),
      messageInjector: injector(),
      diagnosis: const DiagnosisCapabilityImpl(),
      genUi: const GenUiParser(),
      trainingResultRepo: withTrainingResultRepo ? trainingRepo : null,
    );
  }

  /// 模型原始回复：正文 + `[YS_TRAINING]` 协议块（prompt 要求的输出形态）
  const rawWithProtocol =
      '这次改得还是太急。\n[YS_TRAINING]\n'
      '{"result":"partial","reason":"方向对了，细节还要打磨"}\n'
      '[/YS_TRAINING]';

  SendMessageCallbacks cb() => SendMessageCallbacks(
    onStream: (_) {},
    onComplete: (_, __) {},
    onError: (_) {},
    onTrainingResult: (_) {},
  );

  /// 驱动一轮真实训练反馈（走 handleTrainingResult 全链：
  /// TH 追加 + FSM 重评估 + TR 落库）。
  Future<void> driveTrainingRound({String? syndromeId = 'P001'}) async {
    final handler = buildHandler(withTrainingResultRepo: true);
    final resolved = parseTrainingProtocol(rawWithProtocol)!.result;
    await handler.handleTrainingResult(
      sessionId: sessionId,
      currentSubphase: TeachingSubphase.feedback,
      displayContent: '这次改得还是太急。',
      userContent: '他攥紧拳头，指节发白。',
      trainingSyndromeId: syndromeId,
      activeProblems: const [],
      callbacks: cb(),
      trainingResult: resolved,
    );
  }

  /// TH 中的训练记录（功能轨）。
  Future<List<Map<String, dynamic>>> thTrainingRecords() async {
    final history = await studentModelRepo.getTeachingHistory(sessionId);
    return history.where((r) => r['type'] == 'training').toList();
  }

  // ═══════════════════════════════════════════════════════════
  // T1 覆盖契约：TH 训练记录 ⊇ TR 行，共享字段逐条一致
  // ═══════════════════════════════════════════════════════════
  group('T1 覆盖契约（TH ⊇ TR，方案 §4.1）', () {
    test('T1-1 单轮训练反馈 ⇒ TH 1 条 / TR 1 行，共享字段一致', () async {
      await driveTrainingRound();

      final th = await thTrainingRecords();
      final tr = await trainingRepo.queryBySession(sessionId);

      expect(th.length, 1, reason: '功能轨应落 1 条 training 记录');
      expect(tr.length, 1, reason: '记录轨应落 1 行');
      expect(
        th.length >= tr.length,
        isTrue,
        reason: '覆盖契约：TH 训练记录数 ≥ TR 行数（TH 先写，失败不连跳 TR）',
      );
      // 共享字段逐条一致（syndromeId / result 同源同值）
      expect(th.first['syndromeId'], tr.first.syndromeId);
      expect(th.first['result'], tr.first.result);
      // timestamp 两侧同为写入时刻 unix 秒（允许测试执行跨度）
      final thTs = th.first['timestamp'] as int;
      expect(
        (thTs - tr.first.createdAt).abs(),
        lessThanOrEqualTo(2),
        reason: '两侧时间戳应同为写入时刻（容 2 秒执行跨度）',
      );
    });

    test('T1-2 两轮训练反馈 ⇒ TH 2 条 / TR 2 行，按序逐条一致', () async {
      await driveTrainingRound();
      await driveTrainingRound();

      final th = await thTrainingRecords();
      final tr = await trainingRepo.queryBySession(sessionId);

      expect(th.length, 2);
      expect(tr.length, 2);
      expect(th.length >= tr.length, isTrue);
      // 按时间升序配对逐条核对（queryBySession 为倒序，反转后对齐）
      final thAsc = th.reversed.toList();
      final trAsc = tr.reversed.toList();
      for (var i = 0; i < trAsc.length; i++) {
        expect(thAsc[i]['syndromeId'], trAsc[i].syndromeId, reason: '第 $i 条症候');
        expect(thAsc[i]['result'], trAsc[i].result, reason: '第 $i 条结果');
      }
    });

    test('T1-3 无症候训练 ⇒ 双轨皆不写（0 ≥ 0 空满足）', () async {
      await driveTrainingRound(syndromeId: null);

      final th = await thTrainingRecords();
      final tr = await trainingRepo.queryBySession(sessionId);

      expect(th, isEmpty, reason: '无症候时 TH 不追加 training 记录');
      expect(tr, isEmpty, reason: '无症候时 TR 不落库');
      expect(th.length >= tr.length, isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // T2 双写一致：自评回写的仓储序列（_persistSelfAssessment 同序）
  // ═══════════════════════════════════════════════════════════
  group('T2 双写一致（自评回写序列，方案 §3.2-4）', () {
    /// 落一对「无自评」双轨记录（对齐生产：insert 不传 selfAssessment）。
    Future<String> seedDualTrackRow() async {
      await studentModelRepo.appendTeachingHistory(sessionId, {
        'type': 'training',
        'syndromeId': 'P001',
        'result': 'partial',
        'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'sessionId': sessionId,
      });
      return trainingRepo.insertTrainingResult(
        InsertTrainingResultParams(
          sessionId: sessionId,
          syndromeId: 'P001',
          taskType: 'rewrite',
          userContent: '他攥紧拳头，指节发白。',
          result: 'partial',
        ),
      );
    }

    /// 复刻 chat_teaching_controller._persistSelfAssessment 的仓储序列：
    /// 先写 TR 四列，再补 TH 副本（userRating 非空时）。
    Future<void> persistSelfAssessmentLikeController(
      TrainingSelfAssessment assessment,
    ) async {
      final latest = await trainingRepo.queryBySession(sessionId);
      if (latest.isEmpty) return;
      await trainingRepo.updateSelfAssessment(latest.first.id, assessment);
      if (assessment.userRating != null) {
        await studentModelRepo.updateLatestTrainingRating(
          sessionId,
          rating: assessment.userRating!,
          syndromeId: latest.first.syndromeId,
        );
      }
    }

    test('T2-1 正常路径：TR 四列与 TH 副本 userRating 一致', () async {
      await seedDualTrackRow();
      const assessment = TrainingSelfAssessment(
        confidenceRating: 4,
        explanationText: '因为主语要明确。我删掉了情绪词。',
        transferText: '换成对话我会先写动作。',
        userRating: 'good',
      );
      await persistSelfAssessmentLikeController(assessment);

      final tr = await trainingRepo.queryBySession(sessionId);
      expect(tr.single.confidenceRating, assessment.confidenceRating);
      expect(tr.single.explanationText, assessment.explanationText);
      expect(tr.single.transferText, assessment.transferText);
      expect(tr.single.userRating, assessment.userRating);

      final th = await thTrainingRecords();
      expect(
        th.last['userRating'],
        assessment.userRating,
        reason: 'TH 副本应补写同一 rating（FSRS 生效的是这份）',
      );
    });

    test('T2-2 任一方写失败不阻断另一方（现状语义锁定）', () async {
      await seedDualTrackRow();
      const assessment = TrainingSelfAssessment(
        confidenceRating: 4,
        explanationText: '因为主语要明确。我删掉了情绪词。',
        transferText: '换成对话我会先写动作。',
        userRating: 'good',
      );

      // ① TR 侧目标行不存在 ⇒ updateSelfAssessment 静默无感（0 行），不抛错
      await trainingRepo.updateSelfAssessment('non-existent-id', assessment);

      // ② TH 侧无 training 记录 ⇒ updateLatestTrainingRating 返回 false，不抛错
      //    （先造一个只有 diagnosis 历史的会话态）
      final otherSession = await sessionRepo.createBlankSession();
      await studentModelRepo.appendTeachingHistory(otherSession, {
        'type': 'diagnosis',
        'syndromes': ['P001'],
        'maxSeverity': 'L2',
        'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      });
      final thMiss = await studentModelRepo.updateLatestTrainingRating(
        otherSession,
        rating: 'good',
        syndromeId: 'P001',
      );
      expect(thMiss, isFalse, reason: '无 training 记录 ⇒ 静默返回 false');

      // ③ 正常回写仍可完成（前述失败不污染后续写入）
      await persistSelfAssessmentLikeController(assessment);
      final tr = await trainingRepo.queryBySession(sessionId);
      expect(tr.single.confidenceRating, 4);
      final th = await thTrainingRecords();
      expect(th.last['userRating'], 'good');
    });

    test('T2-3 userRating 为空 ⇒ TH 副本不补写（守卫锁定），TR 列照写', () async {
      await seedDualTrackRow();
      const assessment = TrainingSelfAssessment(
        confidenceRating: 3,
        explanationText: '因为主语要明确。我删掉了情绪词。',
        transferText: '换成对话我会先写动作。',
        // userRating 故意缺省
      );
      await persistSelfAssessmentLikeController(assessment);

      final tr = await trainingRepo.queryBySession(sessionId);
      expect(tr.single.confidenceRating, 3);
      expect(tr.single.userRating, isNull, reason: '未提供 rating ⇒ TR 列置空');

      final th = await thTrainingRecords();
      expect(
        th.last.containsKey('userRating'),
        isFalse,
        reason: '无 rating 时守卫跳过 TH 副本补写（不新增字段）',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════
  // T3 门控语义锁：mastered 软门控四种输入输出逐字锁定
  // ═══════════════════════════════════════════════════════════
  group('T3 门控语义锁（四放行路径 + 拦截路径，方案 §4.3）', () {
    /// mastered 候选夹具（对齐 evaluation_service_test #6 / c131）：
    /// consolidating 起点 + L3→L2→L1→L1→L1 诊断史 + 5 次 passed 训练。
    Future<void> seedMasteredCandidate() async {
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
            {'syndrome_id': 's1', 'name': '叙事含糊', 'severity': 'L2'},
          ],
          suggestedActions: const [],
          confidence: 0.8,
        ),
      );
      await diagnosisRepo.updateTeachingState(sessionId, 's1', 'consolidating');
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      int ts = now - 5000;
      for (final maxSeverity in ['L3', 'L2', 'L1', 'L1', 'L1']) {
        await studentModelRepo.appendTeachingHistory(sessionId, {
          'type': 'diagnosis',
          'syndromes': ['s1'],
          'maxSeverity': maxSeverity,
          'timestamp': ts,
          'sessionId': sessionId,
        });
        ts += 1000;
      }
      for (int i = 0; i < 5; i++) {
        await studentModelRepo.appendTeachingHistory(sessionId, {
          'type': 'training',
          'syndromeId': 's1',
          'result': 'passed',
          'timestamp': now + i,
        });
      }
    }

    Future<bool> s1StillActive() async {
      final active = await diagnosisRepo.listActiveProblems(sessionId);
      return active.any((p) => p.syndromeId == 's1');
    }

    test('T3-1 无自评行 ⇒ 放行，mastered 落库并解锁', () async {
      await seedMasteredCandidate();
      await trainingRepo.insertTrainingResult(
        InsertTrainingResultParams(
          sessionId: sessionId,
          syndromeId: 's1',
          taskType: 'rewrite',
          userContent: '（学员练习内容）',
          result: 'passed',
          // selfAssessment 故意不传 ⇒ 三列皆空
        ),
      );
      final service = EvaluationService(
        diagnosisRepo,
        studentModelRepo,
        trainingRepo,
      );

      final result = await service.computeRoundEvaluation(sessionId, 0);

      expect(
        result!.syndromeDetails
            .firstWhere((d) => d.syndromeId == 's1')
            .teachingState,
        TeachingState.mastered,
      );
      expect(
        await s1StillActive(),
        isFalse,
        reason: '路径①：latest 行无自评 ⇒ 放行（渐进 + R-009）',
      );
    });

    test('T3-2 repo 为 null（未装配仓储）⇒ 放行，mastered 落库并解锁', () async {
      await seedMasteredCandidate();
      final service = EvaluationService(diagnosisRepo, studentModelRepo);

      final result = await service.computeRoundEvaluation(sessionId, 0);

      expect(
        result!.syndromeDetails
            .firstWhere((d) => d.syndromeId == 's1')
            .teachingState,
        TeachingState.mastered,
      );
      expect(
        await s1StillActive(),
        isFalse,
        reason: '路径②：未装配仓储 ⇒ 门控整段跳过（X-041c 可选依赖语义）',
      );
    });

    test('T3-3 查询抛错 ⇒ 留痕后放行，mastered 落库并解锁', () async {
      await seedMasteredCandidate();
      final service = EvaluationService(
        diagnosisRepo,
        studentModelRepo,
        _ThrowingTrainingResultRepository(db),
      );

      final result = await service.computeRoundEvaluation(sessionId, 0);

      expect(
        result!.syndromeDetails
            .firstWhere((d) => d.syndromeId == 's1')
            .teachingState,
        TeachingState.mastered,
      );
      expect(
        await s1StillActive(),
        isFalse,
        reason: '路径③：检查失败不阻断教学（留痕 logSilentDegrade 后放行）',
      );
    });

    test('T3-4 低分自评行 ⇒ 拦截，mastered 不落库、症候保持活跃', () async {
      await seedMasteredCandidate();
      await trainingRepo.insertTrainingResult(
        InsertTrainingResultParams(
          sessionId: sessionId,
          syndromeId: 's1',
          taskType: 'rewrite',
          userContent: '（学员练习内容）',
          result: 'passed',
          selfAssessment: const TrainingSelfAssessment(
            confidenceRating: 2, // < 3 ⇒ 三维门拦截
            explanationText: '因为主语要明确。我删掉了情绪词。',
            transferText: '换成对话我会先写动作。',
          ),
        ),
      );
      final service = EvaluationService(
        diagnosisRepo,
        studentModelRepo,
        trainingRepo,
      );

      await service.computeRoundEvaluation(sessionId, 0);

      expect(
        await s1StillActive(),
        isTrue,
        reason: '路径④：低分自评 ⇒ 门控拦截 mastered 迁移（不写回、不解锁）',
      );
      final active = await diagnosisRepo.listActiveProblems(sessionId);
      final s1 = active.firstWhere((p) => p.syndromeId == 's1');
      expect(
        s1.teachingState,
        'consolidating',
        reason: '拦截 ⇒ teaching_state 保持 consolidating 原值',
      );
    });
  });
}
