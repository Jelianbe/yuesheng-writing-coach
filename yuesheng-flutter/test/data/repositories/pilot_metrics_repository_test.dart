// ─────────────────────────────────────────────────────────────
// pilot_metrics_repository_test — 试点埋点仓储单元测试
//
// ADR-C122 后 card_wall_entered / micro_task_submitted 已**停写**
// （卡片墙退役），但 v41 表与仓储 API 保留（历史数据迁移/读数兼容）。
// 本文件继续验证仓储读写能力（用例中的卡片墙事件均为历史数据语义）。
//
// 覆盖：
//   1. 三类事件记录 → 按会话读回
//   2. 按事件类型跨会话查询
//   3. 同会话同类事件计数
//   4. payload 规约：PilotSubmitPayload encode/decode 往返
//   5. 用户级事件（session_id=''）不干扰会话级读数
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/pilot_metrics_repository.dart';

void main() {
  late AppDatabase db;
  late PilotMetricsRepository repo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = PilotMetricsRepository(db);
  });

  tearDown(() async => db.close());

  test('#1 三类事件记录 → 按会话读回（升序）', () async {
    await repo.recordEvent(
      sessionId: 's1',
      eventType: PilotEventTypes.cardWallEntered,
      payload: '{"entry":"auto"}',
    );
    await repo.recordEvent(
      sessionId: 's1',
      eventType: PilotEventTypes.microTaskSubmitted,
      payload: PilotSubmitPayload(card: 'narrate_morning', chars: 64).encode(),
    );
    await repo.recordEvent(sessionId: '', eventType: PilotEventTypes.appOpened);

    final events = await repo.listBySession('s1');
    expect(events, hasLength(2));
    expect(events[0].eventType, PilotEventTypes.cardWallEntered);
    expect(events[0].payload, contains('auto'));
    expect(events[1].eventType, PilotEventTypes.microTaskSubmitted);
    expect(events[1].sessionId, 's1');

    // 用户级事件在会话维度不可见（验收读数口径：用户级单列）
    final s1Opened = await repo.countByType('s1', PilotEventTypes.appOpened);
    expect(s1Opened, 0);
  });

  test('#2 按事件类型跨会话查询（C121-2 读数用）', () async {
    await repo.recordEvent(
      sessionId: 's1',
      eventType: PilotEventTypes.microTaskSubmitted,
      payload: PilotSubmitPayload(card: 'describe_three', chars: 71).encode(),
    );
    await repo.recordEvent(
      sessionId: 's2',
      eventType: PilotEventTypes.microTaskSubmitted,
      payload: PilotSubmitPayload(
        card: 'dialogue_disagree',
        chars: 58,
      ).encode(),
    );
    await repo.recordEvent(
      sessionId: 's2',
      eventType: PilotEventTypes.cardWallEntered,
      payload: '{"entry":"header"}',
    );

    final submitted = await repo.listByType(PilotEventTypes.microTaskSubmitted);
    expect(submitted, hasLength(2));
    expect(submitted[0].sessionId, 's1');
    expect(submitted[1].sessionId, 's2');
  });

  test('#3 同会话同类事件计数（分子分母口径）', () async {
    await repo.recordEvent(
      sessionId: 's1',
      eventType: PilotEventTypes.cardWallEntered,
      payload: '{"entry":"auto"}',
    );
    await repo.recordEvent(
      sessionId: 's1',
      eventType: PilotEventTypes.cardWallEntered,
      payload: '{"entry":"header"}',
    );
    await repo.recordEvent(
      sessionId: 's1',
      eventType: PilotEventTypes.microTaskSubmitted,
      payload: PilotSubmitPayload(card: 'narrate_morning', chars: 60).encode(),
    );

    expect(
      await repo.countByType('s1', PilotEventTypes.cardWallEntered),
      2,
      reason: '30 秒产出率分母 = 进入卡片墙次数（会话内可重复进入）',
    );
    expect(
      await repo.countByType('s1', PilotEventTypes.microTaskSubmitted),
      1,
      reason: '可诊断率分子/分母按提交次数计',
    );
  });

  test('#4 PilotSubmitPayload encode/decode 往返', () async {
    const payload = PilotSubmitPayload(card: 'dialogue_disagree', chars: 128);
    final decoded = PilotSubmitPayload.decode(payload.encode());
    expect(decoded.card, 'dialogue_disagree');
    expect(decoded.chars, 128);
  });

  test('#5 空 payload 事件可记录并读回（default 落库）', () async {
    await repo.recordEvent(
      sessionId: 's3',
      eventType: PilotEventTypes.appOpened,
    );
    final events = await repo.listBySession('s3');
    expect(events, hasLength(1));
    expect(events.first.eventType, PilotEventTypes.appOpened);
    expect(events.first.payload, isEmpty);
  });
}
