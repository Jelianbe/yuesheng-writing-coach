// ─────────────────────────────────────────────────────────────
// MessageList widget 测试 — 消息列表
//
// 覆盖路径：
//   1. 渲染多条消息（user + assistant）
//   2. 空消息列表 + 非流式 → 显示空容器
//   3. 流式中 + streamingContent 非空 → 追加虚拟气泡
//   4. 流式中 + streamingContent 空 → 显示 ThinkingIndicator
//   5. 批次9/17：消息卡片分派（reference_change/phase_upgrade/
//      partial_agreement/phase_summary/diagnosis_failed）
//   6. 批次72：@ 引用徽章点击反查（改名后仍有效 / 删除归档提示不跳转）
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/widgets/diagnosis_failed_card.dart';
import 'package:writingcoach/widgets/message_bubble.dart';
import 'package:writingcoach/widgets/message_list.dart';
import 'package:writingcoach/widgets/partial_agreement_card.dart';
import 'package:writingcoach/widgets/phase_summary_card.dart';
import 'package:writingcoach/widgets/phase_upgrade_card.dart';
import 'package:writingcoach/widgets/reference_change_card.dart';

Message _msg({
  required String id,
  required String role,
  required String content,
  String messageType = 'chat',
  String? referencesJson,
}) {
  return Message(
    id: id,
    sessionId: 's1',
    role: role,
    content: content,
    timestamp: 1700000000,
    messageType: messageType,
    referencesJson: referencesJson,
  );
}

/// 最小路由：宿主页（MessageList）+ 两个跳转目标（Marker Text 标识）
GoRouter _buildRouter(Widget child) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, _) => Scaffold(body: child)),
      GoRoute(
        path: '/writing/:chapterId',
        builder: (_, _) => const Scaffold(body: Text('WRITING_PAGE')),
      ),
      GoRoute(
        path: '/manuscript-detail',
        builder: (_, _) => const Scaffold(body: Text('DETAIL_PAGE')),
      ),
    ],
  );
}

Future<void> _pumpList(
  WidgetTester tester,
  AppDatabase db, {
  required List<Message> messages,
  bool isStreaming = false,
  String streamingContent = '',
  void Function(String messageId)? onDelete,
  // 批次81：三卡回调透传（H1-H3）
  VoidCallback? onContinueTraining,
  VoidCallback? onViewProfile,
  VoidCallback? onBackToChat,
  VoidCallback? onAddContent,
  VoidCallback? onContinueChat,
  void Function(String feedback, String? quickOption)? onPartialAgreementSubmit,
  VoidCallback? onPartialAgreementSkip,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp.router(
        routerConfig: _buildRouter(
          MessageList(
            messages: messages,
            isStreaming: isStreaming,
            streamingContent: streamingContent,
            onDelete: onDelete,
            onContinueTraining: onContinueTraining,
            onViewProfile: onViewProfile,
            onBackToChat: onBackToChat,
            onAddContent: onAddContent,
            onContinueChat: onContinueChat,
            onPartialAgreementSubmit: onPartialAgreementSubmit,
            onPartialAgreementSkip: onPartialAgreementSkip,
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('MessageList', () {
    testWidgets('渲染多条消息', (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final messages = [
        _msg(id: 'm1', role: 'user', content: '你好'),
        _msg(id: 'm2', role: 'assistant', content: '你好，我是月笙'),
      ];

      await _pumpList(tester, db, messages: messages);

      expect(find.text('你好'), findsOneWidget);
      expect(find.text('你好，我是月笙'), findsOneWidget);
    });

    testWidgets('空消息列表 + 非流式 → 显示空容器', (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await _pumpList(tester, db, messages: const []);

      // 空列表应显示占位（SizedBox.shrink 或空容器）
      expect(find.byType(MessageBubble), findsNothing);
    });

    testWidgets('流式中 + streamingContent 非空 → 追加虚拟气泡', (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final messages = [_msg(id: 'm1', role: 'user', content: '你好')];

      await _pumpList(
        tester,
        db,
        messages: messages,
        isStreaming: true,
        streamingContent: '正在回复',
      );

      // 应渲染 user 消息 + streaming 虚拟消息
      expect(find.text('你好'), findsOneWidget);
      expect(find.text('正在回复'), findsOneWidget);
    });

    testWidgets('流式中 + streamingContent 空 → 显示 ThinkingIndicator', (
      tester,
    ) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await _pumpList(
        tester,
        db,
        messages: const [],
        isStreaming: true,
        streamingContent: '',
      );

      expect(find.byType(ThinkingIndicator), findsOneWidget);
    });
  });

  group('批次9：消息卡片分派', () {
    testWidgets('reference_change 消息 → ReferenceChangeCard', (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final messages = [
        _msg(id: 'm1', role: 'user', content: '你好'),
        _msg(
          id: 'm2',
          role: 'system',
          content: jsonEncode({
            'action': 'set_primary',
            'refType': 'chapter',
            'refTitle': '第一章',
          }),
          messageType: 'reference_change',
        ),
      ];

      await _pumpList(tester, db, messages: messages);

      expect(find.byType(ReferenceChangeCard), findsOneWidget);
      expect(find.text('主引用已切换'), findsOneWidget);
    });

    testWidgets('phase_upgrade 消息 → PhaseUpgradeCard', (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final messages = [
        _msg(
          id: 'm1',
          role: 'system',
          content: jsonEncode({'from': 'P0_ENGAGE', 'to': 'P1_WORLD'}),
          messageType: 'phase_upgrade',
        ),
      ];

      await _pumpList(tester, db, messages: messages);

      expect(find.byType(PhaseUpgradeCard), findsOneWidget);
      expect(find.text('进入新阶段！'), findsOneWidget);
      expect(find.text('世界观阶段'), findsOneWidget);
    });
  });

  group('批次17：三卡分派', () {
    testWidgets('partial_agreement 消息 → PartialAgreementCard', (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final messages = [
        _msg(
          id: 'm1',
          role: 'assistant',
          content: jsonEncode({
            'syndromeId': 'P001',
            'syndromeName': '视角跳跃症',
            'severity': 'L2',
          }),
          messageType: 'partial_agreement',
        ),
      ];

      await _pumpList(tester, db, messages: messages);

      expect(find.byType(PartialAgreementCard), findsOneWidget);
      expect(find.text('请补充不符合的地方'), findsOneWidget);
      expect(find.text('视角跳跃症'), findsOneWidget);
    });

    testWidgets('phase_summary 消息 → PhaseSummaryCard', (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final messages = [
        _msg(
          id: 'm1',
          role: 'assistant',
          content: jsonEncode({
            'result': 'passed',
            'resolvedSyndromeCount': 2,
            'trainingCount': 5,
            'trend': 'improving',
            'syndromeChanges': [
              {
                'syndromeId': 'P001',
                'syndromeName': '视角跳跃症',
                'trend': 'improving',
              },
            ],
          }),
          messageType: 'phase_summary',
        ),
      ];

      await _pumpList(tester, db, messages: messages);

      expect(find.byType(PhaseSummaryCard), findsOneWidget);
      expect(find.text('训练达标'), findsOneWidget);
      expect(find.text('视角跳跃症'), findsOneWidget);
    });

    testWidgets('diagnosis_failed 消息 → DiagnosisFailedCard', (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final messages = [
        _msg(
          id: 'm1',
          role: 'assistant',
          content: jsonEncode({'failureCount': 3}),
          messageType: 'diagnosis_failed',
        ),
      ];

      await _pumpList(tester, db, messages: messages);

      expect(find.byType(DiagnosisFailedCard), findsOneWidget);
      expect(find.text('未检测到明显问题'), findsOneWidget);
    });
  });

  group('批次81：三卡回调透传', () {
    testWidgets('phase_summary 三按钮 → 透传到宿主回调', (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      var continued = false;
      var profile = false;
      var back = false;
      await _pumpList(
        tester,
        db,
        messages: [
          _msg(
            id: 'm1',
            role: 'assistant',
            content: jsonEncode({
              'result': 'partial',
              'resolvedSyndromeCount': 1,
              'trainingCount': 4,
              'trend': 'improving',
              'syndromeChanges': <Object>[],
            }),
            messageType: 'phase_summary',
          ),
        ],
        onContinueTraining: () => continued = true,
        onViewProfile: () => profile = true,
        onBackToChat: () => back = true,
      );

      await tester.tap(find.text('继续训练'));
      await tester.tap(find.text('查看学员画像'));
      await tester.tap(find.text('返回对话'));
      await tester.pump();

      expect(continued, isTrue);
      expect(profile, isTrue);
      expect(back, isTrue);
    });

    testWidgets('diagnosis_failed 双按钮 → 透传到宿主回调', (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      var added = false;
      var continued = false;
      await _pumpList(
        tester,
        db,
        messages: [
          _msg(
            id: 'm1',
            role: 'assistant',
            content: jsonEncode({'failureCount': 1}),
            messageType: 'diagnosis_failed',
          ),
        ],
        onAddContent: () => added = true,
        onContinueChat: () => continued = true,
      );

      await tester.tap(find.text('补充内容'));
      await tester.tap(find.text('继续对话'));
      await tester.pump();

      expect(added, isTrue);
      expect(continued, isTrue);
    });

    testWidgets('partial_agreement 提交反馈/快速选项/跳过 → 透传到宿主回调', (
      tester,
    ) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      String? submittedFeedback;
      String? submittedQuick;
      var skipped = false;
      await _pumpList(
        tester,
        db,
        messages: [
          _msg(
            id: 'm1',
            role: 'assistant',
            content: jsonEncode({
              'syndromeId': 'P001',
              'syndromeName': '视角跳跃症',
              'severity': 'L2',
            }),
            messageType: 'partial_agreement',
          ),
        ],
        onPartialAgreementSubmit: (feedback, quickOption) {
          submittedFeedback = feedback;
          submittedQuick = quickOption;
        },
        onPartialAgreementSkip: () => skipped = true,
      );

      // 手动输入 → 提交（wired：提交后输入清空）
      await tester.enterText(
        find.descendant(
          of: find.byType(PartialAgreementCard),
          matching: find.byType(TextField),
        ),
        '我觉得问题不严重',
      );
      await tester.pump();
      await tester.tap(find.text('提交反馈'));
      await tester.pump();
      expect(submittedFeedback, '我觉得问题不严重');
      expect(submittedQuick, isNull);
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byType(PartialAgreementCard),
                matching: find.byType(TextField),
              ),
            )
            .controller!
            .text,
        isEmpty,
      );

      // 快速选项
      await tester.tap(find.text('症状描述不准'));
      await tester.pump();
      expect(submittedFeedback, 'symptom_inaccurate');
      expect(submittedQuick, 'symptom_inaccurate');

      // 跳过
      await tester.tap(find.text('跳过此症候'));
      await tester.pump();
      expect(skipped, isTrue);
    });
  });

  group('批次74：长按删除', () {
    testWidgets('长按系统卡片 → 确认弹窗 → 确认后回调 onDelete', (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final messages = [
        _msg(
          id: 'm1',
          role: 'system',
          content: jsonEncode({
            'action': 'set_primary',
            'refType': 'chapter',
            'refTitle': '第一章',
          }),
          messageType: 'reference_change',
        ),
      ];
      String? deletedId;
      await _pumpList(
        tester,
        db,
        messages: messages,
        onDelete: (id) => deletedId = id,
      );

      await tester.longPress(find.byType(ReferenceChangeCard));
      await tester.pumpAndSettle();

      // 确认弹窗出现
      expect(find.text('确认删除'), findsOneWidget);
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();

      expect(deletedId, 'm1');
    });

    testWidgets('长按卡片 → 取消不回调 onDelete', (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final messages = [
        _msg(
          id: 'm1',
          role: 'system',
          content: jsonEncode({
            'action': 'set_primary',
            'refType': 'chapter',
            'refTitle': '第一章',
          }),
          messageType: 'reference_change',
        ),
      ];
      String? deletedId;
      await _pumpList(
        tester,
        db,
        messages: messages,
        onDelete: (id) => deletedId = id,
      );

      await tester.longPress(find.byType(ReferenceChangeCard));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(deletedId, isNull);
      // 卡片仍在列表中
      expect(find.byType(ReferenceChangeCard), findsOneWidget);
    });

    testWidgets('长按普通气泡 → 确认弹窗 → 确认后回调 onDelete', (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final messages = [
        _msg(id: 'm1', role: 'user', content: '你好'),
      ];
      String? deletedId;
      await _pumpList(
        tester,
        db,
        messages: messages,
        onDelete: (id) => deletedId = id,
      );

      await tester.longPress(find.text('你好'));
      await tester.pumpAndSettle();

      expect(find.text('确认删除'), findsOneWidget);
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();

      expect(deletedId, 'm1');
    });

    testWidgets('未传 onDelete 时卡片长按不弹窗', (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final messages = [
        _msg(id: 'm1', role: 'user', content: '你好'),
      ];
      await _pumpList(tester, db, messages: messages);

      await tester.longPress(find.text('你好'));
      await tester.pumpAndSettle();

      expect(find.text('确认删除'), findsNothing);
    });
  });

  group('批次72：@ 引用徽章点击反查', () {
    testWidgets('章节有效（改名后按 refId 仍可跳）→ 写作页', (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final msRepo = ManuscriptRepository(db);
      final chRepo = ChapterRepository(db);
      final msId = await msRepo.createManuscript(title: '测试小说');
      final chId = await chRepo.createChapter(
        msId,
        title: '旧标题',
        content: '正文',
        sortOrder: 0,
      );
      // 模拟批次71 后的改名场景：快照仍存旧标题，但 refId 未变
      await chRepo.updateChapterTitle(chId, '新标题');

      final messages = [
        _msg(
          id: 'm1',
          role: 'user',
          content: '帮我看看',
          referencesJson: jsonEncode([
            {
              'refType': 'chapter',
              'refId': chId,
              'manuscriptId': msId,
              'title': '测试小说 · 旧标题',
            },
          ]),
        ),
      ];
      await _pumpList(tester, db, messages: messages);

      await tester.tap(find.text('测试小说 · 旧标题'));
      await tester.pumpAndSettle();

      expect(find.text('WRITING_PAGE'), findsOneWidget);
    });

    testWidgets('章节已删除 → SnackBar 提示不跳转', (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final messages = [
        _msg(
          id: 'm1',
          role: 'user',
          content: '帮我看看',
          referencesJson: jsonEncode([
            {
              'refType': 'chapter',
              'refId': 'gone-chapter',
              'manuscriptId': 'gone-ms',
              'title': '已删章节',
            },
          ]),
        ),
      ];
      await _pumpList(tester, db, messages: messages);

      await tester.tap(find.text('已删章节'));
      await tester.pumpAndSettle();

      expect(find.text('该章节已不存在，无法打开'), findsOneWidget);
      expect(find.text('WRITING_PAGE'), findsNothing);
    });

    testWidgets('作品有效 → 跳详情页', (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final msRepo = ManuscriptRepository(db);
      final msId = await msRepo.createManuscript(title: '测试小说');

      final messages = [
        _msg(
          id: 'm1',
          role: 'user',
          content: '结合这本书',
          referencesJson: jsonEncode([
            {
              'refType': 'manuscript',
              'refId': msId,
              'manuscriptId': msId,
              'title': '测试小说',
            },
          ]),
        ),
      ];
      await _pumpList(tester, db, messages: messages);

      await tester.tap(find.text('测试小说'));
      await tester.pumpAndSettle();

      expect(find.text('DETAIL_PAGE'), findsOneWidget);
    });

    testWidgets('作品已归档（软删）→ SnackBar 提示不跳转', (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final msRepo = ManuscriptRepository(db);
      final msId = await msRepo.createManuscript(title: '已删作品');
      await msRepo.deleteManuscript(msId); // 软删 → status=archived

      final messages = [
        _msg(
          id: 'm1',
          role: 'user',
          content: '引用',
          referencesJson: jsonEncode([
            {
              'refType': 'manuscript',
              'refId': msId,
              'manuscriptId': msId,
              'title': '已删作品',
            },
          ]),
        ),
      ];
      await _pumpList(tester, db, messages: messages);

      await tester.tap(find.text('已删作品'));
      await tester.pumpAndSettle();

      expect(find.text('该作品已不存在，无法打开'), findsOneWidget);
      expect(find.text('DETAIL_PAGE'), findsNothing);
    });
  });
}
