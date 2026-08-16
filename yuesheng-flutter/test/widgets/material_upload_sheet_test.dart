// ─────────────────────────────────────────────────────────────
// MaterialUploadSheet widget 测试 — 素材文件添加弹层
//
// 覆盖路径：
//   1. 粘贴文本 → 表单 → 保存 → createAttachedFile 落库 + onSaved + 关闭
//   2. 素材类型切换（大纲）→ 保存落库 fileRole=outline
//   3. 空粘贴确认 → 不显示表单
//   4. 取消 → 不保存
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/reference_repository.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/widgets/material_upload_sheet.dart';

void main() {
  late AppDatabase db;
  late ManuscriptRepository msRepo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    msRepo = ManuscriptRepository(db);
  });

  tearDown(() async => db.close());

  Widget buildHost(
    String bookId,
    String bookTitle,
    void Function(AttachedFileRow? file)? onSaved,
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
                  builder: (_) => MaterialUploadSheet(
                    bookId: bookId,
                    bookTitle: bookTitle,
                    onSaved: (f) => onSaved?.call(f),
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
    String bookId,
    void Function(AttachedFileRow? file)? onSaved,
  ) async {
    await tester.pumpWidget(buildHost(bookId, '测试小说', onSaved));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
  }

  /// 粘贴文本并确认
  Future<void> pasteAndConfirm(WidgetTester tester, String content) async {
    await tester.tap(find.text('粘贴文本'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), content);
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
  }

  testWidgets('#1 粘贴文本 → 表单 → 保存 → 落库 + onSaved + 关闭', (tester) async {
    final msId = await msRepo.createManuscript(title: '测试小说');
    AttachedFileRow? saved;
    await openSheet(tester, msId, (f) => saved = f);

    await pasteAndConfirm(tester, '世界观设定：这是一个架空世界。');

    // 表单出现：类型 chips + 文件名预填（首行）
    expect(find.text('素材类型：'), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);
    // 文件名输入框预填首行
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '世界观设定：这是一个架空世界。',
    );

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.bookId, msId);
    expect(saved!.fileRole, 'general');
    expect(saved!.content, '世界观设定：这是一个架空世界。');
    expect(saved!.fileName, '世界观设定：这是一个架空世界。');

    // 落库
    final files = await db.select(db.attachedFiles).get();
    expect(files, hasLength(1));
    expect(files.single.fileName, saved!.fileName);

    // 弹层关闭
    expect(find.text('添加素材到《测试小说》'), findsNothing);
  });

  testWidgets('#2 切换素材类型「大纲」→ 保存 fileRole=outline', (tester) async {
    final msId = await msRepo.createManuscript(title: '测试小说');
    AttachedFileRow? saved;
    await openSheet(tester, msId, (f) => saved = f);

    await pasteAndConfirm(tester, '第一卷 主线大纲');

    await tester.tap(find.text('大纲'));
    await tester.pump();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.fileRole, 'outline');

    final files = await db.select(db.attachedFiles).get();
    expect(files.single.fileRole, 'outline');
  });

  testWidgets('#3 空粘贴确认 → 不显示表单', (tester) async {
    final msId = await msRepo.createManuscript(title: '测试小说');
    await openSheet(tester, msId, (_) {});

    await tester.tap(find.text('粘贴文本'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();

    expect(find.text('素材类型：'), findsNothing);
    expect(find.text('保存'), findsNothing);
  });

  testWidgets('#4 取消 → 不保存', (tester) async {
    final msId = await msRepo.createManuscript(title: '测试小说');
    var saved = false;
    await openSheet(tester, msId, (_) => saved = true);

    await pasteAndConfirm(tester, '人物表：主角阿月');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(saved, isFalse);
    expect(await db.select(db.attachedFiles).get(), isEmpty);
    expect(find.text('添加素材到《测试小说》'), findsNothing);
  });
}
