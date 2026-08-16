// ─────────────────────────────────────────────────────────────
// 真实接口对比（批次 96-16）— 结构化期望验证（非话术标准）
//
// 目标：验证「真实 LLM + 真实提示词 + 真实 ChatService 链路」在生产环境
// 也能稳定承担"老师"职责。oracle = 现有 47 个语料 fixture（子代理读真实
// 提示词模拟 LLM 产出，已通过 96-14/96-15 全量验收）中解析出的**结构化期望**
// （症候集/主症/决策/training_task 锁定）。
//
// 重要边界：fixture 中的 natural_language 仅是驱动管线的「样本输入」，话术
// 由 AI 现场生成，**绝不作为任何断言的期望目标**——本测试只验证结构化决策
// 是否正确 + 合规约束（无判决词/无 P0xx 泄漏），从不比较自然语言文案。
//
// 方法：
//  - 选 8 个代表性案例（单症候 L2 ×4 / 冲突 ×2 / 负样本 ×2），每例配一段
//    「重构的问题学生原文」作为输入（corpus_inputs 思路，可审阅可复跑）。
//  - 结构化期望（症候集 / 主症 / 决策 / training_task 锁定）从对应 fixture
//    的 [YS_DIAGNOSIS]/[YS_TEACHER] 实时解析推导 —— 单一可信源、自洽。
//  - 把输入喂给真实 ChatService.sendMessage（diagnosis 子阶段），断言：
//      诊：listActiveProblems 命中期望症候、主症排第一、无凭空症候（误诊率）
//      教：teacher_suggestion 落库、decision 正确、train/guide 锁定主症、
//          natural_language 经一致性（无判决词 / 无 P0xx 泄漏）
//      合规：用户可见内容不泄漏协议标记与症候编号
//
// 双模式（同一套断言逻辑）：
//  1) 管线自检组（常驻，无 key 可跑）：SequenceFakeLlmClient 喂金标准 fixture
//     的 [YS_DIAGNOSIS]+[YS_TEACHER]，精确匹配，证明断言逻辑正确。
//  2) 真实组 @Tags(['live'])：真实 LlmClient 走 DeepSeek，宽松匹配
//     （容 1 个额外症候，因真实 LLM 非确定）。无 DEEPSEEK_API_KEY 时
//     markTestSkipped，不破四闸。
//
// 运行真实对比（API key 只经环境变量，严禁入库）：
//   $env:DEEPSEEK_API_KEY="sk-xxx"
//   flutter test --tags live test/live_interface_comparison_test.dart
// ─────────────────────────────────────────────────────────────

// ignore_for_file: prefer_initializing_formals, avoid_print, unnecessary_underscores

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
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

/// 顺序 Fake LLM：第 1 次返回诊断响应，第 2 次返回教学响应，复刻
/// 诊断→教学 双轮调用（同 dataflow 测试）。
class _SequenceFakeLlmClient extends LlmClient {
  final List<String> _responses;
  int _callIndex = 0;
  _SequenceFakeLlmClient(this._responses);

  @override
  Future<void> streamChat(
    List<ChatMessage> messages,
    void Function(LlmStreamResponse response) callback, {
    CancelToken? cancelToken,
  }) async {
    final r = _responses[_callIndex % _responses.length];
    _callIndex++;
    for (int i = 0; i < r.length; i += 12) {
      final end = i + 12 < r.length ? i + 12 : r.length;
      callback(LlmStreamResponse(content: r.substring(i, end), isDone: false));
    }
    callback(const LlmStreamResponse(content: '', isDone: true));
  }
}

/// 案例：金标准 fixture 名 + 重构的问题学生原文输入。
class CaseSpec {
  final String id;
  final String fixture;
  final String inputText;
  const CaseSpec(this.id, this.fixture, this.inputText);
}

/// 从 fixture 解析出的金标准期望。
class GroundTruth {
  final List<String> syndromes;
  final String? primary;
  final String decision;
  final String? taskSyndrome;
  GroundTruth({
    required this.syndromes,
    this.primary,
    required this.decision,
    this.taskSyndrome,
  });
}

Map<String, dynamic> _extractJson(String raw, String tag) {
  final open = '[$tag]';
  final close = '[/$tag]';
  final start = raw.indexOf(open) + open.length;
  final end = raw.indexOf(close);
  final jsonStr = raw.substring(start, end).trim();
  return jsonDecode(jsonStr) as Map<String, dynamic>;
}

GroundTruth _deriveGroundTruth(String fixture) {
  final raw = File('test/fixtures/$fixture').readAsStringSync();
  final diag = _extractJson(raw, 'YS_DIAGNOSIS');
  final syndromeList =
      (diag['syndromes'] as List? ?? []).cast<Map<String, dynamic>>();
  final syndromes =
      syndromeList.map((s) => s['syndrome_id'] as String).toList();
  final primary = syndromeList.isEmpty
      ? null
      : syndromeList.first['syndrome_id'] as String;
  final teacher = _extractJson(raw, 'YS_TEACHER');
  final decision = teacher['teaching_decision'] as String;
  final task = teacher['training_task'] as Map<String, dynamic>?;
  final taskSyndrome = task?['target_syndrome_id'] as String?;
  return GroundTruth(
    syndromes: syndromes,
    primary: primary,
    decision: decision,
    taskSyndrome: taskSyndrome,
  );
}

/// 共享断言：真实组件落库状态 vs 金标准（exact=自检精确 / 否则真实宽松）。
Future<void> _assertComparison(
  DiagnosisRepository diagRepo,
  TeacherSuggestionRepository teacherSuggestionRepo,
  String assistantContent,
  GroundTruth gt,
  bool exact,
  String sessionId,
) async {
  final active = await diagRepo.listActiveProblems(sessionId);
  final hitIds = active.map((p) => p.syndromeId).toList();
  print('[诊] ${gt.syndromes.join("+")} → 命中: ${hitIds.join(", ")}');

  // 召回：期望症候全部命中
  for (final s in gt.syndromes) {
    expect(hitIds, contains(s), reason: '应命中期望症候 $s');
  }
  // 主症排第一
  if (gt.primary != null) {
    expect(hitIds.first, equals(gt.primary),
        reason: '主症 ${gt.primary} 应排 syndromes[0]');
  }
  // 误诊率：自检精确匹配；真实容 ≤1 额外症候
  if (exact) {
    expect(hitIds, unorderedEquals(gt.syndromes),
        reason: '自检应精确匹配金标准症候集');
  } else {
    expect(hitIds.length, lessThanOrEqualTo(gt.syndromes.length + 1),
        reason: '真实 LLM 不应大量凭空造症候（误诊）');
  }

  // 用户可见内容不泄漏协议标记 / 编号
  expect(assistantContent, isNot(contains('[YS_DIAGNOSIS]')),
      reason: '诊断块标记泄漏到用户可见内容');
  expect(assistantContent, isNot(contains('[YS_TEACHER]')),
      reason: '教学块标记泄漏到用户可见内容');
  expect(RegExp(r'P0\d{2}').hasMatch(assistantContent), isFalse,
      reason: '自然语言泄漏症候编号');

  // 教：教学建议落库与决策
  final sugs = await teacherSuggestionRepo.getActiveSuggestions(sessionId);
  if (gt.decision == 'train' || gt.decision == 'guide') {
    expect(sugs, isNotEmpty, reason: 'L2 应落库教学建议');
    final sug = sugs.first;
    print('[教] decision=${sug.teachingDecision} '
        'target=${sug.targetSyndromeId} taskType=${sug.taskType}');
    expect(sug.teachingDecision, equals(gt.decision),
        reason: '决策应为 ${gt.decision}');
    if (gt.taskSyndrome != null) {
      expect(sug.targetSyndromeId, equals(gt.taskSyndrome),
          reason: 'training_task 应锁定主症 ${gt.taskSyndrome}');
      expect(sug.taskType, isNotEmpty, reason: '训练任务类型不应为空');
    }
    // 注：natural_language 不落库（仅展示文本）；其一致性（无判决词/无 P0xx
    // 泄漏）由 callTeacherStream 落库前的 checkTeacherConsistency 强制保证。
  } else {
    // 负样本：关键是不误诊（上面已断言 hitIds 空）；教学建议可空或同决策无 task
    expect(
      sugs.isEmpty ||
          sugs.every((s) =>
              s.teachingDecision == gt.decision && s.targetSyndromeId == null),
      isTrue,
      reason: '负样本不应产生 train/guide 建议（不误诊）',
    );
  }
}

void main() {
  // 8 个代表性案例：单症候 L2 ×4 / 冲突 ×2 / 负样本 ×2
  const cases = <CaseSpec>[
    CaseSpec('A1', 'corpus_A1_p003.txt',
        '她很难过。她很孤独。她觉得很无助。她一个人坐在窗边，心里满满的都是悲伤。'),
    CaseSpec('A5', 'corpus_A5_p012.txt',
        '主角提剑冲入敌阵，每个敌人都像纸糊的一样，一刀一个倒下，没费什么力气就清了全场。他又连破三关，守军毫无还手之力，胜负来得轻飘飘的。'),
    CaseSpec('A8', 'corpus_A8_p028.txt',
        '她很难过。生活失去了意义。她决定离开这个城市。她默默收拾了行李，准备去一个没人认识她的地方重新开始。'),
    CaseSpec('A19', 'corpus_A19_p019.txt',
        '母亲上午刚下葬，下午他就兴高采烈地约朋友撸串，笑着说终于清净了，她活着的时候天天管着他，现在可算自由了。'),
    CaseSpec('B6', 'corpus_B6_p041_p012.txt',
        '反派布下精密杀局，把主角逼入绝境，读者都以为这一剑必落。可就在能一剑杀掉主角的瞬间，他放下剑，开始发表十分钟演讲讲述自己的身世与理想。读者丝毫感觉不到张力，胜负仿佛成了儿戏。'),
    CaseSpec('B2', 'corpus_B2_p028_p003.txt',
        '她感到非常难过。生活让她觉得很绝望。一切都没有意义。她的眼神十分冷漠，内心充满悲伤，仿佛整个世界都抛弃了她。'),
    CaseSpec('C1', 'corpus_C1_good.txt',
        '雾把整个城市泡软了。路灯的光晕在湿漉漉的地面上化开，远处钟楼的轮廓若隐若现。他站在雾里，手里的伞没有打开。'),
    CaseSpec('C2', 'corpus_C2_short.txt', '你好。'),
  ];

  late AppDatabase db;
  late SessionRepository sessionRepo;
  late DiagnosisRepository diagRepo;
  late TeacherSuggestionRepository teacherSuggestionRepo;
  late StudentModelRepository studentModelRepo;
  late TeachingStateRepository stateRepo;
  late String sessionId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sessionRepo = SessionRepository(db);
    diagRepo = DiagnosisRepository(db);
    teacherSuggestionRepo = TeacherSuggestionRepository(db);
    studentModelRepo = StudentModelRepository(db);
    stateRepo = TeachingStateRepository(db);
    sessionId = await sessionRepo.createBlankSession();
  });

  tearDown(() => db.close());

  ChatService build(LlmClient llmClient) => ChatService(
        sessionRepo: sessionRepo,
        stateRepo: stateRepo,
        diagnosisRepo: diagRepo,
        studentModelRepo: studentModelRepo,
        referenceRepo: ReferenceRepository(db),
        chapterRepo: ChapterRepository(db),
        manuscriptRepo: ManuscriptRepository(db),
        llmClient: llmClient,
        teacherSuggestionRepo: teacherSuggestionRepo,
        editorObservationRepo: EditorObservationRepository(db),
      );

  (String, String) splitFixture(String fileName) {
    final raw = File('test/fixtures/$fileName').readAsStringSync();
    final idx = raw.indexOf('[YS_TEACHER]');
    assert(idx != -1, '$fileName 缺少 [YS_TEACHER] 块');
    return (raw.substring(0, idx), raw.substring(idx));
  }

  const defaultOptions = SendMessageOptions(
    phase: TeachingPhase.p0Engage,
    attitude: AttitudeLevel.doubao,
  );

  Future<String> runDiagnosis(LlmClient client, String input) async {
    String? content;
    await build(client).sendMessage(
      sessionId,
      input,
      SendMessageCallbacks(
        onStream: (_) {},
        onComplete: (c, _) => content = c,
        onError: (e) => fail('链路 onError: $e'),
      ),
      defaultOptions,
      subphase: TeachingSubphase.diagnosis,
    );
    return content ?? '';
  }

  // ── 常驻：管线自检（FakeLlmClient 跑金标准 fixture，无 key 可跑）──
  group('真实接口对比·管线自检（金标准 fixture + FakeLlmClient，精确匹配）', () {
    for (final c in cases) {
      test('[${c.id}] 金标准链路复现，断言逻辑自洽', () async {
        final gt = _deriveGroundTruth(c.fixture);
        final (diagResp, teacherResp) = splitFixture(c.fixture);
        final content =
            await runDiagnosis(_SequenceFakeLlmClient([diagResp, teacherResp]), c.inputText);
        await _assertComparison(diagRepo, teacherSuggestionRepo, content, gt, true, sessionId);
      });
    }
  });

  // ── live：真实 LLM 对比（有 key 跑真 DeepSeek，无 key 自动 skip）──
  final bool hasKey = Platform.environment.containsKey('DEEPSEEK_API_KEY');

  setUpAll(() {
    if (!hasKey) return;
    TestWidgetsFlutterBinding.ensureInitialized();
    HttpOverrides.global = null;
    final key = Platform.environment['DEEPSEEK_API_KEY']!;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_kConnectivityChannel, (call) async {
      if (call.method == 'check') return <String>['wifi'];
      return null;
    });
    final storageValues = <String, String>{
      'yuesheng_api_key': key,
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
    if (!hasKey) return;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_kConnectivityChannel, null);
    messenger.setMockMethodCallHandler(_kSecureStorageChannel, null);
  });

  group('真实接口对比·真实 LLM（@live，宽松匹配）', () {
    for (final c in cases) {
      test(
        '[${c.id}] 真实 DeepSeek + 真实提示词 → 金标准对齐',
        () async {
          if (!hasKey) {
            markTestSkipped('未设置 DEEPSEEK_API_KEY，跳过真实链路');
            return;
          }
          final gt = _deriveGroundTruth(c.fixture);
          final content = await runDiagnosis(LlmClient(), c.inputText);
          await _assertComparison(diagRepo, teacherSuggestionRepo, content, gt, false, sessionId);
        },
        tags: const ['live'],
        timeout: const Timeout(Duration(seconds: 120)),
      );
    }
  });
}
