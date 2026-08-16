// ─────────────────────────────────────────────────────────────
// SyndromeTracker 单元测试 — 症候跨轮次追踪聚合
//
// 覆盖路径：
//   1. 无诊断 → 空列表
//   2. 多诊断同症候 → 次数累加 / firstSeen / lastSeen / currentSeverity
//   3. recentPoints 升序 + 超过 5 次截断最近 5
//   4. 趋势：加重（L1→L3）/ 好转（L3→L1）/ 稳定
//   5. 排序：当前严重度降序 → 出现次数降序
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/database/utils.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/services/syndrome_tracker.dart';

void main() {
  late AppDatabase db;
  late String sessionId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    final sessionRepo = SessionRepository(db);
    sessionId = await sessionRepo.createBlankSession();
  });

  tearDown(() async => db.close());

  /// 直接插入诊断结果（可控 timestamp，避免 commitDiagnosis 秒级时间戳碰撞）
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

  test('#1 无诊断 → 空列表', () async {
    final tracker = SyndromeTracker(DiagnosisRepository(db));
    expect(await tracker.loadSyndromeTrends(sessionId), isEmpty);
  });

  test('#2 多诊断同症候 → 聚合次数/首见/末见/当前严重度', () async {
    await insertDiagnosis(
      timestamp: 1000,
      syndromes: [
        {'syndrome_id': 's1', 'name': '情绪标签化', 'severity': 'L2'},
      ],
    );
    await insertDiagnosis(
      timestamp: 2000,
      syndromes: [
        {'syndrome_id': 's1', 'name': '情绪标签化', 'severity': 'L3'},
      ],
    );

    final tracker = SyndromeTracker(DiagnosisRepository(db));
    final trends = await tracker.loadSyndromeTrends(sessionId);

    expect(trends, hasLength(1));
    final t = trends.single;
    expect(t.syndromeId, 's1');
    expect(t.name, '情绪标签化');
    expect(t.occurrenceCount, 2);
    expect(t.firstSeen, 1000);
    expect(t.lastSeen, 2000);
    expect(t.currentSeverity, 'L3'); // 最新时间戳的严重度
    expect(t.recentPoints, hasLength(2));
    // 升序
    expect(t.recentPoints.first.timestamp, 1000);
    expect(t.recentPoints.last.timestamp, 2000);
  });

  test('#3 recentPoints 超 5 次 → 截断最近 5', () async {
    for (var i = 1; i <= 7; i++) {
      await insertDiagnosis(
        timestamp: i * 100,
        syndromes: [
          {'syndrome_id': 's1', 'name': '情绪标签化', 'severity': 'L2'},
        ],
      );
    }

    final tracker = SyndromeTracker(DiagnosisRepository(db));
    final trends = await tracker.loadSyndromeTrends(sessionId);

    expect(trends.single.occurrenceCount, 7);
    expect(trends.single.recentPoints, hasLength(5));
    // 最近 5 次 = 时间戳 300..700
    expect(trends.single.recentPoints.first.timestamp, 300);
    expect(trends.single.recentPoints.last.timestamp, 700);
  });

  test('#4 趋势：加重（L1→L3）', () async {
    await insertDiagnosis(
      timestamp: 100,
      syndromes: [
        {'syndrome_id': 's1', 'name': '情绪标签化', 'severity': 'L1'},
      ],
    );
    await insertDiagnosis(
      timestamp: 200,
      syndromes: [
        {'syndrome_id': 's1', 'name': '情绪标签化', 'severity': 'L3'},
      ],
    );

    final tracker = SyndromeTracker(DiagnosisRepository(db));
    final trends = await tracker.loadSyndromeTrends(sessionId);

    expect(trends.single.trend, 'worsening');
    expect(getTrendLabel('worsening'), '加重');
  });

  test('#5 趋势：好转（L3→L1）', () async {
    await insertDiagnosis(
      timestamp: 100,
      syndromes: [
        {'syndrome_id': 's1', 'name': '情绪标签化', 'severity': 'L3'},
      ],
    );
    await insertDiagnosis(
      timestamp: 200,
      syndromes: [
        {'syndrome_id': 's1', 'name': '情绪标签化', 'severity': 'L1'},
      ],
    );

    final tracker = SyndromeTracker(DiagnosisRepository(db));
    final trends = await tracker.loadSyndromeTrends(sessionId);

    expect(trends.single.trend, 'improving');
    expect(getTrendLabel('improving'), '好转');
  });

  test('#6 趋势：稳定（L2→L2）', () async {
    await insertDiagnosis(
      timestamp: 100,
      syndromes: [
        {'syndrome_id': 's1', 'name': '情绪标签化', 'severity': 'L2'},
      ],
    );
    await insertDiagnosis(
      timestamp: 200,
      syndromes: [
        {'syndrome_id': 's1', 'name': '情绪标签化', 'severity': 'L2'},
      ],
    );

    final tracker = SyndromeTracker(DiagnosisRepository(db));
    final trends = await tracker.loadSyndromeTrends(sessionId);

    expect(trends.single.trend, 'stable');
    expect(getTrendLabel('stable'), '稳定');
  });

  test('#7 排序：严重度降序 → 出现次数降序', () async {
    // s1 出现 2 次 L3；s2 出现 1 次 L3；s3 出现 1 次 L1
    await insertDiagnosis(
      timestamp: 100,
      syndromes: [
        {'syndrome_id': 's1', 'name': '症候A', 'severity': 'L3'},
        {'syndrome_id': 's2', 'name': '症候B', 'severity': 'L3'},
        {'syndrome_id': 's3', 'name': '症候C', 'severity': 'L1'},
      ],
    );
    await insertDiagnosis(
      timestamp: 200,
      syndromes: [
        {'syndrome_id': 's1', 'name': '症候A', 'severity': 'L3'},
      ],
    );

    final tracker = SyndromeTracker(DiagnosisRepository(db));
    final trends = await tracker.loadSyndromeTrends(sessionId);

    expect(trends.map((t) => t.syndromeId).toList(), ['s1', 's2', 's3']);
    expect(trends[0].occurrenceCount, 2); // 同严重度按次数降序
  });
}
