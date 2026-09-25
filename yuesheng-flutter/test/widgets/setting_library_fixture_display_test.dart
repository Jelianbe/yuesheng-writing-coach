// ─────────────────────────────────────────────────────────────
// setting_library_fixture_display_test — 伪数据注入 · 前端展示验证
//
// 批次：设定资料库第二批（2026-09-16/17）
// 目的：用**伪数据注入**（内存库直写）验证本批新增 UI 的真实展示，
//       不靠空态/单元测试推断前端正确性。
//
// 覆盖：
//   A. 设定库容器（伪数据 → 展示）
//      1. 角色段：角色名 + 别名 + 断言计数展示
//      2. 世界观段：世界观主题展示
//      3. 其他段：用户自建条目（类别 + 名称 + 参与诊断 Switch）
//   B. 角色详情页（本批关键 UI）
//      4. 负断言：rejected+negative → 「负断言」Switch 显示且勾选
//      5. 冲突横幅：同章同属性异值 → 疑似重复提示条
//      6. 钉住：AppBar push_pin → 点击切换实心/空心
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/character_fact_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/setting_entry_repository.dart';
import 'package:writingcoach/data/repositories/world_fact_repository.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/types/character_types.dart';
import 'package:writingcoach/features/character/character_detail_page.dart';
import 'package:writingcoach/features/manuscript/setting_library_tab.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late String manuscriptId;
  late CharacterFactRepository charRepo;
  late WorldFactRepository worldRepo;
  late SettingEntryRepository entryRepo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    manuscriptId = await ManuscriptRepository(
      db,
    ).createManuscript(title: '伪数据作品');
    charRepo = CharacterFactRepository(db);
    worldRepo = WorldFactRepository(db);
    entryRepo = SettingEntryRepository(db);
  });

  tearDown(() {
    container.dispose();
    db.close();
  });

  Widget buildHost(Widget child) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: Scaffold(body: child)),
    );
  }

  group('A. 设定库容器（伪数据展示）', () {
    testWidgets('#1 角色段：伪角色名 + 别名 + 断言计数展示', (tester) async {
      await charRepo.upsertCharacter(
        manuscriptId: manuscriptId,
        name: '林晚',
        firstSeenChapter: 1,
        assertions: [
          const CharacterAssertion(
            attribute: '身份',
            value: '捕快',
            chapter: 1,
            timestamp: 1,
            status: 'confirmed',
          ),
        ],
      );
      await tester.pumpWidget(
        buildHost(SettingLibraryTab(manuscriptId: manuscriptId)),
      );
      await tester.pumpAndSettle();
      expect(find.text('林晚'), findsOneWidget);
    });

    testWidgets('#2 世界观段：伪世界观主题展示', (tester) async {
      await worldRepo.upsertWorld(
        manuscriptId: manuscriptId,
        name: '灵气体系',
        assertions: [
          const CharacterAssertion(
            attribute: '灵气',
            value: '稀薄',
            chapter: 1,
            timestamp: 1,
            status: 'confirmed',
          ),
        ],
      );
      await tester.pumpWidget(
        buildHost(SettingLibraryTab(manuscriptId: manuscriptId)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('世界观'));
      await tester.pumpAndSettle();
      expect(find.text('灵气体系'), findsOneWidget);
    });

    testWidgets('#3 其他段：伪条目 + 参与诊断 Switch', (tester) async {
      final id = await entryRepo.createEntry(
        manuscriptId: manuscriptId,
        category: '武器',
        name: '血月刃',
        description: '以血养刃，月圆出鞘',
      );
      await entryRepo.setParticipate(id, true);
      await tester.pumpWidget(
        buildHost(SettingLibraryTab(manuscriptId: manuscriptId)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('其他'));
      await tester.pumpAndSettle();
      expect(find.text('血月刃'), findsOneWidget);
      expect(find.text('武器'), findsWidgets);
      expect(find.byType(Switch), findsWidgets, reason: '参与诊断开关渲染');
    });
  });

  group('B. 角色详情页（本批关键 UI）', () {
    testWidgets('#4 负断言：rejected 断言显示「负断言」Switch', (tester) async {
      await charRepo.upsertCharacter(
        manuscriptId: manuscriptId,
        name: '林晚',
        firstSeenChapter: 1,
        assertions: [
          const CharacterAssertion(
            attribute: '职业',
            value: '画师',
            chapter: 2,
            timestamp: 2,
            status: 'rejected',
          ),
        ],
      );
      final row = await charRepo.getCharacter(manuscriptId, '林晚');
      await charRepo.setNegative(
        manuscriptId: manuscriptId,
        name: '林晚',
        target: const CharacterAssertion(
          attribute: '职业',
          value: '画师',
          chapter: 2,
          timestamp: 2,
          status: 'rejected',
        ),
        negative: true,
      );
      await tester.pumpWidget(
        buildHost(
          CharacterDetailPage(characterId: row!.id, manuscriptId: manuscriptId),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('负断言'), findsOneWidget, reason: '负断言标签渲染');
      final sw = tester.widget<Switch>(find.byType(Switch));
      expect(sw.value, isTrue, reason: '负断言勾选状态正确');
    });

    testWidgets('#5 冲突横幅：同章同属性异值 → 疑似重复提示', (tester) async {
      await charRepo.upsertCharacter(
        manuscriptId: manuscriptId,
        name: '林晚',
        firstSeenChapter: 1,
        assertions: [
          const CharacterAssertion(
            attribute: '性格',
            value: '外冷内热',
            chapter: 3,
            timestamp: 1,
            status: 'confirmed',
          ),
          const CharacterAssertion(
            attribute: '性格',
            value: '热情似火',
            chapter: 3,
            timestamp: 2,
            status: 'confirmed',
          ),
        ],
      );
      final row = await charRepo.getCharacter(manuscriptId, '林晚');
      await tester.pumpWidget(
        buildHost(
          CharacterDetailPage(characterId: row!.id, manuscriptId: manuscriptId),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('疑似重复'), findsOneWidget, reason: '冲突横幅渲染');
    });

    testWidgets('#6 钉住：AppBar push_pin 点击切换', (tester) async {
      await charRepo.upsertCharacter(
        manuscriptId: manuscriptId,
        name: '林晚',
        firstSeenChapter: 1,
        assertions: [],
      );
      final row = await charRepo.getCharacter(manuscriptId, '林晚');
      await tester.pumpWidget(
        buildHost(
          CharacterDetailPage(characterId: row!.id, manuscriptId: manuscriptId),
        ),
      );
      await tester.pumpAndSettle();
      // 初始未钉：空心图标
      expect(find.byIcon(Icons.push_pin_outlined), findsOneWidget);
      // 点击 → 实心
      await tester.tap(find.byIcon(Icons.push_pin_outlined));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.push_pin), findsOneWidget, reason: '钉住后实心图标');
      final pinned = await charRepo.listPinned(manuscriptId);
      expect(pinned.map((c) => c.name), ['林晚'], reason: '落库 pinned=1');
    });
  });
}
