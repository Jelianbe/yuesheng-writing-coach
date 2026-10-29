// ─────────────────────────────────────────────────────────────
// ADR-0010：流式终态标记（「isDone 恰好一次」契约）与断流文案
//
// 为什么测这一层：ChatService 的 `sawDone` 不看 SSE 原始字节，只看
// `LlmStreamResponse.isDone` 帧 —— 该帧由 LlmClient._flushIsDone 在
// 「某次尝试真见过 `[DONE]`」时才投递。因此本文件钉住的就是
// 「缺 `[DONE]` ⇒ 无 isDone 帧（sawDone=false ⇒ UI 打断续标记）」，
// 「有 `[DONE]` ⇒ 恰好一次（sawDone=true ⇒ 不误报）」。
//
// 隔离：httpClientAdapter 用内存 SSE 替身，不触真实网络；connectivity
// 平台通道按既有 live_* 测试同款 mock（checkNetwork 依赖）。
// ─────────────────────────────────────────────────────────────

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/config/svc_copy.dart' show kStreamTruncatedMessage;
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/services/llm_config_storage.dart'
    show LlmConfigValues;

const MethodChannel _kConnectivityChannel = MethodChannel(
  'dev.fluttercommunity.plus/connectivity',
);

/// flutter_secure_storage：_prepareEndpoints 会读备选端点原始值（无则 null）
const MethodChannel _kSecureStorageChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

/// 内存 SSE 替身：按原样把预设字节当作响应流返回。
class _SseAdapter implements HttpClientAdapter {
  _SseAdapter(this.body);

  final String body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: ['text/event-stream'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

LlmClient _clientWith(String sse) {
  final dio = Dio()..httpClientAdapter = _SseAdapter(sse);
  return LlmClient(
    null,
    dio,
    () async => LlmConfigValues(
      apiKey: 'unit-test-key',
      baseUrl: 'https://unit.test',
      // 非 deepseek 系：空流降级不在本文件射程内
      model: 'gpt-4o-mini',
    ),
  );
}

Future<List<LlmStreamResponse>> _collect(String sse) async {
  final received = <LlmStreamResponse>[];
  await _clientWith(
    sse,
  ).streamChat(const [ChatMessage(role: 'user', content: '你好')], received.add);
  return received;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_kConnectivityChannel, (call) async {
      if (call.method == 'check') return <String>['wifi'];
      return null;
    });
    messenger.setMockMethodCallHandler(_kSecureStorageChannel, (call) async {
      return null;
    });
  });

  tearDownAll(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_kConnectivityChannel, null);
    messenger.setMockMethodCallHandler(_kSecureStorageChannel, null);
  });

  group('ADR-0010 流式终态标记', () {
    test('A1 有内容但无 [DONE]（对端主动关流）⇒ 不投 isDone 帧', () async {
      final received = await _collect(
        'data: {"choices":[{"delta":{"content":"前半段"}}]}\n\n',
      );

      final content = received.where((r) => !r.isDone).map((r) => r.content);
      expect(content.join(), '前半段', reason: '已投递的内容必须照常送达');
      expect(
        received.where((r) => r.isDone),
        isEmpty,
        reason: '缺 [DONE] 时伪造终态，会让断流被当成成功（本卡要修的正是这个）',
      );
    });

    test('A2 带 [DONE] ⇒ 恰好一次 isDone 帧，且在确认后才投递', () async {
      final received = await _collect(
        'data: {"choices":[{"delta":{"content":"完整回复"}}]}\n\n'
        'data: [DONE]\n\n',
      );

      final doneFrames = received.where((r) => r.isDone).toList();
      expect(doneFrames.length, 1, reason: '「恰好一次」契约');
      expect(received.last.isDone, isTrue, reason: '终态帧必须是最后一帧');
      expect(
        received.where((r) => !r.isDone).map((r) => r.content).join(),
        '完整回复',
      );
    });

    test('A3 断流文案逐字（R-027 报批稿 §2-① 钉住的字面量）', () {
      expect(kStreamTruncatedMessage, '回复中断（未收到结束标记），这条内容可能不完整');
    });
  });
}
