// ─────────────────────────────────────────────────────────────
// live_fading_replay_test — ADR-C136 项1：fading 支架渐退层级遵循度回放
//
// 目标：构造同一症候（P029 降智反派）在会话内 prior confirmed 计数
// c=0 / c=1 / c≥2 三种状态，走真实 ChatService 诊断链路打真实 DeepSeek，
// 断言**可见反馈文本**遵循 feedback_tier.dart 层级表（N=c+1 口径）：
//   c=0 → N=1 首次：指认症候 + 受限示范单句（默认教学路径，不注入 override）
//   c=1 → N=2：只指根因 + 方向，无示范句
//   c≥2 → N≥3：引导式提问「你发现了吗」，不直接指认、不给改法
//
// 断言的是**遵循度**而非代写质量（R-009）；真实 LLM 非确定：每层级 3 票，
// ≥2/3 遵循判绿，逐票留痕（输出摘要 + monitor.totals）。
//
// 双组结构（仿 live_interface_comparison_test）：
//  1) 常驻自检组（无 live tag，门禁全量必跑）：_ScriptFakeLlmClient 脚本化
//     喂三种层级各一段合规输出，跑同一套行为判据，证明判据自洽、无 key 可跑。
//  2) live 组（per-test tags: live,external，无库级 tag）：真实 LlmClient 走 DeepSeek；
//     无 DEEPSEEK_API_KEY 时 markTestSkipped，不破四闸。
//
// 费用护栏（测试内实现）：
//  - 共享 LlmUsageMonitor 累计真实调用；每票前检查，达 30 次立即 fail 停止
//    （3 层级×3 票×诊断+教学双轮=18 次为满票，余量给重试/重跑）。
//  - 仅瞬时错误（网络/5xx/超时）允许重试最多 2 次、3s/6s 退避；
//    鉴权错误（401/403）立即 fail 并如实打印。
//
// 运行方式（key 只经环境变量传入，严禁写入源码/入库）：
//   $env:DEEPSEEK_API_KEY="sk-xxx"
//   flutter test --tags live test/live_fading_replay_test.dart
// ─────────────────────────────────────────────────────────────

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
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
import 'package:writingcoach/services/chat_service.dart';
import 'package:writingcoach/services/diagnosis_committer.dart';
import 'package:writingcoach/services/message_injector.dart';
import 'package:writingcoach/services/chat_context_builder.dart'
    show MaterialCapabilityImpl;
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/services/llm_concurrency_gate.dart';
import 'package:writingcoach/services/llm_config_storage.dart';
import 'package:writingcoach/services/llm_usage_monitor.dart';
import 'package:writingcoach/types/teaching_types.dart';

import 'package:writingcoach/services/diagnosis_flow_handler.dart';
import 'package:writingcoach/services/diagnosis_parser.dart'
    show DiagnosisCapabilityImpl;
import 'package:writingcoach/services/genui_parser.dart' show GenUiParser;
import 'package:writingcoach/services/chat_message_types.dart'
    show SendMessageCallbacks, SendMessageOptions;

const String _kBaseUrl = 'https://api.deepseek.com';
const String _kModel = 'deepseek-v4-flash';
const MethodChannel _kConnectivityChannel = MethodChannel(
  'dev.fluttercommunity.plus/connectivity',
);
const MethodChannel _kSecureStorageChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

/// 本批锁定的症候（corpus_B6_p029_p010.txt 主症）。
const String _kSyndromeId = 'P029';

/// 学员问题原文（B6 重构输入，与 live_interface_comparison_test 同段）。
const String _kStudentText =
    '反派布下精密杀局，把主角逼入绝境，读者都以为这一剑必落。'
    '可就在能一剑杀掉主角的瞬间，他放下剑，开始发表十分钟演讲讲述自己的身世与理想。'
    '读者丝毫感觉不到张力，胜负仿佛成了儿戏。';

/// 诊断触发输入：带强信号词「诊断」（isDiagnosisRequest 中文强信号）。
const String _kInput = '请帮我诊断下面这段文字：\n$_kStudentText';

/// 真实调用预算上限（ADR-C136 §4：fading ≤30）。
const int _kMaxRealCalls = 30;

// ═══════════ 行为判据（遵循度，非代写质量）═══════════

/// 剥离协议块后再判据（可见文本不应含标记，双保险）。
String _stripProtocol(String raw) {
  var t = raw;
  t = t.replaceAll(
    RegExp(r'\[YS_DIAGNOSIS\].*?\[/YS_DIAGNOSIS\]', dotAll: true),
    '',
  );
  t = t.replaceAll(
    RegExp(r'\[YS_TEACHER\].*?\[/YS_TEACHER\]', dotAll: true),
    '',
  );
  return t.trim();
}

/// 是否指认了本症候问题（P029：降智反派 / 张力落空相关概念词）。
bool _mentionsProblem(String t) {
  const kws = <String>[
    '反派',
    '放下剑',
    '放下必杀',
    '演讲',
    '独白',
    '张力',
    '出戏',
    '降智',
    '人设',
    '矛盾',
    '智谋',
  ];
  return kws.any(t.contains);
}

/// 示范句信号（c=1 / c≥2 不得出现；c=0 要求出现，且为单句级非整段改写）。
bool _hasDemoSignal(String t) =>
    RegExp(r'比如|例如|可以写成|试着写成|不妨写|试试把|「[^」]{5,}」').hasMatch(t);

/// 直接给答案/改法信号（c≥2 引导式不得出现——与示范信号合并判）。
bool _givesAnswer(String t) =>
    _hasDemoSignal(t) || RegExp(r'应该改成|应当改成|根因是|其实根因|答案是|正确做法').hasMatch(t);

/// 引导式提问信号（c≥2 要求出现；真实 LLM 措辞谱较宽，放宽列举）。
/// 覆盖：发现类问句 / 你觉得-认为-想+疑问 / 让学员先开口
/// （你先说/你先想/想到了跟我说…）/ 教练克制声明（我先不说/先不急着给
/// 结论/不往下讲…）/ 你能…吗疑问结构。
bool _hasGuidedQuestion(String t) {
  const kws = <String>[
    '你发现',
    '有没有注意',
    '你看出来',
    '你有没有',
    '你意识到',
    '你觉得',
    '你认为',
    '你想',
    '你先说',
    '你说说',
    '你先想',
    '想到了跟我说',
    '告诉我你的判断',
    '先把你的判断说',
    '我先不说',
    '先不急着给结论',
    '不往下讲',
    '不先给答案',
    '先不说我的',
    '你能',
    '能不能',
  ];
  return kws.any(t.contains);
}

/// c=0 / N=1：指认症候 + 受限示范。
bool _compliantFirstTouch(String out) =>
    _mentionsProblem(out) && _hasDemoSignal(out);

/// c=1 / N=2：指根因+方向，无示范句。
bool _compliantRootCauseOnly(String out) =>
    _mentionsProblem(out) && !_hasDemoSignal(out);

/// c≥2 / N≥3：引导提问，不直接给改法/答案。
bool _compliantGuidedRecall(String out) =>
    _hasGuidedQuestion(out) && !_givesAnswer(out);

// ═══════════ 预置 confirmed 计数 ═══════════

/// 经 DiagnosisRepository 的 confirm 流程（commitDiagnosis, isTeachingRound=false
/// → status='confirmed'）预置同症候 confirmed 行。
///
/// NO_OP 去重坑：同症候同 severity 重复诊断会被滤除不建行；故交替 L2/L1
/// severity 绕过去重，保证 countConfirmedDiagnosesBySyndrome 精确=c。
Future<void> _seedConfirmed(
  DiagnosisRepository repo,
  String sessionId,
  int count,
) async {
  const sevs = ['L2', 'L1'];
  for (var i = 0; i < count; i++) {
    await repo.commitDiagnosis(
      DiagnosisInput(
        sessionId: sessionId,
        messageId: 'seed-$i',
        syndromes: [
          {
            'syndrome_id': _kSyndromeId,
            'name': '降智反派',
            'severity': sevs[i % sevs.length],
            'evidence': <String>['放下剑去演讲'],
            'explanation': 'seed：与精密布局人设矛盾',
          },
        ],
        suggestedActions: const [],
        confidence: 0.8,
      ),
    );
  }
}

// ═══════════ 脚本 Fake LLM（常驻自检组用）═══════════

/// 顺序 Fake LLM：第 1 次返回诊断响应，第 2 次返回教学响应（复刻
/// 诊断→教学 双轮调用，同 live_interface_comparison_test）。
class _ScriptFakeLlmClient extends LlmClient {
  final List<String> _responses;
  int _callIndex = 0;
  _ScriptFakeLlmClient(this._responses);

  @override
  Future<void> streamChat(
    List<ChatMessage> messages,
    void Function(LlmStreamResponse response) callback, {
    CancelToken? cancelToken,
    Map<String, dynamic>? extraBody,
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

/// 自检脚本：诊断响应块（P029）。
String _diagBlock() =>
    '[YS_DIAGNOSIS]\n'
    '{"syndromes":[{"syndrome_id":"$_kSyndromeId","name":"降智反派",'
    '"severity":"L2","evidence":["放下剑去演讲"],'
    '"explanation":"行为与人设矛盾"}],"suggested_actions":[],"confidence":0.9}\n'
    '[/YS_DIAGNOSIS]';

/// 自检脚本：教学响应块（NL 在前、块在后——callTeacherStream 的
/// displayContent 取自 [YS_TEACHER] 块之外的自然语言文本；
/// 块内 natural_language 与块外一致，过 consistency 校验）。
String _teacherBlock(String naturalLanguage) =>
    '$naturalLanguage\n\n[YS_TEACHER]\n'
    '{"teaching_decision":"train","teaching_reason":"主症 P029",'
    '"natural_language":${jsonEncode(naturalLanguage)},'
    '"training_task":{"target_syndrome_id":"$_kSyndromeId",'
    '"task_type":"rewrite","task_description":"seed"}}\n'
    '[/YS_TEACHER]';

void main() {
  late AppDatabase db;
  late SessionRepository sessionRepo;
  late DiagnosisRepository diagRepo;
  late TeacherSuggestionRepository teacherSuggestionRepo;
  late StudentModelRepository studentModelRepo;
  late TeachingStateRepository stateRepo;

  /// 全 live 组共享的用量计（真实调用预算尺）——常驻自检组不经过它。
  final monitor = LlmUsageMonitor();
  final bool hasKey = Platform.environment.containsKey('DEEPSEEK_API_KEY');

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sessionRepo = SessionRepository(db);
    diagRepo = DiagnosisRepository(db);
    teacherSuggestionRepo = TeacherSuggestionRepository(db);
    studentModelRepo = StudentModelRepository(db);
    stateRepo = TeachingStateRepository(db);
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
    diagnosisCommitter: DiagnosisCommitter(
      sessionRepo: sessionRepo,
      stateRepo: stateRepo,
      diagnosisRepo: diagRepo,
      studentModelRepo: studentModelRepo,
      referenceRepo: ReferenceRepository(db),
      chapterRepo: ChapterRepository(db),
    ),
    messageInjector: MessageInjector(
      sessionRepo: sessionRepo,
      diagnosisRepo: diagRepo,
      studentModelRepo: studentModelRepo,
      referenceRepo: ReferenceRepository(db),
      chapterRepo: ChapterRepository(db),
      manuscriptRepo: ManuscriptRepository(db),
      diagnosisCommitter: DiagnosisCommitter(
        sessionRepo: sessionRepo,
        stateRepo: stateRepo,
        diagnosisRepo: diagRepo,
        studentModelRepo: studentModelRepo,
        referenceRepo: ReferenceRepository(db),
        chapterRepo: ChapterRepository(db),
      ),
      material: const MaterialCapabilityImpl(),
    ),
    diagnosisFlowHandler: DiagnosisFlowHandler(
      sessionRepo: sessionRepo,
      stateRepo: stateRepo,
      diagnosisRepo: diagRepo,
      studentModelRepo: studentModelRepo,
      referenceRepo: ReferenceRepository(db),
      chapterRepo: ChapterRepository(db),
      teacherSuggestionRepo: TeacherSuggestionRepository(db),
      llmClient: llmClient,
      messageInjector: MessageInjector(
        sessionRepo: sessionRepo,
        diagnosisRepo: diagRepo,
        studentModelRepo: studentModelRepo,
        referenceRepo: ReferenceRepository(db),
        chapterRepo: ChapterRepository(db),
        manuscriptRepo: ManuscriptRepository(db),
        diagnosisCommitter: DiagnosisCommitter(
          sessionRepo: sessionRepo,
          stateRepo: stateRepo,
          diagnosisRepo: diagRepo,
          studentModelRepo: studentModelRepo,
          referenceRepo: ReferenceRepository(db),
          chapterRepo: ChapterRepository(db),
        ),
        material: const MaterialCapabilityImpl(),
      ),
      diagnosisCommitter: DiagnosisCommitter(
        sessionRepo: sessionRepo,
        stateRepo: stateRepo,
        diagnosisRepo: diagRepo,
        studentModelRepo: studentModelRepo,
        referenceRepo: ReferenceRepository(db),
        chapterRepo: ChapterRepository(db),
      ),
      diagnosis: const DiagnosisCapabilityImpl(),
      genUi: const GenUiParser(),
    ),
  );

  const defaultOptions = SendMessageOptions(
    phase: TeachingPhase.p0Engage,
    attitude: AttitudeLevel.gentle,
  );

  Future<String> runDiagnosis(String sessionId, LlmClient client) async {
    String? content;
    await build(client).sendMessage(
      sessionId,
      _kInput,
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

  /// 每票一个全新会话：fresh session 隔离上一轮 live 落库造成的计数膨胀。
  /// 学员资格置 N3_DIAGNOSE → _resolveFadingEligibility 判 highStableOnly
  /// （c≥2 引导提问不致被安全降级为 rootCauseOnly）。
  Future<String> newVotingSession({required int priorConfirmed}) async {
    final sid = await sessionRepo.createBlankSession();
    await stateRepo.updateBeginnerLevel(sid, BeginnerLevel.n3Diagnose.value);
    if (priorConfirmed > 0) {
      await _seedConfirmed(diagRepo, sid, priorConfirmed);
    }
    final rec = await diagRepo.countConfirmedDiagnosesBySyndrome(sid);
    print('[预置] session=$sid prior=$rec (目标 $priorConfirmed)');
    return sid;
  }

  /// 瞬时错误重试（≤2 次，3s/6s 退避）；鉴权错误立即停。
  Future<String> runWithRetry(String sessionId, LlmClient client) async {
    Object? last;
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        return await runDiagnosis(sessionId, client);
      } catch (e) {
        last = e;
        final msg = e.toString();
        if (msg.contains('401') || msg.contains('403')) {
          fail('鉴权失败（$msg），立即停止回放，不重试');
        }
        if (attempt < 3) {
          print('[重试] 瞬时错误 attempt=$attempt: $e；退避 ${3 * attempt}s');
          await Future<void>.delayed(Duration(seconds: 3 * attempt));
        }
      }
    }
    fail('瞬时错误重试 3 次仍失败: $last');
  }

  /// 单层级 3 票计票：≥2/3 遵循判绿；每票前查费用护栏。
  Future<int> runTierVotes({
    required String tierName,
    required int priorConfirmed,
    required bool Function(String out) isCompliant,
    required LlmClient client,
  }) async {
    var compliant = 0;
    for (var vote = 1; vote <= 3; vote++) {
      if (monitor.totals.calls >= _kMaxRealCalls) {
        fail(
          '真实调用预算用尽：已 ${monitor.totals.calls} 次'
          '（上限 $_kMaxRealCalls），停止回放',
        );
      }
      final sid = await newVotingSession(priorConfirmed: priorConfirmed);
      final out = _stripProtocol(await runWithRetry(sid, client));
      final ok = isCompliant(out);
      if (ok) compliant++;
      print(
        '[$tierName vote#$vote] compliant=$ok '
        'calls=${monitor.totals.calls} out=${out.trim()}',
      );
    }
    return compliant;
  }

  // ── 常驻自检组（无 live tag，门禁全量执行，必须确定性通过）──
  group('fading 回放·断言逻辑自检（FakeLlmClient，无 key 可跑）', () {
    test('c=0：指认+受限示范输出 → 判据判遵循', () async {
      final sid = await newVotingSession(priorConfirmed: 0);
      const nl =
          '反派在决胜点放下剑去演讲，和前文精密布局的人设是矛盾的。'
          '比如可以这样写：他剑尖已抵喉，却只是冷笑一声，'
          '下一秒刀锋已经抹过主角的脖颈。';
      final client = _ScriptFakeLlmClient([
        '开场一句。\n\n${_diagBlock()}',
        _teacherBlock(nl),
      ]);
      final out = _stripProtocol(await runDiagnosis(sid, client));
      expect(_compliantFirstTouch(out), isTrue, reason: '输出=$out');
    });

    test('c=1：只指根因+方向（无示范）→ 判据判遵循', () async {
      final sid = await newVotingSession(priorConfirmed: 1);
      const nl =
          '根因在于反派的智谋人设在决胜点崩了：前面布局越精密，'
          '此刻放下剑演讲就越显得不自洽。方向是让他的每个举动'
          '都服务于既定利益。';
      final client = _ScriptFakeLlmClient([
        '开场一句。\n\n${_diagBlock()}',
        _teacherBlock(nl),
      ]);
      final out = _stripProtocol(await runDiagnosis(sid, client));
      expect(_compliantRootCauseOnly(out), isTrue, reason: '输出=$out');
    });

    test('c≥2：引导式提问（不给答案）→ 判据判遵循', () async {
      final sid = await newVotingSession(priorConfirmed: 2);
      const nl =
          '你发现这一处的问题了吗？再读读他放下剑那一刻的举动，'
          '和你前面给他铺的精密人设，有没有哪里对不上？';
      final client = _ScriptFakeLlmClient([
        '开场一句。\n\n${_diagBlock()}',
        _teacherBlock(nl),
      ]);
      final out = _stripProtocol(await runDiagnosis(sid, client));
      expect(_compliantGuidedRecall(out), isTrue, reason: '输出=$out');
    });

    // 真实回放证据回归锁（2026-10-02 真实 LLM 三票，均实际遵循引导式、
    // 放宽前判别器假阴性）——钉死防回退。
    test('判别器回归锁·真实证据三票（引导式→应判遵循）', () {
      const evidences = <String>[
        '先不急着给结论，往回推一步问你：这个反派在那一剑落下的前一秒放下剑、开口演讲——他图什么？这段描述里，你能读到属于他自己的那本账吗？',
        '不过我先不往下讲这一处。你自己再看一遍反派“放下剑”那一刻——你觉得问题出在哪？先把你的判断说给我听，我再说我的。',
        '那我先不说我的判断，问你一句：那个反派，他自己是为什么把剑放下的？你先想想这个，想到了跟我说。',
      ];
      for (final e in evidences) {
        expect(_compliantGuidedRecall(e), isTrue, reason: '真实证据应判遵循: $e');
      }
    });

    // 反例（防放宽过头）：既提问又给答案 / 只给答案无提问 → 必须判 false。
    test('判别器反例·提问但已给答案 → 判不遵循', () {
      const t = '你觉得呢？其实根因是放下剑让张力崩塌，应该改成他犹豫时剑尖微微下压。';
      expect(_hasGuidedQuestion(t), isTrue, reason: '前提：确有引导提问');
      expect(_compliantGuidedRecall(t), isFalse, reason: '已给答案不得判遵循');
    });

    test('判别器反例·只给答案无提问 → 判不遵循', () {
      const t = '根因在于反派放下剑演讲让张力崩塌，应该改成他剑尖微微下压、一句话逼死主角。';
      expect(_compliantGuidedRecall(t), isFalse);
    });
  });

  // ── live 组：真实 DeepSeek（无 key 自动 skip）──
  setUpAll(() {
    if (!hasKey) return;
    TestWidgetsFlutterBinding.ensureInitialized();
    HttpOverrides.global = null;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_kConnectivityChannel, (call) async {
      if (call.method == 'check') return <String>['wifi'];
      return null;
    });
    final storageValues = <String, String>{
      'yuesheng_api_key': Platform.environment['DEEPSEEK_API_KEY'] ?? '',
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

  group('fading 回放·真实 LLM（@live，3 票制）', () {
    LlmClient buildRealClient() {
      final key = Platform.environment['DEEPSEEK_API_KEY']!;
      final cfg = LlmConfigValues(
        apiKey: key,
        baseUrl: _kBaseUrl,
        model: _kModel,
      );
      return LlmClient(
        null,
        null,
        () async => cfg,
        null,
        LlmConcurrencyGate(),
        monitor.sink,
      );
    }

    test(
      'c=0 → N=1 首次：指认 + 受限示范单句（≥2/3 遵循）',
      () async {
        if (!hasKey) {
          markTestSkipped('未设置 DEEPSEEK_API_KEY，跳过真实链路');
          return;
        }
        final ok = await runTierVotes(
          tierName: 'c=0',
          priorConfirmed: 0,
          isCompliant: _compliantFirstTouch,
          client: buildRealClient(),
        );
        print('[汇总 c=0] 遵循 $ok/3 monitor=${monitor.totals}');
        expect(ok, greaterThanOrEqualTo(2), reason: 'c=0 层级遵循度 <2/3');
      },
      tags: const ['live', 'external'],
      timeout: const Timeout(Duration(seconds: 300)),
    );

    test(
      'c=1 → N=2：只指根因+方向、无示范句（≥2/3 遵循）',
      () async {
        if (!hasKey) {
          markTestSkipped('未设置 DEEPSEEK_API_KEY，跳过真实链路');
          return;
        }
        final ok = await runTierVotes(
          tierName: 'c=1',
          priorConfirmed: 1,
          isCompliant: _compliantRootCauseOnly,
          client: buildRealClient(),
        );
        print('[汇总 c=1] 遵循 $ok/3 monitor=${monitor.totals}');
        expect(ok, greaterThanOrEqualTo(2), reason: 'c=1 层级遵循度 <2/3');
      },
      tags: const ['live', 'external'],
      timeout: const Timeout(Duration(seconds: 300)),
    );

    test(
      'c≥2 → N≥3：引导提问「你发现了吗」、不直接给答案（≥2/3 遵循）',
      () async {
        if (!hasKey) {
          markTestSkipped('未设置 DEEPSEEK_API_KEY，跳过真实链路');
          return;
        }
        final ok = await runTierVotes(
          tierName: 'c>=2',
          priorConfirmed: 2,
          isCompliant: _compliantGuidedRecall,
          client: buildRealClient(),
        );
        print('[汇总 c>=2] 遵循 $ok/3 monitor=${monitor.totals}');
        expect(ok, greaterThanOrEqualTo(2), reason: 'c≥2 层级遵循度 <2/3');
      },
      tags: const ['live', 'external'],
      timeout: const Timeout(Duration(seconds: 300)),
    );
  });
}
