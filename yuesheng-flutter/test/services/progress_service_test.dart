// ─────────────────────────────────────────────────────────────
// ProgressService 单元测试 — 会话级学习进度统计
//
// 覆盖路径：
//   1. getProgressSummary：空数据默认值
//   2. getProgressSummary：教学状态 + 诊断/问题统计 + 锁定症候（仅 active）
//   3. getDiagnosisHistory：syndromes JSON → 症候计数
//   4. getProblemStats：全量（active + resolved）按 created_at DESC
//   5. generateReport：文本结构（概览/问题统计/待改进列表）
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/database/utils.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/services/progress_service.dart';
import 'package:writingcoach/types/teaching_types.dart';

void main() {
  late AppDatabase db;
  late String sessionId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sessionId = await SessionRepository(db).createBlankSession();
  });

  tearDown(() async => db.close());

  Future<void> insertDiagnosis({
    required int timestamp,
    required List<Map<String, dynamic>> syndromes,
    double confidence = 0.8,
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
            confidence: Value(confidence),
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

  Future<void> updateTeachingState({
    String phase = 'P2_PRACTICE_LOOP',
    String? beginnerLevel = 'N2_SCENE',
  }) async {
    await (db.update(
      db.teachingState,
    )..where((t) => t.sessionId.equals(sessionId))).write(
      TeachingStateCompanion(
        currentPhase: Value(phase),
        beginnerLevel: Value(beginnerLevel),
      ),
    );
  }

  group('getProgressSummary', () {
    test('#1 空数据 → 默认值（P0 / 0 / 0 / 0 / 无锁定症候）', () async {
      final summary = await ProgressService(db).getProgressSummary(sessionId);

      expect(summary.currentPhase, TeachingPhase.p0Engage);
      expect(summary.totalDiagnoses, 0);
      expect(summary.totalProblems, 0);
      expect(summary.resolvedProblems, 0);
      expect(summary.activeProblems, 0);
      expect(summary.firstDiagnosisAt, isNull);
      expect(summary.lockedSyndromes, isEmpty);
    });

    test('#2 教学状态 + 诊断/问题统计 + 锁定症候（仅 active）', () async {
      await updateTeachingState(
        phase: 'P3_TRAINING',
        beginnerLevel: 'N3_DIAGNOSE',
      );
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
        status: 'active',
        createdAt: 900,
      );
      await insertProblem(
        syndromeId: 's3',
        name: '对话生硬',
        severity: 'L1',
        status: 'resolved',
        createdAt: 800,
        resolvedAt: 1500,
      );

      final summary = await ProgressService(db).getProgressSummary(sessionId);

      expect(summary.currentPhase, TeachingPhase.p3Training);
      expect(summary.beginnerLevel, 'N3_DIAGNOSE');
      expect(summary.totalDiagnoses, 2);
      expect(summary.totalProblems, 3); // DISTINCT syndrome_id
      expect(summary.resolvedProblems, 1);
      expect(summary.activeProblems, 2);
      expect(summary.firstDiagnosisAt, 1000);
      expect(summary.lastDiagnosisAt, 2000);
      // 锁定症候仅 active，按 created_at DESC：s1(1000) > s2(900)
      expect(summary.lockedSyndromes.length, 2);
      expect(summary.lockedSyndromes[0].syndromeId, 's1');
      expect(summary.lockedSyndromes[0].name, '情绪标签化');
      expect(summary.lockedSyndromes[0].severity, Severity.l3);
      expect(summary.lockedSyndromes[1].syndromeId, 's2');
    });
  });

  group('getDiagnosisHistory', () {
    test('#3 syndromes JSON → 症候计数', () async {
      await insertDiagnosis(
        timestamp: 1000,
        syndromes: [
          {'syndrome_id': 's1', 'name': 'a', 'severity': 'L2'},
          {'syndrome_id': 's2', 'name': 'b', 'severity': 'L3'},
          {'syndrome_id': 's3', 'name': 'c', 'severity': 'L1'},
        ],
        confidence: 0.75,
      );

      final records = await ProgressService(db).getDiagnosisHistory(sessionId);

      expect(records.length, 1);
      expect(records.single.syndromeCount, 3);
      expect(records.single.confidence, closeTo(0.75, 0.001));
      expect(records.single.timestamp, 1000);
    });

    test('#3b 非法 syndromes JSON → 计数 0', () async {
      await insertDiagnosis(timestamp: 1000, syndromes: []);
      await (db.update(db.diagnosisResults)
            ..where((t) => t.sessionId.equals(sessionId)))
          .write(DiagnosisResultsCompanion(syndromes: const Value('not-json')));

      final records = await ProgressService(db).getDiagnosisHistory(sessionId);
      expect(records.single.syndromeCount, 0);
    });
  });

  group('getProblemStats', () {
    test('#4 全量（active + resolved）按 created_at DESC', () async {
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
        createdAt: 2000,
        resolvedAt: 2500,
      );
      await insertProblem(
        syndromeId: 's3',
        name: '对话生硬',
        severity: 'L1',
        status: 'active',
        createdAt: 3000,
      );

      final stats = await ProgressService(db).getProblemStats(sessionId);

      expect(stats.length, 3);
      // created_at DESC：s3(3000) → s2(2000) → s1(1000)
      expect(stats[0].syndromeId, 's3');
      expect(stats[1].syndromeId, 's2');
      expect(stats[1].status, 'resolved');
      expect(stats[1].resolvedAt, 2500);
      expect(stats[2].syndromeId, 's1');
      expect(stats[2].severity, Severity.l3);
    });
  });

  group('generateReport', () {
    test('#5 文本结构：概览 + 问题统计 + 待改进列表', () async {
      await updateTeachingState(phase: 'P2_PRACTICE_LOOP');
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

      final report = await ProgressService(db).generateReport(sessionId);

      expect(report, contains('悦生写作教练 - 学习报告'));
      expect(report, contains('当前阶段：训练循环'));
      expect(report, contains('诊断次数：1 次'));
      expect(report, contains('总问题数：1'));
      expect(report, contains('解决率：0%'));
      expect(report, contains('待改进问题（1个）'));
      expect(report, contains('情绪标签化（严重）'));
      expect(report, contains('继续加油，坚持写作！'));
    });
  });
}
