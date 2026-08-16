// ─────────────────────────────────────────────────────────────
// OutlineConfirmationCard 组件测试（批次73）
//
// 覆盖：
//   1. 渲染标题 + 实体名 + 印象文本 + 新实体标签
//   2. 冲突印象显示「与既有认知矛盾」横幅
//   3. 点「接受」→ outline_impression 落库 active + 行收起
//   4. 点「拒绝」→ outline_impression 落库 rejected + 行收起
//   5. fromMessageContent JSON 解析 + 兜底
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/outline_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/services/message_card_service.dart';
import 'package:writingcoach/widgets/outline_confirmation_card.dart';

OutlineConfirmationPayload buildPayload({
  String entityKey = '王建国',
  bool isNewEntity = true,
  List<OutlineImpressionPayload>? impressions,
}) {
  return OutlineConfirmationPayload(
    confirmationId: 'conf-1',
    entityId: 'ent-1',
    entityType: 'character',
    entityKey: entityKey,
    isNewEntity: isNewEntity,
    impressions:
        impressions ??
        const [OutlineImpressionPayload(id: 'imp-1', text: '巷口沉默，攥拳')],
  );
}

Widget wrap(Widget child, {ProviderContainer? container}) {
  if (container != null) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: Scaffold(body: child)),
    );
  }
  return ProviderScope(
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  late AppDatabase db;
  late OutlineRepository repo;
  late String manuscriptId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = OutlineRepository(db);
    manuscriptId = await ManuscriptRepository(
      db,
    ).createManuscript(title: '测试稿');
  });

  tearDown(() async => db.close());

  ProviderContainer container() {
    return ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
  }

  /// 预置实体 + 印象（pending），返回印象 id
  Future<String> seedImpression({
    String impression = '巷口沉默，攥拳',
    String? conflictWith,
  }) async {
    await repo.insertEntity(
      manuscriptId: manuscriptId,
      entityType: 'character',
      entityKey: '王建国',
      aliases: const [],
    );
    final entity = (await repo.listEntities(manuscriptId)).single;
    await repo.insertImpression(
      entityId: entity.id,
      impression: impression,
      conflictWith: conflictWith,
    );
    return (await repo.listImpressions(entity.id)).single.id;
  }

  testWidgets('#1 渲染标题 + 实体名 + 印象文本 + 新实体标签', (tester) async {
    await tester.pumpWidget(
      wrap(OutlineConfirmationCard(payload: buildPayload())),
    );
    expect(find.text('大纲记忆待确认'), findsOneWidget);
    expect(find.text('王建国'), findsOneWidget);
    expect(find.text('人物'), findsOneWidget);
    expect(find.text('新实体'), findsOneWidget);
    expect(find.text('巷口沉默，攥拳'), findsOneWidget);
    expect(find.text('接受'), findsOneWidget);
    expect(find.text('拒绝'), findsOneWidget);
  });

  testWidgets('#2 冲突印象显示矛盾横幅', (tester) async {
    await tester.pumpWidget(
      wrap(
        OutlineConfirmationCard(
          payload: buildPayload(
            isNewEntity: false,
            impressions: const [
              OutlineImpressionPayload(
                id: 'imp-1',
                text: '温柔的丈夫',
                conflictWith: 'old-imp',
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('与既有认知矛盾：接受将更新记忆，拒绝保留原有认知'), findsOneWidget);
    expect(find.text('已有实体'), findsOneWidget);
  });

  testWidgets('#3 点「接受」→ 印象落库 active + 行收起', (tester) async {
    final impId = await seedImpression();
    final c = container();
    addTearDown(c.dispose);

    await tester.pumpWidget(
      wrap(
        OutlineConfirmationCard(
          payload: buildPayload(
            impressions: [OutlineImpressionPayload(id: impId, text: '巷口沉默，攥拳')],
          ),
        ),
        container: c,
      ),
    );

    await tester.tap(find.text('接受'));
    await tester.pumpAndSettle();

    // 落库 active
    final impressions = await repo.listImpressions(
      (await repo.listEntities(manuscriptId)).single.id,
    );
    expect(impressions.single.status, 'active');
    // 行收起 → 显示已确认汇总
    expect(find.text('已确认 1/1 条印象'), findsOneWidget);
    expect(find.text('接受'), findsNothing);
  });

  testWidgets('#4 点「拒绝」→ 印象落库 rejected + 行收起', (tester) async {
    final impId = await seedImpression();
    final c = container();
    addTearDown(c.dispose);

    await tester.pumpWidget(
      wrap(
        OutlineConfirmationCard(
          payload: buildPayload(
            impressions: [OutlineImpressionPayload(id: impId, text: '巷口沉默，攥拳')],
          ),
        ),
        container: c,
      ),
    );

    await tester.tap(find.text('拒绝'));
    await tester.pumpAndSettle();

    final impressions = await repo.listImpressions(
      (await repo.listEntities(manuscriptId)).single.id,
    );
    expect(impressions.single.status, 'rejected');
    expect(find.text('已确认 1/1 条印象'), findsOneWidget);
  });

  testWidgets('#5 fromMessageContent JSON 解析 + 兜底', (tester) async {
    // 合法 JSON
    await tester.pumpWidget(
      wrap(
        OutlineConfirmationCard.fromMessageContent(
          '{"confirmationId":"c1","entityId":"e1","entityType":"character",'
          '"entityKey":"林晚","isNewEntity":true,'
          '"impressions":[{"id":"i1","text":"倔强的渔家女","conflictWith":null}]}',
        ),
      ),
    );
    expect(find.text('林晚'), findsOneWidget);
    expect(find.text('倔强的渔家女'), findsOneWidget);

    // 非法 JSON → 兜底空卡（不抛）
    await tester.pumpWidget(
      wrap(OutlineConfirmationCard.fromMessageContent('not-json')),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('#6 批次5（5.2）过期印象 → 置灰显示已过期，无操作按钮', (tester) async {
    final impId = await seedImpression();
    // 模拟超时清理（负窗口 → 立即过期）→ 印象 expired
    await repo.cleanupPendingImpressions(maxAgeDays: -1);
    final c = container();
    addTearDown(c.dispose);

    await tester.pumpWidget(
      wrap(
        OutlineConfirmationCard(
          payload: buildPayload(
            impressions: [OutlineImpressionPayload(id: impId, text: '巷口沉默，攥拳')],
          ),
        ),
        container: c,
      ),
    );
    // 等待异步 _loadDbStatuses 完成
    await tester.pumpAndSettle();

    expect(find.text('巷口沉默，攥拳'), findsOneWidget);
    expect(find.text('已过期/已处理'), findsOneWidget);
    expect(find.text('接受'), findsNothing, reason: '过期印象不再提供接受按钮');
    expect(find.text('拒绝'), findsNothing, reason: '过期印象不再提供拒绝按钮');
  });

  testWidgets('#7 批次5（5.2）已接受印象重开卡 → 置灰不重复确认', (tester) async {
    final impId = await seedImpression();
    final c = container();
    addTearDown(c.dispose);

    // 先接受落库 active
    await repo.approveImpression(impId);

    // 历史确认卡仍存在（重开会话）→ 以 DB 实际状态置灰
    await tester.pumpWidget(
      wrap(
        OutlineConfirmationCard(
          payload: buildPayload(
            impressions: [OutlineImpressionPayload(id: impId, text: '巷口沉默，攥拳')],
          ),
        ),
        container: c,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('已过期/已处理'), findsOneWidget);
    expect(find.text('接受'), findsNothing);
  });
}
