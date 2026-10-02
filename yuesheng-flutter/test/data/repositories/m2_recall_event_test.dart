// ─────────────────────────────────────────────────────────────
// m2_recall_event_test — M2 复述根因事件落库（ADR-C133 批2）
//
// 覆盖（对齐 ADR-C133 §4.2 / 裁决三件套 §1.2）：
//   1. confirmed 复述事件落库：复述文本 + 根因原文 + payload(kind/verdict/症候)
//   2. corrected 复述事件落库（事件仍入库，留证据卡；不计候选）
//   3. verdict 边界校验：非 confirmed|corrected 拒绝写入
//   4. payload 编解码往返 + 非 M2 payload 安全降级为 null
//   5. M2 复述事件与纯指认 anchor_ack 同表并存，靠 payload.kind 区分
//   6. R-009 形态：落库 payload 无任何 score/passed/达标字段（只记不判）
//
// 事件落库设计 = 选项 A：eventType 复用 'anchor_ack'，payload.kind='M2_recall'
// 区分子类型；零 schema 变更（不改 tables.dart CHECK / 不 migration）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/edit_diff_event_repository.dart';

void main() {
  late AppDatabase db;
  late EditDiffEventRepository repo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = EditDiffEventRepository(db);
  });

  tearDown(() async => db.close());

  test('#1 confirmed 复述事件落库：复述文本/根因原文/payload 三者可观测', () async {
    await repo.recordM2Recall(
      sessionId: 's-m2',
      chapterId: 'c-m2',
      messageId: 'diag-1',
      syndromeId: 'SYN_open',
      syndromeName: '开头俗套',
      recallText: '他每次都从天气写起，读者还没进场景就累了。',
      rootCauseText: '开篇用程式化套语，未把读者直接带入冲突。',
      verdict: M2RecallVerdict.confirmed,
    );

    final events = await repo.listByChapter('c-m2');
    expect(events, hasLength(1));
    final e = events.single;

    // 选项 A：复用 anchor_ack 事件类型（CHECK 约束内，零 schema 变更）。
    expect(e.eventType, EditDiffEventTypes.anchorAck);
    // afterText = 学员复述文本（用自己的话）。
    expect(e.afterText, '他每次都从天气写起，读者还没进场景就累了。');
    // beforeText = 被复述的诊断根因原文（锚点）。
    expect(e.beforeText, '开篇用程式化套语，未把读者直接带入冲突。');
    expect(e.messageId, 'diag-1');

    final p = M2RecallPayload.tryDecode(e.payload);
    expect(p, isNotNull);
    expect(p!.verdict, M2RecallVerdict.confirmed);
    expect(p.syndromeId, 'SYN_open');
    expect(p.syndromeName, '开头俗套');
  });

  test('#2 corrected 复述事件仍落库（留证据卡，不计本格候选）', () async {
    await repo.recordM2Recall(
      sessionId: 's-m2',
      chapterId: 'c-m2b',
      syndromeId: 'SYN_open',
      recallText: '写得太平了。',
      rootCauseText: '开篇用程式化套语。',
      verdict: M2RecallVerdict.corrected,
    );

    final events = await repo.listByChapter('c-m2b');
    expect(events, hasLength(1));
    final e = events.single;
    expect(e.eventType, EditDiffEventTypes.anchorAck);
    final p = M2RecallPayload.tryDecode(e.payload);
    expect(p, isNotNull);
    expect(p!.verdict, M2RecallVerdict.corrected);
    // corrected：复述文本仍如实留痕（证据卡可见）。
    expect(e.afterText, '写得太平了。');
  });

  test('#3 verdict 边界校验：非 confirmed|corrected 拒绝写入', () async {
    expect(
      () => repo.recordM2Recall(
        sessionId: 's',
        chapterId: 'c',
        syndromeId: 'SYN_x',
        recallText: '复述……',
        verdict: 'passed', // 非法值
      ),
      throwsArgumentError,
    );
    // 拒绝后章节内无事件。
    final events = await repo.listByChapter('c');
    expect(events, isEmpty);
  });

  test('#4 payload 编解码往返；非 M2 payload 安全降级 null', () async {
    const p = M2RecallPayload(
      verdict: M2RecallVerdict.confirmed,
      syndromeId: 'SYN_open',
      syndromeName: '开头俗套',
    );
    final decoded = M2RecallPayload.tryDecode(p.encode());
    expect(decoded, isNotNull);
    expect(decoded!.verdict, M2RecallVerdict.confirmed);
    expect(decoded.syndromeId, 'SYN_open');
    expect(decoded.syndromeName, '开头俗套');

    // 纯指认 anchor_ack 的 payload 不是 M2 结构 → 安全降级 null（不抛）。
    expect(M2RecallPayload.tryDecode('{"diff_segments":2}'), isNull);
    expect(M2RecallPayload.tryDecode(''), isNull);
    expect(M2RecallPayload.tryDecode(null), isNull);
    expect(M2RecallPayload.tryDecode('not-json{{'), isNull);
  });

  test('#5 M2 复述事件与纯指认 anchor_ack 同表并存，靠 payload.kind 区分', () async {
    // 纯指认事件（C132）。
    await repo.recordAnchorAcknowledged(
      sessionId: 's',
      chapterId: 'c-mix',
      anchorText: '窗外下着雨。',
    );
    // M2 复述事件（批2）。
    await repo.recordM2Recall(
      sessionId: 's',
      chapterId: 'c-mix',
      syndromeId: 'SYN_open',
      syndromeName: '开头俗套',
      recallText: '自己的复述……',
      verdict: M2RecallVerdict.confirmed,
    );

    final all = await repo.listByType(EditDiffEventTypes.anchorAck);
    expect(all.where((e) => e.chapterId == 'c-mix'), hasLength(2));

    // 消费方按 payload.kind 筛出 M2 复述事件。
    final recalls = all
        .map((e) => (event: e, p: M2RecallPayload.tryDecode(e.payload)))
        .where((r) => r.p != null)
        .toList();
    expect(recalls, hasLength(1));
    expect(recalls.single.event.afterText, '自己的复述……');
    expect(recalls.single.p!.verdict, M2RecallVerdict.confirmed);
  });

  test('#6 R-009 形态：落库 payload 无任何 score/passed/达标字段（只记不判）', () async {
    await repo.recordM2Recall(
      sessionId: 's',
      chapterId: 'c-r009',
      syndromeId: 'SYN_open',
      syndromeName: '开头俗套',
      recallText: '复述文本原样留痕。',
      verdict: M2RecallVerdict.confirmed,
    );
    final e = (await repo.listByChapter('c-r009')).single;
    // payload 仅 kind/verdict/syndrome_id[/syndrome_name] 四元；
    // 不得出现 score / passed / level / 达标 等自动成败字段。
    expect(e.payload.contains('score'), isFalse, reason: 'payload 不得含 score');
    expect(e.payload.contains('passed'), isFalse, reason: 'payload 不得含 passed');
    expect(e.payload.contains('"level"'), isFalse, reason: 'payload 不得含 level');
    expect(e.payload.contains('达标'), isFalse);
    // 复述文本原样留存——「是否照抄/是否到位」不自动计算。
    expect(e.afterText, '复述文本原样留痕。');
  });
}
