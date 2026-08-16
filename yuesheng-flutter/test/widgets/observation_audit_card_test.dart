// ─────────────────────────────────────────────────────────────
// observation_audit_card_test — Editor 观察记录审计卡片测试
//
// 覆盖路径：
//   #1 折叠态：标题显示 + 统计摘要
//   #2 展开 + 有数据：总数/教练触发/触发率 + 最近列表
//   #3 展开 + 无数据：空态提示
//   #4 无 sessionId：无当前会话空态
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/editor_observation_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/services/editor_validator.dart';
import 'package:writingcoach/widgets/observation_audit_card.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late String sessionId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    sessionId = await SessionRepository(db).createBlankSession();
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Widget buildCard({String? sid, int recentLimit = 5}) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              ObservationAuditCard(sessionId: sid, recentLimit: recentLimit),
            ],
          ),
        ),
      ),
    );
  }

  /// 插入一条 observation（先建真实 message 以满足 FK 约束）
  Future<void> insertObservation({
    required String sessionId,
    required bool teacherTriggered,
    required int pronouncedCount,
    required int againstCount,
    String impression = '这段文字氛围营造出色，但视角在第三人称间轻微漂移。',
  }) async {
    final repo = EditorObservationRepository(db);
    final messageId = await SessionRepository(
      db,
    ).addMessage(sessionId, 'user', '测试消息');
    await repo.insertEditorObservation(
      InsertEditorObservationParams(
        sessionId: sessionId,
        messageId: messageId,
        editorResult: EditorResult(
          possibleIntent: '叙事推进',
          intentConfidence: 'moderate',
          observations: const [
            EditorObservation(
              dimension: 'perspective',
              dimensionName: '视角',
              phenomenon: '视角漂移',
              evidence: ['他推开门，看见自己站在镜子前。'],
              readerImpact: '读者混淆人称',
              observationVisibility: 'clear',
              intentAlignment: 'aligned',
            ),
          ],
          overallImpression: impression,
          strengths: const ['氛围营造'],
        ),
        teacherTriggered: teacherTriggered,
        pronouncedCount: pronouncedCount,
        againstCount: againstCount,
      ),
    );
  }

  group('ObservationAuditCard', () {
    testWidgets('#1 折叠态：标题 + 摘要（有数据）', (tester) async {
      await insertObservation(
        sessionId: sessionId,
        teacherTriggered: true,
        pronouncedCount: 2,
        againstCount: 1,
      );
      await tester.pumpWidget(buildCard(sid: sessionId));
      await tester.pumpAndSettle();

      // 折叠态：标题可见 + 摘要（展开后加载的数据在折叠态也可缓存显示）
      expect(find.text('Editor 观察记录'), findsOneWidget);
      // 折叠态不显示统计明细（仅标题行）
      expect(find.text('总数'), findsNothing);
      expect(find.text('刷新'), findsNothing);
    });

    testWidgets('#2 展开 + 有数据 → 统计 + 列表 + 刷新', (tester) async {
      await insertObservation(
        sessionId: sessionId,
        teacherTriggered: true,
        pronouncedCount: 2,
        againstCount: 1,
      );
      await insertObservation(
        sessionId: sessionId,
        teacherTriggered: false,
        pronouncedCount: 0,
        againstCount: 2,
        impression: '第二段节奏平缓，细节丰富。',
      );
      await tester.pumpWidget(buildCard(sid: sessionId));
      await tester.pumpAndSettle();

      // 展开
      await tester.tap(find.text('Editor 观察记录'));
      await tester.pumpAndSettle();

      // 统计：总数 2 / 教练触发 1 / 触发率 50.0%
      expect(find.text('总数'), findsOneWidget);
      expect(find.text('2'), findsWidgets);
      expect(find.text('教练触发'), findsOneWidget);
      expect(find.text('1'), findsWidgets);
      expect(find.text('触发率'), findsOneWidget);
      expect(find.text('50.0%'), findsOneWidget);

      // 最近列表（2 条）：触发/未触发标签
      expect(find.textContaining('· 触发 ·'), findsOneWidget);
      expect(find.textContaining('· 未触发 ·'), findsOneWidget);
      expect(find.textContaining('pronounced 2 / against 1'), findsOneWidget);

      // 刷新按钮
      expect(find.text('刷新'), findsOneWidget);
    });

    testWidgets('#3 展开 + 无数据 → 空态提示', (tester) async {
      await tester.pumpWidget(buildCard(sid: sessionId));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Editor 观察记录'));
      await tester.pumpAndSettle();

      expect(find.text('暂无 observation 数据'), findsOneWidget);
    });

    testWidgets('#4 无 sessionId → 无当前会话空态', (tester) async {
      await tester.pumpWidget(buildCard());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Editor 观察记录'));
      await tester.pumpAndSettle();

      expect(find.text('无当前会话'), findsOneWidget);
    });
  });
}
