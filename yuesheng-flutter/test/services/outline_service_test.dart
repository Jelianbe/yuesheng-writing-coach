// ─────────────────────────────────────────────────────────────
// outline_service_test — 批次72 大纲层业务编排单元测试
//
// 覆盖：
//   1. 无实体 → buildEntityIndexContext 返回 null（零 token）
//   2. 有实体 → 上下文含规范名/别名/已确认印象
//   3. matched_entity_id 命中 → 追加印象到已有实体（不新建）
//   4. matched_entity_id 幻觉 id → 回退别名匹配（防 AI 编造）
//   5. 别名交集匹配 → 命中已有实体（防同人物两次入库）
//   6. 新建实体 → pending 态，印象 pending
//   7. 印象去重（同实体同文本跳过）
//   8. conflict_with 采信（同实体已有印象 id）vs 幻觉置 null
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/outline_repository.dart';
import 'package:writingcoach/services/outline_parser.dart';
import 'package:writingcoach/services/outline_service.dart';

void main() {
  late AppDatabase db;
  late ManuscriptRepository msRepo;
  late OutlineRepository repo;
  late OutlineService service;
  late String manuscriptId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    msRepo = ManuscriptRepository(db);
    repo = OutlineRepository(db);
    service = OutlineService(repo);
    manuscriptId = await msRepo.createManuscript(title: '测试稿');
  });

  tearDown(() async => db.close());

  OutlineExtraction extraction({
    String? matchedEntityId,
    String type = 'character',
    String key = '王建国',
    List<String> aliases = const ['王叔'],
    List<(String, String?)> impressions = const [('冷酷的杀手，左眼有疤', null)],
  }) {
    return OutlineExtraction(
      entities: [
        OutlineEntityUpdate(
          type: type,
          key: key,
          aliases: aliases,
          matchedEntityId: matchedEntityId,
          impressions: impressions
              .map(
                (im) =>
                    OutlineImpressionUpdate(text: im.$1, conflictWith: im.$2),
              )
              .toList(),
        ),
      ],
    );
  }

  test('#1 无实体 → buildEntityIndexContext 返回 null', () async {
    expect(await service.buildEntityIndexContext(manuscriptId), isNull);
  });

  test('#2 有实体 → 上下文含规范名/别名/已确认印象（含印象 id）', () async {
    await service.applyOutlineExtraction(
      manuscriptId: manuscriptId,
      extraction: extraction(),
    );
    final entity = (await repo.listEntities(manuscriptId)).single;
    final imp = (await repo.listImpressions(entity.id)).single;
    // 索引只列 active 印象 → 先确认
    await repo.approveImpression(imp.id);

    final ctx = await service.buildEntityIndexContext(manuscriptId);
    expect(ctx, isNotNull);
    expect(ctx, contains('王建国'));
    expect(ctx, contains('王叔'));
    expect(ctx, contains(entity.id));
    // 批次74：索引带印象 id（供 AI 填 conflict_with 引用）
    expect(ctx, contains('[${imp.id}] 冷酷的杀手，左眼有疤'));
  });

  test('#12 buildEntityProtocolContext：协议说明含标记与规则（批次74）', () {
    final protocol = service.buildEntityProtocolContext();
    expect(protocol, contains('[YS_ENTITY]'));
    expect(protocol, contains('[/YS_ENTITY]'));
    expect(protocol, contains('matched_entity_id'));
    expect(protocol, contains('conflict_with'));
    expect(protocol, contains('一次只给增量'));
  });

  test('#3 matched_entity_id 命中 → 追加印象到已有实体（不新建）', () async {
    await service.applyOutlineExtraction(
      manuscriptId: manuscriptId,
      extraction: extraction(impressions: [('冷酷的杀手，左眼有疤', null)]),
    );
    final entities = await repo.listEntities(manuscriptId);
    expect(entities.length, 1);
    final id = entities.single.id;

    // 第二次：matched_entity_id 命中 → 追加新印象，实体数不变
    await service.applyOutlineExtraction(
      manuscriptId: manuscriptId,
      extraction: extraction(
        matchedEntityId: id,
        impressions: [('温柔的丈夫', null)],
      ),
    );
    final after = await repo.listEntities(manuscriptId);
    expect(after.length, 1, reason: '同一实体不应新建两条');

    final impressions = await repo.listImpressions(id);
    expect(impressions.length, 2);
  });

  test('#4 matched_entity_id 幻觉 id → 回退别名匹配（防 AI 编造）', () async {
    await service.applyOutlineExtraction(
      manuscriptId: manuscriptId,
      extraction: extraction(key: '王建国', aliases: ['王叔']),
    );

    // 幻觉 id：不存在，且新 key/别名命中已有实体 → 追加而非新建
    await service.applyOutlineExtraction(
      manuscriptId: manuscriptId,
      extraction: extraction(
        matchedEntityId: 'fake-id-999',
        key: '王建国',
        aliases: const ['王叔', '建国'],
        impressions: const [('开始涉足商界', null)],
      ),
    );
    final after = await repo.listEntities(manuscriptId);
    expect(after.length, 1, reason: '幻觉 id 应回退别名匹配，不新建');

    final impressions = await repo.listImpressions(after.single.id);
    expect(impressions.length, 2);
    // 别名合并去重
    expect(
      OutlineRepository.parseAliases(after.single.aliases),
      contains('建国'),
    );
  });

  test('#5 别名交集匹配 → 命中已有实体（防同人物两次入库）', () async {
    await service.applyOutlineExtraction(
      manuscriptId: manuscriptId,
      extraction: extraction(key: '王建国', aliases: ['王叔']),
    );

    // 第二次提取用「王叔」当 key（无 matched_entity_id）→ 别名交集命中已有
    await service.applyOutlineExtraction(
      manuscriptId: manuscriptId,
      extraction: extraction(
        matchedEntityId: null,
        key: '王叔',
        aliases: const [],
        impressions: const [('他是王建国的亲随', null)],
      ),
    );
    final after = await repo.listEntities(manuscriptId);
    expect(after.length, 1, reason: '别名「王叔」应命中「王建国」实体');
  });

  test('#6 新建实体 → pending 态，印象 pending', () async {
    await service.applyOutlineExtraction(
      manuscriptId: manuscriptId,
      extraction: extraction(impressions: const [('冷酷的杀手，左眼有疤', null)]),
    );
    final entity = (await repo.listEntities(manuscriptId)).single;
    expect(entity.status, 'pending');
    final impressions = await repo.listImpressions(entity.id);
    expect(impressions.single.status, 'pending');
    expect(impressions.single.conflictWith, isNull);
  });

  test('#7 印象去重（同实体同文本跳过）', () async {
    await service.applyOutlineExtraction(
      manuscriptId: manuscriptId,
      extraction: extraction(impressions: [('冷酷的杀手，左眼有疤', null)]),
    );
    final entity = (await repo.listEntities(manuscriptId)).single;

    // 第二次同文本印象 → 跳过
    await service.applyOutlineExtraction(
      manuscriptId: manuscriptId,
      extraction: extraction(
        matchedEntityId: entity.id,
        impressions: const [('冷酷的杀手，左眼有疤', null)],
      ),
    );
    expect((await repo.listImpressions(entity.id)).length, 1);
  });

  test('#8 conflict_with 采信 vs 幻觉置 null', () async {
    await service.applyOutlineExtraction(
      manuscriptId: manuscriptId,
      extraction: extraction(impressions: const [('冷酷的杀手', null)]),
    );
    final entity = (await repo.listEntities(manuscriptId)).single;
    final existingId = (await repo.listImpressions(entity.id)).single.id;

    // 第二次提取：一条指向已有印象（采信），一条指向不存在 id（幻觉置 null）
    await service.applyOutlineExtraction(
      manuscriptId: manuscriptId,
      extraction: OutlineExtraction(
        entities: [
          OutlineEntityUpdate(
            type: 'character',
            key: '王建国',
            aliases: const [],
            matchedEntityId: entity.id,
            impressions: const [
              OutlineImpressionUpdate(
                text: '温柔的丈夫',
                conflictWith: 'fake-id-999',
              ),
              OutlineImpressionUpdate(text: '开始涉足商界', conflictWith: null),
            ],
          ),
        ],
      ),
    );
    final impressions = await repo.listImpressions(entity.id);
    expect(impressions.length, 3);
    // 指向已有印象 id → 采信保留
    await service.applyOutlineExtraction(
      manuscriptId: manuscriptId,
      extraction: OutlineExtraction(
        entities: [
          OutlineEntityUpdate(
            type: 'character',
            key: '王建国',
            aliases: const [],
            matchedEntityId: entity.id,
            impressions: [
              OutlineImpressionUpdate(
                text: '矛盾的补充印象',
                conflictWith: existingId,
              ),
            ],
          ),
        ],
      ),
    );
    final after = await repo.listImpressions(entity.id);
    final conflictImp = after.lastWhere((i) => i.impression == '矛盾的补充印象');
    expect(conflictImp.conflictWith, existingId, reason: '指向已有印象应采信');
    // 幻觉 conflict id → null
    final hallucinated = after.firstWhere((i) => i.impression == '温柔的丈夫');
    expect(hallucinated.conflictWith, isNull);
  });

  test('#9 approveImpression：印象 active + 实体 active（批次73 确认操作）', () async {
    await service.applyOutlineExtraction(
      manuscriptId: manuscriptId,
      extraction: extraction(impressions: [('冷酷的杀手，左眼有疤', null)]),
    );
    final entity = (await repo.listEntities(manuscriptId)).single;
    expect(entity.status, 'pending');
    final imp = (await repo.listImpressions(entity.id)).single;

    await repo.approveImpression(imp.id);

    expect((await repo.listImpressions(entity.id)).single.status, 'active');
    final afterEntity = (await repo.listEntities(manuscriptId)).single;
    expect(afterEntity.status, 'active');
  });

  test('#10 rejectImpression：印象 rejected（确认卡「拒绝」）', () async {
    await service.applyOutlineExtraction(
      manuscriptId: manuscriptId,
      extraction: extraction(impressions: [('冷酷的杀手，左眼有疤', null)]),
    );
    final entity = (await repo.listEntities(manuscriptId)).single;
    final imp = (await repo.listImpressions(entity.id)).single;

    await repo.rejectImpression(imp.id);

    expect((await repo.listImpressions(entity.id)).single.status, 'rejected');
  });

  test('#11 冲突二选一：approve 冲突印象 → 旧印象 superseded', () async {
    // 先建两条印象（一条作为旧认知）
    await service.applyOutlineExtraction(
      manuscriptId: manuscriptId,
      extraction: extraction(impressions: [('冷酷的杀手', null)]),
    );
    final entity = (await repo.listEntities(manuscriptId)).single;
    final oldImp = (await repo.listImpressions(entity.id)).single;

    // 新印象标记冲突（指向旧印象）
    await service.applyOutlineExtraction(
      manuscriptId: manuscriptId,
      extraction: OutlineExtraction(
        entities: [
          OutlineEntityUpdate(
            type: 'character',
            key: '王建国',
            aliases: const [],
            matchedEntityId: entity.id,
            impressions: [
              OutlineImpressionUpdate(text: '温柔的丈夫', conflictWith: oldImp.id),
            ],
          ),
        ],
      ),
    );
    final newImp = (await repo.listImpressions(entity.id)).last;

    // 用户「接受」新印象 → 新 active、旧 superseded（二选一）
    await repo.approveImpression(newImp.id);

    final after = await repo.listImpressions(entity.id);
    expect(after.firstWhere((i) => i.id == newImp.id).status, 'active');
    expect(after.firstWhere((i) => i.id == oldImp.id).status, 'superseded');
  });
}
