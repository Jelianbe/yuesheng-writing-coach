// ─────────────────────────────────────────────────────────────
// manuscript_repository_test — 批次94-5 标签落库仓储单元测试
//
// 覆盖：
//   1. parseTags：合法 JSON string[] / 非法 JSON / 非数组 / 混入非字符串
//   2. createManuscript 带 tags → 落库 → parseTags 读回
//   3. updateManuscript(tags:) → 更新落库
//   4. 未传 tags 的 update 不清空既有 tags
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';

void main() {
  late AppDatabase db;
  late ManuscriptRepository repo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = ManuscriptRepository(db);
  });

  tearDown(() async => db.close());

  group('parseTags（批次94-5）', () {
    test('#1 合法 JSON string[] → 原样返回', () {
      final m = Manuscript(
        id: 'm1',
        title: 't',
        description: '',
        genre: '',
        tags: '["重生","系统"]',
        language: '中文',
        status: 'active',
        sortOrder: 0,
        createdAt: 0,
        updatedAt: 0,
      );
      expect(ManuscriptRepository.parseTags(m), ['重生', '系统']);
    });

    test('#2 非法 JSON → 空列表（容错）', () {
      final m = Manuscript(
        id: 'm1',
        title: 't',
        description: '',
        genre: '',
        tags: 'not-json{',
        language: '中文',
        status: 'active',
        sortOrder: 0,
        createdAt: 0,
        updatedAt: 0,
      );
      expect(ManuscriptRepository.parseTags(m), isEmpty);
    });

    test('#3 非数组 JSON → 空列表（容错）', () {
      final m = Manuscript(
        id: 'm1',
        title: 't',
        description: '',
        genre: '',
        tags: '{"a":1}',
        language: '中文',
        status: 'active',
        sortOrder: 0,
        createdAt: 0,
        updatedAt: 0,
      );
      expect(ManuscriptRepository.parseTags(m), isEmpty);
    });

    test('#4 混入非字符串元素 → 仅保留字符串', () {
      final m = Manuscript(
        id: 'm1',
        title: 't',
        description: '',
        genre: '',
        tags: '["重生", 42, null]',
        language: '中文',
        status: 'active',
        sortOrder: 0,
        createdAt: 0,
        updatedAt: 0,
      );
      expect(ManuscriptRepository.parseTags(m), ['重生']);
    });
  });

  group('tags 落库读写（批次94-5）', () {
    test('#5 createManuscript(tags:) → 读回一致', () async {
      final id = await repo.createManuscript(
        title: '测试稿',
        tags: ['重生', '系统'],
      );
      final m = await repo.getManuscript(id);
      expect(ManuscriptRepository.parseTags(m!), ['重生', '系统']);
    });

    test('#6 updateManuscript(tags:) → 更新落库', () async {
      final id = await repo.createManuscript(title: '测试稿');
      await repo.updateManuscript(id, tags: ['悬疑', '修仙']);
      final m = await repo.getManuscript(id);
      expect(ManuscriptRepository.parseTags(m!), ['悬疑', '修仙']);
    });

    test('#7 未传 tags 的 update 不清空既有 tags', () async {
      final id = await repo.createManuscript(
        title: '测试稿',
        tags: ['甜宠'],
      );
      await repo.updateManuscript(id, title: '改名');
      final m = await repo.getManuscript(id);
      expect(ManuscriptRepository.parseTags(m!), ['甜宠']);
    });

    test('#8 未传 tags 的 create 落库为空数组', () async {
      final id = await repo.createManuscript(title: '测试稿');
      final m = await repo.getManuscript(id);
      expect(ManuscriptRepository.parseTags(m!), isEmpty);
    });
  });
}
