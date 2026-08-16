// ─────────────────────────────────────────────────────────────
// subplot_fact_repository_test — 批次67 B62j 支线知识仓储单元测试
//
// 覆盖：
//   1. upsert 新支线 → list/get 往返
//   2. 重复 upsert → 更新（UNIQUE(manuscript_id, name)）
//   3. 按引入章节排序（null 排最后）
//   4. 回收字段（resolvedChapter/resolvedAt）往返保留
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/subplot_fact_repository.dart';

void main() {
  late AppDatabase db;
  late SubplotFactRepository repo;
  late String manuscriptId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = SubplotFactRepository(db);
    manuscriptId = await ManuscriptRepository(
      db,
    ).createManuscript(title: '测试稿');
  });

  tearDown(() async => db.close());

  test('#1 upsert 新支线 → list/get 往返', () async {
    await repo.upsertSubplot(
      manuscriptId: manuscriptId,
      name: '钥匙的秘密',
      introducedChapter: 3,
      description: '第3章捡到的钥匙',
    );

    final list = await repo.listSubplots(manuscriptId);
    expect(list.length, 1);
    expect(list.first.name, '钥匙的秘密');
    expect(list.first.introducedChapter, 3);
    expect(list.first.resolvedChapter, isNull);
    expect(list.first.description, '第3章捡到的钥匙');

    final got = await repo.getSubplot(manuscriptId, '钥匙的秘密');
    expect(got, isNotNull);
    expect(got!.name, '钥匙的秘密');
  });

  test('#2 重复 upsert → 更新（不新增行）', () async {
    await repo.upsertSubplot(
      manuscriptId: manuscriptId,
      name: '钥匙的秘密',
      introducedChapter: 3,
    );
    await repo.upsertSubplot(
      manuscriptId: manuscriptId,
      name: '钥匙的秘密',
      introducedChapter: 3,
      resolvedChapter: 8,
      resolvedAt: 8000,
    );

    final list = await repo.listSubplots(manuscriptId);
    expect(list.length, 1, reason: '同作品同名支线唯一');

    final got = await repo.getSubplot(manuscriptId, '钥匙的秘密');
    expect(got!.resolvedChapter, 8);
    expect(got.resolvedAt, 8000);
  });

  test('#3 按引入章节排序（null 排最后）', () async {
    await repo.upsertSubplot(
      manuscriptId: manuscriptId,
      name: '后期支线',
      introducedChapter: 9,
    );
    await repo.upsertSubplot(
      manuscriptId: manuscriptId,
      name: '无锚点支线',
      introducedChapter: null,
    );
    await repo.upsertSubplot(
      manuscriptId: manuscriptId,
      name: '早期支线',
      introducedChapter: 2,
    );

    final list = await repo.listSubplots(manuscriptId);
    expect(list.map((s) => s.name).toList(), ['早期支线', '后期支线', '无锚点支线']);
  });

  test('#4 回收字段（resolvedChapter/resolvedAt）往返保留', () async {
    await repo.upsertSubplot(
      manuscriptId: manuscriptId,
      name: '妹妹的身世',
      introducedChapter: 5,
      resolvedChapter: 12,
      resolvedAt: 12000,
    );

    final got = await repo.getSubplot(manuscriptId, '妹妹的身世');
    expect(got, isNotNull);
    expect(got!.introducedChapter, 5);
    expect(got.resolvedChapter, 12);
    expect(got.resolvedAt, 12000);
  });
}
