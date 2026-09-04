// ─────────────────────────────────────────────────────────────
// 教学环境重验证（live）— sendMessage 完整链路 + 真实 DeepSeek 实测
// 批次 25 步骤②：重构——不再直接调 LlmClient，改为走 ChatService.sendMessage
// 完整教学链路（L1+L2 prompt 组装 → 活跃症候 L3 注入 → 真实 LLM 流式调用），
// 校验真实诊断输出合规性 + 教学闭环落库证据。
//
// 运行方式（API key 只经环境变量传入，严禁写入源码）：
//   $env:DEEPSEEK_API_KEY="sk-xxx"
//   flutter test --tags live test/live_teaching_flow_test.dart
//
// 保护机制：
//   - 无 DEEPSEEK_API_KEY 时自动 markTestSkipped，不影响四闸全量跑
//   - @Tags(['live']) 标识，便于只跑真实链路
// ─────────────────────────────────────────────────────────────

@Tags(['live'])
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
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
import 'package:writingcoach/types/teaching_types.dart';

const String _kBaseUrl = 'https://api.deepseek.com';
const String _kModel = 'deepseek-v4-flash';
const MethodChannel _kConnectivityChannel = MethodChannel(
  'dev.fluttercommunity.plus/connectivity',
);
const MethodChannel _kSecureStorageChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final bool hasKey = Platform.environment.containsKey('DEEPSEEK_API_KEY');

  setUpAll(() {
    HttpOverrides.global = null;
    final key = Platform.environment['DEEPSEEK_API_KEY'];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_kConnectivityChannel, (call) async {
      if (call.method == 'check') return <String>['wifi'];
      return null;
    });
    // 真实 LlmClient 从 secure storage 读配置（api_key / base_url / model）
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

  test(
    '完整教学链路：sendMessage 组装 L1+L2+L3 + DeepSeek 诊断输出合规性',
    () async {
      if (!hasKey) {
        markTestSkipped('未设置 DEEPSEEK_API_KEY，跳过真实链路');
        return;
      }

      // 1. 应用内构造教学场景（P2 诊断子阶段 + 活跃症候 P003 → 触发 L3 注入）
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      try {
        final sessionRepo = SessionRepository(db);
        final sessionId = await sessionRepo.createBlankSession();
        final diagRepo = DiagnosisRepository(db);
        await diagRepo.commitDiagnosis(
          DiagnosisInput(
            sessionId: sessionId,
            messageId: 'live-msg-p003',
            syndromes: [
              {
                'syndrome_id': 'P003',
                'name': '情绪标签化',
                'severity': 'L2',
                'evidence': <String>['他很累。他很无聊。他觉得很没意思。'],
                'explanation': '连续情绪标签，缺少行为化呈现',
              },
            ],
            suggestedActions: const [],
            confidence: 0.7,
          ),
        );

        // 2. 真实链路：ChatService.sendMessage（L1+L2+L3 组装 → 真实 LLM）
        final service = ChatService(
          sessionRepo: sessionRepo,
          stateRepo: TeachingStateRepository(db),
          diagnosisRepo: diagRepo,
          studentModelRepo: StudentModelRepository(db),
          referenceRepo: ReferenceRepository(db),
          chapterRepo: ChapterRepository(db),
          manuscriptRepo: ManuscriptRepository(db),
          llmClient: LlmClient(),
          teacherSuggestionRepo: TeacherSuggestionRepository(db),
          editorObservationRepo: EditorObservationRepository(db),
          // ADR-C74 K-5：诊断提交编排器收紧为 required
          diagnosisCommitter: DiagnosisCommitter(
            sessionRepo: sessionRepo,
            stateRepo: TeachingStateRepository(db),
            diagnosisRepo: diagRepo,
            studentModelRepo: StudentModelRepository(db),
            referenceRepo: ReferenceRepository(db),
            chapterRepo: ChapterRepository(db),
          ),
        );

        // 学员文本（对齐 promptfoo TC-01 平淡叙事：无冲突、情绪标签）
        const studentText = '''
小明早上起床，刷牙洗脸，吃了早饭，然后出门去上班。路上遇到了同事小张，两人一起走进了公司大楼。
到了办公室，小明打开电脑开始工作。中午和同事一起吃了午饭，下午继续工作，然后下班回家。
晚上看了会儿电视就睡了。他很累。他很无聊。他觉得很没意思。
''';

        // 用户消息对齐真实诊断链路（RN chat.tsx L212 / Flutter chat_page.dart L236-244）：
        // 诊断请求 + 章节内容 + 显式 [YS_DIAGNOSIS] 输出指令（协议 3.9 之外 UI 层强制）
        final userPrompt =
            '请对以下写作内容进行写作诊断分析：\n\n'
            '【测试章节】\n\n'
            '$studentText\n\n'
            '---\n'
            '重要：诊断说明后必须输出 [YS_DIAGNOSIS]...[/YS_DIAGNOSIS] 包裹的 JSON 块，'
            '含 syndromes 数组（每条含 syndrome_id/name/severity/evidence/explanation）、'
            'suggested_actions（数组）、confidence（0-1）。'
            '此结构化数据用于驱动后续教学流程，不可缺少。';

        final sb = StringBuffer();
        String? completeContent;
        String? errorMsg;
        await service.sendMessage(
          sessionId,
          userPrompt,
          SendMessageCallbacks(
            onStream: (delta) => sb.write(delta),
            onComplete: (content, _) => completeContent = content,
            onError: (err) => errorMsg = err,
          ),
          const SendMessageOptions(
            phase: TeachingPhase.p2PracticeLoop,
            attitude: AttitudeLevel.yuesheng,
          ),
          subphase: TeachingSubphase.diagnosis,
        );
        expect(errorMsg, isNull, reason: 'sendMessage 链路失败: $errorMsg');

        final reply = (completeContent ?? sb.toString()).trim();
        expect(reply, isNotEmpty, reason: 'DeepSeek 无回复');
        // ignore: avoid_print
        print('[链路] 教学链路完成，回复 ${reply.length} 字符');

        // 3. V-03 合规：sendMessage 已剥离诊断块 → 用户可见内容不含标记与编号
        expect(
          reply,
          isNot(contains('[YS_DIAGNOSIS]')),
          reason: '诊断块标记泄漏到用户可见内容',
        );
        expect(
          reply,
          isNot(contains('[/YS_DIAGNOSIS]')),
          reason: '诊断块闭合标记泄漏到用户可见内容',
        );
        expect(
          RegExp(r'P\d{3}').hasMatch(reply),
          isFalse,
          reason: '自然语言泄漏症候编号（V-03 违规）',
        );
        // ignore: avoid_print
        print('[合规] 用户可见内容合规（无诊断块/编号泄漏）');

        // 4. 教学闭环证据：本次诊断已落库
        // （预置 P003 1 条 + 本次模型诊断症候 ≥1 → 扁平列表应 >1）
        final results = await diagRepo.getAllDiagnoses(sessionId: sessionId);
        expect(results.length, greaterThan(1), reason: '本次诊断未落库');
        // ignore: avoid_print
        print(
          '[闭环] 诊断落库 ${results.length} 条症候 | ${results.map((e) => e.syndromeId).join(",")}',
        );
      } finally {
        await db.close();
      }
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );
}
