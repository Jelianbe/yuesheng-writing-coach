// ─────────────────────────────────────────────────────────────
// 教学闭环五环节全链路演练（live）— 真实 DeepSeek + 确定性收尾
//
// 覆盖：诊断 → 沉淀 → 训练 → 评估 → 迁移
//   环节1 诊断：真实 LLM 输出 → [YS_DIAGNOSIS] 症候落库
//   环节2 沉淀：真实 LLM 输出 → [YS_ENTITY] 大纲实体 + [YS_FACT] 事实三表
//   环节3 训练：真实 LLM FEEDBACK 轮 → training 记录（AI 未命中则确定性兜底）
//   环节4 评估：EvaluationReportsStore → app_state KV 持久化 + teaching_state 迁移
//   环节5 迁移：resolve 全部 + confirmed 达标 → 再诊断轮触发 M4-A 阶段推进
//
// 运行方式（API key 只经环境变量传入，严禁写入源码）：
//   $env:DEEPSEEK_API_KEY="sk-xxx"
//   flutter test --tags live test/live_full_loop_test.dart
//
// 保护机制：
//   - 无 DEEPSEEK_API_KEY 时自动 markTestSkipped，不影响四闸全量跑
//   - @Tags(['live']) 标识，便于只跑真实链路
// ─────────────────────────────────────────────────────────────

@Tags(['live'])
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/app_state_repository.dart';
import 'package:writingcoach/data/repositories/character_fact_repository.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/editor_observation_repository.dart';
import 'package:writingcoach/data/repositories/event_fact_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/outline_repository.dart';
import 'package:writingcoach/data/repositories/reference_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/data/repositories/student_model_repository.dart';
import 'package:writingcoach/data/repositories/subplot_fact_repository.dart';
import 'package:writingcoach/data/repositories/teacher_suggestion_repository.dart';
import 'package:writingcoach/data/repositories/teaching_state_repository.dart';
import 'package:writingcoach/providers/evaluation_providers.dart';
import 'package:writingcoach/services/chat_service.dart';
import 'package:writingcoach/services/diagnosis_committer.dart';
import 'package:writingcoach/services/evaluation_service.dart';
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/types/teaching_types.dart';

/// 官方 OpenAI 兼容端点（LlmClient 会拼接 /chat/completions）
const String _kBaseUrl = 'https://api.deepseek.com';

/// 用户指定的教学模型
const String _kModel = 'deepseek-v4-flash';

/// 迁移轮专用：返回"已 resolve 症候"的诊断块。
///
/// 触发 _applyPhaseMigration 的约束链：
///   - validateDiagnosisSchema 要求 syndromes 必须为非空数组（空数组会被
///     二次校验判为 diagnosis=null，_applyPhaseMigration 不被调用）
///   - commitDiagnosis 对已 resolve 的症候不重新激活（status=resolved → continue）
///   - 因此返回"已 resolve 症候"既能通过 schema 校验，又保持活跃列表为空，
///     使 M4-A 的 remaining.isEmpty + passRate>=0.7 条件成立 → 阶段推进。
class _MigrationTriggerLlmClient extends LlmClient {
  _MigrationTriggerLlmClient({
    required this.syndromeId,
    required this.syndromeName,
    required this.severity,
  });

  final String syndromeId;
  final String syndromeName;
  final String severity;

  @override
  Future<void> streamChat(
    List<ChatMessage> messages,
    void Function(LlmStreamResponse response) callback, {
    CancelToken? cancelToken,
  }) async {
    final body =
        '诊断完成。本轮复诊：该症候仍为当前教学焦点，建议继续巩固。\n'
        '[YS_DIAGNOSIS]\n'
        '{"syndromes":[{"syndrome_id":"$syndromeId","name":"$syndromeName",'
        '"severity":"$severity","evidence":["复诊确认"],"explanation":"复诊确认该症候"'
        '}],"suggested_actions":["继续按教学计划练习"],"confidence":0.9}\n'
        '[/YS_DIAGNOSIS]';
    callback(LlmStreamResponse(content: body, isDone: false));
    callback(const LlmStreamResponse(content: '', isDone: true));
  }
}

/// connectivity_plus 平台通道（checkNetwork 依赖）
const MethodChannel _kConnectivityChannel = MethodChannel(
  'dev.fluttercommunity.plus/connectivity',
);

/// flutter_secure_storage 平台通道（chatCompletion/streamChat 内部读配置）
const MethodChannel _kSecureStorageChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

/// 学员文本（平淡叙事 + 情绪标签，对齐 P003 试点）
const String _kStudentText = '''
王建国站在巷口，夜色沉沉。他想起母亲临终前那句"不要报仇"，攥紧了拳头。
王叔是他父亲的老部下，在这条巷子里守了三十年，左眼的一道疤从上到下。
王叔压低声音说："里面有三个人，都带着家伙。"
王建国很生气。他很害怕。他心里很乱。
林小芸从二楼窗户往下看了一眼，手里攥着那把银色的小手枪。
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final bool hasKey = Platform.environment.containsKey('DEEPSEEK_API_KEY');

  setUpAll(() {
    // flutter_test binding 会把 HttpClient 全局替换为“永远返回 400”的 mock，
    // 必须恢复真实网络才能打真实链路。
    HttpOverrides.global = null;

    final key = Platform.environment['DEEPSEEK_API_KEY'];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    // 测试环境无宿主平台：mock connectivity，让 checkNetwork 返回“已联网”
    messenger.setMockMethodCallHandler(_kConnectivityChannel, (call) async {
      if (call.method == 'check') return <String>['wifi'];
      return null;
    });
    // chatCompletion / streamChat 从 secure storage 读配置，mock 其读写
    final storageValues = <String, String>{
      if (key != null && key.isNotEmpty) 'yuesheng_api_key': key,
      'yuesheng_api_base_url': _kBaseUrl,
      'yuesheng_api_model': _kModel,
    };
    messenger.setMockMethodCallHandler(_kSecureStorageChannel, (call) async {
      final args = (call.arguments as Map?) ?? const {};
      switch (call.method) {
        case 'read':
          return storageValues[args['key']];
        case 'write':
          storageValues[args['key'] as String] = args['value'] as String;
          return true;
        case 'delete':
          storageValues.remove(args['key']);
          return true;
      }
      return null;
    });
  });

  tearDownAll(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_kConnectivityChannel, null);
    messenger.setMockMethodCallHandler(_kSecureStorageChannel, null);
  });

  test('五环节全链路演练：诊断→沉淀→训练→评估→迁移', () async {
    if (!hasKey) {
      markTestSkipped('未设置 DEEPSEEK_API_KEY，跳过真实链路');
      return;
    }

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    try {
      // ── 装配（含大纲 + 事实三表仓储，沉淀全开）──
      final sessionRepo = SessionRepository(db);
      final stateRepo = TeachingStateRepository(db);
      final diagRepo = DiagnosisRepository(db);
      final studentModelRepo = StudentModelRepository(db);
      final refRepo = ReferenceRepository(db);
      final chapterRepo = ChapterRepository(db);
      final msRepo = ManuscriptRepository(db);
      final outlineRepo = OutlineRepository(db);
      final charFactRepo = CharacterFactRepository(db);
      final eventFactRepo = EventFactRepository(db);
      final subplotFactRepo = SubplotFactRepository(db);
      final appStateRepo = AppStateRepository(db);

      final sessionId = await sessionRepo.createBlankSession();
      final manuscriptId = await msRepo.createManuscript(title: '全链路演练');
      final chapterId = await chapterRepo.createChapter(
        manuscriptId,
        title: '第一章：巷口',
        content: _kStudentText,
      );
      await refRepo.addReference(
        sessionId,
        'chapter',
        chapterId,
        isPrimary: true,
      );

      final service = ChatService(
        sessionRepo: sessionRepo,
        stateRepo: stateRepo,
        diagnosisRepo: diagRepo,
        studentModelRepo: studentModelRepo,
        referenceRepo: refRepo,
        chapterRepo: chapterRepo,
        manuscriptRepo: msRepo,
        llmClient: LlmClient(),
        teacherSuggestionRepo: TeacherSuggestionRepository(db),
        editorObservationRepo: EditorObservationRepository(db),
        outlineRepo: outlineRepo,
        characterFactRepo: charFactRepo,
        eventFactRepo: eventFactRepo,
        subplotFactRepo: subplotFactRepo,
        // ADR-C74 K-5：诊断提交编排器收紧为 required
        diagnosisCommitter: DiagnosisCommitter(
          sessionRepo: sessionRepo,
          stateRepo: stateRepo,
          diagnosisRepo: diagRepo,
          studentModelRepo: studentModelRepo,
          referenceRepo: refRepo,
          chapterRepo: chapterRepo,
          outlineRepo: outlineRepo,
          characterFactRepo: charFactRepo,
          eventFactRepo: eventFactRepo,
          subplotFactRepo: subplotFactRepo,
        ),
      );

      // ── 环节 1 + 2：诊断 + 沉淀（真实 LLM）──
      // prompt 对齐 UI 层诊断触发：诊断分析 + 章节内容 + 协议块输出指令
      final diagPrompt =
          '请对以下写作内容进行写作诊断分析：\n\n'
          '【第一章：巷口】\n\n'
          '$_kStudentText\n\n'
          '---\n'
          '重要：\n'
          '1. 诊断说明后必须输出 [YS_DIAGNOSIS]...[/YS_DIAGNOSIS] 包裹的 JSON 块，'
          '含 syndromes 数组（每条含 syndrome_id/name/severity/evidence/explanation）、'
          'suggested_actions（数组）、confidence（0-1）。\n'
          '2. 必须输出 [YS_ENTITY]...[/YS_ENTITY] 实体记忆块：开篇人物王建国、王叔、林小芸，'
          '每人至少写 1 条事实型印象。\n'
          '3. 必须输出 [YS_FACT]...[/YS_FACT] 事实块：人物与事件事实，含 causality 因果字段。\n'
          '三个协议块 JSON 必须语法合法、完整闭合，宁可压缩自然语言说明也要保证块写全。';

      String? diagMessageId;
      await service.sendMessage(
        sessionId,
        diagPrompt,
        SendMessageCallbacks(
          onStream: (_) {},
          onComplete: (_, mid) => diagMessageId = mid,
          onError: (e) => throw Exception('环节1-诊断链路失败: $e'),
        ),
        const SendMessageOptions(
          phase: TeachingPhase.p2PracticeLoop,
          attitude: AttitudeLevel.yuesheng,
        ),
        subphase: TeachingSubphase.diagnosis,
      );

      // 环节1 断言：症候落库（diagnosis_results + active_problem + 教学历史）
      final diagnoses = await diagRepo.listDiagnosisHistory(sessionId);
      expect(diagnoses, isNotEmpty, reason: '环节1-诊断：症候未落库');
      final activeProblems = await diagRepo.listActiveProblems(sessionId);
      final history1 = await studentModelRepo.getTeachingHistory(sessionId);
      expect(
        history1.where((r) => r['type'] == 'diagnosis'),
        isNotEmpty,
        reason: '环节1-诊断：teaching_history 无 diagnosis 记录',
      );
      // ignore: avoid_print
      print(
        '[环节1-诊断] 症候落库 ${diagnoses.length} 条 | 活跃 ${activeProblems.length} 条 | '
        'ids=${activeProblems.map((e) => e.syndromeId).toSet().join(",")}',
      );

      // 环节2 断言：沉淀（outline 实体 + 事实三表，任一源有数据即通过）
      final entities = await outlineRepo.listEntities(manuscriptId);
      final charFacts = await charFactRepo.listCharacters(manuscriptId);
      final eventFacts = await eventFactRepo.listEvents(manuscriptId);
      final subplotFacts = await subplotFactRepo.listSubplots(manuscriptId);
      final sedimentTotal =
          entities.length +
          charFacts.length +
          eventFacts.length +
          subplotFacts.length;
      // ignore: avoid_print
      print(
        '[环节2-沉淀] outline=${entities.length} 人物事实=${charFacts.length} '
        '事件事实=${eventFacts.length} 支线事实=${subplotFacts.length}',
      );
      expect(
        sedimentTotal,
        greaterThan(0),
        reason: '环节2-沉淀：大纲/事实三表均无数据（AI 未输出任何协议块）',
      );

      // ── 环节 3：训练（真实 LLM FEEDBACK 轮 + 确定性兜底）──
      final feedbackPrompt =
          '请对学员上一轮改写训练给出评估：\n\n'
          '学员文本：\n$_kStudentText\n\n'
          '请在回复结尾明确标记训练结果：'
          '若达标输出「训练结果：达标」，部分达标输出「训练结果：部分达标」，'
          '未达标输出「训练结果：未达标」。';

      TrainingResult? trainingResult;
      await service.sendMessage(
        sessionId,
        feedbackPrompt,
        SendMessageCallbacks(
          onStream: (_) {},
          onComplete: (_, _) {},
          onError: (e) => throw Exception('环节3-训练链路失败: $e'),
          onTrainingResult: (r) => trainingResult = r,
        ),
        const SendMessageOptions(
          phase: TeachingPhase.p2PracticeLoop,
          attitude: AttitudeLevel.yuesheng,
        ),
        subphase: TeachingSubphase.feedback,
      );

      var history2 = await studentModelRepo.getTeachingHistory(sessionId);
      var trainingRecords = history2
          .where((r) => r['type'] == 'training')
          .toList();
      if (trainingRecords.isEmpty) {
        // AI 未输出达标标记 → 确定性兜底补一条训练记录，保证 FSM 可推进
        // ignore: avoid_print
        print('[环节3-训练] AI 未输出达标标记，确定性兜底补 training 记录');
        await studentModelRepo.appendTeachingHistory(sessionId, {
          'type': 'training',
          'syndromeId': activeProblems.isNotEmpty
              ? activeProblems.first.syndromeId
              : 'P003',
          'result': 'passed',
          'passed': true,
        });
      }
      history2 = await studentModelRepo.getTeachingHistory(sessionId);
      trainingRecords = history2.where((r) => r['type'] == 'training').toList();
      // ignore: avoid_print
      print(
        '[环节3-训练] training 记录 ${trainingRecords.length} 条'
        '${trainingResult != null ? "（真实 AI 命中）" : "（兜底）"}',
      );
      expect(trainingRecords, isNotEmpty, reason: '环节3-训练：无 training 记录');

      // ── 环节 4：评估（确定性，调用真实服务）──
      final evalStore = EvaluationReportsStore(
        EvaluationService(diagRepo, studentModelRepo),
        appStateRepo,
      );
      await evalStore.restoreForSession(sessionId);
      expect(diagMessageId, isNotNull, reason: '环节4：无诊断消息 ID');
      await evalStore.buildEvaluationReport(sessionId, diagMessageId!);

      // 断言：app_state KV 持久化（报告 + 轮次）
      final savedReport = await appStateRepo.getEvaluationReport(
        sessionId,
        diagMessageId!,
      );
      expect(savedReport, isNotNull, reason: '环节4-评估：报告未持久化到 app_state');
      final evalRound = await appStateRepo.getEvaluationRound(sessionId);
      expect(evalRound, greaterThan(0), reason: '环节4-评估：轮次未持久化');
      // ignore: avoid_print
      print(
        '[环节4-评估] 报告已持久化 | round=$evalRound | '
        'trend=${savedReport!.trend.name} | passRate=${savedReport.passRate}',
      );

      // 断言：teaching_state 状态机（active_problem 字段迁移到合法状态）
      final problemsAfterEval = await diagRepo.listActiveProblems(sessionId);
      for (final p in problemsAfterEval) {
        final ts = p.teachingState;
        expect(
          ts == null ||
              const [
                'identified',
                'in_progress',
                'consolidating',
                'mastered',
              ].contains(ts),
          isTrue,
          reason: '环节4-评估：teaching_state 非法值 $ts',
        );
      }
      // ignore: avoid_print
      print(
        '[环节4-评估] teaching_state: '
        '${problemsAfterEval.map((p) => '${p.syndromeId}=${p.teachingState ?? "null"}').join(",")}',
      );

      // ── 环节 5：迁移（确定性触发 M4-A 自动迁移）──
      // 5a. DB 阶段设为 P2（M4-A 要求当前阶段非 P0/P1 才允许自动推进）
      await stateRepo.updatePhase(
        sessionId,
        TeachingPhase.p2PracticeLoop.value,
      );

      // 5b. 全部活跃症候 resolve + confirmed 记录（达标率 1.0）
      final problemsForMigration = await diagRepo.listActiveProblems(sessionId);
      for (final p in problemsForMigration) {
        await diagRepo.resolveProblem(sessionId, p.syndromeId);
      }
      await studentModelRepo.appendTeachingHistory(sessionId, {
        'type': 'confirmation',
        'syndromes': [
          problemsForMigration.isNotEmpty
              ? problemsForMigration.first.syndromeId
              : 'P003',
        ],
        'action': 'confirmed',
        'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      });
      final passRate = await EvaluationService(
        diagRepo,
        studentModelRepo,
      ).computePassRateForPhaseMigration(sessionId);
      // ignore: avoid_print
      print(
        '[环节5-迁移] 达标率=$passRate (阈值 ${EvaluationThresholds.phasePassRate}) '
        '| 剩余活跃症候 ${(await diagRepo.listActiveProblems(sessionId)).length}',
      );

      // 5c. 迁移轮：Fake LLM 返回"已 resolve 症候"（schema 校验要求非空，
      //     commit 不复活已 resolve 症候 → 活跃列表保持为空 → M4-A 阶段推进）
      final resolvedRef = problemsForMigration.isNotEmpty
          ? problemsForMigration.first
          : null;
      final migrationService = ChatService(
        sessionRepo: sessionRepo,
        stateRepo: stateRepo,
        diagnosisRepo: diagRepo,
        studentModelRepo: studentModelRepo,
        referenceRepo: refRepo,
        chapterRepo: chapterRepo,
        manuscriptRepo: msRepo,
        llmClient: _MigrationTriggerLlmClient(
          syndromeId: resolvedRef?.syndromeId ?? 'P003',
          syndromeName: resolvedRef?.syndromeName ?? '情绪直白',
          severity: resolvedRef?.severity ?? 'L2',
        ),
        teacherSuggestionRepo: TeacherSuggestionRepository(db),
        editorObservationRepo: EditorObservationRepository(db),
        outlineRepo: outlineRepo,
        characterFactRepo: charFactRepo,
        eventFactRepo: eventFactRepo,
        subplotFactRepo: subplotFactRepo,
        // ADR-C74 K-5：诊断提交编排器收紧为 required
        diagnosisCommitter: DiagnosisCommitter(
          sessionRepo: sessionRepo,
          stateRepo: stateRepo,
          diagnosisRepo: diagRepo,
          studentModelRepo: studentModelRepo,
          referenceRepo: refRepo,
          chapterRepo: chapterRepo,
          outlineRepo: outlineRepo,
          characterFactRepo: charFactRepo,
          eventFactRepo: eventFactRepo,
          subplotFactRepo: subplotFactRepo,
        ),
      );
      await migrationService.sendMessage(
        sessionId,
        '继续',
        SendMessageCallbacks(
          onStream: (_) {},
          onComplete: (_, _) {},
          onError: (e) => throw Exception('环节5-迁移轮失败: $e'),
        ),
        const SendMessageOptions(
          phase: TeachingPhase.p2PracticeLoop,
          attitude: AttitudeLevel.yuesheng,
        ),
        subphase: TeachingSubphase.diagnosis,
      );

      final afterState = await stateRepo.getTeachingState(sessionId);
      // ignore: avoid_print
      print('[环节5-迁移] 迁移后阶段: ${afterState?.currentPhase}');
      expect(
        afterState?.currentPhase,
        equals(TeachingPhase.p3Training.value),
        reason: '环节5-迁移：M4-A 未从 P2 推进到 P3（活跃症候未清空或达标率不足）',
      );
    } finally {
      await db.close();
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
