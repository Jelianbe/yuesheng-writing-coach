// ─────────────────────────────────────────────────────────────
// DiagnosisCard 组件测试
//
// 对齐 RN DiagnosisCard.tsx 核心结构 + 月色竹青视觉
// 覆盖：
//   #1 基础渲染：问题数 + 信心 + 标签行 + 矿物色严重度
//   #2 展开/收起：点击 header 展开后看到症候证据、改写建议
//   #3 空态：syndromes=0 显示"本次未发现显著问题"
//   #4 严重度配色：L1/L2/L3 对应矿物色
//   D5B-1~4 确认栏：三按钮 / 认同落库 / 不认同 / 无 session 不渲染
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/config/app_theme.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/database/utils.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/services/message_card_service.dart';
import 'package:writingcoach/services/teaching_state_cache.dart';
import 'package:writingcoach/types/teaching_types.dart';
import 'package:writingcoach/widgets/diagnosis_card.dart';

/// 基础渲染包装：ProviderScope（DiagnosisCard 为 Consumer 组件）
Widget _wrap(Widget child) => ProviderScope(
  child: MaterialApp(home: Scaffold(body: child)),
);

void main() {
  // ── 数据构造：典型诊断 payload ──
  final threeSyndromes = [
    const DiagnosisSyndromeCard(
      syndromeId: 'P003',
      name: '情绪标签化',
      severity: 'L2',
      evidenceCount: 2,
    ),
    const DiagnosisSyndromeCard(
      syndromeId: 'P005',
      name: '视角漂移',
      severity: 'L1',
      evidenceCount: 1,
    ),
    const DiagnosisSyndromeCard(
      syndromeId: 'P012',
      name: '张力不足症',
      severity: 'L3',
      evidenceCount: 3,
    ),
  ];

  final actions = ['先处理 P003 情绪标签化，把最刺眼的 3 处改成动作表达', '把视角切换的两处用分节符隔开，保持单视角叙事'];

  group('DiagnosisCard 基础结构', () {
    testWidgets('#1 渲染：问题数/信心/标签行/矿物色严重度', (tester) async {
      await tester.pumpWidget(
        _wrap(
          DiagnosisCard(
            syndromeCount: 3,
            syndromes: threeSyndromes,
            suggestedActions: actions,
            confidence: 0.92,
          ),
        ),
      );

      // Header：问题数 + 信心百分比
      expect(find.text('本次诊断'), findsOneWidget);
      expect(find.text('3 个问题'), findsOneWidget);
      expect(find.text('92% 信心'), findsOneWidget);

      // 收起态：标签行包含 3 个症候名（用 hitTestable 过滤 SizeTransition 折叠态的详情副本）
      expect(find.text('情绪标签化').hitTestable(), findsOneWidget);
      expect(find.text('视角漂移').hitTestable(), findsOneWidget);
      expect(find.text('张力不足症').hitTestable(), findsOneWidget);

      // 矿物色断言：L1 = 竹青淡 #E8F0EE，L2 = 矿物黄 #F5E6B8，L3 = 矿物红 #E8C5C5
      // 复用 #4 的 hasChipWithColor 模式：chip 外层容器特征是有 borderRadius（圆点没有）
      bool hasChipWithBgColor(String label, Color bg) => find
          .byWidgetPredicate((w) {
            if (w is! Container) return false;
            final deco = w.decoration as BoxDecoration?;
            if (deco == null) return false;
            if (deco.color != bg) return false;
            if (deco.borderRadius == null) {
              return false; // 排除圆点（shape=circle，无 borderRadius）
            }
            return find
                .descendant(of: find.byWidget(w), matching: find.text(label))
                .evaluate()
                .isNotEmpty;
          })
          .evaluate()
          .isNotEmpty;

      expect(
        hasChipWithBgColor('视角漂移', const Color(0xFFE8F0EE)),
        isTrue,
        reason: '视角漂移 L1 → 竹青淡背景',
      );
      expect(
        hasChipWithBgColor('情绪标签化', const Color(0xFFF5E6B8)),
        isTrue,
        reason: '情绪标签化 L2 → 矿物黄背景',
      );
      expect(
        hasChipWithBgColor('张力不足症', const Color(0xFFE8C5C5)),
        isTrue,
        reason: '张力不足症 L3 → 矿物红背景',
      );
    });

    testWidgets('#2 展开：点击 header → 显示症候块 + 改写建议块', (tester) async {
      await tester.pumpWidget(
        _wrap(
          SingleChildScrollView(
            child: DiagnosisCard(
              syndromeCount: 3,
              syndromes: threeSyndromes,
              suggestedActions: actions,
              confidence: 0.92,
            ),
          ),
        ),
      );

      // 初始收起：SizeTransition 折叠态，内容不可命中（高度为 0）
      expect(find.text('证据：').hitTestable(), findsNothing);
      expect(find.text('改写建议').hitTestable(), findsNothing);

      // 点 header 展开
      await tester.tap(find.text('本次诊断'));
      await tester.pumpAndSettle();

      // 展开后：内容变为可命中
      // 3 个 syndrome × 每个详情块 1 个"证据："
      expect(find.text('证据：').hitTestable(), findsNWidgets(3));
      // 改写建议块（竹青品牌条）
      expect(find.text('改写建议').hitTestable(), findsOneWidget);
      expect(find.textContaining('先处理 P003').hitTestable(), findsOneWidget);
      // 症候名在 chip 行 + 详情块各出现一次 → 2 个
      expect(
        find.text('情绪标签化').hitTestable(),
        findsNWidgets(2),
        reason: '情绪标签化在 chip + 详情块各出现一次',
      );
      expect(
        find.text('视角漂移').hitTestable(),
        findsNWidgets(2),
        reason: '视角漂移在 chip + 详情块各出现一次',
      );
    });

    testWidgets('#3 空态：syndromes=0 → "本次未发现显著问题"标签', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const DiagnosisCard(
            syndromeCount: 0,
            syndromes: [],
            suggestedActions: [],
            confidence: 0.7,
          ),
        ),
      );

      expect(find.text('本次诊断'), findsOneWidget);
      expect(find.text('0 个问题'), findsOneWidget);
      // 空态文案（chip 行 + 详情空态各 1 个，hitTestable 只统计可见的 chip 行）
      expect(find.text('本次未发现显著问题').hitTestable(), findsOneWidget);
    });

    testWidgets('#4 严重度配色：L1/L2/L3', (tester) async {
      await tester.pumpWidget(
        _wrap(
          DiagnosisCard(
            syndromeCount: 3,
            syndromes: threeSyndromes,
            suggestedActions: actions,
            confidence: 1.0,
          ),
        ),
      );

      // L1 视角漂移 → 矿物青淡 #E8F0EE；L2 情绪标签化 → #F5E6B8；L3 张力不足症 → #E8C5C5
      // 用 predicate 匹配 syndrome chip 容器颜色
      bool hasChipWithColor(String label, Color color) => find
          .byWidgetPredicate(
            (w) =>
                w is Container &&
                w.child is Row &&
                (w.decoration as BoxDecoration?)?.color == color &&
                find
                    .descendant(
                      of: find.byWidget(w),
                      matching: find.text(label),
                    )
                    .evaluate()
                    .isNotEmpty,
          )
          .evaluate()
          .isNotEmpty;

      expect(
        hasChipWithColor('视角漂移', const Color(0xFFE8F0EE)),
        isTrue,
        reason: '视角漂移 severity=L1 → #E8F0EE',
      );
      expect(
        hasChipWithColor('情绪标签化', const Color(0xFFF5E6B8)),
        isTrue,
        reason: '情绪标签化 severity=L2 → #F5E6B8',
      );
      expect(
        hasChipWithColor('张力不足症', const Color(0xFFE8C5C5)),
        isTrue,
        reason: '张力不足症 severity=L3 → #E8C5C5',
      );
    });
  });

  // ── D5-B: 症候确认栏（对齐 RN DiagnosisConfirmationBar）──
  group('D5-B 确认栏', () {
    late AppDatabase db;
    late ProviderContainer container;
    late String sessionId;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
      sessionId = await SessionRepository(db).createBlankSession();
      // 先落一条诊断，创建 active_problem 记录（S001）
      await DiagnosisRepository(db).commitDiagnosis(
        DiagnosisInput(
          sessionId: sessionId,
          messageId: 'msg-1',
          syndromes: [
            {'syndrome_id': 'S001', 'name': '情绪标签化', 'severity': 'L2'},
          ],
          suggestedActions: [],
          confidence: 0.8,
        ),
      );
    });

    tearDown(() {
      container.dispose();
      db.close();
    });

    Widget wrapWithSession(Widget child) => UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: Scaffold(body: child)),
    );

    DiagnosisCard cardWithSession() => DiagnosisCard(
      syndromeCount: 1,
      syndromes: const [
        DiagnosisSyndromeCard(
          syndromeId: 'S001',
          name: '情绪标签化',
          severity: 'L2',
          evidenceCount: 2,
        ),
      ],
      suggestedActions: const [],
      confidence: 0.8,
      sessionId: sessionId,
    );

    testWidgets('D5B-1 展开后渲染确认栏：prompt + 三按钮', (tester) async {
      await tester.pumpWidget(
        wrapWithSession(SingleChildScrollView(child: cardWithSession())),
      );

      // 收起态：确认栏不可见（SizeTransition 折叠）
      expect(find.text('这个诊断符合你的实际情况吗？').hitTestable(), findsNothing);

      // 展开
      await tester.tap(find.text('本次诊断'));
      await tester.pumpAndSettle();

      // 确认栏：prompt + 三按钮
      expect(find.text('这个诊断符合你的实际情况吗？'), findsOneWidget);
      expect(find.text('认同'), findsOneWidget);
      expect(find.text('部分认同'), findsOneWidget);
      expect(find.text('不认同'), findsOneWidget);
    });

    testWidgets('批次54 卡片会话级缓存：首次查库写入，重建复用不重查', (tester) async {
      // 清缓存（setUp 的 commitDiagnosis 已失效，此处显式清避免状态残留）
      invalidateTeachingStates(sessionId);

      // 首次渲染 → 走 DB 查询并写入会话级缓存
      await tester.pumpWidget(
        wrapWithSession(SingleChildScrollView(child: cardWithSession())),
      );
      await tester.pumpAndSettle();
      expect(
        readCachedTeachingStates(sessionId),
        isA<Map<String, TeachingState>>(),
        reason: '首次加载（DB 查询）后应写入会话级缓存',
      );

      // 销毁重建（模拟 ListView 滚动回收重建）→ 命中缓存，渲染不受影响
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        wrapWithSession(SingleChildScrollView(child: cardWithSession())),
      );
      await tester.pumpAndSettle();
      expect(find.text('本次诊断'), findsOneWidget);
      expect(find.text('情绪标签化').hitTestable(), findsOneWidget);
    });

    testWidgets('D5B-2 点击「认同」→ 「已认同」状态 + active_problem 落库 confirmed', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrapWithSession(SingleChildScrollView(child: cardWithSession())),
      );
      await tester.tap(find.text('本次诊断'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('认同'));
      await tester.pumpAndSettle();

      // UI 状态切换
      expect(find.text('已认同'), findsOneWidget);
      expect(find.textContaining('可以开始针对'), findsOneWidget);
      // 三按钮消失
      expect(find.text('部分认同'), findsNothing);

      // 落库验证：active_problems confirmation_status == confirmed
      final active = await DiagnosisRepository(
        db,
      ).listActiveProblems(sessionId);
      final s001 = active.firstWhere((p) => p.syndromeId == 'S001');
      expect(s001.confirmationStatus, 'confirmed');
    });

    testWidgets('D5B-3 点击「不认同」→ 「已质疑」状态', (tester) async {
      await tester.pumpWidget(
        wrapWithSession(SingleChildScrollView(child: cardWithSession())),
      );
      await tester.tap(find.text('本次诊断'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('不认同'));
      await tester.pumpAndSettle();

      expect(find.text('已质疑'), findsOneWidget);
      expect(find.text('诊断已标记为不适用'), findsOneWidget);
    });

    testWidgets('D5B-4 sessionId 为 null → 不渲染确认栏', (tester) async {
      await tester.pumpWidget(
        _wrap(
          SingleChildScrollView(
            child: DiagnosisCard(
              syndromeCount: 1,
              syndromes: const [
                DiagnosisSyndromeCard(
                  syndromeId: 'S001',
                  name: '情绪标签化',
                  severity: 'L2',
                  evidenceCount: 2,
                ),
              ],
              suggestedActions: const [],
              confidence: 0.8,
            ),
          ),
        ),
      );
      await tester.tap(find.text('本次诊断'));
      await tester.pumpAndSettle();

      expect(find.text('这个诊断符合你的实际情况吗？'), findsNothing);
      expect(find.text('认同'), findsNothing);
    });

    testWidgets('D5B-5 点击「部分认同」→ 插入 partial_agreement 卡片（B1）', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrapWithSession(SingleChildScrollView(child: cardWithSession())),
      );
      await tester.tap(find.text('本次诊断'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('部分认同'));
      await tester.pumpAndSettle();

      // UI 状态切换为部分认同
      expect(find.text('部分认同'), findsOneWidget);
      expect(find.text('建议继续沟通确认'), findsOneWidget);

      // 落库验证：插入了一条 partial_agreement 消息卡片（B1 生产者接线）
      final messages = await SessionRepository(db).listMessages(sessionId);
      final pa = messages
          .where((m) => m.messageType == 'partial_agreement')
          .toList();
      expect(pa, hasLength(1));
    });
  });

  // ── 批次8: SyndromeDetailModal 接线（症候 chip 点击 → 详情弹层）──
  group('批次8：SyndromeDetailModal 接线', () {
    late AppDatabase db;
    late ProviderContainer container;
    late String sessionId;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
      sessionId = await SessionRepository(db).createBlankSession();
      // 造一条诊断历史，供 syndrome_tracker 聚合
      await DiagnosisRepository(db).commitDiagnosis(
        DiagnosisInput(
          sessionId: sessionId,
          messageId: 'msg-1',
          syndromes: [
            {'syndrome_id': 'S001', 'name': '情绪标签化', 'severity': 'L2'},
          ],
          suggestedActions: [],
          confidence: 0.8,
        ),
      );
    });

    tearDown(() {
      container.dispose();
      db.close();
    });

    testWidgets('D5C-1 点击症候 chip → 打开详情弹层', (tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: DiagnosisCard(
                syndromeCount: 1,
                syndromes: const [
                  DiagnosisSyndromeCard(
                    syndromeId: 'S001',
                    name: '情绪标签化',
                    severity: 'L2',
                    evidenceCount: 2,
                  ),
                ],
                suggestedActions: const [],
                confidence: 0.8,
                sessionId: sessionId,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 点击症候 chip（收起态标签行可见；详情块被 SizeTransition 折叠 → hitTestable 过滤）→ 弹层
      await tester.tap(find.text('情绪标签化').hitTestable());
      await tester.pumpAndSettle();

      expect(find.text('出现次数'), findsOneWidget);
      expect(find.text('趋势变化'), findsOneWidget);
      expect(find.text('诊断记录'), findsOneWidget);
      expect(find.text('1'), findsOneWidget); // occurrenceCount=1
      expect(find.text('稳定'), findsOneWidget); // 单点 → stable
    });

    testWidgets('D5C-2 无 sessionId → chip 不可点击（无弹层）', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const DiagnosisCard(
            syndromeCount: 1,
            syndromes: [
              DiagnosisSyndromeCard(
                syndromeId: 'S001',
                name: '情绪标签化',
                severity: 'L2',
                evidenceCount: 2,
              ),
            ],
            suggestedActions: [],
            confidence: 0.8,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('情绪标签化').hitTestable());
      await tester.pumpAndSettle();

      expect(find.text('出现次数'), findsNothing);
    });

    testWidgets('批次80 M1 证据区文案名实相符（详情展开态）', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const DiagnosisCard(
            syndromeCount: 1,
            syndromes: [
              DiagnosisSyndromeCard(
                syndromeId: 'S001',
                name: '情绪标签化',
                severity: 'L2',
                evidenceCount: 2,
              ),
            ],
            suggestedActions: [],
            confidence: 0.8,
            defaultExpanded: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 修复前承诺「跳转原文查看」但实际无此功能 → 改为「查看详情与趋势」
      expect(find.textContaining('共 2 处证据'), findsOneWidget);
      expect(find.textContaining('点击症候可查看详情与趋势'), findsOneWidget);
      expect(find.textContaining('跳转原文'), findsNothing);
    });

    testWidgets('批次80 M2 无跨轮次追踪数据 → 点症候 chip → SnackBar 轻提示', (tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: DiagnosisCard(
                syndromeCount: 1,
                syndromes: const [
                  DiagnosisSyndromeCard(
                    syndromeId: 'S999', // 历史仅 S001 → 无追踪数据
                    name: '情节断裂',
                    severity: 'L3',
                    evidenceCount: 1,
                  ),
                ],
                suggestedActions: const [],
                confidence: 0.8,
                sessionId: sessionId,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 修复前 tracked==null 静默 return → 现在轻提示
      await tester.tap(find.text('情节断裂').hitTestable());
      await tester.pumpAndSettle();

      expect(find.text('暂无该症候的追踪记录'), findsOneWidget);
      expect(find.text('出现次数'), findsNothing);
    });
  });

  // ── 批次45: 教学状态色点（对齐 RN SyndromeTag P0-3）──
  group('批次45：教学状态色点', () {
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

    /// 提交一条诊断（直接 insert diagnosisResults，绕过 commitDiagnosis 记忆合并，
    /// 保证同症候多严重度记录全部落库——画像聚合需要完整历史推断 teachingState）
    Future<void> seedDiagnosis(String severity, int index) async {
      final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000 + index;
      await db
          .into(db.diagnosisResults)
          .insert(
            DiagnosisResultsCompanion.insert(
              id: generateUuid(),
              sessionId: sessionId,
              messageId: 'msg-${generateUuid()}',
              syndromes: Value(
                jsonEncode([
                  {
                    'syndrome_id': 'S001',
                    'name': '情绪标签化',
                    'severity': severity,
                    'evidence': ['例${index + 1}'],
                  },
                ]),
              ),
              suggestedActions: const Value('[]'),
              confidence: const Value(0.8),
              timestamp: Value(ts),
              createdAt: Value(ts),
            ),
          );
    }

    bool hasDotWithColor(Color expected) => find
        .byWidgetPredicate((w) {
          if (w is! Container) return false;
          final deco = w.decoration as BoxDecoration?;
          if (deco == null) return false;
          // 教学状态色点是 6x6 圆点（shape: circle），无 borderRadius
          if (deco.shape != BoxShape.circle) return false;
          return deco.color == expected;
        })
        .evaluate()
        .isNotEmpty;

    testWidgets('#45-1 诊断历史趋势改善（L3→L2→L1→L1）→ 色点显示 consolidating 竹青而非严重度色', (
      tester,
    ) async {
      // 趋势改善历史：teachingState 推断为 consolidating（画像同源）
      await seedDiagnosis('L3', 0);
      await seedDiagnosis('L2', 1);
      await seedDiagnosis('L1', 2);
      await seedDiagnosis('L1', 3);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: DiagnosisCard(
                syndromeCount: 1,
                syndromes: const [
                  DiagnosisSyndromeCard(
                    syndromeId: 'S001',
                    name: '情绪标签化',
                    severity: 'L2',
                    evidenceCount: 2,
                  ),
                ],
                suggestedActions: const [],
                confidence: 0.8,
                sessionId: sessionId,
              ),
            ),
          ),
        ),
      );
      // 等异步 _loadTeachingStates 完成
      await tester.pumpAndSettle();

      // consolidating → AppColors.primary（竹青），而非 L2 严重度色 l2Text
      expect(
        hasDotWithColor(AppColors.primary),
        isTrue,
        reason: '趋势改善历史 → 色点应为 consolidating 竹青',
      );
      expect(hasDotWithColor(AppColors.l2Text), isFalse, reason: '不应再显示严重度色点');
    });

    testWidgets('#45-2 无诊断历史 → 色点回退严重度色（L2 → l2Text）', (tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: DiagnosisCard(
                syndromeCount: 1,
                syndromes: const [
                  DiagnosisSyndromeCard(
                    syndromeId: 'S001',
                    name: '情绪标签化',
                    severity: 'L2',
                    evidenceCount: 2,
                  ),
                ],
                suggestedActions: const [],
                confidence: 0.8,
                sessionId: sessionId,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 无诊断历史 → teachingState 空 → 回退严重度色点 l2Text
      expect(
        hasDotWithColor(AppColors.l2Text),
        isTrue,
        reason: '无教学状态时应回退严重度色点',
      );
      expect(
        hasDotWithColor(AppColors.primary),
        isFalse,
        reason: '不应错误显示教学状态色',
      );
    });
  });
}
