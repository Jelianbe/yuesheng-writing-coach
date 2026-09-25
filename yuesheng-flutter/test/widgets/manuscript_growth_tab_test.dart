// ─────────────────────────────────────────────────────────────
// manuscript_growth_tab_test — 书籍级成长页签（P0-2）
//
// 验证：
//   1. 有本书诊断 → 圆环 + 诊断数 + SeverityBar + 活跃问题 + 复发
//   2. 无诊断的书 → 空态引导
//   3. 错误 → 错误态
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/features/manuscript/manuscript_growth_tab.dart';

void main() {
  late AppDatabase db;
  late ManuscriptRepository manuscriptRepo;
  late ChapterRepository chapterRepo;
  late SessionRepository sessionRepo;
  late DiagnosisRepository diagRepo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    manuscriptRepo = ManuscriptRepository(db);
    chapterRepo = ChapterRepository(db);
    sessionRepo = SessionRepository(db);
    diagRepo = DiagnosisRepository(db);
  });

  tearDown(() async => db.close());

  /// 建一本书 + 一章，返回 (manuscriptId, chapterId)。
  Future<(String, String)> createBookWithChapter() async {
    final m = await manuscriptRepo.createManuscript(title: '成长测试书');
    final c = await chapterRepo.createChapter(m, title: '第一章');
    return (m, c);
  }

  /// 落一条诊断（L2）。
  Future<void> commitDiagnosis(String m, String c, String sessionId) async {
    await diagRepo.commitDiagnosis(
      DiagnosisInput(
        sessionId: sessionId,
        messageId: 'msg-$m',
        syndromes: const [
          {'syndrome_id': 'P003', 'name': '口语化', 'severity': 'L2'},
        ],
        suggestedActions: const [],
        confidence: 0.8,
        targetRefType: 'chapter',
        targetRefId: c,
      ),
    );
  }

  Future<void> pumpTab(WidgetTester tester, String manuscriptId) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: Scaffold(body: ManuscriptGrowthTab(manuscriptId: manuscriptId)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('#1 有诊断 → 圆环 + 诊断数 + 症候概览 + 活跃问题', (tester) async {
    final (m, c) = await createBookWithChapter();
    final sid = await sessionRepo.getOrCreateSessionForChapter(m, c);
    await commitDiagnosis(m, c, sid);

    await pumpTab(tester, m);

    expect(find.text('本书能力画像'), findsOneWidget);
    expect(find.text('本书诊断 1 次'), findsOneWidget);
    expect(find.text('本书症候概览'), findsOneWidget);
    expect(find.text('1 个活跃'), findsOneWidget);
    expect(find.text('口语化'), findsWidgets);
  });

  testWidgets('#2 无诊断 → 空态引导', (tester) async {
    final (m, _) = await createBookWithChapter();

    await pumpTab(tester, m);

    expect(find.text('这本书还没有诊断记录'), findsOneWidget);
    expect(find.text('本书能力画像'), findsNothing);
  });

  testWidgets('#3 多书隔离：只显示本书数据', (tester) async {
    final (m1, c1) = await createBookWithChapter();
    final m2 = await manuscriptRepo.createManuscript(title: '另一本书');
    final c2 = await chapterRepo.createChapter(m2, title: '第一章');
    final s1 = await sessionRepo.getOrCreateSessionForChapter(m1, c1);
    final s2 = await sessionRepo.getOrCreateSessionForChapter(m2, c2);
    await commitDiagnosis(m1, c1, s1);
    await commitDiagnosis(m2, c2, s2);

    await pumpTab(tester, m1);

    expect(find.text('本书诊断 1 次'), findsOneWidget);
    expect(find.text('本书诊断 2 次'), findsNothing);
  });
}
