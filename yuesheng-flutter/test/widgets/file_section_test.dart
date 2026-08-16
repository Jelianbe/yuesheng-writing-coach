// ─────────────────────────────────────────────────────────────
// FileSection widget 测试 — 素材文件区
//
// 覆盖路径：
//   1. 空态 → 显示提示与「上传素材」按钮
//   2. 有素材 → 显示文件卡片 + role 徽章 + 大小
//   3. 「添加素材」→ 打开 MaterialUploadSheet
//   4. 长按删除 → 确认 → 删除落库
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/reference_repository.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/widgets/file_section.dart';

void main() {
  late AppDatabase db;
  late ManuscriptRepository msRepo;
  late ReferenceRepository refRepo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    msRepo = ManuscriptRepository(db);
    refRepo = ReferenceRepository(db);
  });

  tearDown(() async => db.close());

  Widget buildHost(String manuscriptId, String manuscriptTitle) {
    return ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              FileSection(
                manuscriptId: manuscriptId,
                manuscriptTitle: manuscriptTitle,
              ),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('#1 空态 → 提示 + 上传按钮', (tester) async {
    final msId = await msRepo.createManuscript(title: '测试小说');
    await tester.pumpWidget(buildHost(msId, '测试小说'));
    await tester.pumpAndSettle();

    expect(find.text('素材文件'), findsOneWidget);
    expect(find.text('还没有素材文件'), findsOneWidget);
    expect(find.text('上传素材'), findsOneWidget);
  });

  testWidgets('#2 有素材 → 文件卡片 + role 徽章 + 大小', (tester) async {
    final msId = await msRepo.createManuscript(title: '测试小说');
    await refRepo.createAttachedFile(
      bookId: msId,
      fileName: '世界观大纲.md',
      fileRole: 'outline',
      content: '这是一个架空世界，共分五卷。',
    );

    await tester.pumpWidget(buildHost(msId, '测试小说'));
    await tester.pumpAndSettle();

    expect(find.text('世界观大纲.md'), findsOneWidget);
    expect(find.text('大纲'), findsOneWidget);
    // 大小显示
    expect(find.textContaining('B'), findsWidgets);
  });

  testWidgets('#3 「添加素材」→ 打开 MaterialUploadSheet', (tester) async {
    final msId = await msRepo.createManuscript(title: '测试小说');
    await tester.pumpWidget(buildHost(msId, '测试小说'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('添加素材'));
    await tester.pumpAndSettle();

    expect(find.text('添加素材到《测试小说》'), findsOneWidget);
    expect(find.text('粘贴文本'), findsOneWidget);
  });

  testWidgets('#4 长按删除 → 确认 → 删除落库', (tester) async {
    final msId = await msRepo.createManuscript(title: '测试小说');
    final file = await refRepo.createAttachedFile(
      bookId: msId,
      fileName: '人物表.txt',
      fileRole: 'material',
      content: '主角：阿月',
    );

    await tester.pumpWidget(buildHost(msId, '测试小说'));
    await tester.pumpAndSettle();

    // 长按文件卡片 → 删除确认
    await tester.longPress(find.text('人物表.txt'));
    await tester.pumpAndSettle();
    expect(find.text('删除文件'), findsOneWidget);

    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    // 落库删除 + UI 回到空态
    final files = await db.select(db.attachedFiles).get();
    expect(files, isEmpty);
    expect(find.text('人物表.txt'), findsNothing);
    expect(find.text('还没有素材文件'), findsOneWidget);
    expect(file.id, isNotEmpty);
  });

  testWidgets('#5 批次75 行尾删除按钮可见 → 点击确认删除', (tester) async {
    final msId = await msRepo.createManuscript(title: '测试小说');
    final file = await refRepo.createAttachedFile(
      bookId: msId,
      fileName: '人物表.txt',
      fileRole: 'material',
      content: '主角：阿月',
    );

    await tester.pumpWidget(buildHost(msId, '测试小说'));
    await tester.pumpAndSettle();

    // 删除按钮可见（无需长按）
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(find.text('删除文件'), findsOneWidget);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    final files = await db.select(db.attachedFiles).get();
    expect(files, isEmpty);
    expect(find.text('人物表.txt'), findsNothing);
    expect(file.id, isNotEmpty);
  });

  testWidgets('#6 批次75 删除按钮 → 取消不删除', (tester) async {
    final msId = await msRepo.createManuscript(title: '测试小说');
    await refRepo.createAttachedFile(
      bookId: msId,
      fileName: '人物表.txt',
      fileRole: 'material',
      content: '主角：阿月',
    );

    await tester.pumpWidget(buildHost(msId, '测试小说'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    final files = await db.select(db.attachedFiles).get();
    expect(files, hasLength(1));
    expect(find.text('人物表.txt'), findsOneWidget);
  });
}
