// ─────────────────────────────────────────────────────────────
// C121-1 批「模拟诊断」闭环验证（仅测试层模拟 LLM，不改产品运行时）
//
// 背景（G1 缺口）：无 Key 离线示例分支（llm_client.dart cfg==null）只回固定
//   教学文案、不含诊断块 ⇒ diagnosis_results 不落库。本测试用测试替身
//   FakeLlmClient（与 chat_service_send_message_test.dart 同一 @override 契约）
//   返回一段「教练安全反馈 + [YS_DIAGNOSIS] 协议块」，走真实 ChatService 诊断链，
//   断言 C121-1 微任务提交后的闭环：
//     微任务素材文本（≥50 字，对齐 kMicroTaskMinChars）
//       → ChatService.sendMessage（= ChatTeachingController.handleSend 的服务层等价）
//       → _writeUserMessage → _applyDiagnosisInjection → _runDiagnosisFlow
//       → DiagnosisFlowHandler.parseAndPersist / commitDiagnosisAndSuggestions
//       → diagnosis_results 落库（症候 / 严重度 / 训练动作 suggested_actions）
//       + 教练安全反馈渲染（assistant 消息 = 症候识别 + 训练引导，不含代写形态）
//
// 边界（R-009 / R-010）：
//   - 模拟 LLM 只存在于本测试层；产品运行时的离线示例分支一行未改。
//   - 模拟反馈刻意写成「只识别症候 + 给训练引导」，不代写句子 / 不打分 / 不给处方。
//   - 本文件为新增测试，不改动任何 lib/ 产品代码。
//
// 覆盖映射（既有测试已覆盖、本测试不重复造）：
//   - ui_e2e_test.dart E2E-3：widget 级「发送→诊断卡渲染→diagnosis_results/
//     active_problems 落库」（短聊天输入、断言 history 非空 + active 含 P002）。
//   - chat_service_send_message_test.dart：诊断块拦截 / teacher 段 / 协议块剥离。
//   - pilot_llm_sim_test.dart：解析层 R-009 / teacher 一致性（无 P0xx 泄漏）。
//   本测试补的断言缺口 = 微任务≥50字素材文本 + diagnosis_results 字段级
//   （syndrome_id/severity/suggestedActions）+ 教练反馈文本 R-009 形态审计。
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/editor_observation_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
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
import 'package:writingcoach/services/genui_parser.dart' show GenUiParser;
import 'package:writingcoach/services/chat_message_types.dart'
    show SendMessageCallbacks, SendMessageOptions;

/// 测试替身：模拟「有 LLM 响应」时教练的安全诊断输出。
///
/// 与 chat_service_send_message_test.dart 的 FakeLlmClient 同一 @override 契约：
/// 只 override streamChat，把预设文本按 chunk 推给真实 ChatService。
/// 预设文本 = 教练安全反馈（症候识别 + 训练引导，无代写）+ [YS_DIAGNOSIS] 块。
class _CoachSimLlmClient extends LlmClient {
  final String _fullResponse;
  int callCount = 0;

  _CoachSimLlmClient(this._fullResponse);

  @override
  Future<void> streamChat(
    List<ChatMessage> messages,
    void Function(LlmStreamResponse response) callback, {
    CancelToken? cancelToken,
    Map<String, dynamic>? extraBody,
  }) async {
    callCount++;
    // 一次推完（单 chunk 即可；拦截逻辑对单 chunk 与跨 chunk 等价）。
    callback(LlmStreamResponse(content: _fullResponse, isDone: false));
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

  /// 构造真实 ChatService（注入模拟 LLM）。装配与
  /// chat_service_send_message_test.dart.buildChatService 逐一对齐。
  ChatService buildChatService(LlmClient llmClient) {
    return ChatService(
      sessionRepo: sessionRepo,
      stateRepo: TeachingStateRepository(db),
      diagnosisRepo: DiagnosisRepository(db),
      studentModelRepo: StudentModelRepository(db),
      referenceRepo: ReferenceRepository(db),
      chapterRepo: ChapterRepository(db),
      manuscriptRepo: ManuscriptRepository(db),
      llmClient: llmClient,
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
        llmClient: llmClient,
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
    );
  }

  const defaultOptions = SendMessageOptions(
    phase: TeachingPhase.p0Engage,
    attitude: AttitudeLevel.gentle,
  );

  test('C121-1 微任务素材提交 → 模拟诊断链完整落库（症候/严重度/训练动作）+ 教练安全反馈', () async {
    // ── 微任务素材：对齐 narrate_morning 卡，≥50 字（kMicroTaskMinChars）──
    // 刻意带「他很着急」这种情绪标签句，喂给模拟教练。
    const microTaskText =
        '闹钟响了三遍他才睁眼。天花板有一块水渍。'
        '他很着急，怕迟到，抓起外套就往外冲，鞋都没换好。'
        '然后他在楼道里想起母亲的话，停了一下。';
    expect(
      microTaskText.length,
      greaterThanOrEqualTo(50),
      reason: '前置：微任务素材须达可诊断门槛（与卡片墙提交门槛一致）',
    );

    // ── 模拟 LLM 响应：教练安全反馈（症候识别 + 训练引导，不代写）+ 诊断块 ──
    // R-009：反馈只指出「情绪被直接报出」并引导「挑一处落到动作上」，
    //   不给出改写后的句子、不打分、不开处方。
    const llmResponse =
        '我读了你这段早晨。时间线从睁眼到出门是顺的。'
        '注意到「他很着急」是把情绪直接报了出来，'
        '读者还没从动作里自己感到它——情绪被你替读者说了。'
        '先不急着改全篇，挑这一处，把它落到一个身体动作上：'
        '肩、脚、呼吸任选一个，让读者自己感到急。\n'
        '[YS_DIAGNOSIS]\n'
        '{"syndromes":[{"syndrome_id":"P002","name":"情绪标签化","severity":"L1",'
        '"evidence":["他很着急，怕迟到"],'
        '"explanation":"情绪直接点破，未转化为动作或细节"}],'
        '"suggested_actions":["挑一处情绪句，把标签词换成一个身体动作，只改一处"],'
        '"confidence":0.7}\n'
        '[/YS_DIAGNOSIS]';

    final llm = _CoachSimLlmClient(llmResponse);
    final chatService = buildChatService(llm);

    String? completeContent;
    await chatService.sendMessage(
      sessionId,
      microTaskText,
      SendMessageCallbacks(
        onStream: (_) {},
        onComplete: (content, _) => completeContent = content,
        onError: (e) => fail('不应报错：$e'),
      ),
      defaultOptions,
    );

    // ── 环节①：用户素材落库在前，教练反馈落库在后 ──
    // 注：诊断结果卡由 DiagnosisFlowHandler._insertDiagnosisResultCard 另插一条
    // messageType='diagnosis_result' 的 assistant 行，故消息总数 ≥3（user + 反馈 + 卡）。
    final messages = await sessionRepo.listMessages(sessionId);
    expect(
      messages.length,
      greaterThanOrEqualTo(2),
      reason: '至少 user 素材 + assistant 教练反馈',
    );
    expect(messages[0].role, 'user');
    expect(messages[0].content, contains('闹钟响了三遍'));

    // 教练自由文本反馈（非诊断卡）：含症候识别句的那条 assistant 消息
    final feedbackMsgs = messages
        .where(
          (m) => m.role == 'assistant' && m.messageType != 'diagnosis_result',
        )
        .toList();
    expect(feedbackMsgs, isNotEmpty, reason: '应有教练自由文本反馈消息');
    final feedback = feedbackMsgs.first.content;

    // 诊断结果卡另插一条（结构化卡渲染的落库证据）
    final diagCards = messages
        .where((m) => m.messageType == 'diagnosis_result')
        .toList();
    expect(diagCards, isNotEmpty, reason: '诊断结果卡应随诊断一并插入消息流');

    // ── 环节②：diagnosis_results 落库（症候 / 严重度 / 训练动作）──
    final diagRepo = DiagnosisRepository(db);
    final history = await diagRepo.listDiagnosisHistory(sessionId);
    expect(history, hasLength(1), reason: '模拟有诊断响应 ⇒ 应有 1 条 diagnosis_results');
    final row = history.first;

    final syndromes = (jsonDecode(row.syndromes) as List)
        .whereType<Map<String, dynamic>>()
        .toList();
    expect(syndromes, isNotEmpty);
    final p002 = syndromes.firstWhere(
      (s) => s['syndrome_id'] == 'P002',
      orElse: () => fail('diagnosis_results.syndromes 应含 P002'),
    );
    expect(p002['name'], '情绪标签化');
    expect(p002['severity'], 'L1', reason: '严重度应落库为 L1');

    // 训练动作（suggested_actions）非空 —— 这是「训练动作」字段的落库证据
    final actions = (jsonDecode(row.suggestedActions) as List)
        .whereType<dynamic>()
        .toList();
    expect(actions, isNotEmpty, reason: 'suggested_actions（训练动作）应落库');
    expect(actions.join('|'), contains('身体动作'));

    // ── 环节③：active_problems 同步落库 ──
    final active = await diagRepo.listActiveProblems(sessionId);
    expect(
      active.map((p) => p.syndromeId),
      contains('P002'),
      reason: 'P002 应进入活跃问题表',
    );

    // ── 环节④：教练安全反馈渲染（assistant 消息，feedback 已在环节①取出）──
    // 协议块对用户不可见（诊断 JSON 不得上屏）
    expect(
      feedback.contains('[YS_DIAGNOSIS]'),
      isFalse,
      reason: '诊断协议块应被剥离，不得进用户可见文本',
    );
    expect(completeContent, isNotNull);
    expect(completeContent!.contains('[YS_DIAGNOSIS]'), isFalse);
    // 症候识别：反馈应点出「情绪被直接报出」这一观察
    expect(
      feedback,
      contains('情绪直接报了出来'),
      reason: '教练反馈应做症候识别（指出问题），而非只说「诊断完成」',
    );
    // 训练引导：反馈应指向「落到身体动作」的训练方向
    expect(feedback, contains('身体动作'));

    // ── 环节⑤：R-009 审计 —— 反馈无代写 / 打分 / 处方形态 ──
    final writingDone = RegExp(r'例如|范文|比如你可以改|评分|打分为|分数是').hasMatch(feedback);
    expect(
      writingDone,
      isFalse,
      reason:
          '教练反馈不得代写句子(例如/范文)、不得打分(评分/分数)——'
          '只做症候识别 + 训练引导',
    );

    // ── 环节⑥：轻度 L1 首诊不触发 Teacher 二次流（callCount==1）──
    expect(
      llm.callCount,
      1,
      reason:
          '单条 L1 症候不达 Teacher 触发线（L2/L3 或 ≥3 条），'
          '冷启动首诊不应追加第二次 LLM 调用',
    );
  });
}
