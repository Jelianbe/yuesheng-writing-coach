// ─────────────────────────────────────────────────────────────
// FileViewerModal widget 测试 — 素材内容查看页
//
// 覆盖路径：
//   1. 加载文件 → 显示文件名/角色徽章/内容
//   2. 文件不存在 → 空态提示
//   3. 更改角色 → 确认 → updateAttachedFile 落库 + UI 更新
//   4. 删除 → 确认 → 落库删除 + onDeleted 回调 + 页面关闭
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/reference_repository.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/widgets/file_viewer_modal.dart';

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

  Widget buildHost(String fileId, {VoidCallback? onDeleted}) {
    return ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        home: FileViewerModal(fileId: fileId, onDeleted: onDeleted),
      ),
    );
  }

  testWidgets('#1 加载文件 → 显示文件名/角色徽章/内容', (tester) async {
    final msId = await msRepo.createManuscript(title: '测试小说');
    final file = await refRepo.createAttachedFile(
      bookId: msId,
      fileName: '世界观大纲.md',
      fileRole: 'outline',
      content: '这是一个架空世界，共分五卷。\n第一卷：开端。',
    );

    await tester.pumpWidget(buildHost(file.id));
    await tester.pumpAndSettle();

    expect(find.text('世界观大纲.md'), findsOneWidget);
    expect(find.text('大纲'), findsOneWidget);
    expect(find.textContaining('这是一个架空世界'), findsOneWidget);
    expect(find.text('更改角色'), findsOneWidget);
    expect(find.text('删除文件'), findsOneWidget);
  });

  testWidgets('#2 文件不存在 → 空态提示', (tester) async {
    await tester.pumpWidget(buildHost('no-such-file'));
    await tester.pumpAndSettle();

    expect(find.text('文件不存在或已被删除'), findsOneWidget);
  });

  testWidgets('#3 更改角色 → 确认 → 落库 outline→material + UI 更新', (tester) async {
    final msId = await msRepo.createManuscript(title: '测试小说');
    final file = await refRepo.createAttachedFile(
      bookId: msId,
      fileName: '世界观.md',
      fileRole: 'outline',
      content: '五卷架构',
    );

    await tester.pumpWidget(buildHost(file.id));
    await tester.pumpAndSettle();

    await tester.tap(find.text('更改角色'));
    await tester.pumpAndSettle();
    // outline → material（角色轮换）
    expect(find.textContaining('将「世界观.md」的角色改为「素材」'), findsOneWidget);
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    // UI 徽章更新 + 落库
    expect(find.text('素材'), findsOneWidget);
    final updated = await refRepo.getAttachedFile(file.id);
    expect(updated!.fileRole, 'material');
  });

  testWidgets('#4 删除 → 确认 → 落库 + onDeleted + 页面关闭', (tester) async {
    final msId = await msRepo.createManuscript(title: '测试小说');
    final file = await refRepo.createAttachedFile(
      bookId: msId,
      fileName: '人物表.txt',
      fileRole: 'material',
      content: '主角：阿月',
    );
    var deleted = false;

    // 用可 pop 的路由承载（验证关闭）
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      fullscreenDialog: true,
                      builder: (_) => FileViewerModal(
                        fileId: file.id,
                        onDeleted: () => deleted = true,
                      ),
                    ),
                  ),
                  child: const Text('打开'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('删除文件'));
    await tester.pumpAndSettle();
    expect(find.textContaining('确定要删除「人物表.txt」'), findsOneWidget);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(deleted, isTrue);
    expect(await db.select(db.attachedFiles).get(), isEmpty);
    // 页面已关闭（回到宿主页）
    expect(find.text('打开'), findsOneWidget);
  });
}
