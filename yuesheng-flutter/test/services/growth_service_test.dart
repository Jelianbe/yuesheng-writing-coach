// ─────────────────────────────────────────────────────────────
// GrowthService 单元测试 — 用户级成长数据聚合（批次 51a）
//
// 覆盖路径：
//   1. getGrowthOverview：空数据默认值 / 聚合（字数/诊断/解决/阶段/写作天数/首末）
//   2. getAbilityScores：空数据空数组 / 六维度分类 + 评分公式 + 趋势
//   3. getWritingCurve：空数据空数组 / 近 N 天序列 + 每日字数/诊断聚合
//   4. getSyndromeHistory：空数据空数组 / detected+resolved 合并按时间 DESC
// ─────────────────────────────────────────────────────────────

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/database/utils.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/data/repositories/student_model_repository.dart';
import 'package:writingcoach/services/growth_service.dart';
import 'package:writingcoach/types/teaching_types.dart';

void main() {
  late AppDatabase db;
  late String sessionId;
  late String manuscriptId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sessionId = await SessionRepository(db).createBlankSession();
    manuscriptId = await ManuscriptRepository(
      db,
    ).createManuscript(title: '测试作品');
  });

  tearDown(() async => db.close());

  /// 今天 0 点（UTC）的秒级时间戳
  int todayUtcSec() {
    final now = DateTime.now().toUtc();
    return DateTime.utc(now.year, now.month, now.day).millisecondsSinceEpoch ~/
        1000;
  }

  Future<void> insertChapter({
    required int wordCount,
    required int updatedAt,
  }) async {
    final chRepo = ChapterRepository(db);
    final chapterId = await chRepo.createChapter(
      manuscriptId,
      title: '章节',
      content: 'x' * wordCount,
    );
    await (db.update(db.chapters)..where((t) => t.id.equals(chapterId))).write(
      ChaptersCompanion(
        wordCount: Value(wordCount),
        updatedAt: Value(updatedAt),
      ),
    );
  }

  Future<void> insertDiagnosis({required int timestamp}) async {
    await db
        .into(db.diagnosisResults)
        .insert(
          DiagnosisResultsCompanion.insert(
            id: generateUuid(),
            sessionId: sessionId,
            messageId: 'msg-${generateUuid()}',
            syndromes: const Value('[]'),
            suggestedActions: const Value('[]'),
            confidence: const Value(0.8),
            timestamp: Value(timestamp),
            createdAt: Value(timestamp),
          ),
        );
  }

  Future<void> insertProblem({
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
            syndromeId: 's-${generateUuid()}',
            syndromeName: Value(name),
            severity: Value(severity),
            status: Value(status),
            createdAt: Value(createdAt),
            resolvedAt: Value(resolvedAt),
          ),
        );
  }

  Future<void> insertTeachingState({
    String phase = 'P3_TRAINING',
    required int updatedAt,
  }) async {
    final exists = await (db.select(
      db.teachingState,
    )..where((t) => t.sessionId.equals(sessionId))).getSingleOrNull();
    if (exists != null) {
      await (db.update(
        db.teachingState,
      )..where((t) => t.sessionId.equals(sessionId))).write(
        TeachingStateCompanion(
          currentPhase: Value(phase),
          updatedAt: Value(updatedAt),
        ),
      );
    } else {
      await db
          .into(db.teachingState)
          .insert(
            TeachingStateCompanion.insert(
              id: generateUuid(),
              sessionId: sessionId,
              currentPhase: Value(phase),
              updatedAt: Value(updatedAt),
            ),
          );
    }
  }

  /// 写入一条活跃症候记录（指定会话与症候 ID，供跨会话复发率聚合构造）
  Future<void> insertRecurrenceProblem({
    required String sessionId,
    required String syndromeId,
    required String name,
    required String status,
    required int createdAt,
    String confirmationStatus = 'confirmed',
  }) async {
    await db
        .into(db.activeProblems)
        .insert(
          ActiveProblemsCompanion.insert(
            id: 'ap-${generateUuid()}',
            sessionId: sessionId,
            syndromeId: syndromeId,
            syndromeName: Value(name),
            severity: const Value('L2'),
            status: Value(status),
            confirmationStatus: Value(confirmationStatus),
            createdAt: Value(createdAt),
          ),
        );
  }

  group('getGrowthOverview', () {
    test('#1 空数据 → 全 0 + P0 + 无首末写作', () async {
      final o = await GrowthService(db).getGrowthOverview();

      expect(o.totalWords, 0);
      expect(o.totalDiagnoses, 0);
      expect(o.totalResolved, 0);
      expect(o.totalActive, 0);
      expect(o.currentPhase, TeachingPhase.p0Engage);
      expect(o.writingDays, 0);
      expect(o.firstWritingAt, isNull);
      expect(o.lastWritingAt, isNull);
    });

    test('#2 聚合：字数/诊断/解决/待改进/写作天数/首末写作/阶段', () async {
      final t = todayUtcSec();
      await insertChapter(wordCount: 500, updatedAt: t - 86400); // 昨天
      await insertChapter(wordCount: 300, updatedAt: t); // 今天
      await insertChapter(wordCount: 0, updatedAt: t); // word_count=0 不计
      await insertDiagnosis(timestamp: t - 3600);
      await insertDiagnosis(timestamp: t);
      await insertProblem(
        name: '情绪标签化',
        severity: 'L2',
        status: 'active',
        createdAt: t - 7200,
      );
      await insertProblem(
        name: '情节断裂',
        severity: 'L3',
        status: 'active',
        createdAt: t - 7200,
      );
      await insertProblem(
        name: '对话生硬',
        severity: 'L1',
        status: 'resolved',
        createdAt: t - 86400,
        resolvedAt: t - 3600,
      );
      await insertTeachingState(phase: 'P2_PRACTICE_LOOP', updatedAt: t);

      final o = await GrowthService(db).getGrowthOverview();

      expect(o.totalWords, 800);
      expect(o.totalDiagnoses, 2);
      expect(o.totalResolved, 1);
      expect(o.totalActive, 2);
      expect(o.currentPhase, TeachingPhase.p2PracticeLoop);
      expect(o.writingDays, 2); // 昨天 + 今天（word_count>0）
      expect(o.firstWritingAt, t - 86400);
      expect(o.lastWritingAt, t);
      // 批次61：无训练历史 → AI 介入 = 诊断次数
      expect(o.aiInterventions, 2);
    });

    test('#3 批次61 有训练历史 → AI 介入 = 诊断 + 训练', () async {
      final t = todayUtcSec();
      await insertDiagnosis(timestamp: t);
      await insertDiagnosis(timestamp: t - 3600);
      final modelRepo = StudentModelRepository(db);
      await modelRepo.appendTeachingHistory(sessionId, {
        'type': 'training',
        'syndromeId': 'P003',
        'result': 'passed',
        'timestamp': t,
      });
      await modelRepo.appendTeachingHistory(sessionId, {
        'type': 'training',
        'syndromeId': 'P003',
        'result': 'failed',
        'timestamp': t - 1800,
      });

      final o = await GrowthService(db).getGrowthOverview();

      expect(o.totalDiagnoses, 2);
      expect(o.aiInterventions, 4); // 2 诊断 + 2 训练
    });
  });

  group('getAbilityScores', () {
    test('#3 空数据 → 空数组（触发 UI 空态）', () async {
      final scores = await GrowthService(db).getAbilityScores();
      expect(scores, isEmpty);
    });

    test('#4 六维度分类 + 评分公式 + 趋势', () async {
      final t = todayUtcSec();
      // 情节构建：2 检测 1 解决 → score = 80-10+3=73，resolved(1) >= detected(2)*0.5 → improving
      await insertProblem(
        name: '情节断裂',
        severity: 'L3',
        status: 'active',
        createdAt: t,
      );
      await insertProblem(
        name: '情节断裂',
        severity: 'L2',
        status: 'resolved',
        createdAt: t,
        resolvedAt: t + 1,
      );
      // 人物：1 次检测 0 解决 → score = 75，down
      await insertProblem(
        name: '角色单薄',
        severity: 'L2',
        status: 'active',
        createdAt: t,
      );
      // 无数据的维度给 70 基线 + stable

      final scores = await GrowthService(db).getAbilityScores();

      expect(scores.length, 6); // 恒为 6 维
      final byDim = {for (final s in scores) s.dimension: s};
      // 情节构建
      expect(byDim['情节构建']!.score, 73);
      expect(byDim['情节构建']!.trend, Trend.improving);
      // 人物塑造
      expect(byDim['人物塑造']!.score, 75);
      expect(byDim['人物塑造']!.trend, Trend.worsening);
      // 其余维度 70 + stable
      expect(byDim['语言表达']!.score, 70);
      expect(byDim['语言表达']!.trend, Trend.stable);
      expect(byDim['逻辑连贯']!.score, 70);
      expect(byDim['主题深度']!.score, 70);
      expect(byDim['情感共鸣']!.score, 70);
    });

    test('#5 解决率 ≥50% → up 趋势', () async {
      final t = todayUtcSec();
      // 2 检测 1 解决 → resolved(1) >= detected(2)*0.5(1) → up
      await insertProblem(
        name: '情绪标签化',
        severity: 'L2',
        status: 'active',
        createdAt: t,
      );
      await insertProblem(
        name: '情绪标签化',
        severity: 'L2',
        status: 'resolved',
        createdAt: t,
        resolvedAt: t + 1,
      );

      final scores = await GrowthService(db).getAbilityScores();
      final emotion = scores.firstWhere((s) => s.dimension == '情感共鸣');
      // score = 80 - 10 + 3 = 73
      expect(emotion.score, 73);
      expect(emotion.trend, Trend.improving);
    });
  });

  group('getWritingCurve', () {
    test('#6 空数据 → 空数组', () async {
      final points = await GrowthService(db).getWritingCurve();
      expect(points, isEmpty);
    });

    test('#7b 仅诊断无写作（chapterRows 空）→ 仍返回近 N 天序列', () async {
      final t = todayUtcSec();
      await insertDiagnosis(timestamp: t);

      final points = await GrowthService(db).getWritingCurve(days: 3);

      expect(points, isNotEmpty); // 空守卫须两者皆空才返回空
      expect(points.last.diagnosisCount, 1);
    });
    test('#7 近 N 天序列完整 + 每日字数/诊断聚合', () async {
      final t = todayUtcSec();
      // 昨天：800 字 + 1 诊断；今天：1200 字 + 2 诊断
      await insertChapter(wordCount: 800, updatedAt: t - 86400);
      await insertChapter(wordCount: 1200, updatedAt: t);
      await insertDiagnosis(timestamp: t - 86400 + 3600);
      await insertDiagnosis(timestamp: t);
      await insertDiagnosis(timestamp: t + 3600);

      final points = await GrowthService(db).getWritingCurve(days: 14);

      expect(points.length, 14); // 完整序列
      // 从旧到新
      expect(points.last.date, isNot(points.first.date));
      // 昨天聚合
      final yesterday = points[points.length - 2];
      expect(yesterday.wordCount, 800);
      expect(yesterday.diagnosisCount, 1);
      // 今天聚合
      final today = points.last;
      expect(today.wordCount, 1200);
      expect(today.diagnosisCount, 2);
    });
  });

  group('getSyndromeHistory', () {
    test('#8 空数据 → 空数组', () async {
      final events = await GrowthService(db).getSyndromeHistory();
      expect(events, isEmpty);
    });

    test('#9 detected + resolved 合并按时间 DESC + 事件类型正确', () async {
      final t = todayUtcSec();
      await insertProblem(
        name: '情绪标签化',
        severity: 'L2',
        status: 'active',
        createdAt: t - 7200, // 发现
      );
      // 注意：RN detected 查询不过滤 status，已解决症候同时产生
      // detected(created_at) 与 resolved(resolved_at) 两条事件
      await insertProblem(
        name: '情节断裂',
        severity: 'L3',
        status: 'resolved',
        createdAt: t - 86400,
        resolvedAt: t - 3600, // 最近解决
      );

      final events = await GrowthService(db).getSyndromeHistory();

      // 3 条：情节断裂 resolved(t-3600) > 情绪标签化 detected(t-7200) > 情节断裂 detected(t-86400)
      expect(events.length, 3);
      expect(events.first.eventType, 'resolved');
      expect(events.first.syndromeName, '情节断裂');
      expect(events.first.severity, Severity.l3);
      expect(events[1].eventType, 'detected');
      expect(events[1].syndromeName, '情绪标签化');
      expect(events.last.eventType, 'detected');
      expect(events.last.syndromeName, '情节断裂');
    });
  });

  group('批次53c: getLatestStyleProfile', () {
    test('#S10 无 style_profile 数据返回 null', () async {
      final style = await GrowthService(db).getLatestStyleProfile();
      expect(style, isNull);
    });

    test('#S11 多条时取 updated_at 最新的风格画像', () async {
      final repo = StudentModelRepository(db);
      // 先写一条旧风格
      await repo.updateStyleProfile(
        sessionId,
        WritingStyleProfile(
          sensory: SensoryPreference.auditory,
          rhythm: RhythmPreference.long,
          narrativeDistance: NarrativeDistance.observational,
          toneTexture: ToneTexture.spare,
          structure: StructureInstinct.fragmented,
          summary: '旧风格：偏听觉。',
        ),
      );
      // 再建一个会话写新风格（updated_at 更新 → 应取这条）
      final session2 = await SessionRepository(db).createBlankSession();
      await repo.updateStyleProfile(
        session2,
        WritingStyleProfile(
          sensory: SensoryPreference.visual,
          rhythm: RhythmPreference.short,
          narrativeDistance: NarrativeDistance.intimate,
          toneTexture: ToneTexture.poetic,
          structure: StructureInstinct.linear,
          summary: '新风格：画家的眼睛。',
        ),
      );

      final style = await GrowthService(db).getLatestStyleProfile();
      expect(style, isNotNull);
      expect(style!.sensory, SensoryPreference.visual);
      expect(style.rhythm, RhythmPreference.short);
      expect(style.summary, contains('画家的眼睛'));
    });

    test('#S12 非法 JSON 返回 null（不抛出）', () async {
      await db.customStatement(
        "INSERT INTO student_model (id, session_id, style_profile, teaching_history, created_at, updated_at) "
        "VALUES ('bad-style', ?, '{not-json', '[]', unixepoch(), unixepoch())",
        [sessionId],
      );
      final style = await GrowthService(db).getLatestStyleProfile();
      expect(style, isNull);
    });
  });

  group('批次65 B62h: getSyndromeRecurrences', () {
    test('#R1 空数据 → 空数组', () async {
      final result = await GrowthService(db).getSyndromeRecurrences();
      expect(result, isEmpty);
    });

    test('#R2 「出现→好转→再犯」跨会话聚合 + 复发率计算 + 排序', () async {
      final t = todayUtcSec();
      // 症候 A：出现(t0) → 好转(t1) → 再犯(t2) → occurrences=3, recovered=1, recurrences=1, rate=0.5
      final s1 = await SessionRepository(db).createBlankSession();
      final s2 = await SessionRepository(db).createBlankSession();
      final s3 = await SessionRepository(db).createBlankSession();
      await insertRecurrenceProblem(
        sessionId: s1,
        syndromeId: 'P001',
        name: '情绪标签化',
        status: 'active',
        createdAt: t - 7200,
      );
      await insertRecurrenceProblem(
        sessionId: s2,
        syndromeId: 'P001',
        name: '情绪标签化',
        status: 'resolved',
        createdAt: t - 3600,
      );
      await insertRecurrenceProblem(
        sessionId: s3,
        syndromeId: 'P001',
        name: '情绪标签化',
        status: 'active',
        createdAt: t,
      );
      // 症候 B：出现 → 未好转再出现 → 好转 → 不构成复发
      // occurrences=3, recovered=1, recurrences=0, rate=0
      final s4 = await SessionRepository(db).createBlankSession();
      final s5 = await SessionRepository(db).createBlankSession();
      final s6 = await SessionRepository(db).createBlankSession();
      await insertRecurrenceProblem(
        sessionId: s4,
        syndromeId: 'P002',
        name: '情节断裂',
        status: 'active',
        createdAt: t - 7200,
      );
      await insertRecurrenceProblem(
        sessionId: s5,
        syndromeId: 'P002',
        name: '情节断裂',
        status: 'active',
        createdAt: t - 3600,
      );
      await insertRecurrenceProblem(
        sessionId: s6,
        syndromeId: 'P002',
        name: '情节断裂',
        status: 'resolved',
        createdAt: t,
      );

      final result = await GrowthService(db).getSyndromeRecurrences();

      expect(result.length, 2);
      // 复发率降序：A(0.5) 在前
      expect(result.first.syndromeId, 'P001');
      expect(result.first.occurrences, 3);
      expect(result.first.recovered, 1);
      expect(result.first.recurrences, 1);
      expect(result.first.rate, closeTo(0.5, 1e-9));
      // B：未好转再出现不计复发
      expect(result.last.syndromeId, 'P002');
      expect(result.last.occurrences, 3);
      expect(result.last.recovered, 1);
      expect(result.last.recurrences, 0);
      expect(result.last.rate, 0);
    });

    test('#R3 rejected 否定诊断不参与聚合', () async {
      final t = todayUtcSec();
      // 同症候两条：一条 confirmed、一条 rejected → 仅 confirmed 参与
      final s1 = await SessionRepository(db).createBlankSession();
      final s2 = await SessionRepository(db).createBlankSession();
      await insertRecurrenceProblem(
        sessionId: s1,
        syndromeId: 'P003',
        name: '对话生硬',
        status: 'active',
        createdAt: t - 3600,
      );
      await insertRecurrenceProblem(
        sessionId: s2,
        syndromeId: 'P003',
        name: '对话生硬',
        status: 'active',
        createdAt: t,
        confirmationStatus: 'rejected',
      );

      final result = await GrowthService(db).getSyndromeRecurrences();

      // rejected 被排除 → 仅 1 条出现，occurrences=1 → 无复发意义
      expect(result.length, 1);
      expect(result.first.occurrences, 1);
      expect(result.first.recurrences, 0);
      expect(result.first.rate, 0);
    });

    test('#R4 单次出现（occurrences=1）→ 复发率 0', () async {
      final t = todayUtcSec();
      await insertRecurrenceProblem(
        sessionId: sessionId,
        syndromeId: 'P004',
        name: '用词重复',
        status: 'active',
        createdAt: t,
      );

      final result = await GrowthService(db).getSyndromeRecurrences();

      expect(result.length, 1);
      expect(result.first.occurrences, 1);
      expect(result.first.rate, 0);
    });
  });
}
