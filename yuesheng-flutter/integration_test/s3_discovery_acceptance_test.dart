// ─────────────────────────────────────────────────────────────
// S3 三态发现折叠条 · 真机验收集成测试（T-20261108-02 · 判据①②③）
//
// 在真实 Android 模拟器运行：真实 UI + 真实 DB + 真实 FlutterSecureStorage
// + 真实分块链路由（>4000 字进 progressive）+ 真实 payload 落库/往返，
// 仅 LLM 响应桩（FakeLlmClient 状态机）与验证层三键为受控输入。
//
// 三态触发矩阵（E1 实测链路）：
//   态① 三键全空 ⇒ discoveryConfigured()=false ⇒「验证层未启用，本次无清单外发现」
//   态② 三键写齐 + 发现调用零条 ⇒「本次全部已归类」
//   态③ 三键写齐 + 发现调用 1 条 unclassified ⇒「未归类现象」+ 展开逐条 + 底部声明
//
// 用例顺序 = 执行顺序（①必须先于②③跑：storage 为设备全局态）。
// FakeLlmClient 状态机：merge（streamChat）之前的一切 chatCompletion = 分块
// 分析（回 {"notes":[]}）；merge 之后的 chatCompletion = 发现调用（回桩响应）。
// 运行：flutter test integration_test/s3_discovery_acceptance_test.dart -d emulator-5554
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/app_state_repository.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/providers/session_providers.dart';
import 'package:writingcoach/providers/writing_providers.dart';
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/services/verification_gate.dart';
import 'package:writingcoach/widgets/diagnosis_card.dart';
import 'package:writingcoach/features/writing/writing_coach_panel.dart';

import 's3_acceptance_fixture.dart';

/// merge 段流式响应（含合法 YS_DIAGNOSIS 块；severity L1 不触发教学二次调用）。
const String kMergeFakeResponse =
    '诊断完成。本章环境描写扎实，叙事节奏平稳。'
    '\n[YS_DIAGNOSIS]'
    '\n{"syndromes":[{"syndrome_id":"s1","name":"叙事含糊","severity":"L1","evidence":[],"explanation":"节奏平稳，无严重症候"}],"suggested_actions":[],"confidence":0.8}'
    '\n[/YS_DIAGNOSIS]';

/// 态②发现响应：零条（fail-closed 与真零条同形 ⇒ 归态②，报批单 §二 E6）。
const String kDiscoveryEmptyResponse = '{"observations":[]}';

/// 态③发现响应：1 条出口三（unclassified）。锚点 = 正文逐字子串
/// （parseDiscoveryNotes 的 chunk.contains 硬校验）。reason 为桩模型产出，
/// 非产品文案，不触 R-027。
const String kDiscoveryOneNoteResponse =
    '{"observations":[{"exit":"unclassified",'
    '"anchorQuotes":["弗利西安看向火车的窗外。"],'
    '"reason":"原句：弗利西安看向火车的窗外。／说明：该句为纯环境铺垫，'
    '不属于任何在册症候，仅记录供参考。"}]}';

/// 状态机 Fake LLM（S3 验收专用）。
class S3FakeLlmClient extends LlmClient {
  final String discoveryResponse;
  bool _mergeDone = false;
  int chunkCalls = 0;

  S3FakeLlmClient(this.discoveryResponse);

  @override
  Future<String> chatCompletion(
    List<ChatMessage> messages, {
    int? maxTokens,
    Map<String, dynamic>? extraBody,
    CancelToken? cancelToken,
  }) async {
    if (!_mergeDone) {
      chunkCalls++;
      return '{"notes":[]}';
    }
    return discoveryResponse;
  }

  @override
  Future<void> streamChat(
    List<ChatMessage> messages,
    void Function(LlmStreamResponse response) callback, {
    CancelToken? cancelToken,
    Map<String, dynamic>? extraBody,
  }) async {
    _mergeDone = true;
    final body = kMergeFakeResponse;
    for (var i = 0; i < body.length; i += 40) {
      final end = i + 40 < body.length ? i + 40 : body.length;
      callback(
        LlmStreamResponse(content: body.substring(i, end), isDone: false),
      );
    }
    callback(const LlmStreamResponse(content: '', isDone: true));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const storage = FlutterSecureStorage();
  late AppDatabase db;
  late ProviderContainer container;
  late String chapterId;
  late String manuscriptId;

  Future<void> setKeys(String baseUrl) async {
    await storage.write(key: kVerificationKeyBaseUrl, value: baseUrl);
    await storage.write(key: kVerificationKeyApiKey, value: 's3-test-key');
    await storage.write(key: kVerificationKeyModel, value: 's3-test-model');
  }

  Future<void> clearKeys() async {
    await storage.delete(key: kVerificationKeyBaseUrl);
    await storage.delete(key: kVerificationKeyApiKey);
    await storage.delete(key: kVerificationKeyModel);
  }

  /// 公共装配：建稿建章 + 覆盖 LLM + 挂面板 + 触发诊断。
  /// 三态差异只由 [discoveryResponse] 与三键预置（用例内自行 set/clear）决定。
  Future<void> setupAndDiagnose(
    WidgetTester tester,
    String discoveryResponse,
  ) async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    // C2 引导预跳过：nudge 判定 getApiConfigHintSeen()==false 且内存库无
    // 账号 ⇒ showDialog await 用户点击 ⇒ 集成测试挂死。预置 seen=true 跳过。
    await AppStateRepository(db).setApiConfigHintSeen(true);
    final msRepo = ManuscriptRepository(db);
    final chRepo = ChapterRepository(db);
    manuscriptId = await msRepo.createManuscript(title: 'S3 验收稿');
    chapterId = await chRepo.createChapter(
      manuscriptId,
      title: kS3AcceptanceChapterTitle,
      content: kS3AcceptanceText,
    );
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        llmClientProvider.overrideWithValue(S3FakeLlmClient(discoveryResponse)),
      ],
    );
    await container
        .read(writingStoreProvider(chapterId).notifier)
        .loadChapter();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: WritingCoachPanel(
              chapterId: chapterId,
              manuscriptId: manuscriptId,
              chapterTitle: kS3AcceptanceChapterTitle,
              onClose: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('诊断本章'));
    await _waitFor(tester, find.byType(DiagnosisCard));
  }

  Future<void> teardown() async {
    container.dispose();
    await db.close();
  }

  /// 轮询等待 finder 命中（分块链多轮异步，pumpAndSettle 不足）。
  Future<void> waitForState(WidgetTester tester, String text) async {
    final finder = find.text(text);
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 120));
      if (finder.evaluate().isNotEmpty) return;
    }
    fail('S3 验收等待超时: $text');
  }

  // ── 态①：三键全空 ⇒ 验证层未启用（fail-closed）──
  testWidgets('S3 态① 三键空 ⇒ 折叠条「验证层未启用，本次无清单外发现"', (tester) async {
    await clearKeys();
    await setupAndDiagnose(tester, kDiscoveryEmptyResponse);
    await waitForState(tester, '验证层未启用，本次无清单外发现');
    expect(find.text('本次全部已归类'), findsNothing, reason: '态①②文案不得混现');
    await teardown();
  });

  // ── 态②：三键齐 + 零未归类 ⇒「本次全部已归类」──
  testWidgets('S3 态② 三键齐零发现 ⇒ 折叠条「本次全部已归类"', (tester) async {
    await setKeys('http://10.0.2.2:9/v1');
    await setupAndDiagnose(tester, kDiscoveryEmptyResponse);
    await waitForState(tester, '本次全部已归类');
    expect(find.text('验证层未启用，本次无清单外发现'), findsNothing, reason: '态①②文案不得混现');
    await teardown();
  });

  // ── 态③：三键齐 + 1 条未归类 ⇒ 折叠条 + 展开逐条 + 底部声明 ──
  testWidgets('S3 态③ 有未归类 ⇒ 「未归类现象」展开逐条 + 底部声明', (tester) async {
    await setKeys('http://10.0.2.2:9/v1');
    await setupAndDiagnose(tester, kDiscoveryOneNoteResponse);
    await waitForState(tester, '未归类现象');
    expect(find.text('本次全部已归类'), findsNothing, reason: '态③不得出现态②文案');
    // 默认收起：底部声明不可见（仅展开态出现，报批单 §四主案）
    expect(
      find.text('这些现象暂不在症候清单内，仅记录，供你参考。'),
      findsNothing,
      reason: '收起态不应出现底部声明',
    );
    await tester.tap(find.text('未归类现象'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('原句：弗利西安看向火车的窗外。'),
      findsOneWidget,
      reason: '展开后逐条 reason 可见',
    );
    expect(
      find.text('这些现象暂不在症候清单内，仅记录，供你参考。'),
      findsOneWidget,
      reason: '展开态底部声明可见',
    );
    await teardown();
  });
}

/// 顶部公共等待（供 setupAndDiagnose 内部使用；独立顶层函数避免 main 嵌套超限）。
Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 120));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('S3 验收等待超时: $finder');
}
