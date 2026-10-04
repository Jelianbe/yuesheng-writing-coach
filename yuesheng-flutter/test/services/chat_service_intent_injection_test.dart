// ─────────────────────────────────────────────────────────────
// chat_service_intent_injection_test — 批次63 B62b 意图注入测试
//
// 覆盖：
//   1. smalltalk → 注入「闲聊」system 消息 + 最近意图序列
//   2. ask → 注入「询问」消息
//   3. revise → 注入「修改」消息
//   4. compose → 不注入
//   5. 意图向量保留最近 3 条
// ─────────────────────────────────────────────────────────────

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/editor_observation_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/reference_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/data/repositories/student_model_repository.dart';
import 'package:writingcoach/data/repositories/teacher_suggestion_repository.dart';
import 'package:writingcoach/data/repositories/teaching_state_repository.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/services/chat_service.dart';
import 'package:writingcoach/services/diagnosis_committer.dart';
import 'package:writingcoach/services/message_injector.dart';
import 'package:writingcoach/services/chat_context_builder.dart'
    show MaterialCapabilityImpl;
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/types/teaching_types.dart';

import 'package:writingcoach/services/diagnosis_flow_handler.dart';
import 'package:writingcoach/services/diagnosis_parser.dart'
    show DiagnosisCapabilityImpl, parseDiagnosis;
import 'package:writingcoach/services/genui_parser.dart' show GenUiParser;
import 'package:writingcoach/services/chat_message_types.dart'
    show SendMessageCallbacks, SendMessageOptions;

import 'package:writingcoach/data/repositories/app_state_repository.dart';
import 'package:writingcoach/types/coach_persona.dart';

/// 捕获注入 messages 的 Fake LLM
class _CaptureLlmClient extends LlmClient {
  List<String> systemContents = [];
  List<String> capturedUserContent = [];

  /// ★ A-1：保留完整序列，供「注入位置」回归断言（此前只捕获内容，
  /// 导致「注入被挪走/挪错位置」无护栏）。
  List<ChatMessage> capturedMessages = [];

  @override
  Future<void> streamChat(
    List<ChatMessage> messages,
    void Function(LlmStreamResponse response) callback, {
    CancelToken? cancelToken,
    Map<String, dynamic>? extraBody,
  }) async {
    capturedMessages = List<ChatMessage>.from(messages);
    systemContents = messages
        .where((m) => m.role == 'system')
        .map((m) => m.content)
        .toList();
    // TH 五批：诊断协议注入的是 **user** 消息内容，需单独捕获
    capturedUserContent = messages
        .where((m) => m.role == 'user')
        .map((m) => m.content)
        .toList();
    callback(const LlmStreamResponse(content: '收到，我们继续。', isDone: false));
    callback(const LlmStreamResponse(content: '', isDone: true));
  }
}

/// G4（ADR-C113）：getActiveCoachPersonaId 抛错 → 触发
/// `_resolveDirectExplainThreshold` 的 catch 兜底（chat_service.dart:1268-1269）。
class _ThrowingAppStateRepo extends AppStateRepository {
  _ThrowingAppStateRepo(super.db);

  @override
  Future<String?> getActiveCoachPersonaId() async {
    throw StateError('test-active-id-throw');
  }
}

/// G1-a（ADR-C113）：固定返回 5 条 L2 症候诊断 JSON 的可计数 Fake。
/// callCount == 流式调用次数：1 = 仅主诊断流（Teacher 被短路）；2 = 主诊断 + Teacher。
class _FiveSyndromeLlmClient extends LlmClient {
  int callCount = 0;

  static const String _response =
      '你的文本问题较多。\n[YS_DIAGNOSIS]\n'
      '{"syndromes":['
      '{"syndrome_id":"s1","name":"n1","severity":"L2","evidence":[],"explanation":"t"},'
      '{"syndrome_id":"s2","name":"n2","severity":"L2","evidence":[],"explanation":"t"},'
      '{"syndrome_id":"s3","name":"n3","severity":"L2","evidence":[],"explanation":"t"},'
      '{"syndrome_id":"s4","name":"n4","severity":"L2","evidence":[],"explanation":"t"},'
      '{"syndrome_id":"s5","name":"n5","severity":"L2","evidence":[],"explanation":"t"}'
      '],"suggested_actions":[],"confidence":0.8}\n[/YS_DIAGNOSIS]';

  @override
  Future<void> streamChat(
    List<ChatMessage> messages,
    void Function(LlmStreamResponse response) callback, {
    CancelToken? cancelToken,
    Map<String, dynamic>? extraBody,
  }) async {
    callCount++;
    callback(const LlmStreamResponse(content: _response, isDone: false));
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
    LlmClient llmClient, {
    AppStateRepository? appStateRepo,
  }) {
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
      appStateRepo: appStateRepo,
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

  SendMessageCallbacks callbacks() => SendMessageCallbacks(
    onStream: (_) {},
    onComplete: (_, _) {},
    onError: (_) {},
  );

  SendMessageOptions options() => const SendMessageOptions(
    phase: TeachingPhase.p1World,
    attitude: AttitudeLevel.gentle,
  );

  bool hasIntentNote(List<String> systems, String marker) {
    return systems.any((s) => s.contains('## 交互意图') && s.contains(marker));
  }

  test('#1 smalltalk → 注入「闲聊」消息', () async {
    final llm = _CaptureLlmClient();
    final service = buildChatService(llm);

    await service.sendMessage(sessionId, '你好', callbacks(), options());
    await service.sendMessage(sessionId, '在吗', callbacks(), options());

    expect(llm.systemContents, isNotEmpty);
    // 至少一轮注入闲聊意图（第二轮的 systemContents 即本次）
    expect(hasIntentNote(llm.systemContents, '闲聊'), true);
    expect(llm.systemContents.join('\n'), contains('不要发起诊断'));
  });

  test('#2 ask → 注入「询问」消息', () async {
    final llm = _CaptureLlmClient();
    final service = buildChatService(llm);

    await service.sendMessage(sessionId, '这段对话怎么改更好？', callbacks(), options());

    expect(hasIntentNote(llm.systemContents, '询问'), true);
    expect(llm.systemContents.join('\n'), contains('不要展开新的诊断'));
  });

  test('#3 revise → 注入「修改」消息（降诊断强度 + 不替写）', () async {
    final llm = _CaptureLlmClient();
    final service = buildChatService(llm);

    await service.sendMessage(sessionId, '把这段对话改成动作描写', callbacks(), options());

    expect(hasIntentNote(llm.systemContents, '修改'), true);
    final joined = llm.systemContents.join('\n');
    expect(joined, contains('只提示最关键的问题'));
    expect(joined, contains('不替学员改写正文'));
  });

  test('#4 compose → 不注入意图消息', () async {
    final llm = _CaptureLlmClient();
    final service = buildChatService(llm);

    await service.sendMessage(
      sessionId,
      '他推开门，风灌了进来，桌上的信纸被吹落在地。',
      callbacks(),
      options(),
    );

    expect(hasIntentNote(llm.systemContents, '创作'), false);
    expect(llm.systemContents.any((s) => s.contains('## 交互意图')), false);
  });

  test('#5 意图向量保留最近 3 条（序列注入）', () async {
    final llm = _CaptureLlmClient();
    final service = buildChatService(llm);

    // 连续 4 条：ask → ask → smalltalk → ask；最后一条注入含最近 3 条意图
    await service.sendMessage(sessionId, '怎么提升节奏？', callbacks(), options());
    await service.sendMessage(sessionId, '为什么这段出戏？', callbacks(), options());
    await service.sendMessage(sessionId, '好的', callbacks(), options());
    await service.sendMessage(sessionId, '这段话是什么意思？', callbacks(), options());

    final joined = llm.systemContents.join('\n');
    // 最近 3 条意图 = smalltalk → ask（第一条 ask 已被挤出）
    expect(joined, contains('smalltalk → ask'));
    // 不应包含 4 条意图（只保留 3）
    expect(joined.contains('ask → ask → smalltalk → ask'), false);
  });

  test('#6 「长话短说」→ 注入压缩颗粒度消息', () async {
    final llm = _CaptureLlmClient();
    final service = buildChatService(llm);

    await service.sendMessage(sessionId, '这段怎么改，长话短说', callbacks(), options());

    expect(llm.systemContents.any((s) => s.contains('回复颗粒度：压缩')), true);
    expect(llm.systemContents.join('\n'), contains('一句话结论'));
    expect(llm.systemContents.join('\n'), contains('删除一切铺垫'));
  });

  test('#7 「详细点」→ 注入展开颗粒度消息', () async {
    final llm = _CaptureLlmClient();
    final service = buildChatService(llm);

    await service.sendMessage(sessionId, '再详细讲讲这个技巧', callbacks(), options());

    expect(llm.systemContents.any((s) => s.contains('回复颗粒度：展开')), true);
    expect(llm.systemContents.join('\n'), contains('完整示范'));
  });

  test('#8 无颗粒度信号 → 不注入颗粒度消息', () async {
    final llm = _CaptureLlmClient();
    final service = buildChatService(llm);

    await service.sendMessage(sessionId, '他推开门，风灌了进来', callbacks(), options());

    expect(llm.systemContents.any((s) => s.contains('回复颗粒度')), false);
  });

  // ─────────────────────────────────────────────────────────────
  // A-1 前缀稳定契约（2026-09-15）
  //
  // 背景：意图向量（滚动窗口）与颗粒度（依赖当前消息措辞）逐轮必变，
  // 且 `buildIntentInstruction` 在 compose 时返回 null ⇒ **整项消失**。
  // 二者原先排在注入段第 3/4 位，一旦变化/消失，其后所有消息（含**追加式
  // 历史**、Live 约束）索引整体前移 ⇒ 上下文缓存从该点起全断。
  // 真机实测（模拟器 + 真实 API，11 次调用）：稳态每轮 miss 固定
  // 5.0–5.3k tokens；探针确认公共前缀恰好止于注入段第 2 项之后。
  // ⇒ 契约：二者必须排在**最后一条 user 消息之后**。
  // ─────────────────────────────────────────────────────────────
  group('A-1 前缀稳定契约（注入位置）', () {
    test('#12 意图与颗粒度注入必须位于最后一条 user 消息之后', () async {
      final llm = _CaptureLlmClient();
      final service = buildChatService(llm);

      await service.sendMessage(
        sessionId,
        '这段对话怎么改更好？',
        callbacks(),
        options(),
      );
      await service.sendMessage(
        sessionId,
        '那我再试试这段怎么改，长话短说',
        callbacks(),
        options(),
      );

      final msgs = llm.capturedMessages;
      final intentIdx = msgs.indexWhere((m) => m.content.contains('## 交互意图'));
      final detailIdx = msgs.indexWhere((m) => m.content.contains('回复颗粒度'));
      final lastUserIdx = msgs.lastIndexWhere((m) => m.role == 'user');
      final disciplineIdx = msgs.indexWhere(
        (m) => m.content.contains('# 回复纪律（最后提醒）'),
      );

      expect(intentIdx, greaterThan(-1), reason: '本轮措辞应命中询问意图');
      expect(detailIdx, greaterThan(-1), reason: '「长话短说」应命中压缩颗粒度');
      expect(lastUserIdx, greaterThan(-1));

      // ★ 核心契约：排在历史之后 ⇒ 前缀不被逐轮必变项打断
      expect(
        intentIdx,
        greaterThan(lastUserIdx),
        reason: '意图注入必须先于最后一条 user 消息之后的任何位置之前',
      );
      expect(detailIdx, greaterThan(lastUserIdx));
      // 纪律重申仍居最末（保持既有「最后提醒」语义）
      expect(disciplineIdx, greaterThan(detailIdx));
    });

    test('#13 意图由注入/不注入切换时，历史段之前的消息序列不变', () async {
      final llm = _CaptureLlmClient();
      final service = buildChatService(llm);

      // 第一轮：ask ⇒ 注入意图；第二轮：compose ⇒ 意图整项消失
      await service.sendMessage(
        sessionId,
        '这段对话怎么改更好？',
        callbacks(),
        options(),
      );
      final first = List<ChatMessage>.from(llm.capturedMessages);
      await service.sendMessage(
        sessionId,
        '他推开门，风灌了进来，桌上的信纸被吹落在地。',
        callbacks(),
        options(),
      );
      final second = llm.capturedMessages;

      // 第二轮不再注入意图
      expect(second.any((m) => m.content.contains('## 交互意图')), false);

      // 两轮中「第一条 user 消息之前」的 system 序列必须逐字节一致
      // （= 前缀稳定：注入段不再随意图有无而错位）
      List<ChatMessage> headOf(List<ChatMessage> ms) {
        final cut = ms.indexWhere((m) => m.role == 'user');
        return cut <= 0 ? const [] : ms.sublist(0, cut);
      }

      final h1 = headOf(first);
      final h2 = headOf(second);
      expect(h1.length, h2.length);
      for (var i = 0; i < h1.length; i++) {
        expect(h2[i].content, h1[i].content, reason: '第 $i 条 system 前缀应稳定');
      }
    });
  });

  // ─────────────────────────────────────────────────────────────
  // TH 五批：诊断协议注入判据（措辞 + 会话级诊断上下文）
  //
  // 不能只靠字符串契约验证——注入的是 **user 消息**内容，必须看实际发出去的
  // user 消息是否带 `kDiagnosisProtocolSuffix`。命中后果不是措辞偏差：AI 出块后
  // `diagnosis_flow_handler.parseAndPersist` 只看块存在、不看场景 ⇒ 落库诊断
  // + 触发 Teacher 二次 API 调用。
  // ─────────────────────────────────────────────────────────────
  group('诊断协议注入判据（TH 五批）', () {
    test('#9 教学轮 + 弱信号措辞 → 不注入协议', () async {
      final llm = _CaptureLlmClient();
      final service = buildChatService(llm);

      // 无待诊断全文、会话无活跃症候 ⇒ 教学 / 自由对话轮次
      await service.sendMessage(
        sessionId,
        '这段怎么改更好一点？',
        callbacks(),
        options(),
      );

      final sent = llm.capturedUserContent.join('\n');
      expect(sent, isNot(contains('[YS_DIAGNOSIS]')));
      expect(sent, isNot(contains('用户明确请求诊断')));
    });

    test('#10 教学轮 + 强信号措辞 → 仍注入协议', () async {
      final llm = _CaptureLlmClient();
      final service = buildChatService(llm);

      await service.sendMessage(sessionId, '请诊断我这段文字', callbacks(), options());

      final sent = llm.capturedUserContent.join('\n');
      expect(sent, contains('[YS_DIAGNOSIS]'));
      expect(sent, contains('用户明确请求诊断'));
    });

    test('#11 带待诊断全文 + 弱信号措辞 → 注入协议（上下文成立）', () async {
      final llm = _CaptureLlmClient();
      final service = buildChatService(llm);

      await service.sendMessage(
        sessionId,
        '这段怎么改更好一点？',
        callbacks(),
        const SendMessageOptions(
          phase: TeachingPhase.p1World,
          attitude: AttitudeLevel.gentle,
          chapterFullText: '她推开门，发现房间里没有人。',
        ),
      );

      final sent = llm.capturedUserContent.join('\n');
      expect(sent, contains('[YS_DIAGNOSIS]'));
      expect(sent, contains('待诊断全文'));
    });

    // ★ 2026-10-04 新增（舰长真机 0.4.1 反馈：说问题时出现
    //   「【（症状名称）】：（症状说明）」这种答复结构）。
    //
    //   根因不在模型，在**同一条 user 消息里混了三套标记**：
    //     ·协议块   [YS_DIAGNOSIS]（方括号）
    //     · 全貌块   【症候过多时的全貌呈现】（六角括号）
    //     · 清单项   「序号. [P005] 症状名——落在哪句」（方括号 + 破折号）
    //   模型命中「症状数 ≥ threshold」的全貌分支时会把三套混编。
    //
    //   修法是**统一标记族 + 显式禁止括号包裹**。本组钉住两件事：
    //     ① 注入段内不再出现 【】 这一套标记；
    //     ② 全貌块带「不要把症候名用括号括起来」的显式约束。
    //   保留 [P005] 仍属必须——学员回「先练 P005」要能被 P00x 正则命中
    //   （message_injector._parseUserFocusFromMessage）。
    test('#22 诊断注入段内无【】标记（症状格式污染源）', () async {
      final llm = _CaptureLlmClient();
      final service = buildChatService(llm);

      await service.sendMessage(sessionId, '请诊断我这段文字', callbacks(), options());

      final sent = llm.capturedUserContent.join('\n');
      // 协议块与全貌块都用了【】，模型据此混编 ⇒ 断言已清除
      expect(
        sent,
        isNot(contains('【输出要求·最高优先级】')),
        reason: '协议块标题应改用方括号族（与 [YS_DIAGNOSIS] 同族）',
      );
      expect(sent, isNot(contains('【症候过多时的全貌呈现】')), reason: '全貌块标题应改用方括号族');
      expect(sent, contains('[全貌呈现]'), reason: '全貌块必须仍存在（选P 能力依赖它）');
    });

    test('#23 全貌清单显式禁止把症候名用括号包裹（正面堵混编）', () async {
      final llm = _CaptureLlmClient();
      final service = buildChatService(llm);

      await service.sendMessage(sessionId, '请诊断我这段文字', callbacks(), options());

      final sent = llm.capturedUserContent.join('\n');
      expect(sent, contains('不要把症候名用括号括起来'), reason: '混编的根因是格式指令含糊，必须正面禁止');
      // 清单项模板仍带 [P005]（学员选 P00x 要靠它）
      expect(sent, contains('[P005]'));
    });

    // 小项3（台账§一.17）：`kDiagnosisProtocolSuffix` 注入到 user 消息后，
    // 内嵌的 [YS_DIAGNOSIS] 示例 JSON 必须与解析器 schema 严格一致，否则 AI
    // 即便照抄示例也会因 `syndrome_item_not_object` / `confidence_invalid`
    // 被静默拒收。这里直接对「实际发出去的 user 消息」跑解析器（端到端，
    // 比单测常量字面量更强），防未来把示例改回「字符串数组 / 范围字符串 confidence」。
    test('#12 注入的协议后缀示例 JSON 可被 parseDiagnosis 解析（小项3 §一.17）', () async {
      final llm = _CaptureLlmClient();
      final service = buildChatService(llm);

      // 强信号措辞 → 触发诊断协议注入（同 #10 路径）
      await service.sendMessage(sessionId, '请诊断我这段文字', callbacks(), options());

      final sent = llm.capturedUserContent.join('\n');
      expect(sent, contains('[YS_DIAGNOSIS]'));

      // 对实际发出的 user 消息跑解析器：示例 JSON 须通过校验
      final result = parseDiagnosis(sent);
      expect(
        result.diagnosis,
        isNotNull,
        reason: '注入示例须通过解析器（syndromes 须为对象数组、confidence 须为 0-1 数字）',
      );
      expect(result.rejectReason, isNull, reason: '注入示例不应触发任何 rejectReason');
      expect(result.diagnosis!.syndromes.first.syndromeId, 'P001');
    });

    test('#13 直接说明指令注入默认阈值 5（无自定义人格 → 默认）', () async {
      final llm = _CaptureLlmClient();
      final service = buildChatService(llm);

      await service.sendMessage(sessionId, '请诊断我这段文字', callbacks(), options());

      final sent = llm.capturedUserContent.join('\n');
      expect(sent, contains('[YS_DIAGNOSIS]'));
      expect(sent, contains('症候数量 ≥ 5'));
      expect(sent, contains('编号列出全部症候'));
      // P0-2：0.3.3 三条新行为此前只守了一行，现逐条补断言——
      // 1. 全貌清单不给改法（负向约束）
      expect(sent, contains('不要给改法'), reason: '全貌模式必须明确不给改法');
      // 2. 末尾把选择权交给学员
      expect(sent, contains('你想先动哪个'), reason: '末尾必须反问先动哪个');
      // 3. 选定后才展开改法
      expect(sent, contains('学员选定一条后，才对那一条展开'), reason: '选定后才展开改法');
      // P0-1：清单必须同时输出症候编号，让 P00x 解析器命中学员选择
      expect(sent, contains('[P005]'), reason: '全貌清单须带症候编号示例');
    });

    test('#14 自定义人格阈值生效（激活人格 threshold=7 → 注入 ≥ 7）', () async {
      final llm = _CaptureLlmClient();
      final appState = AppStateRepository(db);
      await appState.saveCustomCoachPersona(
        CoachPersona(
          id: 'custom_t',
          name: '测',
          label: '测',
          isSystem: false,
          attitudeLevel: AttitudeLevel.gentle,
          systemPromptFragment: '测试',
          directExplainThreshold: 7,
        ),
      );
      await appState.setActiveCoachPersona('custom_t');
      final service = buildChatService(llm, appStateRepo: appState);

      await service.sendMessage(sessionId, '请诊断我这段文字', callbacks(), options());

      final sent = llm.capturedUserContent.join('\n');
      expect(sent, contains('症候数量 ≥ 7'));
      expect(sent, isNot(contains('症候数量 ≥ 5')));
    });

    test('#15 系统预设阈值覆盖生效（yuesheng 覆盖 8 → 注入 ≥ 8）', () async {
      final llm = _CaptureLlmClient();
      final appState = AppStateRepository(db);
      await appState.setActiveCoachPersona('yuesheng');
      await appState.setCoachPersonaDirectThreshold('yuesheng', 8);
      final service = buildChatService(llm, appStateRepo: appState);

      await service.sendMessage(sessionId, '请诊断我这段文字', callbacks(), options());

      final sent = llm.capturedUserContent.join('\n');
      expect(sent, contains('症候数量 ≥ 8'));
    });

    // P0-4：静默兜底路径——repo 存在但无 activeCoachPersonaId → 回退默认值 5。
    // 此前这两条 fallback（repo null / activeId null）连单测都没走到。
    test('#16 兜底：repo 存在但无 activeCoachPersonaId → 回退默认阈值 5', () async {
      final llm = _CaptureLlmClient();
      // 装配 repo 但从不 setActiveCoachPersona → getActiveCoachPersonaId 返回 null
      final appState = AppStateRepository(db);
      final service = buildChatService(llm, appStateRepo: appState);

      await service.sendMessage(sessionId, '请诊断我这段文字', callbacks(), options());

      final sent = llm.capturedUserContent.join('\n');
      expect(
        sent,
        contains('症候数量 ≥ 5'),
        reason: '无激活人格时必须回退默认阈值 kDefaultDirectExplainThreshold',
      );
    });

    // P0-4：repo 完全为 null（不传 appStateRepo）→ 也回退默认 5。
    // #13 已覆盖此路径（buildChatService(llm) 不传 repo），这里再显式断言常量值。
    test('#17 兜底：repo 为 null → 回退默认阈值 5', () async {
      final llm = _CaptureLlmClient();
      // 不传 appStateRepo → _appStateRepo == null → 第一条 return 兜底
      final service = buildChatService(llm);
      await service.sendMessage(sessionId, '请诊断我这段文字', callbacks(), options());
      final sent = llm.capturedUserContent.join('\n');
      expect(sent, contains('症候数量 ≥ 5'));
    });

    // G4（ADR-C113）：仍未覆盖的两条兜底分支——
    //   #18 = chat_service.dart:1267（activeId 既非 builtin、也不在 customs 列表里落空）
    //   #19 = chat_service.dart:1268-1269（catch 兜底）。
    // （:1254 repo==null 已被 #13/#17 守；:1257 activeId==null 已被 #16 守；
    //   builtin 分支已被 #15 守；customs 循环已被 #14 守——勿重复造。）
    test('#18 兜底：activeId 既非内置也不在自定义列表 → 落空回退默认阈值 5', () async {
      final llm = _CaptureLlmClient();
      final appState = AppStateRepository(db);
      // 写一个既非 builtin(gentle/yuesheng/sensei)、也未 save 成 custom 的 id：
      // builtInCoachPersonaById → null；getCustomCoachPersonas → []；循环不命中 ⇒ 落空分支。
      await appState.setActiveCoachPersona('no_such_persona_xyz');
      final service = buildChatService(llm, appStateRepo: appState);

      await service.sendMessage(sessionId, '请诊断我这段文字', callbacks(), options());

      final sent = llm.capturedUserContent.join('\n');
      expect(
        sent,
        contains('症候数量 ≥ 5'),
        reason: '未知 activeId 落空分支必须回退默认阈值 kDefaultDirectExplainThreshold',
      );
    });

    test('#19 兜底：读 activeId 抛异常 → catch 回退默认阈值 5 且不向上冒泡', () async {
      final llm = _CaptureLlmClient();
      final appState = _ThrowingAppStateRepo(db);
      final service = buildChatService(llm, appStateRepo: appState);

      // getActiveCoachPersonaId 抛错 ⇒ 必须被内部 catch 吞掉，sendMessage 不冒泡、注入仍为默认 5。
      await service.sendMessage(sessionId, '请诊断我这段文字', callbacks(), options());

      final sent = llm.capturedUserContent.join('\n');
      expect(sent, contains('症候数量 ≥ 5'), reason: 'catch 兜底分支必须回退默认阈值且不向上抛');
    });
  });

  // G1-a（ADR-C113）：Teacher 短路护栏——inDirectExplain 时「跳过本轮教师」，
  // 不替学员选一条直接讲（R-009）。用可计数 Fake 验证 callCount：
  //   Case 1 正向：默认阈值 5 + 5 症候 ≥ 5 ⇒ inDirectExplain ⇒ Teacher 0 次（callCount=1）
  //   Case 2 反面对照：阈值 99 + 5 症候 < 99 ⇒ 非全貌 ⇒ Teacher 1 次（callCount=2）
  //   Case 3 诊断边界：阈值 99（非全貌）+ 「只诊断」声明 ⇒ diagnosisOnly 独立阻断（callCount=1）
  group('G1-a Teacher directExplain 短路（ADR-C113）', () {
    test('Case1 默认阈值 5 + 5 条 L2 ⇒ inDirectExplain ⇒ Teacher 0 次', () async {
      final llm = _FiveSyndromeLlmClient();
      final service = buildChatService(llm); // appStateRepo=null → 阈值 5
      final phases = <bool>[];
      await service.sendMessage(
        sessionId,
        '帮我分析这段。',
        SendMessageCallbacks(
          onStream: (_) {},
          onComplete: (_, __) {},
          onError: (_) {},
          onTeacherPhase: (a) => phases.add(a),
        ),
        options(),
      );
      expect(
        llm.callCount,
        1,
        reason: '5 症候 ≥ 阈值 5 ⇒ inDirectExplain ⇒ 必须跳过本轮教师（只主诊断流 1 次）',
      );
      expect(phases, isEmpty, reason: 'Teacher 未触发 ⇒ onTeacherPhase 不应出现 true');
    });

    test('Case2 反向对照：阈值 99 + 5 条 L2 < 99 ⇒ 非全貌 ⇒ Teacher 1 次', () async {
      final llm = _FiveSyndromeLlmClient();
      final appState = AppStateRepository(db);
      await appState.setActiveCoachPersona('gentle');
      await appState.setCoachPersonaDirectThreshold('gentle', 99);
      final service = buildChatService(llm, appStateRepo: appState);
      await service.sendMessage(
        sessionId,
        '帮我分析这段。',
        SendMessageCallbacks(
          onStream: (_) {},
          onComplete: (_, __) {},
          onError: (_) {},
        ),
        options(),
      );
      expect(
        llm.callCount,
        2,
        reason: '5 < 99 ⇒ 非全貌 ⇒ Teacher 应触发一次（主诊断 + 教师共 2 次）',
      );
    });

    test('Case3 边界：阈值 99（非全貌）+「只诊断」⇒ diagnosisOnly 独立阻断 Teacher', () async {
      final llm = _FiveSyndromeLlmClient();
      final appState = AppStateRepository(db);
      await appState.setActiveCoachPersona('gentle');
      await appState.setCoachPersonaDirectThreshold('gentle', 99);
      final service = buildChatService(llm, appStateRepo: appState);
      await service.sendMessage(
        sessionId,
        '只诊断，帮我分析这段。',
        SendMessageCallbacks(
          onStream: (_) {},
          onComplete: (_, __) {},
          onError: (_) {},
        ),
        options(),
      );
      expect(
        llm.callCount,
        1,
        reason: 'diagnosisOnly=true 必须独立阻断 Teacher（即使非全貌、症候够多）',
      );
    });
  });
}
