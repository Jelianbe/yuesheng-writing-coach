// ─────────────────────────────────────────────────────────────
// SessionDrawer widget 测试 — 会话管理抽屉
//
// 覆盖路径：
//   1. 空态：还没有会话 + 发起第一次对话 CTA + 新建会话按钮
//   2. 列表：标题 / 预览 / 相对时间 / 阶段标签（P2 → 训练循环）
//   3. 点击会话 → onSelect 回调（+ drawer 关闭）
//   4. 底部新建 → onCreate 回调
//   5. 空态 CTA → onCreate 回调
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/widgets/session_drawer.dart';

void main() {
  SessionWithPhase makeSession({
    required String id,
    String title = '新建会话',
    String preview = '',
    String? phase,
    int updatedAgoSec = 180, // 默认 3 分钟前
  }) {
    final now = DateTime.now();
    return SessionWithPhase(
      session: SessionRow(
        id: id,
        title: title,
        preview: preview,
        diagnosisSummary: '{}',
        createdAt: now.millisecondsSinceEpoch ~/ 1000,
        updatedAt:
            now
                .subtract(Duration(seconds: updatedAgoSec))
                .millisecondsSinceEpoch ~/
            1000,
      ),
      currentPhase: phase,
    );
  }

  Widget buildHost({
    required List<SessionWithPhase> sessions,
    String? currentSessionId,
    ValueChanged<String>? onSelect,
    VoidCallback? onCreate,
    ValueChanged<String>? onDelete,
  }) {
    return MaterialApp(
      home: Scaffold(
        // AppBar 提供 drawer 自动汉堡 leading（对齐 ChatPage 用法）
        appBar: AppBar(),
        drawer: SessionDrawer(
          sessions: sessions,
          currentSessionId: currentSessionId,
          onSelect: onSelect ?? (_) {},
          onCreate: onCreate ?? () {},
          onDelete: onDelete,
        ),
        body: const SizedBox.expand(),
      ),
    );
  }

  Future<void> openDrawer(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
  }

  testWidgets('#1 空态 → CTA + 新建按钮', (tester) async {
    await tester.pumpWidget(buildHost(sessions: const []));
    await openDrawer(tester);

    expect(find.text('对话'), findsOneWidget);
    expect(find.text('还没有会话'), findsOneWidget);
    expect(find.text('发起你的第一次对话，开始写作诊断之旅'), findsOneWidget);
    expect(find.text('发起第一次对话'), findsOneWidget);
    expect(find.text('新建会话'), findsOneWidget);
  });

  testWidgets('#2 列表：标题/预览/时间/阶段标签', (tester) async {
    final sessions = [
      makeSession(
        id: 's1',
        title: '第一章修改讨论',
        preview: '这段过渡可以更顺滑',
        phase: 'P2_PRACTICE_LOOP',
      ),
      makeSession(id: 's2', title: '大纲推演', preview: '', updatedAgoSec: 360),
    ];

    await tester.pumpWidget(
      buildHost(sessions: sessions, currentSessionId: 's1'),
    );
    await openDrawer(tester);

    expect(find.text('第一章修改讨论'), findsOneWidget);
    expect(find.text('这段过渡可以更顺滑'), findsOneWidget);
    expect(find.text('3 分钟前'), findsOneWidget); // s1: updatedAgoSec=180
    expect(find.text('训练循环'), findsOneWidget); // P2_PRACTICE_LOOP 标签
    expect(find.text('大纲推演'), findsOneWidget);
    expect(find.text('6 分钟前'), findsOneWidget); // s2: updatedAgoSec=360
    expect(find.text('暂无消息'), findsOneWidget); // 空 preview 兜底
  });

  testWidgets('#3 点击会话 → onSelect 回调 + drawer 关闭', (tester) async {
    final sessions = [
      makeSession(id: 's1', title: '会话一'),
      makeSession(id: 's2', title: '会话二'),
    ];
    String? gotId;
    await tester.pumpWidget(
      buildHost(
        sessions: sessions,
        currentSessionId: 's1',
        onSelect: (id) {
          gotId = id;
        },
      ),
    );
    await openDrawer(tester);

    await tester.tap(find.text('会话二'));
    await tester.pumpAndSettle();

    expect(gotId, 's2');
    // drawer 已关闭（对话标题不可见）
    expect(find.text('对话'), findsNothing);
  });

  testWidgets('#4 底部新建 → onCreate 回调', (tester) async {
    final sessions = [makeSession(id: 's1', title: '会话一')];
    var created = 0;
    await tester.pumpWidget(
      buildHost(sessions: sessions, onCreate: () => created++),
    );
    await openDrawer(tester);

    await tester.tap(find.text('新建会话'));
    await tester.pumpAndSettle();

    expect(created, 1);
  });

  testWidgets('#5 空态 CTA → onCreate 回调', (tester) async {
    var created = 0;
    await tester.pumpWidget(
      buildHost(sessions: const [], onCreate: () => created++),
    );
    await openDrawer(tester);

    await tester.tap(find.text('发起第一次对话'));
    await tester.pumpAndSettle();

    expect(created, 1);
  });

  testWidgets('批次73：长按会话 → 确认弹窗 → 点删除 → onDelete 回调 + 抽屉关闭', (tester) async {
    final sessions = [makeSession(id: 's1', title: '会话一')];
    String? deletedId;
    await tester.pumpWidget(
      buildHost(
        sessions: sessions,
        currentSessionId: 's1',
        onDelete: (id) => deletedId = id,
      ),
    );
    await openDrawer(tester);

    await tester.longPress(find.text('会话一'));
    await tester.pumpAndSettle();

    expect(find.text('删除会话'), findsOneWidget);
    expect(find.textContaining('此操作不可撤销'), findsOneWidget);

    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(deletedId, 's1');
    expect(find.text('对话'), findsNothing); // 抽屉已关闭
  });

  testWidgets('批次73：长按 → 点取消 → 不触发 onDelete', (tester) async {
    final sessions = [makeSession(id: 's1', title: '会话一')];
    String? deletedId;
    await tester.pumpWidget(
      buildHost(sessions: sessions, onDelete: (id) => deletedId = id),
    );
    await openDrawer(tester);

    await tester.longPress(find.text('会话一'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(deletedId, isNull);
    // 抽屉仍在
    expect(find.text('对话'), findsOneWidget);
  });
}
