// ─────────────────────────────────────────────────────────────
// edit_diff_event_repository_test — 写作修改事件埋点（ADR-C132 批1）
//
// 覆盖：
//   1. 三类事件记录 → 按章节/会话/类型读回
//   2. saveChapterContent 自动捕获位置级 diff（修改 / 无变化 / 章节缺失）
//   3. 会话关联：章节有会话时事件记 session_id，无则 ''
//   4. EditDiffInput payload encode/decode 往返
// ─────────────────────────────────────────────────────────────

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/edit_diff_event_repository.dart';

void main() {
  late AppDatabase db;
  late EditDiffEventRepository repo;
  late ChapterRepository chapters;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = EditDiffEventRepository(db);
    chapters = ChapterRepository(db);
  });

  tearDown(() async => db.close());

  test('#1 三类事件记录 → 按章节读回（升序）', () async {
    await repo.recordDiff(
      EditDiffInput(
        sessionId: 's1',
        chapterId: 'c1',
        messageId: 'm1',
        anchorStart: 0,
        anchorEnd: 5,
        beforeText: '原文',
        afterText: '修改后',
        diffSegments: 1,
      ),
    );
    await repo.recordAnchorAcknowledged(
      sessionId: 's1',
      chapterId: 'c1',
      messageId: 'm1',
      anchorStart: 0,
      anchorEnd: 2,
      anchorText: '原文',
    );
    await repo.recordCompletion(sessionId: 's1', chapterId: 'c1');

    final byChapter = await repo.listByChapter('c1');
    expect(byChapter, hasLength(3));
    // 同秒写入 createdAt 相同，升序不保证插入序 → 按事件类型分组断言。
    final byType = {for (final e in byChapter) e.eventType: e};
    expect(byType[EditDiffEventTypes.diff]!.messageId, 'm1');
    expect(byType[EditDiffEventTypes.diff]!.beforeText, '原文');
    expect(byType[EditDiffEventTypes.diff]!.afterText, '修改后');
    expect(byType[EditDiffEventTypes.anchorAck]!.afterText, '原文');
    expect(byType[EditDiffEventTypes.completion]!.chapterId, 'c1');
  });

  test('#2 saveChapterContent 自动捕获 diff（修改 / 无变化 / 章节缺失）', () async {
    await db
        .into(db.manuscripts)
        .insert(ManuscriptsCompanion.insert(id: 'm1', title: Value('测试作品')));
    final chapterId = await chapters.createChapter('m1', title: '第一章');
    await chapters.saveChapterContent(chapterId, '他走了过去。');

    // 有修改 → 一条 diff 事件（无会话关联 → session_id=''；首次写入跳过）
    await chapters.saveChapterContent(chapterId, '他慢慢走了过去。');
    var events = await repo.listByChapter(chapterId);
    expect(events, hasLength(1));
    expect(events.first.eventType, EditDiffEventTypes.diff);
    // 变化中段语义：'他走了过去。'→'他慢慢走了过去。' 剥离公共前后缀
    // （他 / 走了过去。）后，中段是 ''→'慢慢'，位置 [1,3)。
    expect(events.first.beforeText, '');
    expect(events.first.afterText, '慢慢');
    expect(events.first.anchorStart, 1);
    expect(events.first.anchorEnd, 3);
    expect(events.first.sessionId, '');

    // 无变化保存 → 不写事件
    await chapters.saveChapterContent(chapterId, '他慢慢走了过去。');
    events = await repo.listByChapter(chapterId);
    expect(events, hasLength(1));

    // 章节不存在 → 不写事件、不报错
    await chapters.saveChapterContent('missing', 'x');
    events = await repo.listByChapter(chapterId);
    expect(events, hasLength(1));
  });

  test('#3 会话关联：章节有会话时事件记 session_id', () async {
    await db
        .into(db.manuscripts)
        .insert(ManuscriptsCompanion.insert(id: 'm2', title: Value('作品二')));
    final chapterId = await chapters.createChapter('m2', title: '第一章');
    await db
        .into(db.sessions)
        .insert(
          SessionsCompanion.insert(
            id: 's9',
            chapterId: Value<String?>(chapterId),
          ),
        );

    await chapters.saveChapterContent(chapterId, '旧');
    await chapters.saveChapterContent(chapterId, '新内容');

    final events = await repo.listByChapter(chapterId);
    expect(events, hasLength(1));
    expect(events.first.sessionId, 's9');
  });

  test('#4 EditDiffInput payload encode/decode 往返', () async {
    const input = EditDiffInput(
      sessionId: 's1',
      chapterId: 'c1',
      messageId: 'm1',
      anchorStart: 2,
      anchorEnd: 8,
      beforeText: 'a',
      afterText: 'b',
      diffSegments: 1,
    );
    final decoded = EditDiffInput.decodePayload(
      input.encodePayload(),
      sessionId: 's1',
      chapterId: 'c1',
      messageId: 'm1',
      anchorStart: 2,
      anchorEnd: 8,
      beforeText: 'a',
      afterText: 'b',
    );
    expect(decoded.diffSegments, 1);
    expect(decoded.chapterId, 'c1');
  });

  // #5 anchor_ack 可空位置（ADR-C132 批3）：诊断证据通常只有「段落位置 +
  //   原文摘录」，无字符级偏移 ⇒ anchorStart/anchorEnd/messageId 均可空。
  //   此前 #1 只覆盖了非空路径，可空写入路径零行为证据（产品代码已改 int?）。
  test(
    '#5 anchor_ack 位置可空：anchorStart/anchorEnd/messageId 均缺省时正常落库并读回 null',
    () async {
      // 锚点缺失：不传 anchorStart/anchorEnd/messageId，只给 anchorText。
      await repo.recordAnchorAcknowledged(
        sessionId: 's-anchor-null',
        chapterId: 'c-null',
        anchorText: '窗外下着雨，他把杯子放在桌上。',
      );

      final events = await repo.listByChapter('c-null');
      expect(events, hasLength(1));
      final e = events.single;
      expect(e.eventType, EditDiffEventTypes.anchorAck);
      // 表 schema nullable：缺省位置读回 null，而非 0 / 空串。
      // （不用 matcher `isNull`：与 drift 导出的 `isNull` 歧义，故用 == null。）
      expect(
        e.anchorStart == null,
        isTrue,
        reason: '未传 anchorStart ⇒ 读回 null（不是 0）',
      );
      expect(
        e.anchorEnd == null,
        isTrue,
        reason: '未传 anchorEnd ⇒ 读回 null（不是 0）',
      );
      expect(e.messageId == null, isTrue, reason: '未传 messageId ⇒ 读回 null');
      // anchorText 必填，落到 afterText 列（见产品代码 recordAnchorAcknowledged）
      expect(e.afterText, '窗外下着雨，他把杯子放在桌上。');
    },
  );

  // #6 对照：同一章节既有「精确位置 anchor_ack」又有「缺失位置 anchor_ack」
  //   ⇒ 两类并存，null 与非 null 不串扰（隔离可空与非空两条路径）。
  test('#6 精确位置与缺失位置 anchor_ack 同章节并存互不串扰', () async {
    await repo.recordAnchorAcknowledged(
      sessionId: 's1',
      chapterId: 'c-mix',
      messageId: 'm9',
      anchorStart: 3,
      anchorEnd: 7,
      anchorText: '精确片段',
    );
    await repo.recordAnchorAcknowledged(
      sessionId: 's1',
      chapterId: 'c-mix',
      anchorText: '摘录片段',
    );

    final events = await repo.listByChapter('c-mix');
    expect(events, hasLength(2));
    final precise = events.firstWhere((e) => e.anchorStart != null);
    final loose = events.firstWhere((e) => e.anchorStart == null);
    expect(precise.anchorStart, 3);
    expect(precise.anchorEnd, 7);
    expect(precise.messageId, 'm9');
    expect(loose.anchorStart == null, isTrue);
    expect(loose.anchorEnd == null, isTrue);
    expect(loose.afterText, '摘录片段');
  });

  // #7 ADR-C134 批3（M4a）：recordCompletion 扩展独立起稿标记。
  //   - source=null → payload 沿用列默认 ''（与 C132 旧行为零漂移）；
  //   - source=independent_drafting → payload JSON 可解码出 source 标记。
  test('#7 recordCompletion 独立起稿标记：source=null 与带标记两条路径', () async {
    // 普通成稿（source=null）：payload 不落 JSON（列默认 ''）。
    await repo.recordCompletion(sessionId: 's-c', chapterId: 'c-comp');
    // 独立起稿成稿：打标记。
    await repo.recordCompletion(
      sessionId: 's-c',
      chapterId: 'c-comp',
      source: CompletionSource.independentDrafting,
    );

    final events = await repo.listByChapter('c-comp');
    expect(events, hasLength(2));
    final plain = events.firstWhere(
      (e) => CompletionPayload.tryDecode(e.payload) == null,
    );
    final marked = events.firstWhere(
      (e) => CompletionPayload.tryDecode(e.payload) != null,
    );

    // 普通成稿：payload 不可解码为 completion JSON（列默认 '' → tryDecode 返回 null）。
    // （不用 matcher isNull/isNotNull：与 drift 导出歧义，故用 == null 显式判断。）
    expect(plain.eventType, EditDiffEventTypes.completion);
    expect(CompletionPayload.tryDecode(plain.payload) == null, isTrue);
    expect(
      plain.payload,
      isNot('{"kind":"completion","source":"independent_drafting"}'),
    );

    // 独立起稿成稿：payload 可解码出 source 标记（证据卡可观测）。
    final decoded = CompletionPayload.tryDecode(marked.payload);
    expect(decoded == null, isFalse);
    expect(decoded!.source, CompletionSource.independentDrafting);
  });
}
