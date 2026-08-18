// ─────────────────────────────────────────────────────────────
// GenUICard widget 测试（B-1 GenUI v1）
//
// 覆盖：diff 渲染 / 占位渲染 / quiz 提交判分 + 答题状态持久化（写回 genui 消息 content）。
// 用内存 DB + appDatabaseProvider override 隔离。
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/widgets/gen_ui_card.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late SessionRepository sessionRepo;
  late String sessionId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    sessionRepo = SessionRepository(db);
    // 先建真实会话（messages.session_id 外键依赖），再在会话内播种首条消息；
    // 注意 addMessage 返回的是 message id，不是 session id，之前误用导致外键失败。
    final sid = await sessionRepo.createBlankSession(title: 'B-1 测试会话');
    await sessionRepo.addMessage(sid, 'user', 'hello');
    sessionId = sid;
  });

  tearDown(() {
    container.dispose();
    db.close();
  });

  Future<String> insertGenuiMsg(Map<String, dynamic> payload) async {
    return sessionRepo.addMessage(
      sessionId,
      'system',
      jsonEncode(payload),
      messageType: 'genui',
    );
  }

  Widget buildHost(String content, String messageId) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: GenUICard.fromMessageContent(content, messageId: messageId),
        ),
      ),
    );
  }

  group('diff 组件', () {
    testWidgets('渲染原文/改写与标题', (tester) async {
      final id = await insertGenuiMsg({
        'components': [
          {
            'type': 'diff',
            'title': '改写对比',
            'before': '他很愤怒',
            'after': '指节收紧',
          }
        ]
      });
      final content = jsonEncode({
        'components': [
          {
            'type': 'diff',
            'title': '改写对比',
            'before': '他很愤怒',
            'after': '指节收紧',
          }
        ]
      });
      await tester.pumpWidget(buildHost(content, id));
      await tester.pumpAndSettle();

      expect(find.text('改写对比'), findsOneWidget);
      expect(find.text('原文'), findsOneWidget);
      expect(find.text('改写'), findsOneWidget);
      expect(find.text('他很愤怒'), findsOneWidget);
      expect(find.text('指节收紧'), findsOneWidget);
    });
  });

  group('占位组件', () {
    testWidgets('stat 类型诚实渲染暂未支持', (tester) async {
      final id = await insertGenuiMsg({
        'components': [
          {'type': 'stat', 'title': '能力维度'}
        ]
      });
      final content = jsonEncode({
        'components': [
          {'type': 'stat', 'title': '能力维度'}
        ]
      });
      await tester.pumpWidget(buildHost(content, id));
      await tester.pumpAndSettle();

      expect(find.textContaining('将在后续版本支持'), findsOneWidget);
    });
  });

  group('quiz 组件', () {
    final quizPayload = {
      'components': [
        {
          'type': 'quiz',
          'title': '这句的问题',
          'items': [
            {
              'q': '「他很愤怒」违反什么？',
              'options': ['展示而非告知', '视角一致'],
              'answer': 0,
              'explanation': '情绪直接命名',
            }
          ]
        }
      ]
    };

    testWidgets('提交正确选项 → 显示答对并持久化', (tester) async {
      final id = await insertGenuiMsg(quizPayload);
      final content = jsonEncode(quizPayload);
      await tester.pumpWidget(buildHost(content, id));
      await tester.pumpAndSettle();

      // 选正确项
      await tester.tap(find.text('展示而非告知'));
      await tester.pumpAndSettle();
      // 提交
      await tester.tap(find.widgetWithText(ElevatedButton, '提交'));
      await tester.pumpAndSettle();

      expect(find.textContaining('答对 1 / 1'), findsOneWidget);

      // 持久化：DB 中该 genui 消息 content 含 answered=true + userAnswers
      final rows = await (db.select(db.messages)
            ..where((t) => t.id.equals(id)))
          .get();
      expect(rows.length, 1);
      final stored = jsonDecode(rows.first.content) as Map<String, dynamic>;
      final comp = (stored['components'] as List).first as Map;
      expect(comp['answered'], true);
      expect(comp['userAnswers'], [0]);
      expect(comp['results'], [true]);
    });

    testWidgets('未答完 → 提交按钮禁用', (tester) async {
      final id = await insertGenuiMsg(quizPayload);
      final content = jsonEncode(quizPayload);
      await tester.pumpWidget(buildHost(content, id));
      await tester.pumpAndSettle();

      final submit = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, '请完成所有题目'),
      );
      expect(submit.onPressed, isNull);
    });
  });
}
