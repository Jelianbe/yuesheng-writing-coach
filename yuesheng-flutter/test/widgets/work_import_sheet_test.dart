// ─────────────────────────────────────────────────────────────
// WorkImportSheet widget 测试 — 作品导入弹层
//
// 覆盖路径：
//   1. 粘贴文本 → 导入闭环（稿件/章节/主引用落库 + 回调）
//   2. 粘贴对话框取消 → 不导入
//   3. 主弹层取消按钮 → 关闭
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/services/work_import_service.dart';
import 'package:writingcoach/widgets/work_import_sheet.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async => db.close());

  // 通过真实路由打开弹层（保证 _finish 的 Navigator.pop 可正常关闭）
  Widget buildHost(
    String sessionId,
    void Function(WorkImportResult? result) onComplete,
  ) {
    return ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => WorkImportSheet(
                    sessionId: sessionId,
                    onUploadComplete: (r) => onComplete(r),
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

  Future<void> openSheet(
    WidgetTester tester,
    String sessionId,
    void Function(WorkImportResult? result) onComplete,
  ) async {
    await tester.pumpWidget(buildHost(sessionId, onComplete));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
  }

  testWidgets('#1 粘贴文本 → 导入闭环（稿件/章节/主引用落库 + 回调 + 弹层关闭）', (tester) async {
    final sessionId = await SessionRepository(db).createBlankSession();
    WorkImportResult? result;
    await openSheet(tester, sessionId, (r) => result = r);

    expect(find.text('导入作品'), findsOneWidget);

    // 打开粘贴对话框并输入带章节标记的文本
    await tester.tap(find.text('粘贴文本'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      '第一章 启程\n启程正文\n第二章 夜行\n夜行正文',
    );
    await tester.tap(find.text('确认导入'));
    await tester.pumpAndSettle();

    // 回调携带结果
    expect(result, isNotNull);
    expect(result!.title, '未命名作品'); // 粘贴文本无扩展名 → 兜底
    expect(result!.chapterCount, 2);
    expect(result!.totalWords, '启程正文'.length + '夜行正文'.length);
    expect(result!.firstChapterId, isNotEmpty);

    // 弹层已关闭
    expect(find.text('导入作品'), findsNothing);

    // 落库验证：稿件 + 章节 + 主引用
    final msList = await db.select(db.manuscripts).get();
    expect(msList, hasLength(1));
    expect(msList.single.title, '未命名作品');
    expect(msList.single.description, '从文件导入的作品（2章）');

    final chapters = await db.select(db.chapters).get();
    expect(chapters, hasLength(2));
    expect(chapters[0].title, '第一章 启程');
    expect(chapters[1].title, '第二章 夜行');

    final refs = await db.select(db.sessionReferences).get();
    expect(refs, hasLength(1));
    expect(refs.single.refType, 'chapter');
    expect(refs.single.refId, result!.firstChapterId);
    expect(refs.single.isPrimary, 1);
  });

  testWidgets('#2 粘贴对话框取消 → 不导入，弹层仍在', (tester) async {
    final sessionId = await SessionRepository(db).createBlankSession();
    WorkImportResult? result;
    await openSheet(tester, sessionId, (r) => result = r);

    await tester.tap(find.text('粘贴文本'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '第一章 启程\n正文');
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();

    expect(result, isNull);
    expect(find.text('导入作品'), findsOneWidget);
    expect(await db.select(db.manuscripts).get(), isEmpty);
  });

  testWidgets('#3 粘贴对话框空文本确认 → 不导入', (tester) async {
    final sessionId = await SessionRepository(db).createBlankSession();
    WorkImportResult? result;
    await openSheet(tester, sessionId, (r) => result = r);

    await tester.tap(find.text('粘贴文本'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认导入'));
    await tester.pumpAndSettle();

    expect(result, isNull);
    expect(await db.select(db.manuscripts).get(), isEmpty);
  });

  testWidgets('#4 主弹层取消按钮 → 关闭', (tester) async {
    final sessionId = await SessionRepository(db).createBlankSession();
    await openSheet(tester, sessionId, (_) {});

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(find.text('导入作品'), findsNothing);
  });
}
