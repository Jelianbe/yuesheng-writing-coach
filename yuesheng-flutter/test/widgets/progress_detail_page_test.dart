// ─────────────────────────────────────────────────────────────
// progress_detail_page_test — 学习进度详情页 Widget 测试
//
// 覆盖路径：
//   #1 空数据 → 概览卡默认值 + 症候趋势空态 + 生成报告按钮
//   #2 有数据 → 概览卡统计 + 诊断历史 + 问题统计 + 症候趋势行
//   #3 生成学习报告 → 报告视图（标题 + 文本 + 返回）
//   #4 症候趋势行点击 → 症候详情弹层
//   #5 报告视图分享按钮 → 调 share_plus 通道（批次 47 对齐 RN Share.share）
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/database/utils.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/widgets/progress_detail_page.dart';

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

  tearDown(() {
    container.dispose();
    db.close();
  });

  Widget buildPage() {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: ProgressDetailPage(sessionId: sessionId)),
    );
  }

  Future<void> insertDiagnosis({
    required int timestamp,
    required List<Map<String, dynamic>> syndromes,
  }) async {
    await db
        .into(db.diagnosisResults)
        .insert(
          DiagnosisResultsCompanion.insert(
            id: generateUuid(),
            sessionId: sessionId,
            messageId: 'msg-${generateUuid()}',
            syndromes: Value(jsonEncode(syndromes)),
            suggestedActions: const Value('[]'),
            confidence: const Value(0.8),
            timestamp: Value(timestamp),
            createdAt: Value(timestamp),
          ),
        );
  }

  Future<void> insertProblem({
    required String syndromeId,
    required String name,
    required String severity,
    required String status,
    required int createdAt,
    int? resolvedAt,
  }) async {
    await db
        .into(db.activeProblems)
        .insert(
          ActiveProblemsCompanion.insert(
            id: 'ap-${generateUuid()}',
            sessionId: sessionId,
            syndromeId: syndromeId,
            syndromeName: Value(name),
            severity: Value(severity),
            status: Value(status),
            createdAt: Value(createdAt),
            resolvedAt: Value(resolvedAt),
          ),
        );
  }

  Future<void> setPhase(String phase) async {
    await (db.update(db.teachingState)
          ..where((t) => t.sessionId.equals(sessionId)))
        .write(TeachingStateCompanion(currentPhase: Value(phase)));
  }

  group('ProgressDetailPage', () {
    testWidgets('#1 空数据 → 概览卡默认值 + 症候趋势空态 + 生成报告按钮', (tester) async {
      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      expect(find.text('学习进度'), findsOneWidget);
      // 概览卡默认值
      expect(find.text('建立投入'), findsOneWidget); // P0_ENGAGE 标签
      expect(find.text('诊断次数'), findsOneWidget);
      // 症候趋势空态
      expect(find.text('暂无症候追踪'), findsOneWidget);
      // 生成报告按钮
      expect(find.text('生成学习报告'), findsOneWidget);
    });

    testWidgets('#2 有数据 → 概览卡统计 + 诊断历史 + 问题统计 + 症候趋势行', (tester) async {
      await setPhase('P2_PRACTICE_LOOP');
      await insertDiagnosis(
        timestamp: 1000,
        syndromes: [
          {'syndrome_id': 's1', 'name': '情绪标签化', 'severity': 'L2'},
          {'syndrome_id': 's2', 'name': '情节断裂', 'severity': 'L3'},
        ],
      );
      await insertDiagnosis(
        timestamp: 2000,
        syndromes: [
          {'syndrome_id': 's1', 'name': '情绪标签化', 'severity': 'L3'},
        ],
      );
      await insertProblem(
        syndromeId: 's1',
        name: '情绪标签化',
        severity: 'L3',
        status: 'active',
        createdAt: 1000,
      );
      await insertProblem(
        syndromeId: 's2',
        name: '情节断裂',
        severity: 'L2',
        status: 'resolved',
        createdAt: 900,
        resolvedAt: 1500,
      );

      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      // 概览卡：阶段标签 + 统计
      expect(find.text('训练循环'), findsOneWidget);
      expect(find.text('诊断次数'), findsOneWidget);
      expect(find.text('总问题数'), findsOneWidget);
      // 诊断历史 section
      expect(find.text('诊断历史'), findsOneWidget);
      expect(find.text('置信度 80%'), findsNWidgets(2));
      // 症候趋势
      expect(find.text('症候趋势追踪'), findsOneWidget);
      expect(find.text('情绪标签化'), findsWidgets);
      expect(find.text('情节断裂'), findsWidgets);
      expect(find.textContaining('出现 2 次'), findsOneWidget);
      // 问题统计（列表底部，滚动到可见）
      await tester.scrollUntilVisible(
        find.text('问题统计'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('问题统计'), findsOneWidget);
      expect(find.text('已解决'), findsWidgets);
      expect(find.text('待改进'), findsWidgets);
      expect(find.textContaining('共 2 条诊断'), findsOneWidget);
    });

    testWidgets('#2b 批次78 严重度筛选无匹配 → 空态「该档暂无问题」', (tester) async {
      await setPhase('P2_PRACTICE_LOOP');
      // 仅 L2 问题 → 点「L1建议」无匹配
      await insertProblem(
        syndromeId: 's1',
        name: '情绪标签化',
        severity: 'L2',
        status: 'active',
        createdAt: 1000,
      );

      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      // 滚动到问题统计区
      await tester.scrollUntilVisible(
        find.text('问题统计'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      // 默认「全部」→ 有一条 L2 问题
      expect(find.text('情绪标签化'), findsWidgets);
      expect(find.text('该档暂无问题'), findsNothing);

      // 切到 L1建议 → 空态提示（修复前为空白）
      await tester.tap(find.text('L1建议'));
      await tester.pumpAndSettle();

      expect(find.text('该档暂无问题'), findsOneWidget);
      expect(find.text('情绪标签化'), findsNothing);
    });

    testWidgets('#3 生成学习报告 → 报告视图（标题 + 文本 + 返回）', (tester) async {
      await setPhase('P2_PRACTICE_LOOP');
      await insertDiagnosis(
        timestamp: 1000,
        syndromes: [
          {'syndrome_id': 's1', 'name': '情绪标签化', 'severity': 'L3'},
        ],
      );
      await insertProblem(
        syndromeId: 's1',
        name: '情绪标签化',
        severity: 'L3',
        status: 'active',
        createdAt: 1000,
      );

      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      // 生成报告按钮在列表底部，先滚动到可见
      await tester.scrollUntilVisible(
        find.text('生成学习报告'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('生成学习报告'));
      await tester.pumpAndSettle();

      // 报告视图
      expect(find.text('学习报告'), findsOneWidget);
      expect(find.textContaining('悦生写作教练 - 学习报告'), findsOneWidget);
      expect(find.textContaining('当前阶段：训练循环'), findsOneWidget);
      expect(find.textContaining('情绪标签化（严重）'), findsOneWidget);

      // 返回 → 进度页
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.text('学习进度'), findsOneWidget);
    });

    testWidgets('#4 症候趋势行点击 → 症候详情弹层', (tester) async {
      await insertDiagnosis(
        timestamp: 1000,
        syndromes: [
          {'syndrome_id': 's1', 'name': '情绪标签化', 'severity': 'L2'},
        ],
      );

      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      await tester.tap(find.text('情绪标签化'));
      await tester.pumpAndSettle();

      // 复用批次 8 SyndromeDetailModal：出现次数/趋势/首次发现
      expect(find.text('出现 1 次'), findsOneWidget);
      expect(find.text('诊断记录'), findsOneWidget);
    });

    testWidgets('#5 报告视图分享按钮 → 调 share_plus 通道（批次 47）', (tester) async {
      await setPhase('P2_PRACTICE_LOOP');
      await insertDiagnosis(
        timestamp: 1000,
        syndromes: [
          {'syndrome_id': 's1', 'name': '情绪标签化', 'severity': 'L3'},
        ],
      );
      await insertProblem(
        syndromeId: 's1',
        name: '情绪标签化',
        severity: 'L3',
        status: 'active',
        createdAt: 1000,
      );

      await tester.pumpWidget(buildPage());
      await tester.pumpAndSettle();

      // 生成报告按钮在列表底部，先滚动到可见
      await tester.scrollUntilVisible(
        find.text('生成学习报告'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('生成学习报告'));
      await tester.pumpAndSettle();

      // mock share_plus 平台通道（'dev.fluttercommunity.plus/share'），记录调用
      const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
      String? sharedText;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(shareChannel, (call) async {
        expect(call.method, 'share');
        sharedText = call.arguments['text'] as String?;
        return null; // Android 分享结果
      });
      addTearDown(() => messenger.setMockMethodCallHandler(shareChannel, null));

      // 点击分享按钮
      await tester.tap(find.byIcon(Icons.share_outlined));
      await tester.pumpAndSettle();

      // 报告文本被传入分享通道；不再弹"开发中"提示
      expect(sharedText, contains('悦生写作教练 - 学习报告'));
      expect(find.text('分享功能开发中，敬请期待'), findsNothing);
    });
  });
}
