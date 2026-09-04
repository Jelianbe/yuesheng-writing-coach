// 验证流式空闲超时守卫：模拟「网络静默断流」（连接打开但不再吐数据），
// 守卫应在超时后抛 TimeoutException，而非让 await for 永久阻塞。
//
// 这是「消息发送/识别卡死」根因的针对性回归测试。

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/stream_guard.dart';

void main() {
  const kShort = Duration(milliseconds: 200);

  test('首字到达后中段静默断流 → 超时抛 TimeoutException', () async {
    final src = StreamController<String>();
    final guarded = guardStream(
      src.stream,
      connectTimeout: kShort,
      idleTimeout: kShort,
    );
    // 先发一个 chunk（首字），之后永远不再发 → 模拟服务器卡住
    src.add('你好');

    await expectLater(
      guarded,
      emitsInOrder([equals('你好'), emitsError(isA<TimeoutException>())]),
    );
    await src.close();
  });

  test('连接阶段始终无数据 → 连接超时抛 TimeoutException', () async {
    final src = StreamController<String>(); // 只创建，永不 add / 永不 close
    final guarded = guardStream(
      src.stream,
      connectTimeout: kShort,
      idleTimeout: kShort,
    );

    await expectLater(guarded, emitsError(isA<TimeoutException>()));
    await src.close();
  });

  test('收到新 chunk 重置空闲计时（间隙 < idle 不误杀）', () async {
    final src = StreamController<String>();
    final guarded = guardStream(
      src.stream,
      connectTimeout: kShort,
      idleTimeout: kShort,
    );

    src.add('a');
    await Future<void>.delayed(const Duration(milliseconds: 100)); // < 200ms
    src.add('b');
    await Future<void>.delayed(const Duration(milliseconds: 100)); // < 200ms
    src.add('c');
    // 此后不再发 → 从 'c' 起算 idle 200ms 后应超时
    await expectLater(
      guarded,
      emitsInOrder([
        equals('a'),
        equals('b'),
        equals('c'),
        emitsError(isA<TimeoutException>()),
      ]),
    );
    await src.close();
  });

  test('正常流（发完即 close）不触发超时、完整透传', () async {
    final src = StreamController<String>();
    final guarded = guardStream(
      src.stream,
      connectTimeout: kShort,
      idleTimeout: kShort,
    );

    src.add('x');
    src.add('y');
    await src.close(); // 正常结束

    await expectLater(guarded, emitsInOrder([equals('x'), equals('y')]));
  });

  // ── 批次 J-A：补 V4.21 真覆盖（错误透传 + cancelOnError: false 契约）──

  test('#G5 source 抛错 → guarded 透传同一错误（含 stackTrace）', () async {
    final src = StreamController<String>();
    final guarded = guardStream(
      src.stream,
      connectTimeout: kShort,
      idleTimeout: kShort,
    );

    final boom = StateError('模拟服务端 RPC 失败');
    src.addError(boom);

    await expectLater(guarded, emitsError(predicate((Object e) => e == boom)));
    await src.close();
  });

  test(
    '#G6 错误后 source 仍能 add 数据 → guarded 继续透传（cancelOnError: false 生效）',
    () async {
      final src = StreamController<String>();
      final guarded = guardStream(
        src.stream,
        connectTimeout: kShort,
        idleTimeout: kShort,
      );

      src.addError(StateError('首错'));
      // cancelOnError: false → 错误后 source 仍可继续 add，guard 不应自动断开
      src.add('错误后还能收到');

      await expectLater(
        guarded,
        emitsInOrder([emitsError(isA<StateError>()), equals('错误后还能收到')]),
      );
      await src.close();
    },
  );
}
