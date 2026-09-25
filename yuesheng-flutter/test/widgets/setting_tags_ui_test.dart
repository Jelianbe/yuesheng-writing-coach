// ─────────────────────────────────────────────────────────────
// setting_tags_ui_test — 条目标签 UI 测试（v37）
//
// 覆盖：
//   1. 空态：无标签时显示引导文案
//   2. 展示：已有标签渲染为 chips
//   3. 添加：输入回车后新增 chip 且持久化
//   4. 删除：chip 删除按钮移除标签
//   5. 「其他」弹窗：编辑已有条目可管理标签（保存后落库）
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/character_fact_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/setting_entry_repository.dart';
import 'package:writingcoach/data/repositories/setting_link_repository.dart'
    show SettingEntityKind;
import 'package:writingcoach/data/repositories/setting_tag_repository.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/features/character/character_detail_page.dart';
import 'package:writingcoach/widgets/setting/setting_entry_list_view.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late String manuscriptId;
  late String charId;
  late String entryId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    manuscriptId = await ManuscriptRepository(
      db,
    ).createManuscript(title: '标签 UI 测试作品');
    final charRepo = CharacterFactRepository(db);
    await charRepo.upsertCharacter(
      manuscriptId: manuscriptId,
      name: '林晚',
      firstSeenChapter: 1,
    );
    charId = (await charRepo.getCharacter(manuscriptId, '林晚'))!.id;
    entryId = await SettingEntryRepository(
      db,
    ).createEntry(manuscriptId: manuscriptId, category: '武器', name: '血月刃');
  });

  tearDown(() {
    container.dispose();
    db.close();
  });

  Widget buildCharacterPage() {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: CharacterDetailPage(
          characterId: charId,
          manuscriptId: manuscriptId,
        ),
      ),
    );
  }

  testWidgets('#1 空态：无标签时显示引导文案', (tester) async {
    await tester.pumpWidget(buildCharacterPage());
    await tester.pumpAndSettle();
    expect(find.text('标签'), findsWidgets);
    expect(find.textContaining('暂无标签'), findsOneWidget);
  });

  testWidgets('#2 展示：已有标签渲染为 chips', (tester) async {
    await SettingTagRepository(
      db,
    ).addTag(manuscriptId, SettingEntityKind.character, charId, '主角团');
    await tester.pumpWidget(buildCharacterPage());
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InputChip, '主角团'), findsOneWidget);
  });

  testWidgets('#3 添加：输入回车后新增 chip 且持久化', (tester) async {
    await tester.pumpWidget(buildCharacterPage());
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '添加标签'), '悬疑');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InputChip, '悬疑'), findsOneWidget);
    final persisted = await SettingTagRepository(
      db,
    ).listForEntity(SettingEntityKind.character, charId);
    expect(persisted, ['悬疑']);
  });

  testWidgets('#4 删除：chip 删除按钮移除标签', (tester) async {
    await SettingTagRepository(
      db,
    ).addTag(manuscriptId, SettingEntityKind.character, charId, '主角团');
    await tester.pumpWidget(buildCharacterPage());
    await tester.pumpAndSettle();
    final chip = find.widgetWithText(InputChip, '主角团');
    expect(chip, findsOneWidget);
    await tester.tap(find.descendant(of: chip, matching: find.byType(Icon)));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InputChip, '主角团'), findsNothing);
    final persisted = await SettingTagRepository(
      db,
    ).listForEntity(SettingEntityKind.character, charId);
    expect(persisted, isEmpty);
  });

  testWidgets('#5 「其他」弹窗：编辑条目管理标签并保存落库', (tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: SettingEntryListView(manuscriptId: manuscriptId),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('血月刃'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '添加标签'), '关键道具');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    final persisted = await SettingTagRepository(
      db,
    ).listForEntity(SettingEntityKind.setting, entryId);
    expect(persisted, ['关键道具']);
  });
}
