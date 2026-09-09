// ─────────────────────────────────────────────────────────────
// 诊断落库序列「两条路径一致」契约测试 — CR-50（第八批 services 审查）
//
// 背景：ADR-C74 K-9 把 chat_service 拆成 DiagnosisFlowHandler /
// DiagnosisCommitter 后，widget 端 commitDiagnosisFromContent（超长分块
// 诊断 >4000 字）与 ChatService 内部 commitDiagnosisAndSuggestions（单次
// 诊断 ≤4000 字）各自实现了一份「提交历史 → 重置子阶段 → 卡片 → 阶段迁移
// → 风格画像」，但**顺序不一致**：前者「卡片→阶段迁移」，后者「阶段迁移
// →卡片」。两者都经 sessionRepo.addMessage 写 messages 表，而阶段迁移
// 内部还会插 phase_upgrade 卡 → 同一份诊断在长短文本下卡片排列相反。
//
// 本文件把「两条路径产出相同的卡片序列」钉成契约：任何一侧未来调整顺序
// 而另一侧没跟上，这里立刻红。此前**没有任何测试触达该顺序**——
// 这正是它能静默存在的原因。
// ─────────────────────────────────────────────────────────────

// ignore_for_file: prefer_initializing_formals, unnecessary_underscores

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
import 'package:writingcoach/services/chat_context_builder.dart'
    show MaterialCapabilityImpl;
import 'package:writingcoach/services/chat_message_types.dart'
    show SendMessageCallbacks, SendMessageOptions;
import 'package:writingcoach/services/diagnosis_committer.dart';
import 'package:writingcoach/services/diagnosis_flow_handler.dart';
import 'package:writingcoach/services/diagnosis_parser.dart'
    show DiagnosisCapabilityImpl;
import 'package:writingcoach/services/genui_parser.dart' show GenUiParser;
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/services/message_injector.dart';
import 'package:writingcoach/types/teaching_types.dart';

class FakeLlmClient extends LlmClient {
  FakeLlmClient(this._fullResponse);

  final String _fullResponse;

  @override
  Future<void> streamChat(
    List<ChatMessage> messages,
    void Function(LlmStreamResponse response) callback, {
    CancelToken? cancelToken,
  }) async {
    if (_fullResponse.isNotEmpty) {
      callback(LlmStreamResponse(content: _fullResponse, isDone: false));
    }
    callback(const LlmStreamResponse(content: '', isDone: true));
  }
}

const _p0Options = SendMessageOptions(
  phase: TeachingPhase.p0Engage,
  attitude: AttitudeLevel.doubao,
);

void main() {
  late AppDatabase db;
  late SessionRepository sessionRepo;
  late TeachingStateRepository stateRepo;
  late DiagnosisRepository diagnosisRepo;
  late StudentModelRepository studentModelRepo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sessionRepo = SessionRepository(db);
    stateRepo = TeachingStateRepository(db);
    diagnosisRepo = DiagnosisRepository(db);
    studentModelRepo = StudentModelRepository(db);
  });

  tearDown(() async => db.close());

  /// 诊断响应：带 suggested_phase → 触发阶段迁移路径（会产生升级卡）。
  String resp() =>
      '诊断完成。'
      '\n[YS_DIAGNOSIS]'
      '\n{"syndromes":[{"syndrome_id":"s1","name":"叙事含糊","severity":"L2",'
      '"evidence":[],"explanation":"测试"}],"suggested_actions":[],'
      '"confidence":0.8,"suggested_phase":"P1_WORLD"}'
      '\n[/YS_DIAGNOSIS]';

  DiagnosisCommitter buildCommitter() => DiagnosisCommitter(
    sessionRepo: sessionRepo,
    stateRepo: stateRepo,
    diagnosisRepo: diagnosisRepo,
    studentModelRepo: studentModelRepo,
    referenceRepo: ReferenceRepository(db),
    chapterRepo: ChapterRepository(db),
  );

  DiagnosisFlowHandler buildHandler() => DiagnosisFlowHandler(
    sessionRepo: sessionRepo,
    stateRepo: stateRepo,
    diagnosisRepo: diagnosisRepo,
    studentModelRepo: studentModelRepo,
    referenceRepo: ReferenceRepository(db),
    chapterRepo: ChapterRepository(db),
    teacherSuggestionRepo: TeacherSuggestionRepository(db),
    llmClient: FakeLlmClient(resp()),
    messageInjector: MessageInjector(
      sessionRepo: sessionRepo,
      diagnosisRepo: DiagnosisRepository(db),
      studentModelRepo: StudentModelRepository(db),
      referenceRepo: ReferenceRepository(db),
      chapterRepo: ChapterRepository(db),
      manuscriptRepo: ManuscriptRepository(db),
      diagnosisCommitter: buildCommitter(),
      material: const MaterialCapabilityImpl(),
    ),
    diagnosisCommitter: buildCommitter(),
    diagnosis: const DiagnosisCapabilityImpl(),
    genUi: const GenUiParser(),
  );

  /// 种子教学状态 P0/N3 → P1_WORLD 为合法相邻递进。
  Future<String> seedSession() async {
    final sid = await sessionRepo.createBlankSession();
    await stateRepo.updatePhase(sid, TeachingPhase.p0Engage.value);
    await stateRepo.updateBeginnerLevel(sid, BeginnerLevel.n3Diagnose.value);
    return sid;
  }

  /// 取该会话消息流中的卡片类型序列（只保留诊断卡与阶段升级卡）。
  Future<List<String>> cardTypes(String sid) async {
    final msgs = await sessionRepo.listMessages(sid);
    return msgs
        .where(
          (m) =>
              m.messageType == 'diagnosis_result' ||
              m.messageType == 'phase_upgrade',
        )
        .map((m) => m.messageType!)
        .toList();
  }

  /// 路径 A：widget 端超长分块诊断入口。
  Future<List<String>> runPathA() async {
    final sid = await seedSession();
    await buildHandler().commitDiagnosisFromContent(
      sessionId: sid,
      fullContent: resp(),
    );
    return cardTypes(sid);
  }

  /// 路径 B：ChatService 内部单次诊断入口（parseAndPersist + 落库两步）。
  Future<List<String>> runPathB() async {
    final sid = await seedSession();
    final handler = buildHandler();
    final parsed = await handler.parseAndPersist(
      sessionId: sid,
      fullContent: resp(),
      inDiagnosisBlock: true,
      primaryRef: null,
      chapterContent: null,
      callbacks: SendMessageCallbacks(
        onStream: (_) {},
        onComplete: (_, __) {},
        onError: (_) {},
      ),
      options: _p0Options,
    );
    if (parsed.aborted) return const [];
    await handler.commitDiagnosisAndSuggestions(
      sessionId: sid,
      diagnosis: parsed.diagnosis,
      messageId: parsed.messageId,
      primaryRef: null,
      teacherResult: parsed.teacherResult,
      rapidFire: false,
      flowBypassed: false,
      genuiComponents: parsed.genuiComponents,
    );
    return cardTypes(sid);
  }

  test('#1 两条路径都产出卡片（前置：本测试确实触达了落库序列）', () async {
    final a = await runPathA();
    final b = await runPathB();
    expect(a, isNotEmpty, reason: '路径A 未产出任何卡片，后续断言无意义');
    expect(b, isNotEmpty, reason: '路径B 未产出任何卡片，后续断言无意义');
  });

  test('#2 核心契约：两条路径的卡片顺序完全一致', () async {
    final a = await runPathA();
    final b = await runPathB();
    expect(
      a,
      equals(b),
      reason:
          '两条诊断路径的卡片序列必须一致 —— '
          '不一致说明又出现了两份落库实现（P1-13）',
    );
  });

  test('#3 顺序为「诊断卡 → 阶段升级卡」（先结果后升级）', () async {
    final b = await runPathB();
    if (b.contains('phase_upgrade')) {
      expect(b.first, 'diagnosis_result');
    }
  });
}
