// ─────────────────────────────────────────────────────────────
// 教学环境重验证（应用内构造 + Fake LLM）— 批次 25 步骤①
//
// 复刻批次 22 步骤③ 验收目标：buildSystemPromptV2 组装完整 prompt
// （L1+L2+L3）+ 教学上下文（学员画像）在真实教学链路中完整生效。
//
// 方法（对齐用户约束「构造后在应用里测试」）：
//   不直接调 LLM API，而是走 ChatService.sendMessage 完整链路，
//   用 CaptureLlmClient 捕获最终发给 LLM 的 system messages，断言：
//     - L1 常驻：核心铁三角 + 态度档位 + 位置判断引导语
//     - L2 按需：按教学语境决议的完整组（diagnosis/training/beginner）
//     - L3 检索：活跃症候完整定义 + 聚焦技法（仅活跃症候场景注入）
//     - 学员画像注入（有诊断历史时）
//     - token 预算合规（validatePrompt）
//
// 场景矩阵：
//   #1 P1 诊断（doubao，非零基础，无活跃症候）→ L2 diagnosis + 无 L3
//   #2 P2 训练（training 子阶段 + 活跃症候 P003）→ L2 training + L3 + 画像
//   #3 零基础（N1_ELEMENTS + P1）→ L2 beginner
//   #4 Sensei 态度（P1）→ attitude-sensei 注入（不含 doubao）
//   #5 token 预算：场景 #1-#4 的 system prompt 均 validatePrompt 通过
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
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/services/skill_dispatcher.dart';
import 'package:writingcoach/types/teaching_types.dart';

/// 捕获型 Fake LLM：记录每批发送给 LLM 的 messages + 回放预设流式响应
class CaptureLlmClient extends LlmClient {
  final String _fullResponse;

  /// 每次 streamChat 收到的完整 messages（含 system + history）
  final List<List<ChatMessage>> sentBatches = [];

  CaptureLlmClient([this._fullResponse = '好的，我来看看这段内容。']);

  @override
  Future<void> streamChat(
    List<ChatMessage> messages,
    void Function(LlmStreamResponse response) callback, {
    CancelToken? cancelToken,
  }) async {
    sentBatches.add(List.of(messages));
    callback(LlmStreamResponse(content: _fullResponse, isDone: false));
    callback(const LlmStreamResponse(content: '', isDone: true));
  }
}

void main() {
  late AppDatabase db;
  late SessionRepository sessionRepo;
  late String sessionId;
  late TeachingStateRepository stateRepo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sessionRepo = SessionRepository(db);
    stateRepo = TeachingStateRepository(db);
    sessionId = await sessionRepo.createBlankSession();
  });

  tearDown(() async => db.close());

  /// 构造 ChatService（注入捕获型 Fake LLM）
  ChatService buildChatService(LlmClient llmClient) {
    return ChatService(
      sessionRepo: sessionRepo,
      stateRepo: stateRepo,
      diagnosisRepo: DiagnosisRepository(db),
      studentModelRepo: StudentModelRepository(db),
      referenceRepo: ReferenceRepository(db),
      chapterRepo: ChapterRepository(db),
      manuscriptRepo: ManuscriptRepository(db),
      llmClient: llmClient,
      teacherSuggestionRepo: TeacherSuggestionRepository(db),
      editorObservationRepo: EditorObservationRepository(db),
      // ADR-C74 K-5：诊断提交编排器收紧为 required
      diagnosisCommitter: DiagnosisCommitter(
        sessionRepo: sessionRepo,
        stateRepo: stateRepo,
        diagnosisRepo: DiagnosisRepository(db),
        studentModelRepo: StudentModelRepository(db),
        referenceRepo: ReferenceRepository(db),
        chapterRepo: ChapterRepository(db),
      ),
    );
  }

  /// 执行一次 sendMessage（完整链路），返回捕获器
  Future<CaptureLlmClient> runSendMessage(
    LlmClient llmClient, {
    required TeachingPhase phase,
    AttitudeLevel attitude = AttitudeLevel.doubao,
    TeachingSubphase? subphase,
  }) async {
    // 批次6 M2：sendMessage 阶段上下文以 DB currentPhase 为准（DB 优先于 options.phase）。
    // 测试需先将目标阶段持久化到 DB，prompt 才能按目标阶段加载对应 L2 组。
    await stateRepo.updatePhase(sessionId, phase.value);
    final service = buildChatService(llmClient);
    await service.sendMessage(
      sessionId,
      '测试教学消息',
      SendMessageCallbacks(
        onStream: (_) {},
        onComplete: (_, _) {},
        onError: (_) {},
      ),
      SendMessageOptions(phase: phase, attitude: attitude),
      subphase: subphase,
    );
    return llmClient as CaptureLlmClient;
  }

  /// 拼接最近一批中所有 system 消息（L1+L2 prompt + 画像 + L3 + 引用）
  String systemText(CaptureLlmClient client) {
    if (client.sentBatches.isEmpty) return '';
    return client.sentBatches.last
        .where((m) => m.role == 'system')
        .map((m) => m.content)
        .join('\n\n---\n\n');
  }

  group('教学环境重验证（应用内构造）', () {
    test('#1 P1 诊断（doubao，无活跃症候）→ L1+L2(diagnosis)，无 L3', () async {
      final client = await runSendMessage(
        CaptureLlmClient(),
        phase: TeachingPhase.p1World,
      );
      final sys = systemText(client);

      // L1 常驻
      expect(sys, contains('铁三角'), reason: '缺 L1 核心铁三角');
      expect(sys, contains('位置判断'), reason: '缺位置判断引导语');
      // 态度档位
      expect(sys, contains('态度：豆包'), reason: '缺 attitude-doubao');
      // 表达密度小节随档位注入（批次 41）：doubao 示范只给最小可感知的一例
      expect(sys, contains('一次只抛一个点'), reason: 'doubao 档位缺表达密度小节');
      // L2 diagnosis 组
      expect(sys, contains('教学方法目录'), reason: '缺 L2 diagnosis 组');
      // 无活跃症候 → 不注入 L3
      expect(sys, isNot(contains('## 活跃症候详细定义')), reason: '无活跃症候不应注入 L3');
      // 临场输出约束（批次 41：表达密度规则近因生效）
      expect(sys, contains('临场输出约束'), reason: '缺临场输出约束注入');
    });

    test('#1b 临场输出约束注入在历史消息之前 + 完整内容', () async {
      final client = await runSendMessage(
        CaptureLlmClient(),
        phase: TeachingPhase.p1World,
      );
      final batch = client.sentBatches.last;
      // 约束为 system 角色，且位于历史 user/assistant 消息之前
      final constraintIndex = batch.indexWhere(
        (m) => m.role == 'system' && m.content.contains('临场输出约束'),
      );
      expect(constraintIndex, isNot(-1), reason: '缺临场输出约束 system 消息');
      // 约束之后的非 system 消息必须是历史消息（user 先行）
      final after = batch.sublist(constraintIndex + 1);
      expect(
        after.any((m) => m.role == 'user' && m.content == '测试教学消息'),
        isTrue,
        reason: '约束后应紧跟历史 user 消息',
      );
      // 内容完整（RN e8c46bb 三要素）
      final constraint = batch[constraintIndex].content;
      expect(constraint, contains('内部参考'), reason: '缺内部参考说明');
      expect(constraint, contains('一次只抛一个点'), reason: '缺表达密度规则');
      expect(constraint, contains('分轮展开'), reason: '缺分轮展开规则');
    });

    test('#2 P2 训练（training + 活跃症候 P003）→ L2(training) + L3 + 画像', () async {
      // 构造活跃症候 P003（诊断落库 → active_problem）
      await DiagnosisRepository(db).commitDiagnosis(
        DiagnosisInput(
          sessionId: sessionId,
          messageId: 'msg-p003',
          syndromes: [
            {
              'syndrome_id': 'P003',
              'name': '情绪标签化',
              'severity': 'L2',
              'evidence': <String>['他很难过。'],
              'explanation': '连续情绪标签，缺少行为化呈现',
            },
          ],
          suggestedActions: const [],
          confidence: 0.7,
        ),
      );

      final client = await runSendMessage(
        CaptureLlmClient(),
        phase: TeachingPhase.p2PracticeLoop,
        subphase: TeachingSubphase.practice,
      );
      final sys = systemText(client);

      // L1 常驻 + 态度
      expect(sys, contains('铁三角'));
      expect(sys, contains('态度：豆包'));
      // L2 training 组（V2 替换后）
      expect(sys, contains('训练循环指南'), reason: '缺 L2 training 组');
      // L3 症候详情 + 技法
      expect(sys, contains('## 活跃症候详细定义'), reason: '缺 L3 症候定义');
      expect(sys, contains('## 聚焦技法详细内容'), reason: '缺 L3 技法详情');
      expect(sys, contains('当前教学焦点 P003'), reason: '缺 focus 症候段落');
      // 学员画像注入（有诊断历史）
      expect(sys, contains('# 学员画像'), reason: '缺学员画像注入');
    });

    test('#3 零基础（N1_ELEMENTS + P1）→ L2 beginner 组', () async {
      await stateRepo.updateBeginnerLevel(sessionId, 'N1_ELEMENTS');

      final client = await runSendMessage(
        CaptureLlmClient(),
        phase: TeachingPhase.p1World,
      );
      final sys = systemText(client);

      expect(sys, contains('铁三角'));
      expect(sys, contains('零基础教学路径'), reason: '缺 L2 beginner 组');
    });

    test('#4 Sensei 态度（P1）→ attitude-sensei 注入，不含 doubao', () async {
      final client = await runSendMessage(
        CaptureLlmClient(),
        phase: TeachingPhase.p1World,
        attitude: AttitudeLevel.sensei,
      );
      final batch = client.sentBatches.last;
      // 在 L1+L2 system prompt（含 attitude-sensei）内断言档位专属内容
      final l1Prompt = batch
          .where((m) => m.role == 'system' && m.content.contains('态度：Sensei'))
          .first
          .content;

      expect(l1Prompt, contains('态度：Sensei'), reason: '缺 attitude-sensei');
      expect(
        l1Prompt,
        isNot(contains('态度：豆包')),
        reason: 'sensei 场景不应注入 doubao 档位',
      );
      // 表达密度小节随档位注入（批次 41）：sensei 无示范只给方向
      expect(l1Prompt, contains('无示范只给方向'), reason: 'sensei 档位缺表达密度小节');
      expect(
        l1Prompt,
        isNot(contains('示范只给最小可感知的一例')),
        reason: 'sensei 档位不应含 doubao/yuesheng 的示范规则',
      );
    });

    test('#5 token 预算合规：各场景 system prompt validatePrompt 通过', () async {
      // 场景 #1 P1 诊断
      final c1 = await runSendMessage(
        CaptureLlmClient(),
        phase: TeachingPhase.p1World,
      );
      // 场景 #2 P2 训练（含 L3 + 画像）
      await DiagnosisRepository(db).commitDiagnosis(
        DiagnosisInput(
          sessionId: sessionId,
          messageId: 'msg-token',
          syndromes: [
            {
              'syndrome_id': 'P003',
              'name': '情绪标签化',
              'severity': 'L2',
              'evidence': <String>['他很难过。'],
              'explanation': '',
            },
          ],
          suggestedActions: const [],
          confidence: 0.7,
        ),
      );
      final c2 = await runSendMessage(
        CaptureLlmClient(),
        phase: TeachingPhase.p2PracticeLoop,
        subphase: TeachingSubphase.practice,
      );
      // 场景 #3 beginner
      await stateRepo.updateBeginnerLevel(sessionId, 'N1_ELEMENTS');
      final c3 = await runSendMessage(
        CaptureLlmClient(),
        phase: TeachingPhase.p1World,
      );

      for (final entry in [
        ('P1 诊断', systemText(c1)),
        ('P2 训练(L3+画像)', systemText(c2)),
        ('beginner', systemText(c3)),
      ]) {
        final v = validatePrompt(entry.$2);
        expect(
          v.valid,
          isTrue,
          reason: '${entry.$1} token 预算超限: errors=${v.errors}',
        );
      }
    });

    test('#6 引用注入：主引用 + 附加引用均注入 system prompt（批次39 死数据修复回归）', () async {
      // 构造作品 + 两章节，主引用（isPrimary=1）+ 附加引用（isPrimary=0）
      final msRepo = ManuscriptRepository(db);
      final chRepo = ChapterRepository(db);
      final refRepo = ReferenceRepository(db);
      final msId = await msRepo.createManuscript(title: '测试小说');
      final chId = await chRepo.createChapter(
        msId,
        title: '第一章',
        content: '主引用正文AAA',
        sortOrder: 0,
      );
      final ch2Id = await chRepo.createChapter(
        msId,
        title: '第二章',
        content: '附加引用正文BBB',
        sortOrder: 1,
      );
      await refRepo.addReference(sessionId, 'chapter', chId, isPrimary: true);
      await refRepo.addReference(sessionId, 'chapter', ch2Id);

      final client = await runSendMessage(
        CaptureLlmClient(),
        phase: TeachingPhase.p1World,
      );
      final sys = systemText(client);

      expect(sys, contains('主引用正文AAA'), reason: '主引用正文未注入');
      expect(sys, contains('附加引用正文BBB'), reason: '附加引用正文未注入');
      expect(sys, contains('【主引用】'), reason: '主引用标注缺失');
    });
  });
}
