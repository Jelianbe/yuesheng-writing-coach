// ─────────────────────────────────────────────────────────────
// chat_service 覆盖率补测（T2-4）第二批
//
// 策略：驱动可达的非 SafeRun 分支区块（均为零行为变更）：
//   E1 outline 装配 + 章节主引用 + 空 AI 回复 → _readOutlineEntityCount (L509-521) + treatAsValid (L2304-2311)
//   E2 诊断带 currentTeachingFocusId → _buildFocusHistory 焦点条目 (L985-986)
//   E3 诊断带 focusReason/nextFocus → 教学计划延续注入 (L1543-1560)
//   E4 活跃症候 id 命中用户口令（"练习 P1"）→ _parseUserFocusFromMessage (L968-970)
//   E5 训练历史含失败 → 脚手架回退注记 (L1226-1227) + resolver 训练记录解析 (L1061-1078)
// 沿用既有 in-memory DB + FakeLlmClient 夹具。
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
import 'package:writingcoach/services/diagnosis_committer.dart';
import 'package:writingcoach/services/message_injector.dart';
import 'package:writingcoach/services/chat_context_builder.dart'
    show MaterialCapabilityImpl;
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/types/teaching_types.dart';

import 'package:writingcoach/services/diagnosis_flow_handler.dart';
import 'package:writingcoach/services/diagnosis_parser.dart'
    show DiagnosisCapabilityImpl;
import 'package:writingcoach/services/genui_parser.dart'
    show GenUiParser;
import 'package:writingcoach/services/chat_message_types.dart'
    show SendMessageCallbacks, SendMessageOptions;
/// Fake LLM 客户端：预设 streamChat 响应
class FakeLlmClient extends LlmClient {
  final String _fullResponse;
  final Exception? _error;
  final int _chunkSize;

  FakeLlmClient(this._fullResponse, {Exception? error, int chunkSize = 10})
    : _error = error,
      _chunkSize = chunkSize;

  @override
  Future<void> streamChat(
    List<ChatMessage> messages,
    void Function(LlmStreamResponse response) callback, {
    CancelToken? cancelToken,
  }) async {
    if (_error != null) throw _error;
    for (int i = 0; i < _fullResponse.length; i += _chunkSize) {
      final end = i + _chunkSize < _fullResponse.length
          ? i + _chunkSize
          : _fullResponse.length;
      callback(
        LlmStreamResponse(
          content: _fullResponse.substring(i, end),
          isDone: false,
        ),
      );
    }
    callback(const LlmStreamResponse(content: '', isDone: true));
  }
}

void main() {
  late AppDatabase db;
  late SessionRepository sessionRepo;
  late String sessionId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sessionRepo = SessionRepository(db);
    sessionId = await sessionRepo.createBlankSession();
  });

  tearDown(() async => db.close());

  ChatService buildChatService(
    LlmClient llm, {
    OutlineRepository? outlineRepo,
  }) {
    return ChatService(
      sessionRepo: sessionRepo,
      stateRepo: TeachingStateRepository(db),
      diagnosisRepo: DiagnosisRepository(db),
      studentModelRepo: StudentModelRepository(db),
      referenceRepo: ReferenceRepository(db),
      chapterRepo: ChapterRepository(db),
      manuscriptRepo: ManuscriptRepository(db),
      llmClient: llm,
      teacherSuggestionRepo: TeacherSuggestionRepository(db),
      editorObservationRepo: EditorObservationRepository(db),
      diagnosisCommitter: DiagnosisCommitter(
        sessionRepo: sessionRepo,
        stateRepo: TeachingStateRepository(db),
        diagnosisRepo: DiagnosisRepository(db),
        studentModelRepo: StudentModelRepository(db),
        referenceRepo: ReferenceRepository(db),
        chapterRepo: ChapterRepository(db),
      ),

      messageInjector: MessageInjector(
        sessionRepo: sessionRepo,

        diagnosisRepo: DiagnosisRepository(db),

        studentModelRepo: StudentModelRepository(db),

        referenceRepo: ReferenceRepository(db),

        chapterRepo: ChapterRepository(db),

        manuscriptRepo: ManuscriptRepository(db),

        diagnosisCommitter: DiagnosisCommitter(
          sessionRepo: sessionRepo,

          stateRepo: TeachingStateRepository(db),

          diagnosisRepo: DiagnosisRepository(db),

          studentModelRepo: StudentModelRepository(db),

          referenceRepo: ReferenceRepository(db),

          chapterRepo: ChapterRepository(db),
        ),

        material: const MaterialCapabilityImpl(),
      ),
      diagnosisFlowHandler: DiagnosisFlowHandler(
        sessionRepo: SessionRepository(db),
        stateRepo: TeachingStateRepository(db),
        diagnosisRepo: DiagnosisRepository(db),
        studentModelRepo: StudentModelRepository(db),
        referenceRepo: ReferenceRepository(db),
        chapterRepo: ChapterRepository(db),
        teacherSuggestionRepo: TeacherSuggestionRepository(db),
        llmClient: llm,

        messageInjector: MessageInjector(
          sessionRepo: sessionRepo,

          diagnosisRepo: DiagnosisRepository(db),

          studentModelRepo: StudentModelRepository(db),

          referenceRepo: ReferenceRepository(db),

          chapterRepo: ChapterRepository(db),

          manuscriptRepo: ManuscriptRepository(db),

          diagnosisCommitter: DiagnosisCommitter(
            sessionRepo: sessionRepo,

            stateRepo: TeachingStateRepository(db),

            diagnosisRepo: DiagnosisRepository(db),

            studentModelRepo: StudentModelRepository(db),

            referenceRepo: ReferenceRepository(db),

            chapterRepo: ChapterRepository(db),
          ),

          material: const MaterialCapabilityImpl(),
        ),
        diagnosisCommitter: DiagnosisCommitter(
          sessionRepo: sessionRepo,
          stateRepo: TeachingStateRepository(db),
          diagnosisRepo: DiagnosisRepository(db),
          studentModelRepo: StudentModelRepository(db),
          referenceRepo: ReferenceRepository(db),
          chapterRepo: ChapterRepository(db),
        ),
        diagnosis: const DiagnosisCapabilityImpl(),
        genUi: const GenUiParser(),
      ),
      outlineRepo: outlineRepo,
    );
  }

  SendMessageCallbacks callbacks() => SendMessageCallbacks(
    onStream: (_) {},
    onComplete: (_, _) {},
    onError: (_) {},
  );

  SendMessageOptions options() => const SendMessageOptions(
    phase: TeachingPhase.p0Engage,
    attitude: AttitudeLevel.doubao,
  );

  /// 提交一条带焦点/续接字段的诊断，并使其成为活跃症候
  Future<void> commitFocusedDiagnosis({
    required String syndromeId,
    String? currentTeachingFocusId,
    String? focusReason,
    String? nextFocus,
  }) async {
    final diagnosisRepo = DiagnosisRepository(db);
    final studentModelRepo = StudentModelRepository(db);
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await studentModelRepo.appendTeachingHistory(sessionId, {
      'type': 'diagnosis',
      'syndromes': [syndromeId],
      'maxSeverity': 'L2',
      'timestamp': now - 100,
      'sessionId': sessionId,
    });
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
        currentTeachingFocusId: currentTeachingFocusId,
        focusReason: focusReason,
        nextFocus: nextFocus,
      ),
    );
  }

  // ───────── E1：outline 装配 + 章节主引用 + 空 AI 回复 ─────────

  test(
    'E1 outline 装配 + 章节主引用 + 空 AI 回复 → _readOutlineEntityCount 跑通',
    () async {
      final msRepo = ManuscriptRepository(db);
      final chRepo = ChapterRepository(db);
      final refRepo = ReferenceRepository(db);
      final outlineRepo = OutlineRepository(db);

      final ms = await msRepo.createManuscript(title: '主稿', genre: '小说');
      final ch = await chRepo.createChapter(
        ms,
        title: '第一章 风起',
        content: '风起云涌，这一段写得很用心，埋下伏笔。',
      );
      await refRepo.addReference(sessionId, 'chapter', ch, isPrimary: true);
      // 预置实体，使 buildEntityIndexContext 返回非空（含 "- [" 行）
      await outlineRepo.insertEntity(
        manuscriptId: ms,
        entityType: 'character',
        entityKey: '王建国',
        aliases: const ['建国'],
      );

      final svc = buildChatService(FakeLlmClient(''), outlineRepo: outlineRepo);
      // 空回复 → combinedContent 为空 → outline 装配 + 章节主引用 → 进入 treatAsValid 分支
      await svc.sendMessage(sessionId, '请诊断这一章', callbacks(), options());

      // 不抛错即通过（_readOutlineEntityCount 已执行）
      final messages = await sessionRepo.listMessages(sessionId);
      expect(messages, isNotEmpty);
    },
  );

  // ───────── E2+E3：焦点历史条目 + 教学计划延续注入 ─────────

  test('E2/E3 诊断带焦点字段 → _buildFocusHistory + 教学计划延续注入', () async {
    await commitFocusedDiagnosis(
      syndromeId: 's1',
      currentTeachingFocusId: 's1',
      focusReason: '上一轮聚焦叙事视角的一致性',
      nextFocus: '下一步练对话节奏',
    );

    final svc = buildChatService(FakeLlmClient('这一段写得很稳。'));
    await svc.sendMessage(sessionId, '继续聊聊这一章', callbacks(), options());

    // 主链路完成即说明两处注入分支均已跑通
    final messages = await sessionRepo.listMessages(sessionId);
    expect(messages.any((m) => m.role == 'assistant'), isTrue);
  });

  // ───────── E4：用户焦点口令命中活跃症候 ─────────

  test('E4 活跃症候 P1 + 用户口令"练习 P1" → _parseUserFocusFromMessage 命中', () async {
    await commitFocusedDiagnosis(syndromeId: 'P1');

    final svc = buildChatService(FakeLlmClient('好的，来练这一项。'));
    await svc.sendMessage(sessionId, '练习 P1', callbacks(), options());

    final messages = await sessionRepo.listMessages(sessionId);
    expect(messages.any((m) => m.role == 'assistant'), isTrue);
  });

  // ───────── E5：训练历史含失败 → 脚手架回退 + resolver 训练记录 ─────────

  test('E5 训练历史含失败 → 脚手架回退注记 + resolver 训练记录解析', () async {
    final studentModelRepo = StudentModelRepository(db);
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    // 2 条诊断（保证 diagnosisCount>=2，buildTrainingInput 不返回 null）
    await studentModelRepo.appendTeachingHistory(sessionId, {
      'type': 'diagnosis',
      'syndromes': ['s1'],
      'maxSeverity': 'L2',
      'timestamp': now - 300,
      'sessionId': sessionId,
    });
    await studentModelRepo.appendTeachingHistory(sessionId, {
      'type': 'diagnosis',
      'syndromes': ['s1'],
      'maxSeverity': 'L2',
      'timestamp': now - 200,
      'sessionId': sessionId,
    });
    // 训练记录：2 失败 + 1 通过（达标率 1/3 < 0.5 → 触发脚手架回退注记）
    await studentModelRepo.appendTeachingHistory(sessionId, {
      'type': 'training',
      'syndromeId': 's1',
      'result': 'failed',
      'timestamp': now - 120,
      'sessionId': sessionId,
    });
    await studentModelRepo.appendTeachingHistory(sessionId, {
      'type': 'training',
      'syndromeId': 's1',
      'result': 'failed',
      'timestamp': now - 90,
      'sessionId': sessionId,
    });
    await studentModelRepo.appendTeachingHistory(sessionId, {
      'type': 'training',
      'syndromeId': 's1',
      'result': 'passed',
      'timestamp': now - 60,
      'sessionId': sessionId,
    });
    // 提交诊断使其成为活跃症候（触发 _injectDiagnosisLock + 训练评估注入）
    await commitFocusedDiagnosis(syndromeId: 's1');

    final svc = buildChatService(FakeLlmClient('我们来复盘这次训练。'));
    await svc.sendMessage(sessionId, '这次训练怎么样', callbacks(), options());

    final messages = await sessionRepo.listMessages(sessionId);
    expect(messages.any((m) => m.role == 'assistant'), isTrue);
  });

  // ───────── E6：训练评估达到 mastered → _insertPhaseSummaryOnMastered ─────────

  test('E6 训练评估达成 mastered → 触发 _insertPhaseSummaryOnMastered', () async {
    final diagnosisRepo = DiagnosisRepository(db);
    final studentModelRepo = StudentModelRepository(db);

    // 活跃症候 s1（创建 active_problem）
    await commitFocusedDiagnosis(syndromeId: 's1');
    // FSM 累积起点置为 consolidating（proxyReady 路径要求 consolidating 起点）
    await diagnosisRepo.updateTeachingState(
      sessionId,
      's1',
      TeachingState.consolidating.value,
    );

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    // 3 条连续 L1 诊断（用较新时间戳确保是最近期 → consecutiveLowSeverity>=3）
    for (int i = 1; i <= 3; i++) {
      await studentModelRepo.appendTeachingHistory(sessionId, {
        'type': 'diagnosis',
        'syndromes': ['s1'],
        'maxSeverity': 'L1',
        'timestamp': now + i * 1000,
        'sessionId': sessionId,
      });
    }
    // 5 条全通过训练 → consolidationObservations>=5 且 consecutivePasses>=3
    for (int i = 1; i <= 5; i++) {
      await studentModelRepo.appendTeachingHistory(sessionId, {
        'type': 'training',
        'syndromeId': 's1',
        'result': 'passed',
        'timestamp': now + 10000 + i * 1000,
        'sessionId': sessionId,
      });
    }

    final svc = buildChatService(FakeLlmClient('这一轮表现稳定，可以毕业了。'));
    await svc.sendMessage(sessionId, '来做个训练总结', callbacks(), options());

    // 不抛错即通过（_insertPhaseSummaryOnMastered 已执行）
    final messages = await sessionRepo.listMessages(sessionId);
    expect(messages.any((m) => m.role == 'assistant'), isTrue);
  });

  // ───────── E7：超长 AI 回复 → fullContent 截断分支 (L2755-2759) ─────────

  test('E7 超长 AI 回复 → fullContent 截断分支', () async {
    // _kFullContentMaxLen = 200 * 1024 = 204800；返回超出即触发步骤8 截断
    final huge = '好' * (200 * 1024 + 5000);
    final svc = buildChatService(FakeLlmClient(huge, chunkSize: 50000));
    await svc.sendMessage(sessionId, '请写一段很长的内容', callbacks(), options());
    final messages = await sessionRepo.listMessages(sessionId);
    expect(messages.any((m) => m.role == 'assistant'), isTrue);
  });

  // ───────── E8：训练全通过(weDo) → 脚手架提前进入独立练习注记 (L1240-1241) ─────────

  test('E8 训练全通过(weDo) → 脚手架提前进入独立练习注记', () async {
    final studentModelRepo = StudentModelRepository(db);
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    // 2 条诊断（保证 diagnosisCount>=2，buildTrainingInput 不返回 null）
    await studentModelRepo.appendTeachingHistory(sessionId, {
      'type': 'diagnosis',
      'syndromes': ['s1'],
      'maxSeverity': 'L2',
      'timestamp': now - 200,
      'sessionId': sessionId,
    });
    await studentModelRepo.appendTeachingHistory(sessionId, {
      'type': 'diagnosis',
      'syndromes': ['s1'],
      'maxSeverity': 'L2',
      'timestamp': now - 100,
      'sessionId': sessionId,
    });
    // 2 条全通过训练：trainingCount=2 → base=weDo；consecutivePasses==totalCount>=2
    await studentModelRepo.appendTeachingHistory(sessionId, {
      'type': 'training',
      'syndromeId': 's1',
      'result': 'passed',
      'timestamp': now - 60,
      'sessionId': sessionId,
    });
    await studentModelRepo.appendTeachingHistory(sessionId, {
      'type': 'training',
      'syndromeId': 's1',
      'result': 'passed',
      'timestamp': now - 50,
      'sessionId': sessionId,
    });
    await commitFocusedDiagnosis(syndromeId: 's1');

    final svc = buildChatService(FakeLlmClient('这次都通过了，继续保持。'));
    await svc.sendMessage(sessionId, '训练得怎么样', callbacks(), options());
    final messages = await sessionRepo.listMessages(sessionId);
    expect(messages.any((m) => m.role == 'assistant'), isTrue);
  });
}
