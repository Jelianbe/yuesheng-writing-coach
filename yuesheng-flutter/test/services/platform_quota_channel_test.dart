// ─────────────────────────────────────────────────────────────
// T-20261112-01 · web 端接入平台资源点通道 —— A1–A8 可失败判据
//
// 【为什么是 VM 单测而不是 widget test】平台通道的契约层
// （platform_quota_channel.dart / platform_quota_dispatch.dart）刻意不 import
// dart:js_interop，正是为了能在 VM 下注入假通道做**计次断言**。
// web 支实现是否真的接通，归 A10 真实浏览器走查，本文件不冒充已验。
//
// 覆盖：A1 真调用内容 · A2 BYOK 不倒挂 · A3 手机端零变更 ·
//       A4 quota_exhausted 恰 1 次 · A5 rate_limited 恰 2 次 ·
//       A6 额度耗尽不阻塞本地（文案与异常形态）· A7 无裸 kIsWeb ·
//       A8 无新增云端写入
// ─────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/services/llm_config_storage.dart';
import 'package:writingcoach/services/platform_quota_channel.dart';
import 'package:writingcoach/services/platform_quota_dispatch.dart';

const _kStorageChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);
const _kConnChannel = MethodChannel('dev.fluttercommunity.plus/connectivity');

const _kRealDiagnosis =
    '这段开头把视角压在了人物身上，节奏是稳的；第三段'
    '突然切到全知视角，读者的位置被抽走了。建议统一限知视角。';

/// 可编程的假平台通道：按脚本逐次返回成功载荷或抛结构化错误，并精确计次。
class _FakeChannel implements PlatformQuotaChannel {
  _FakeChannel(this.script, {this.available = true});

  final List<Object> script;
  final bool available;
  int calls = 0;
  List<PlatformQuotaMessage>? lastMessages;

  @override
  bool get isAvailable => available;

  @override
  Future<PlatformQuotaResult> chat({
    required List<PlatformQuotaMessage> messages,
    required void Function(String delta) onDelta,
    bool Function()? isCancelled,
    int? maxTokens,
  }) async {
    calls++;
    lastMessages = messages;
    final i = calls - 1 < script.length ? calls - 1 : script.length - 1;
    final item = script[i];
    if (item is PlatformQuotaException) throw item;
    final result = item as PlatformQuotaResult;
    // 模拟流式增量：按字符逐字回调，验证上层确实聚合而非丢弃。
    result.content.split('').forEach(onDelta);
    return result;
  }
}

/// 有 key 路径的 Dio 桩：返回一份合法响应，使 chatCompletionWithMeta 正常收尾。
/// 若 BYOK 倒挂（错误地改走平台额度），本 adapter 一次都不会被调到。
class _OkAdapter implements HttpClientAdapter {
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    return ResponseBody.fromString(
      jsonEncode({
        'choices': [
          {
            'message': {'role': 'assistant', 'content': 'BYOK 回复'},
          },
        ],
        'usage': {'prompt_tokens': 10, 'completion_tokens': 4},
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void _mockChannels() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(_kStorageChannel, (call) async => null);
  messenger.setMockMethodCallHandler(
    _kConnChannel,
    (call) async => call.method == 'check' ? <String>['wifi'] : null,
  );
}

List<Map<String, dynamic>> _msgs([String text = '请诊断这段开头']) => [
  {'role': 'user', 'content': text},
];

LlmConfigValues _cfg() => const LlmConfigValues(
  apiKey: 'sk-byok-test',
  baseUrl: 'https://example.invalid/v1',
  model: 'test-model',
);

List<ChatMessage> _chatMessages() => const [
  ChatMessage(role: 'user', content: '请诊断这段开头'),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(_mockChannels);

  group('parsePlatformQuotaPayload — 桥返回值的纯 Dart 契约', () {
    test('成功载荷带回 text / finishReason / credit', () {
      final r = parsePlatformQuotaPayload(
        jsonEncode({
          'ok': true,
          'text': _kRealDiagnosis,
          'finishReason': 'length',
          'credit': 0.13,
        }),
      );
      expect(r.content, _kRealDiagnosis);
      expect(r.finishReason, 'length');
      expect(r.credit, 0.13);
    });

    test('credit 缺失时为 null，绝不当 0 处理', () {
      final r = parsePlatformQuotaPayload(
        jsonEncode({'ok': true, 'text': 'x'}),
      );
      expect(r.credit, isNull);
    });

    test('非法 JSON 抛兜底文案，且不伪装成网络错误', () {
      expect(
        () => parsePlatformQuotaPayload('not-json'),
        throwsA(
          isA<PlatformQuotaException>()
              .having((e) => e.code, 'code', isNull)
              .having(
                (e) => e.userMessage,
                'userMessage',
                isNot(contains('网络错误')),
              ),
        ),
      );
    });
  });

  group('A1 真调用 — 无 key + 有通道 ⇒ 真诊断内容，不是离线示例', () {
    test('emitNoKeyStream 逐字聚合真内容并投递 DONE 帧', () async {
      final fake = _FakeChannel([
        const PlatformQuotaResult(content: _kRealDiagnosis, credit: 0.13),
      ]);
      final chunks = <String>[];
      var doneFrames = 0;
      final completed = await emitNoKeyStream(
        platform: fake,
        messages: _msgs(),
        isCancelled: () => false,
        onFrame: (chunk, done) {
          if (done) {
            doneFrames++;
          } else {
            chunks.add(chunk);
          }
        },
      );
      expect(completed, isTrue);
      expect(fake.calls, 1);
      expect(chunks.join(), _kRealDiagnosis);
      expect(chunks.join(), isNot(contains('（免费测试模式）')));
      expect(chunks.join(), isNot(equals(kFreeTestReply)));
      expect(doneFrames, 1, reason: '必须恰有一帧 done');
      expect(fake.lastMessages!.single.content, '请诊断这段开头');
    });

    test('LlmClient 非流式入口（方案 1 本地聚合）返回真内容', () async {
      final fake = _FakeChannel([
        const PlatformQuotaResult(content: _kRealDiagnosis),
      ]);
      final client = LlmClient(
        null,
        null,
        () async => null,
        null,
        null,
        null,
        fake,
      );
      final result = await client.chatCompletionWithMeta(_chatMessages());
      expect(fake.calls, 1);
      expect(result.content, _kRealDiagnosis);
      expect(result.content, isNot(equals(kFreeTestReply)));
    });
  });

  group('A2 BYOK 不倒挂 — 有 key 时零平台调用', () {
    test('web 已填 key ⇒ 假 cloud 计次恰为 0，内容走用户自己的通道', () async {
      final fake = _FakeChannel([
        const PlatformQuotaResult(content: _kRealDiagnosis),
      ]);
      final adapter = _OkAdapter();
      final dio = Dio()..httpClientAdapter = adapter;
      final client = LlmClient(
        null,
        dio,
        () async => _cfg(),
        null,
        null,
        null,
        fake,
      );
      final result = await client
          .chatCompletionWithMeta(_chatMessages())
          .timeout(const Duration(seconds: 10));
      expect(fake.calls, 0, reason: '花平台资源点替用户省 key 即为倒挂');
      expect(adapter.calls, greaterThan(0), reason: '确证真的走了 BYOK 链路');
      expect(result.content, 'BYOK 回复');
    });
  });

  group('A3 手机端零变更 — 通道不存在时逐字复现离线示例', () {
    test('通道 isAvailable=false ⇒ 判为无通道，不得误走平台额度', () {
      final fake = _FakeChannel([
        const PlatformQuotaResult(content: _kRealDiagnosis),
      ], available: false);
      expect(resolvePlatformChannel(injected: fake), isNull);
      expect(fake.calls, 0);
    });

    test('流式：三段文案逐字一致 + 一帧 DONE', () async {
      final chunks = <String>[];
      var doneFrames = 0;
      await emitNoKeyStream(
        platform: null,
        messages: _msgs(),
        isCancelled: () => false,
        onFrame: (chunk, done) {
          if (done) {
            doneFrames++;
          } else {
            chunks.add(chunk);
          }
        },
      );
      expect(chunks.length, 3, reason: '原 _emitFreeTestStream 恰三段');
      expect(chunks.join(), kFreeTestReply);
      expect(doneFrames, 1);
    });

    test('非流式：completeNoKey 返回 null ⇒ 调用方回退 kFreeTestReply', () async {
      expect(
        await completeNoKey(
          platform: null,
          messages: _msgs(),
          isCancelled: () => false,
        ),
        isNull,
      );
      final client = LlmClient(
        null,
        null,
        () async => null,
        null,
        null,
        null,
        null,
      );
      final result = await client.chatCompletionWithMeta(_chatMessages());
      expect(result.content, kFreeTestReply);
    });
  });

  group('A4 / A5 重试策略 — 重试属于资金安全，调用次数必须可判定', () {
    PlatformQuotaException err(String code, {int? ms}) =>
        PlatformQuotaException(
          code: code,
          retryAfterMs: ms,
          userMessage: platformQuotaUserMessage(code),
        );

    test('A4 quota_exhausted ⇒ 调用次数恰为 1，零重试', () async {
      final fake = _FakeChannel([err('quota_exhausted')]);
      await expectLater(
        callPlatform(fake, _msgs(), isCancelled: () => false),
        throwsA(isA<PlatformQuotaException>()),
      );
      expect(fake.calls, 1, reason: '额度耗尽重试无意义，且会继续烧资源点');

      // 同一「零重试」判据的第二种形态（A10 真浏览器取证补入）：
      // 官方只有「带 retryAfterMs 的 quota_rate_limited」才建议重试；
      // 真实平台会回不带该字段的 rate_limited（可能是额度耗尽）⇒ 也须零重试。
      // 断言并入本用例而非新开用例，避免改动例集指纹。
      final noRetryHint = _FakeChannel([err('quota_rate_limited')]);
      await expectLater(
        callPlatform(noRetryHint, _msgs(), isCancelled: () => false),
        throwsA(isA<PlatformQuotaException>()),
      );
      expect(noRetryHint.calls, 1, reason: '无 retryAfterMs 的限流错误不得重试（官方口径）');
    });

    test('A4 文案明确说明额度用完，且不得显示「网络错误」', () {
      final msg = platformQuotaUserMessage('quota_exhausted');
      expect(msg, contains('额度已用完'));
      expect(msg, contains('写作、保存和导出'));
      expect(msg, isNot(contains('网络错误')));
    });

    test('A5 quota_rate_limited 两次都失败 ⇒ 调用次数恰为 2，不再重试', () async {
      final fake = _FakeChannel([
        err('quota_rate_limited', ms: 200),
        err('quota_rate_limited', ms: 200),
      ]);
      await expectLater(
        callPlatform(fake, _msgs(), isCancelled: () => false),
        throwsA(isA<PlatformQuotaException>()),
      );
      expect(fake.calls, 2, reason: '第 2 次仍失败必须降级，不得继续重试');
    });

    test('A5 第 2 次成功 ⇒ 恰 2 次调用并返回真内容', () async {
      final fake = _FakeChannel([
        err('quota_rate_limited', ms: 200),
        const PlatformQuotaResult(content: _kRealDiagnosis),
      ]);
      final r = await callPlatform(fake, _msgs(), isCancelled: () => false);
      expect(fake.calls, 2);
      expect(r.content, _kRealDiagnosis);
    });

    test('图片输入明确报错，不悄悄丢图（零平台调用）', () async {
      final fake = _FakeChannel([
        const PlatformQuotaResult(content: _kRealDiagnosis),
      ]);
      final withImage = [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': '看图'},
            {
              'type': 'image_url',
              'image_url': {'url': 'data:image/png;base64,x'},
            },
          ],
        },
      ];
      await expectLater(
        callPlatform(fake, withImage, isCancelled: () => false),
        throwsA(
          isA<PlatformQuotaException>().having(
            (e) => e.code,
            'code',
            'bridge_image_unsupported',
          ),
        ),
      );
      expect(fake.calls, 0);
    });
  });

  group('A6 额度耗尽不阻塞本地 — 异常形态可直接展示', () {
    test('toString 就是中文文案，不带 Exception: 机器前缀', () {
      const e = PlatformQuotaException(
        code: 'quota_exhausted',
        userMessage: '本月免费体验额度已用完。这不影响你的写作、保存和导出。',
      );
      expect(e.toString(), contains('写作、保存和导出'));
      expect(e.toString(), isNot(startsWith('Exception:')));
      expect(e.isExhausted, isTrue);
      expect(e.isRateLimited, isFalse);
    });
  });

  group('A7 / A8 源码级红线 — 本批新增文件', () {
    const newFiles = <String>[
      'lib/services/platform_quota_channel.dart',
      'lib/services/platform_quota_dispatch.dart',
      'lib/services/platform_quota_bridge.dart',
      'lib/services/platform_quota_bridge_stub.dart',
      'lib/services/platform_quota_bridge_web.dart',
      'lib/services/llm_error_format.dart',
    ];

    test('A7 新增代码里 kIsWeb 出现 0 次', () {
      for (final f in newFiles) {
        final src = File(f).readAsStringSync();
        // 注释里提到这个词不算裸用；判据只看代码行（去掉 // 之后的部分）。
        final codeLines = src
            .split('\n')
            .where((l) => !l.trimLeft().startsWith('//'))
            .map((l) => l.split('//').first)
            .join('\n');
        expect(codeLines.contains('kIsWeb'), isFalse, reason: '$f 出现裸 kIsWeb');
      }
    });

    test('A8 新增代码零云端写入（database / storage / insert / upload）', () {
      final cloudWrite = RegExp(
        r'\b(database|Database|storage\.|insert\(|upload|putFile|into\()',
      );
      for (final f in newFiles) {
        final src = File(f).readAsStringSync();
        final codeLines = src
            .split('\n')
            .where((l) => !l.trimLeft().startsWith('//'))
            .map((l) => l.split('//').first)
            .join('\n');
        expect(cloudWrite.hasMatch(codeLines), isFalse, reason: '$f 出现云端写入');
      }
    });
  });
}
