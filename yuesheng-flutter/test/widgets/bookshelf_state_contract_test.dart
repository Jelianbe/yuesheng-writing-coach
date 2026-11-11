// ─────────────────────────────────────────────────────────────
// bookshelf_state_contract_test — 书架三态 + AppBar 图标契约
//
// 真源：`T-20261111-01` U1 设计稿（舰长 2026-11-11 批）
//   §ST-5 空态 / 无结果态**成套互斥**契约（三例 + 负对照）
//   §IA-1 搜索态收掉「新建作品」
//   §IA-2 空库时 AppBar 不出图标
//
// 写作纪律（设计稿 §11 三条）：
//   ① 断言写成「完全在内 / 顺序在前 / 存在且互斥」，**不写像素常量**
//   ② 每条正向断言配一条负对照，否则可能只是在测「整页没渲染」
//   ③ 每条判据在改动前必须是红的（改动前实测已记入批次回执）
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/features/bookshelf/bookshelf_page.dart';
import 'package:writingcoach/providers/app_providers.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() {
    container.dispose();
    db.close();
  });

  Widget buildPage() => UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: BookshelfPage()),
  );

  Future<void> usePhone(WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(360, 740));
    addTearDown(() => t.binding.setSurfaceSize(null));
  }

  // ══════════════════════════════════════════════════════════
  // ST-5：空态 vs 搜索无结果 —— 三例成套（两态互斥 + 负对照）
  // ══════════════════════════════════════════════════════════
  group('ST-5 空态 / 无结果态互斥契约', () {
    testWidgets('① 空库 → 只有「空库」图标，无「无结果」图标', (tester) async {
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.library_books), findsOneWidget);
      expect(find.byIcon(Icons.search_off), findsNothing);
    });

    testWidgets('② 有 1 本 + 搜索无命中 → 只有「无结果」图标', (tester) async {
      await ManuscriptRepository(db).createManuscript(title: '测试作品');
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      // 进入搜索态并输入一个绝不命中的串
      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'zzz绝不存在zzz');
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.search_off), findsOneWidget);
      expect(find.byIcon(Icons.library_books), findsNothing);
    });

    testWidgets('③ 负对照：有 1 本且无搜索 → 两个图标都不在', (tester) async {
      await ManuscriptRepository(db).createManuscript(title: '测试作品');
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      // 这一例是前两例的支点：若它不成立，说明 ①② 只是在测
      // 「页面里凑巧只有一个图标」，并不证明两态互斥。
      expect(find.byIcon(Icons.library_books), findsNothing);
      expect(find.byIcon(Icons.search_off), findsNothing);
      // 正对照：列表确实渲染出来了（否则本条可能因为页面空白而恒真）
      expect(find.text('测试作品'), findsOneWidget);
    });
  });

  // ══════════════════════════════════════════════════════════
  // IA-1 / IA-2：AppBar 图标随状态收敛
  // ══════════════════════════════════════════════════════════
  group('IA-1 / IA-2 AppBar 图标契约', () {
    testWidgets('IA-2 空库 → 搜索/排序/新建三个图标全部不渲染', (tester) async {
      await usePhone(tester);
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.search), findsNothing);
      expect(find.byIcon(Icons.sort), findsNothing);
      expect(find.byIcon(Icons.add), findsNothing);
      // 正对照：空态的主 CTA 必须在（否则可能整页没渲染）
      expect(find.text('新建作品'), findsOneWidget);
    });

    testWidgets('IA-2 负对照：有 1 本 → 三个图标都在', (tester) async {
      await usePhone(tester);
      await ManuscriptRepository(db).createManuscript(title: '测试作品');
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.search), findsOneWidget);
      expect(find.byIcon(Icons.sort), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('IA-1 搜索态 → 收掉「新建作品」，保留「排序」', (tester) async {
      await usePhone(tester);
      await ManuscriptRepository(db).createManuscript(title: '测试作品');
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.add), findsNothing, reason: '搜索态不该出现新建');
      expect(find.byIcon(Icons.sort), findsOneWidget, reason: '排序要留着');
      // 负对照：确认真的进了搜索态（否则「add 不见了」可能是页面崩了）
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    });

    testWidgets('IA-1 退出搜索态 → 「新建作品」回来', (tester) async {
      await usePhone(tester);
      await ManuscriptRepository(db).createManuscript(title: '测试作品');
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.add), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });
  });
}
