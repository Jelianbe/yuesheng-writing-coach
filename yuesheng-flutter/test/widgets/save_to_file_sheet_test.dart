// ─────────────────────────────────────────────────────────────
// SaveToFileSheet 测试 — 保存到文件弹层（缺口清单 C 类）
//
// 覆盖：渲染（标题/副标题/角色 chips/文件名预填）/ 保存落库 /
// 角色切换 / 空内容拦截 / 空文件名兜底 / 首行截取 40 字。
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/reference_repository.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/widgets/save_to_file_sheet.dart';

void main() {
  late AppDatabase db;
  late String bookId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    // attached_files.book_id 有 FK → 预置真实作品作为保存目标
    bookId = await ManuscriptRepository(db).createManuscript(title: '测试作品');
  });

  tearDown(() async => db.close());

  Widget buildSheet({
    required String content,
    String? targetBookId,
    String bookTitle = '测试作品',
    String? suggestedRole,
    String? suggestedFileName,
    void Function(AttachedFileRow file)? onSaved,
  }) {
    return ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => SaveToFileSheet(
                    content: content,
                    bookId: targetBookId ?? bookId,
                    bookTitle: bookTitle,
                    suggestedRole: suggestedRole,
                    suggestedFileName: suggestedFileName,
                    onSaved: onSaved,
                  ),
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 打开弹层
  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
  }

  const firstLineContent = '这是教练的回复内容\n第二行内容';

  testWidgets('渲染：标题 + 副标题 + 角色 chips + 文件名预填首行', (tester) async {
    await tester.pumpWidget(
      buildSheet(
        content: firstLineContent,
        targetBookId: bookId,
        bookTitle: '测试作品',
      ),
    );
    await openSheet(tester);

    expect(find.text('保存到文件'), findsOneWidget);
    expect(find.text('保存到《测试作品》'), findsOneWidget);
    // 三个角色 chips
    expect(find.text('常规'), findsOneWidget);
    expect(find.text('大纲'), findsOneWidget);
    expect(find.text('素材'), findsOneWidget);
    // 文件名预填 = 内容首行
    final input = tester.widget<TextField>(find.byType(TextField));
    expect(input.controller!.text, '这是教练的回复内容');
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);
  });

  testWidgets('默认角色 general → 保存 → createAttachedFile 落库 + 弹层关闭', (
    tester,
  ) async {
    AttachedFileRow? saved;
    await tester.pumpWidget(
      buildSheet(
        content: firstLineContent,
        targetBookId: bookId,
        bookTitle: '测试作品',
        onSaved: (file) => saved = file,
      ),
    );
    await openSheet(tester);

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final rows = await db.select(db.attachedFiles).get();
    expect(rows, hasLength(1));
    expect(rows.single.bookId, bookId);
    expect(rows.single.fileRole, 'general');
    expect(rows.single.content, firstLineContent);
    expect(rows.single.fileName, '这是教练的回复内容');
    expect(saved, isNotNull);
    // 弹层已关闭
    expect(find.text('保存到文件'), findsNothing);
  });

  testWidgets('切换「素材」角色 → 保存 → file_role=material', (tester) async {
    await tester.pumpWidget(
      buildSheet(content: firstLineContent, targetBookId: bookId),
    );
    await openSheet(tester);

    await tester.tap(find.text('素材'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final rows = await db.select(db.attachedFiles).get();
    expect(rows.single.fileRole, 'material');
  });

  testWidgets('空内容 → 提示「内容为空，无法保存」且不落库', (tester) async {
    await tester.pumpWidget(buildSheet(content: '', targetBookId: bookId));
    await openSheet(tester);

    // 空内容 → 文件名预填日期兜底
    final input = tester.widget<TextField>(find.byType(TextField));
    expect(input.controller!.text, startsWith('AI 回复 - '));

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('内容为空，无法保存'), findsOneWidget);
    final rows = await db.select(db.attachedFiles).get();
    expect(rows, isEmpty);
  });

  testWidgets('清空文件名 → 保存兜底「未命名」', (tester) async {
    await tester.pumpWidget(
      buildSheet(content: firstLineContent, targetBookId: bookId),
    );
    await openSheet(tester);

    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final rows = await db.select(db.attachedFiles).get();
    expect(rows.single.fileName, '未命名');
  });

  testWidgets('长首行 > 40 字 → 预填截取前 40 字', (tester) async {
    final longFirstLine = '一' * 50;
    await tester.pumpWidget(buildSheet(content: '$longFirstLine\n第二行'));
    await openSheet(tester);

    final input = tester.widget<TextField>(find.byType(TextField));
    expect(input.controller!.text, hasLength(40));
    expect(input.controller!.text, '一' * 40);
  });

  testWidgets('suggestedFileName 优先于内容首行预填', (tester) async {
    await tester.pumpWidget(
      buildSheet(content: firstLineContent, suggestedFileName: '用户指定名称'),
    );
    await openSheet(tester);

    final input = tester.widget<TextField>(find.byType(TextField));
    expect(input.controller!.text, '用户指定名称');
  });
}
