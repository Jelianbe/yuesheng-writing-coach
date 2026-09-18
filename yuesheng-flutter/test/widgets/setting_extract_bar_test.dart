// ─────────────────────────────────────────────────────────────
// setting_extract_bar_test — 「从正文提炼断言」条测试（创建体验 A2）
//
//   1. 无正文 → 不显示（SizedBox.shrink）
//   2. 有正文 → 按钮显示
//   3. 成功路径 → SnackBar「已提炼 N 条…」+ onExtracted 收到断言
//   4. 空结果 → SnackBar「未能从正文中提炼出断言…」+ onExtracted 不调用
//   5. LLM 抛异常 → SnackBar「提炼失败：…」+ onExtracted 不调用
//   6. _busy → 按钮禁用 + label「提炼中…」
//
// 第 3~6 条是「管线自检组」（G8 缺口上半）：A2 链路此前无覆盖 —— 真实调用
// 依赖模型配置与网络，测试环境不可控。改用 override `llmClientProvider`
// 注入 fake LLM 后，成功/空/异常三分支**无 key 常驻可跑**。
//
// ⚠️ SnackBar 自带自动消失计时器：新用例一律**不用 pumpAndSettle**
//    （会一直等到计时器超时并挂住），改用 pump() + pump(100ms) 手动推帧；
//    用例末尾由 `_settleSnackBar` 把计时器推完，避免残留 pending Timer。
// ─────────────────────────────────────────────────────────────

// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/providers/session_providers.dart';
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/services/llm_retry.dart';
import 'package:writingcoach/types/character_types.dart';
import 'package:writingcoach/widgets/setting/setting_extract_bar.dart';

/// Fake LLM：预设响应串，可选抛异常 / 挂起（骨架同 `editor_service_test.dart:35`）。
///
/// **只覆写元数据方法**：`chatCompletionWithContinuation` 是基类实现并委托它。
/// [gate] 非空时返回其 future —— 用于把调用停在「在途」态断言 `_busy`。
class _FakeLlmClient extends LlmClient {
  final String _response;
  final Exception? _error;
  final Completer<ChatCompletionResult>? _gate;

  _FakeLlmClient(
    this._response, {
    Exception? error,
    Completer<ChatCompletionResult>? gate,
  }) : _error = error,
       _gate = gate;

  @override
  Future<ChatCompletionResult> chatCompletionWithMeta(
    List<ChatMessage> messages, {
    int? maxTokens,
    Map<String, dynamic>? extraBody,
    CancelToken? cancelToken,
    LlmRetryPolicy retryPolicy = LlmRetryPolicy.standard,
  }) async {
    if (_gate != null) return _gate.future;
    if (_error != null) throw _error;
    return ChatCompletionResult(content: _response);
  }
}

/// 清场：把 SnackBar 的自动消失计时器推完（树里无 SnackBar 时无副作用）。
Future<void> _settleSnackBar(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() {
    container.dispose();
    db.close();
  });

  Widget buildHost({
    required String description,
    Future<int> Function(dynamic extracted)? onExtracted,
  }) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: SettingExtractBar(
            manuscriptId: 'm1',
            entityName: '林晚',
            description: description,
            chapterIdentity: 1,
            onExtracted:
                onExtracted ??
                (extracted) async {
                  return extracted.length;
                },
          ),
        ),
      ),
    );
  }

  /// 注入 fake LLM 的宿主（test/ 下首例 `llmClientProvider` override）。
  ///
  /// `overrideWithValue` 直接绕过该 provider 的 db 依赖 ⇒ 不需要 appDatabase。
  Widget buildFakeHost({
    required LlmClient client,
    required String description,
    required Future<int> Function(List<CharacterAssertion> extracted)
    onExtracted,
  }) {
    return ProviderScope(
      overrides: [llmClientProvider.overrideWithValue(client)],
      child: MaterialApp(
        home: Scaffold(
          body: SettingExtractBar(
            manuscriptId: 'm1',
            entityName: '林晚',
            description: description,
            chapterIdentity: 1,
            onExtracted: onExtracted,
          ),
        ),
      ),
    );
  }

  testWidgets('#1 无正文 → 不显示', (tester) async {
    await tester.pumpWidget(buildHost(description: '   '));
    await tester.pumpAndSettle();
    expect(find.text('从正文提炼断言'), findsNothing);
  });

  testWidgets('#2 有正文 → 按钮显示', (tester) async {
    await tester.pumpWidget(buildHost(description: '她是守夜人，持青铜剑。'));
    await tester.pumpAndSettle();
    expect(find.text('从正文提炼断言'), findsOneWidget);
  });

  // ─────────────────────────────────────────────────────────────
  // 管线自检组：注入 fake LLM，真走 _extract() 三分支
  // ─────────────────────────────────────────────────────────────

  testWidgets('#3 成功路径 → SnackBar 报总数 + onExtracted 收到 1 条', (tester) async {
    List<CharacterAssertion>? received;
    var calls = 0;

    await tester.pumpWidget(
      buildFakeHost(
        client: _FakeLlmClient('[{"attribute": "身份", "value": "守夜人"}]'),
        description: '她是守夜人。',
        onExtracted: (extracted) async {
          calls++;
          received = extracted;
          return 3;
        },
      ),
    );
    await tester.pump();

    final button = find.text('从正文提炼断言');
    expect(button, findsOneWidget, reason: '前置：按钮必须存在（不得静默通过）');

    await tester.tap(button);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('已提炼 1 条断言（待确认），现有共 3 条'), findsOneWidget);
    expect(calls, 1, reason: '落库回调必须被调用一次');
    expect(received, isNotNull);
    expect(received!.length, 1);
    expect(received!.single.attribute, '身份');
    expect(received!.single.chapterSortOrder, 1, reason: 'chapterIdentity 透传');

    await _settleSnackBar(tester);
  });

  testWidgets('#4 空结果 → SnackBar 提示补正文 + onExtracted 不调用', (tester) async {
    var calls = 0;

    await tester.pumpWidget(
      buildFakeHost(
        client: _FakeLlmClient('[]'),
        description: '她是守夜人。',
        onExtracted: (extracted) async {
          calls++;
          return extracted.length;
        },
      ),
    );
    await tester.pump();

    final button = find.text('从正文提炼断言');
    expect(button, findsOneWidget);

    await tester.tap(button);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('未能从正文中提炼出断言，可尝试补充正文内容'), findsOneWidget);
    expect(calls, 0, reason: '空结果不得落库');

    await _settleSnackBar(tester);
  });

  testWidgets('#5 LLM 抛异常 → SnackBar 降级 + onExtracted 不调用', (tester) async {
    var calls = 0;

    await tester.pumpWidget(
      buildFakeHost(
        client: _FakeLlmClient('', error: Exception('boom')),
        description: '她是守夜人。',
        onExtracted: (extracted) async {
          calls++;
          return extracted.length;
        },
      ),
    );
    await tester.pump();

    final button = find.text('从正文提炼断言');
    expect(button, findsOneWidget);

    await tester.tap(button);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('提炼失败：请确认已配置模型服务，或稍后重试'), findsOneWidget);
    expect(calls, 0, reason: '异常不得落库');

    await _settleSnackBar(tester);
  });

  testWidgets('#6 busy 期间按钮禁用 + label「提炼中…」', (tester) async {
    final gate = Completer<ChatCompletionResult>();

    await tester.pumpWidget(
      buildFakeHost(
        client: _FakeLlmClient(
          '[{"attribute": "身份", "value": "守夜人"}]',
          gate: gate,
        ),
        description: '她是守夜人。',
        onExtracted: (extracted) async => extracted.length,
      ),
    );
    await tester.pump();

    await tester.tap(find.text('从正文提炼断言'));
    await tester.pump(); // _busy=true 已 setState；gate 未完成 ⇒ 停在在途态

    expect(find.text('提炼中…'), findsOneWidget);
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNull,
      reason: 'busy 期间必须禁用，防重复提交',
    );

    gate.complete(
      const ChatCompletionResult(
        content: '[{"attribute": "身份", "value": "守夜人"}]',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('已提炼 1 条断言（待确认），现有共 1 条'), findsOneWidget);

    await _settleSnackBar(tester);
  });
}
