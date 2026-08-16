// ─────────────────────────────────────────────────────────────
// ReferenceBar widget 测试 — 聊天页顶部引用条
//
// 覆盖路径：
//   1. 无引用 → 占位文案「还没有引用作品，点下方按钮添加」+ 标题 + 引用数
//   2. 有主引用 → 主引用标签 + 标题
//   3. 多个引用 → 其它引用数量徽章（+N）
//   4. 展开 → 引用列表（类型标签 + 主引用徽章 + + 添加引用）
//   5. 点击引用 → 设为主引用（DB is_primary 迁移 + SnackBar）
//   6. 移除 → 引用消失 + SnackBar
//   7. 多选 → 全选 / 批量删除 → 引用清空
//   8. 「+ 添加引用」→ onPressPicker 回调
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/reference_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/widgets/reference_bar.dart';

void main() {
  late AppDatabase db;
  late SessionRepository sessionRepo;
  late ManuscriptRepository msRepo;
  late ReferenceRepository refRepo;
  late String sessionId;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sessionRepo = SessionRepository(db);
    msRepo = ManuscriptRepository(db);
    refRepo = ReferenceRepository(db);
  });

  tearDown(() async => db.close());

  Future<void> newSession() async {
    sessionId = await sessionRepo.createBlankSession(title: '测试会话');
  }

  Widget buildHost(
    void Function()? onPressPicker, {
    void Function(String action, String refType, String refTitle)?
    onReferencesChanged,
  }) {
    return ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        home: Scaffold(
          body: ReferenceBar(
            sessionId: sessionId,
            onPressPicker: onPressPicker ?? () {},
            onReferencesChanged: onReferencesChanged,
          ),
        ),
      ),
    );
  }

  testWidgets('#1 无引用 → 占位文案 + 标题 + 0 个引用', (tester) async {
    await newSession();
    await tester.pumpWidget(buildHost(null));
    await tester.pumpAndSettle();

    // 批次76：标题「引用管理」+ 空态引导文案
    expect(find.text('引用管理'), findsOneWidget);
    expect(find.text('0 个引用'), findsOneWidget);
    expect(find.text('还没有引用作品，点下方按钮添加'), findsOneWidget);
    // 无主引用时数量徽章不显示
    expect(find.textContaining('+'), findsNothing);
  });

  testWidgets('#2 有主引用 → 标签 + 标题显示', (tester) async {
    await newSession();
    final msId = await msRepo.createManuscript(title: '测试小说', genre: '小说');
    await refRepo.addReference(sessionId, 'manuscript', msId, isPrimary: true);

    await tester.pumpWidget(buildHost(null));
    await tester.pumpAndSettle();

    expect(find.text('作品（主引用）'), findsOneWidget);
    expect(find.text('测试小说'), findsOneWidget);
    expect(find.text('还没有引用作品，点下方按钮添加'), findsNothing);
    // 批次76：标题 + 引用数徽章（1 个引用）
    expect(find.text('引用管理'), findsOneWidget);
    expect(find.text('1 个引用'), findsOneWidget);
  });

  testWidgets('#3 多个引用 → +N 徽章', (tester) async {
    await newSession();
    final msId1 = await msRepo.createManuscript(title: '小说一', genre: '小说');
    final msId2 = await msRepo.createManuscript(title: '小说二', genre: '小说');
    await refRepo.addReference(sessionId, 'manuscript', msId1, isPrimary: true);
    await refRepo.addReference(sessionId, 'manuscript', msId2);

    await tester.pumpWidget(buildHost(null));
    await tester.pumpAndSettle();

    expect(find.text('+1'), findsOneWidget);
  });

  testWidgets('#4 展开 → 引用列表（类型标签 + 主引用徽章 + 添加按钮）', (tester) async {
    await newSession();
    final msId1 = await msRepo.createManuscript(title: '小说一', genre: '小说');
    final msId2 = await msRepo.createManuscript(title: '小说二', genre: '小说');
    await refRepo.addReference(sessionId, 'manuscript', msId1, isPrimary: true);
    await refRepo.addReference(sessionId, 'manuscript', msId2);

    await tester.pumpWidget(buildHost(null));
    await tester.pumpAndSettle();

    // 点击主引用行展开
    await tester.tap(find.text('小说一'));
    await tester.pumpAndSettle();

    // 列表：主引用行（小说一）+ 列表两行 + 类型标签 + 主引用徽章
    expect(find.text('小说一'), findsNWidgets(2)); // 主引用行 + 列表行
    expect(find.text('小说二'), findsOneWidget); // 仅列表行
    expect(find.text('作品'), findsNWidgets(2)); // 类型标签 x2
    expect(find.text('主引用'), findsOneWidget);
    expect(find.text('+ 添加引用'), findsOneWidget);
    expect(find.text('全选'), findsOneWidget); // 引用 >1 显示全选
  });

  testWidgets('#5 点击引用 → 设为主引用（DB 迁移 + SnackBar）', (tester) async {
    await newSession();
    final msId1 = await msRepo.createManuscript(title: '小说一', genre: '小说');
    final msId2 = await msRepo.createManuscript(title: '小说二', genre: '小说');
    await refRepo.addReference(sessionId, 'manuscript', msId1, isPrimary: true);
    await refRepo.addReference(sessionId, 'manuscript', msId2);

    await tester.pumpWidget(buildHost(null));
    await tester.pumpAndSettle();

    // 展开后点击「小说二」（非主引用）→ 设为主引用
    await tester.tap(find.text('小说一'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('小说二').last);
    await tester.pumpAndSettle();

    // DB 验证：小说二成为主引用
    final refs = await refRepo.listReferencesOfSession(sessionId);
    final ms2 = refs.firstWhere((r) => r.refId == msId2);
    final ms1 = refs.firstWhere((r) => r.refId == msId1);
    expect(ms2.isPrimary, 1);
    expect(ms1.isPrimary, 0);

    // SnackBar 提示
    expect(find.text('已切换到：小说二'), findsOneWidget);
  });

  testWidgets('#6 移除引用 → 引用消失 + SnackBar', (tester) async {
    await newSession();
    final msId = await msRepo.createManuscript(title: '测试小说', genre: '小说');
    await refRepo.addReference(sessionId, 'manuscript', msId, isPrimary: true);

    await tester.pumpWidget(buildHost(null));
    await tester.pumpAndSettle();

    // 展开 → 点移除按钮
    await tester.tap(find.text('测试小说'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    // 引用清空 → 占位文案回归
    expect(find.text('还没有引用作品，点下方按钮添加'), findsOneWidget);
    expect(find.text('测试小说'), findsNothing);
    expect(find.text('已移除引用：测试小说'), findsOneWidget);

    // DB 验证
    final refs = await refRepo.listReferencesOfSession(sessionId);
    expect(refs, isEmpty);
  });

  testWidgets('#7 多选批量删除 → 全选 / 已选 N 项 / 删除选中', (tester) async {
    await newSession();
    final msId1 = await msRepo.createManuscript(title: '小说一', genre: '小说');
    final msId2 = await msRepo.createManuscript(title: '小说二', genre: '小说');
    await refRepo.addReference(sessionId, 'manuscript', msId1, isPrimary: true);
    await refRepo.addReference(sessionId, 'manuscript', msId2);

    await tester.pumpWidget(buildHost(null));
    await tester.pumpAndSettle();

    // 展开 → 全选
    await tester.tap(find.text('小说一'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();

    // 多选操作条出现
    expect(find.text('已选 2 项'), findsOneWidget);
    expect(find.text('删除选中'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);

    // 删除选中
    await tester.tap(find.text('删除选中'));
    await tester.pumpAndSettle();

    // 全部清空 → 占位文案 + SnackBar
    expect(find.text('还没有引用作品，点下方按钮添加'), findsOneWidget);
    expect(find.text('已批量删除 2 项引用'), findsOneWidget);

    // DB 验证
    final refs = await refRepo.listReferencesOfSession(sessionId);
    expect(refs, isEmpty);
  });

  testWidgets('#8 「+ 添加引用」→ onPressPicker 回调', (tester) async {
    await newSession();
    final msId = await msRepo.createManuscript(title: '测试小说', genre: '小说');
    await refRepo.addReference(sessionId, 'manuscript', msId, isPrimary: true);

    var pickerCalls = 0;
    await tester.pumpWidget(buildHost(() => pickerCalls++));
    await tester.pumpAndSettle();

    await tester.tap(find.text('测试小说'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('+ 添加引用'));
    await tester.pumpAndSettle();

    expect(pickerCalls, 1);
  });

  testWidgets('#9 设主引用 → onReferencesChanged(set_primary)', (tester) async {
    await newSession();
    final msId1 = await msRepo.createManuscript(title: '小说一', genre: '小说');
    final msId2 = await msRepo.createManuscript(title: '小说二', genre: '小说');
    await refRepo.addReference(sessionId, 'manuscript', msId1, isPrimary: true);
    await refRepo.addReference(sessionId, 'manuscript', msId2);

    String? gotAction;
    String? gotRefType;
    String? gotTitle;
    await tester.pumpWidget(
      buildHost(
        null,
        onReferencesChanged: (a, t, title) {
          gotAction = a;
          gotRefType = t;
          gotTitle = title;
        },
      ),
    );
    await tester.pumpAndSettle();

    // 展开 → 点「小说二」设主引用
    await tester.tap(find.text('小说一'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('小说二').last);
    await tester.pumpAndSettle();

    expect(gotAction, 'set_primary');
    expect(gotRefType, 'manuscript');
    expect(gotTitle, '小说二');
  });

  testWidgets('#10 移除引用 → onReferencesChanged(remove)', (tester) async {
    await newSession();
    final msId = await msRepo.createManuscript(title: '测试小说', genre: '小说');
    await refRepo.addReference(sessionId, 'manuscript', msId, isPrimary: true);

    String? gotAction;
    String? gotTitle;
    await tester.pumpWidget(
      buildHost(
        null,
        onReferencesChanged: (a, t, title) {
          gotAction = a;
          gotTitle = title;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('测试小说'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(gotAction, 'remove');
    expect(gotTitle, '测试小说');
  });
}
