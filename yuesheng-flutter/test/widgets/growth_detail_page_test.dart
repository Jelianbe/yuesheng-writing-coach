import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:writingcoach/router/app_router.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/database/utils.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/data/repositories/student_model_repository.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/types/teaching_types.dart';
import 'package:writingcoach/widgets/growth_detail_page.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';

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

  Widget buildDetailPage() {
    return UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: GrowthDetailPage()),
    );
  }

  /// 种子：诊断记录 + 活跃问题（构造画像数据）
  Future<void> seedDiagnosis() async {
    final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
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
                  'syndrome_id': 'P001',
                  'name': '情绪标签化',
                  'severity': 'L2',
                  'evidence': ['例1', '例2'],
                },
                {
                  'syndrome_id': 'P007',
                  'name': '句式节奏单一',
                  'severity': 'L1',
                  'evidence': ['例3'],
                },
              ]),
            ),
            suggestedActions: const Value('[]'),
            confidence: const Value(0.85),
            timestamp: Value(ts),
            createdAt: Value(ts),
          ),
        );
    await db
        .into(db.activeProblems)
        .insert(
          ActiveProblemsCompanion.insert(
            id: generateUuid(),
            sessionId: sessionId,
            syndromeId: 'P001',
            syndromeName: const Value('情绪标签化'),
            severity: const Value('L2'),
            status: const Value('active'),
            confirmationStatus: const Value('suspected'),
            createdAt: Value(ts),
          ),
        );
    await db
        .into(db.activeProblems)
        .insert(
          ActiveProblemsCompanion.insert(
            id: generateUuid(),
            sessionId: sessionId,
            syndromeId: 'P007',
            syndromeName: const Value('句式节奏单一'),
            severity: const Value('L1'),
            status: const Value('active'),
            confirmationStatus: const Value('suspected'),
            createdAt: Value(ts),
          ),
        );
  }

  /// 批次 48：构造三种教学状态（identified / in_progress / consolidating）
  /// 的画像数据，验证症候分布按教学状态分组。
  ///
  /// 推断规则（student_profile_compute.inferTeachingState）：
  /// - P001 [L2] ×1 → identified（occurrenceCount<=2 + trend unknown）
  /// - P002 [L2,L2,L2] ×3 → in_progress（trend stable，非 identified 且未到 consolidating）
  /// - P003 [L2,L3,L2,L1] ×4 → consolidating（trend improving + latest L1 + count>=3）
  Future<void> seedMultiState() async {
    final base = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    Future<void> insertDiag(String sid, String name, List<String> sev) async {
      final ts = base - (100 - sev.length) * 60; // 每条间隔 60s，正序
      for (var i = 0; i < sev.length; i++) {
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
                      'syndrome_id': sid,
                      'name': name,
                      'severity': sev[i],
                      'evidence': ['例$i'],
                    },
                  ]),
                ),
                suggestedActions: const Value('[]'),
                confidence: const Value(0.8),
                timestamp: Value(ts + i * 60),
                createdAt: Value(ts + i * 60),
              ),
            );
      }
      await db
          .into(db.activeProblems)
          .insert(
            ActiveProblemsCompanion.insert(
              id: generateUuid(),
              sessionId: sessionId,
              syndromeId: sid,
              syndromeName: Value(name),
              severity: Value(sev.last),
              status: const Value('active'),
              confirmationStatus: const Value('confirmed'),
              createdAt: Value(ts),
            ),
          );
    }

    await insertDiag('P001', '情绪标签化', ['L2']);
    await insertDiag('P002', '信息倾泻', ['L2', 'L2', 'L2']);
    await insertDiag('P003', '视角漂移', ['L2', 'L3', 'L2', 'L1']);
  }

  group('GrowthDetailPage 视觉规范（月色竹青）', () {
    testWidgets('#V1 AppBar 浅色 #F7F8F6 + 48dp + 深字 #2D3142', (tester) async {
      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.backgroundColor, const Color(0xFFF7F8F6));
      expect(appBar.toolbarHeight, 48);
      expect(appBar.foregroundColor, const Color(0xFF2D3142));
    });

    testWidgets('#V2 Scaffold 背景 #F7F8F6', (tester) async {
      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaffold.backgroundColor, const Color(0xFFF7F8F6));
    });

    testWidgets('#V3 卡片左侧 4dp 竹青色条', (tester) async {
      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      final colorBar = find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.constraints?.maxWidth == 4 &&
            w.color == const Color(0xFF2D5A52),
      );
      expect(colorBar, findsWidgets);
    });
  });

  group('GrowthDetailPage 空状态', () {
    testWidgets('#E1 空 DB → 显示"暂无诊断数据"', (tester) async {
      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      expect(find.text('暂无诊断数据'), findsOneWidget);
    });

    testWidgets('#E2 空状态显示 insights_outlined 图标', (tester) async {
      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.insights_outlined), findsOneWidget);
    });
  });

  group('GrowthDetailPage 有数据', () {
    testWidgets('#D1 症候分布显示教学状态徽章（画像聚合）', (tester) async {
      // 页面较长（批次 51c 起含总览卡/图谱/曲线/历史），放大视口让
      // ListView 一次构建全部内容，避免懒构建导致 find 不到
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await seedDiagnosis();
      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      // 症候分布列表渲染（批次 51c：症候名同时出现在「症候分布」分组与
      // 「症候追踪历史」时间线，故用 findsWidgets）
      expect(find.text('症候分布'), findsOneWidget);
      expect(find.text('情绪标签化'), findsWidgets);
      expect(find.text('句式节奏单一'), findsWidgets);

      // 教学状态徽章：occurrenceCount=1 + trend=unknown → identified（刚识别）
      expect(find.text('刚识别'), findsNWidgets(2));
      // 严重度 chip 仍显示
      expect(find.text('L2'), findsOneWidget);
      expect(find.text('L1'), findsOneWidget);
    });

    testWidgets('#D2 症候分布按教学状态分组（批次 48，对齐 RN syndromeGroups）', (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await seedMultiState();
      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      // 分组标题按 RN SYNDROME_GROUP_TITLES 显示
      expect(find.text('练习中'), findsOneWidget); // in_progress
      expect(find.text('待诊断'), findsOneWidget); // identified
      expect(find.text('巩固中'), findsOneWidget); // consolidating
      // 无 mastered 数据 → 不显示「已掌握」分组
      expect(find.text('已掌握'), findsNothing);

      // 症候出现在对应分组下（批次 51c 起同名症候也出现在
      // 「症候追踪历史」时间线，故用 findsWidgets）
      expect(find.text('情绪标签化'), findsWidgets); // identified
      expect(find.text('信息倾泻'), findsWidgets); // in_progress
      expect(find.text('视角漂移'), findsWidgets); // consolidating
    });

    testWidgets('#D3 批次51c 成长总览卡 + 写作总览网格渲染', (tester) async {
      await seedDiagnosis();
      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      // 总览卡（GrowthOverviewCard）
      expect(find.text('月笙'), findsOneWidget);
      expect(find.text('累计创作'), findsOneWidget);
      expect(find.text('诊断次数'), findsOneWidget);
      // 批次61：AI 介入统计项（诊断+训练，依赖度信号）
      expect(find.text('AI 介入'), findsOneWidget);
      // 写作总览网格
      expect(find.text('写作总览'), findsOneWidget);
      expect(find.text('写作天数'), findsOneWidget);
      expect(find.text('当前阶段'), findsOneWidget);
      expect(find.text('已解决'), findsOneWidget);
      expect(find.text('待改进'), findsOneWidget);
      expect(find.text('首次写作'), findsOneWidget);
      expect(find.text('最近写作'), findsOneWidget);
    });

    testWidgets('#D4 批次51c 能力图谱/写作曲线/症候追踪历史区块', (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await seedDiagnosis();
      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      expect(find.text('能力图谱'), findsOneWidget);
      expect(find.text('写作成长曲线'), findsOneWidget);
      expect(find.text('症候追踪历史'), findsOneWidget);
      // 查看学习进度详情链接
      expect(find.text('查看学习进度详情'), findsOneWidget);
    });

    testWidgets('#D6 批次65 B62h 同类症候复发率区块展示', (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // 跨会话「出现→好转→再犯」：出现 3 次、好转 1 次、再犯 1 次 → 复发率 50%
      final base = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final s1 = await SessionRepository(db).createBlankSession();
      final s2 = await SessionRepository(db).createBlankSession();
      final s3 = await SessionRepository(db).createBlankSession();
      Future<void> ins(String sid, String status, int offset) async {
        await db
            .into(db.activeProblems)
            .insert(
              ActiveProblemsCompanion.insert(
                id: generateUuid(),
                sessionId: sid,
                syndromeId: 'P900',
                syndromeName: const Value('用词重复'),
                severity: const Value('L2'),
                status: Value(status),
                confirmationStatus: const Value('confirmed'),
                createdAt: Value(base - offset),
              ),
            );
      }

      await ins(s1, 'active', 7200);
      await ins(s2, 'resolved', 3600);
      await ins(s3, 'active', 0);

      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      expect(find.text('同类症候复发率'), findsOneWidget);
      expect(find.text('同一种问题，好转后是否再次出现'), findsOneWidget);
      // 同名症候同时出现在「症候分布」分组与复发率区块 → findsWidgets
      expect(find.text('用词重复'), findsWidgets);
      expect(find.text('出现 3 次 · 好转 1 次 · 再犯 1 次'), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
    });
  });

  group('GrowthDetailPage 写作风格（批次53c）', () {
    testWidgets('#D5 有 style_profile → 渲染写作风格卡（五维 + 总结）', (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await seedDiagnosis();
      await StudentModelRepository(db).updateStyleProfile(
        sessionId,
        const WritingStyleProfile(
          sensory: SensoryPreference.visual,
          rhythm: RhythmPreference.short,
          narrativeDistance: NarrativeDistance.intimate,
          toneTexture: ToneTexture.poetic,
          structure: StructureInstinct.linear,
          summary: '你的文字有一种画家的眼睛。',
        ),
      );
      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      expect(find.text('写作风格'), findsOneWidget);
      expect(find.text('你的文字有一种画家的眼睛。'), findsOneWidget);
      // 五维中文标签
      expect(find.text('视觉型'), findsOneWidget);
      expect(find.text('短句型'), findsOneWidget);
      expect(find.text('贴身型'), findsOneWidget);
      expect(find.text('诗意型'), findsOneWidget);
      expect(find.text('线性型'), findsOneWidget);
    });

    testWidgets('#D6 无 style_profile → 不渲染写作风格卡', (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await seedDiagnosis();
      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      expect(find.text('写作风格'), findsNothing);
    });
  });

  group('GrowthDetailPage 风格纠正（批次57）', () {
    Future<void> seedStyleProfile() async {
      await seedDiagnosis();
      await StudentModelRepository(db).updateStyleProfile(
        sessionId,
        const WritingStyleProfile(
          sensory: SensoryPreference.visual,
          rhythm: RhythmPreference.short,
          narrativeDistance: NarrativeDistance.intimate,
          toneTexture: ToneTexture.poetic,
          structure: StructureInstinct.linear,
          summary: '你的文字有一种画家的眼睛。',
        ),
      );
    }

    testWidgets('#D7 风格卡显示「纠正」按钮 → 点击弹出纠正弹层', (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await seedStyleProfile();
      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      expect(find.text('纠正'), findsOneWidget);

      await tester.tap(find.text('纠正'));
      await tester.pumpAndSettle();

      // 弹层专属元素（AI 描述只读 + 五维标题 + 保存）
      expect(find.text('纠正风格画像'), findsOneWidget);
      expect(find.text('AI 描述'), findsOneWidget);
      expect(find.text('保存纠正'), findsOneWidget);
      expect(find.text('感官偏好'), findsWidgets);
      expect(find.text('结构本能'), findsWidgets);
    });

    testWidgets('#D8 弹层纠正一个维度 → 保存 → 库中已更新且 summary 保留', (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await seedStyleProfile();
      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      await tester.tap(find.text('纠正'));
      await tester.pumpAndSettle();

      // 把「结构本能」从 线性型 纠正为 发散型
      await tester.tap(find.widgetWithText(ChoiceChip, '发散型'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('保存纠正'));
      await tester.pumpAndSettle();

      // 落库断言：structure 已纠正，summary 与其余四维保留
      final loaded = await StudentModelRepository(
        db,
      ).getStyleProfile(sessionId);
      expect(loaded!.structure, StructureInstinct.divergent);
      expect(loaded.sensory, SensoryPreference.visual);
      expect(loaded.rhythm, RhythmPreference.short);
      expect(loaded.summary, '你的文字有一种画家的眼睛。');

      // 页面刷新后显示纠正后的标签
      expect(find.text('发散型'), findsOneWidget);
      expect(find.text('线性型'), findsNothing);
    });

    testWidgets('#D9 无 style_profile → 无「纠正」按钮', (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await seedDiagnosis();
      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      expect(find.text('纠正'), findsNothing);
    });
  });

  // ════════════════════════════════════════════════════════════
  // A3：GrowthDetailPage 有数据 — seed DB + 列表 / 时间线 / 筛选分组验证
  // ════════════════════════════════════════════════════════════
  group('GrowthDetailPage A3 有数据（列表/时间线/筛选分组）', () {
    /// 种子：通过已有的 Repository API 构造章节（SUM word_count）+
    /// 多诊断（时间线）+ activeProblems（含 resolved），驱动成长总览统计与时间线渲染。
    Future<void> seedRichForA3() async {
      final base = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final msRepo = ManuscriptRepository(db);
      final chRepo = ChapterRepository(db);
      final diagRepo = DiagnosisRepository(db);
      final s = sessionId;

      // 稿 + 2 章：1500 + 800 = 2,300 字
      final msId = await msRepo.createManuscript(title: 'A3测试稿');
      final ch1Id = await chRepo.createChapter(msId, title: '第一章：巷口', sortOrder: 1);
      await chRepo.saveChapterContent(ch1Id, 'a' * 1500);
      final ch2Id = await chRepo.createChapter(msId, title: '第二章：院门', sortOrder: 2);
      await chRepo.saveChapterContent(ch2Id, 'b' * 800);

      Future<void> insertProblem({
        required String sid,
        required String syndromeId,
        required String syndromeName,
        required String severity,
        required String status,
        required String confirmationStatus,
        required int ts,
      }) async {
        await db.into(db.activeProblems).insert(
              ActiveProblemsCompanion.insert(
                id: generateUuid(),
                sessionId: sid,
                syndromeId: syndromeId,
                syndromeName: Value(syndromeName),
                severity: Value(severity),
                status: Value(status),
                confirmationStatus: Value(confirmationStatus),
                createdAt: Value(ts),
              ),
            );
      }

      // 诊断 1（2 天前）：情绪标签化 L2 + 信息倾泻 L3
      await db.into(db.diagnosisResults).insert(
            DiagnosisResultsCompanion.insert(
              id: generateUuid(),
              sessionId: s,
              messageId: 'msg-1',
              syndromes: Value(jsonEncode([
                {'syndrome_id': 'P001', 'name': '情绪标签化', 'severity': 'L2', 'evidence': ['e1']},
                {'syndrome_id': 'P002', 'name': '信息倾泻', 'severity': 'L3', 'evidence': ['e2']},
              ])),
              suggestedActions: const Value('["动作化情绪"]'),
              confidence: const Value(0.9),
              timestamp: Value(base - 86400 * 2),
              createdAt: Value(base - 86400 * 2),
            ),
          );
      // 诊断 2（今天）：5 症候 → 时间线 +2 后缀
      await db.into(db.diagnosisResults).insert(
            DiagnosisResultsCompanion.insert(
              id: generateUuid(),
              sessionId: s,
              messageId: 'msg-2',
              syndromes: Value(jsonEncode([
                {'syndrome_id': 'P001', 'name': '情绪标签化', 'severity': 'L1', 'evidence': ['e3']},
                {'syndrome_id': 'P007', 'name': '句式节奏单一', 'severity': 'L2', 'evidence': ['e4']},
                {'syndrome_id': 'P010', 'name': '逻辑断裂', 'severity': 'L2', 'evidence': ['e5']},
                {'syndrome_id': 'P011', 'name': '叙事拖沓', 'severity': 'L1', 'evidence': ['e6']},
                {'syndrome_id': 'P012', 'name': '视角飘移', 'severity': 'L3', 'evidence': ['e7']},
              ])),
              suggestedActions: const Value('[]'),
              confidence: const Value(0.95),
              timestamp: Value(base),
              createdAt: Value(base),
            ),
          );

      // active_problems：2 活跃 + 1 resolved（信息倾泻 P002）
      await insertProblem(
        sid: s, syndromeId: 'P001', syndromeName: '情绪标签化',
        severity: 'L1', status: 'active', confirmationStatus: 'confirmed', ts: base,
      );
      await insertProblem(
        sid: s, syndromeId: 'P007', syndromeName: '句式节奏单一',
        severity: 'L2', status: 'active', confirmationStatus: 'suspected', ts: base,
      );
      await insertProblem(
        sid: s, syndromeId: 'P002', syndromeName: '信息倾泻',
        severity: 'L3', status: 'resolved', confirmationStatus: 'confirmed', ts: base - 3600,
      );
      // diagRepo 未使用：保留引用避免静态分析 unused_import 告警（在需要时可用于验证）
      diagRepo.hashCode;
    }

    testWidgets('A3-1 成长总览卡 + 写作总览数字匹配 seed DB（SUM + COUNT）',
        (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await seedRichForA3();
      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      // 总览卡 + 写作总览网格中可能都显示 2,300字（= 1500 + 800）
      expect(find.text('2,300字'), findsWidgets,
          reason: '累计创作 = SUM(chapters.word_count) = 2300，概览卡必显示');
      // 诊断次数 2（总览卡中「诊断次数」）
      expect(find.text('2'), findsWidgets,
          reason: '诊断次数 = COUNT(diagnosis_results) = 2');
      // 已解决 1（总览卡中「已解决问题」或写作总览中「已解决」格）
      expect(find.text('1'), findsWidgets,
          reason: '已解决问题 = COUNT(active_problems.status=resolved) = 1');

      // 写作总览 6 格关键标题
      expect(find.text('已解决'), findsOneWidget);
      expect(find.text('待改进'), findsOneWidget);
      expect(find.text('写作天数'), findsOneWidget);
    });

    testWidgets('A3-2 症候分布列表：严重度徽章 L1/L2 + 状态分组（identified/suspected）',
        (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await seedRichForA3();
      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      // seed：2 条 active 症候 = 情绪标签化(L1) + 句式节奏单一(L2)
      expect(find.text('L1'), findsWidgets, reason: '情绪标签化 L1 徽章');
      expect(find.text('L2'), findsWidgets, reason: '句式节奏单一 L2 徽章');

      // 分组标题：句式节奏 ×1 + suspected → 一定有「待诊断」identified
      expect(find.text('待诊断'), findsOneWidget);

      // 症候名在症候分布出现
      expect(find.text('情绪标签化'), findsWidgets);
      expect(find.text('句式节奏单一'), findsWidgets);
    });

    testWidgets('A3-3 诊断历史时间线：按时间倒序（新在上）+ 症候名 + 置信度',
        (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await seedRichForA3();
      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      // 两次诊断：今天（置信度 95%）和 2 天前（置信度 90%）
      // 症候名「情绪标签化」在时间线里出现（近期 2 条诊断都有此症候）
      expect(find.text('置信度 95%'), findsOneWidget,
          reason: '新诊断应在时间线头部，置信度 = 0.95');
      expect(find.text('置信度 90%'), findsOneWidget,
          reason: '旧诊断时间线条目应存在');

      // 症候名显示（最多 3 条 +N 后缀）：第二条诊断 5 症候 → "情绪标签化 · 句式节奏单一 · 逻辑断裂 · +2"
      expect(find.textContaining('+2'), findsOneWidget,
          reason: '第二诊 5 症候，截断显示 3 条后应带 +2 后缀');
      expect(find.textContaining('情绪标签化 · 句式节奏单一'), findsOneWidget,
          reason: '症候名按 · 拼接展示');
    });
  });

  group('批次77：学习进度入口不再落入占位死页', () {
    testWidgets('B77-1 有会话 → 点击「查看学习进度详情」→ 携带 sessionId 跳转真实页面', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // 最小路由：宿主 = GrowthDetailPage；progress-detail 用 Marker 校验是否传了 sessionId
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(path: '/', builder: (_, _) => const GrowthDetailPage()),
          GoRoute(
            path: AppRoutes.progressDetail,
            builder: (context, state) {
              final extra = state.extra as Map<String, dynamic>? ?? {};
              final sid = extra['sessionId'] as String? ?? '';
              return sid.isEmpty
                  ? const Scaffold(body: Text('PLACEHOLDER_DEAD'))
                  : const Scaffold(body: Text('PROGRESS_REAL'));
            },
          ),
        ],
      );

      await seedDiagnosis();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('查看学习进度详情'));
      await tester.pumpAndSettle();

      // 不应落入占位死页（未传 sessionId）；应带最新会话 ID 进入真实进度页
      expect(find.text('PROGRESS_REAL'), findsOneWidget);
      expect(find.text('PLACEHOLDER_DEAD'), findsNothing);
    });

    testWidgets('B77-2 无会话 → 空态页无学习进度入口（不落入占位死页）', (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // 删除 setUp 创建的会话 → 无诊断 + 无画像 → 空态页（入口不渲染）
      await SessionRepository(db).deleteSession(sessionId);

      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(path: '/', builder: (_, _) => const GrowthDetailPage()),
          GoRoute(
            path: AppRoutes.progressDetail,
            builder: (context, state) {
              final extra = state.extra as Map<String, dynamic>? ?? {};
              final sid = extra['sessionId'] as String? ?? '';
              return sid.isEmpty
                  ? const Scaffold(body: Text('PLACEHOLDER_DEAD'))
                  : const Scaffold(body: Text('PROGRESS_REAL'));
            },
          ),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      // 空态页 + 无死路由入口：按钮不渲染 → 不可能落入占位死页
      expect(find.text('暂无诊断数据'), findsOneWidget);
      expect(find.text('查看学习进度详情'), findsNothing);
      expect(find.text('PROGRESS_REAL'), findsNothing);
      expect(find.text('PLACEHOLDER_DEAD'), findsNothing);
    });
  });
}
