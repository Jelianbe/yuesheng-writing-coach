// ─────────────────────────────────────────────────────────────
// record_entry_service_test — 记录条目提议式全链路（ADR-C143 批B）
//
// DoD §5.2：提议式触发 → pending 暂存 → 作者确认落 kept / 拒绝落 rejected；
// 摘录为原文搬运（测试断言 excerpt 逐字等于输入、无改写）。
//
// R-009：本链路无 LLM 检测/提炼——proposePending 由显式触发（作者喊「记一下」）
// 调用，excerpt 原样落库。
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/record_entry_repository.dart';

void main() {
  late AppDatabase db;
  late RecordEntryRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = RecordEntryRepository(db);
  });
  tearDown(() => db.close());

  test('提议 → pending 暂存，excerpt 逐字原样（无改写/缩写）', () async {
    const raw = '她站在院门口，手里攥着那封被雨浸软的信，很久没有动。';
    final entry = await repo.proposePending(
      manuscriptId: 'm1',
      sessionId: 's1',
      messageId: 'msg-9',
      excerpt: raw,
    );
    expect(entry.status, RecordEntryStatus.pending);
    // ★ 摘录纪律：原样搬运，逐字相等（本层无 LLM 调用、无变换）
    expect(entry.excerpt, raw);
    expect(entry.messageId, 'msg-9');
    expect(entry.decidedAt, isNull);

    final pending = await repo.listPending('m1');
    expect(pending, hasLength(1));
    expect(pending.first.excerpt, raw);
  });

  test('作者确认 → pending 落 kept；作者拒绝 → 落 rejected', () async {
    final kept = await repo.proposePending(
      manuscriptId: 'm1',
      excerpt: '要留的那条。',
    );
    final rejected = await repo.proposePending(
      manuscriptId: 'm1',
      excerpt: '要拒的那条。',
    );

    await repo.confirm(kept.id);
    await repo.reject(rejected.id);

    final all = await repo.listByManuscript('m1');
    expect(all, hasLength(2));
    final byId = {for (final e in all) e.id: e};
    expect(byId[kept.id]!.status, RecordEntryStatus.kept);
    expect(byId[rejected.id]!.status, RecordEntryStatus.rejected);
    expect(byId[kept.id]!.decidedAt, isNotNull);
    expect(byId[rejected.id]!.decidedAt, isNotNull);

    // 裁决后 pending 列表清空（不再以「待裁」形态出现）
    expect(await repo.listPending('m1'), isEmpty);
  });
}
