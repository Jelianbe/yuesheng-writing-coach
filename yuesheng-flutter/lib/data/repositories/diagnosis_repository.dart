// ─────────────────────────────────────────────────────────────
// DiagnosisRepository — 诊断结果 + 活跃问题 DAO
// 复刻 yuesheng-android/src/db/dao/diagnosis-dao.ts
// 包含：诊断落库、活跃问题 CRUD、症候解决/确认/驳回
// ─────────────────────────────────────────────────────────────

import 'dart:convert';
import 'package:drift/drift.dart';
import '../database/database.dart';
import '../database/utils.dart';
import '../../services/decode_guard.dart';
import '../../services/teaching_state_cache.dart';

/// 诊断落库入参（复刻 DiagnosisResult 类型）
/// 只包含 DAO 层需要的字段，AI 输出校验在 service 层做
class DiagnosisInput {
  final String sessionId;
  final String messageId;
  final List<Map<String, dynamic>> syndromes; // Syndrome[]
  final List<String> suggestedActions;
  final double confidence;
  final String? rootCauseAnalysis;
  final String? nextFocus;
  final String? feedbackSummary;
  final Map<String, dynamic>? teachingProgress;
  final String? targetRefType; // 'manuscript' | 'chapter' | null
  final String? targetRefId;
  final String? currentTeachingFocusId;
  final String? focusReason;
  final String? teachingMode; // S4: socratic/mirror/conflict/direct

  DiagnosisInput({
    required this.sessionId,
    required this.messageId,
    required this.syndromes,
    required this.suggestedActions,
    required this.confidence,
    this.rootCauseAnalysis,
    this.nextFocus,
    this.feedbackSummary,
    this.teachingProgress,
    this.targetRefType,
    this.targetRefId,
    this.currentTeachingFocusId,
    this.focusReason,
    this.teachingMode,
  });
}

/// 活跃问题视图（复刻 listActiveProblems 返回类型）
class ActiveProblemView {
  final String syndromeId;
  final String syndromeName;
  final String severity;
  final String confirmationStatus;
  final String? teachingState; // v19 教学状态机持久化
  final int? confirmedAt;
  ActiveProblemView({
    required this.syndromeId,
    required this.syndromeName,
    required this.severity,
    required this.confirmationStatus,
    this.teachingState,
    this.confirmedAt,
  });
}

/// 症候扁平条目（复刻 SyndromeFlatEntry）
class SyndromeFlatEntry {
  final String syndromeId;
  final String syndromeName;
  final String severity;
  final int timestamp;
  final String sessionId;
  SyndromeFlatEntry({
    required this.syndromeId,
    required this.syndromeName,
    required this.severity,
    required this.timestamp,
    required this.sessionId,
  });
}

class DiagnosisRepository {
  final AppDatabase _db;
  DiagnosisRepository(this._db);

  // ════════════ 诊断结果 ════════════

  /// 落库诊断结果 + 状态联动（事务原子）
  /// 复刻 commitDiagnosis(result)
  /// 步骤：
  ///   0. 记忆合并：识别 NO_OP 症候（同症候同严重度 → 跳过 INSERT，active_problem 仍更新）
  ///   1. INSERT diagnosis_results（仅非 NO_OP 症候）
  ///   2. UPSERT active_problem（全部症候，含 NO_OP）
  ///   3. UPDATE sessions.diagnosis_summary（重算 total/resolved + top_syndromes）
  ///   4. UPDATE chapters.last_diagnosed_at（仅章节引用时）
  ///
  /// 注意：阶段迁移校验（validatePhaseTransition）在 service 层做，
  ///       DAO 只负责落库，不做业务校验。
  Future<String> commitDiagnosis(DiagnosisInput input) async {
    final id = generateUuid();
    final now = nowSec();

    // 0. 记忆合并（Mem0 风格）：与最近一条诊断比对，同症候同严重度 → NO_OP
    // 复刻 diagnosis-dao.ts commitDiagnosis 步骤 0
    final latestRow = await getLatestDiagnosis(input.sessionId);
    final latestSyndromes = latestRow != null
        ? _parseSyndromes(latestRow.syndromes)
        : <Map<String, dynamic>>[];
    final noOpSyndromeIds = <String>{};
    for (final s in input.syndromes) {
      final sid = s['syndrome_id'] as String? ?? '';
      if (sid.isEmpty) continue;
      final match = latestSyndromes
          .where((ls) => ls['syndrome_id'] == sid)
          .toList();
      if (match.isNotEmpty && match.first['severity'] == s['severity']) {
        noOpSyndromeIds.add(sid);
      }
    }
    final filteredSyndromes = input.syndromes
        .where((s) => !noOpSyndromeIds.contains(s['syndrome_id']))
        .toList();

    await _db.transaction(() async {
      // 1. INSERT diagnosis_results（仅非 NO_OP 症候）
      await _db
          .into(_db.diagnosisResults)
          .insert(
            DiagnosisResultsCompanion.insert(
              id: id,
              sessionId: input.sessionId,
              messageId: input.messageId,
              syndromes: Value(jsonEncode(filteredSyndromes)),
              suggestedActions: Value(jsonEncode(input.suggestedActions)),
              rootCauseAnalysis: Value(input.rootCauseAnalysis),
              nextFocus: Value(input.nextFocus),
              feedbackSummary: Value(input.feedbackSummary),
              confidence: Value(input.confidence),
              teachingProgress: Value(
                input.teachingProgress != null
                    ? jsonEncode(input.teachingProgress)
                    : null,
              ),
              targetRefType: Value(input.targetRefType),
              targetRefId: Value(input.targetRefId),
              timestamp: Value(now),
              createdAt: Value(now),
              currentTeachingFocusId: Value(input.currentTeachingFocusId),
              focusReason: Value(input.focusReason),
            ),
          );

      // 2. UPSERT active_problem（不复活已 resolved 的症候）
      for (final syndrome in input.syndromes) {
        final syndromeId = syndrome['syndrome_id'] as String? ?? '';
        final syndromeName = syndrome['name'] as String? ?? '';
        final severity = syndrome['severity'] as String? ?? 'L2';

        // 查现有 active_problem
        final existing =
            await (_db.select(_db.activeProblems)..where(
                  (t) =>
                      t.sessionId.equals(input.sessionId) &
                      t.syndromeId.equals(syndromeId),
                ))
                .getSingleOrNull();

        if (existing != null && existing.status == 'resolved') {
          // 不复活已解决的症候
          continue;
        }

        if (existing != null) {
          // UPDATE（保留 confirmation_status、teaching_state，不重置）
          // 批次5（5.3）：v20 起更新 updated_at
          await (_db.update(
            _db.activeProblems,
          )..where((t) => t.id.equals(existing.id))).write(
            ActiveProblemsCompanion(
              syndromeName: Value(syndromeName),
              severity: Value(severity),
              status: const Value('active'),
              updatedAt: Value(nowSec()),
            ),
          );
        } else {
          // INSERT
          // v19 决策：teaching_state 保持 NULL（不在 INSERT 时初始化 'identified'）
          // 理由：
          //  - 首次诊断前可能已有 teaching_history 画像记录（批次44逻辑），
          //    若初始化 'identified' 会把 startingTeachingState 锁死在 identified，
          //    导致画像推断出的 in_progress/consolidating 无法成为 FSM 起点。
          //  - 正确语义：teaching_state 仅存 FSM 输出，首次评估由
          //    training_input_builder._inferStartingState 按画像推断起点，
          //    然后若 FSM 迁移发生（summary.teachingState != 推断起点）再写入持久化。
          await _db
              .into(_db.activeProblems)
              .insert(
                ActiveProblemsCompanion.insert(
                  id: generateUuid(),
                  sessionId: input.sessionId,
                  syndromeId: syndromeId,
                  syndromeName: Value(syndromeName),
                  severity: Value(severity),
                  status: const Value('active'),
                  confirmationStatus: const Value('suspected'),
                  createdAt: Value(now),
                  updatedAt: Value(now),
                ),
              );
        }
      }

      // 3. UPDATE sessions.diagnosis_summary
      await _updateDiagnosisSummary(input.sessionId);

      // 4. UPDATE chapters.last_diagnosed_at（仅章节引用时）
      if (input.targetRefType == 'chapter' && input.targetRefId != null) {
        await (_db.update(
          _db.chapters,
        )..where((t) => t.id.equals(input.targetRefId!))).write(
          ChaptersCompanion(lastDiagnosedAt: Value(now), updatedAt: Value(now)),
        );
      }

      return id;
    });

    // 批次54：新诊断落库后失效会话级 teaching state 缓存（DiagnosisCard 复用，
    // 保证滚动重建读到的是最新画像）
    invalidateTeachingStates(input.sessionId);
    return id;
  }

  /// 获取最新一条诊断
  /// 复刻 getLatestDiagnosis(sessionId)
  Future<DiagnosisRow?> getLatestDiagnosis(String sessionId) async {
    return (_db.select(_db.diagnosisResults)
          ..where((t) => t.sessionId.equals(sessionId))
          ..orderBy([
            (t) =>
                OrderingTerm(expression: t.timestamp, mode: OrderingMode.desc),
          ])
          ..limit(1))
        .getSingleOrNull();
  }

  /// 列出诊断历史（按 timestamp DESC）
  /// 复刻 listDiagnosisHistory(sessionId)
  Future<List<DiagnosisRow>> listDiagnosisHistory(String sessionId) async {
    return (_db.select(_db.diagnosisResults)
          ..where((t) => t.sessionId.equals(sessionId))
          ..orderBy([
            (t) =>
                OrderingTerm(expression: t.timestamp, mode: OrderingMode.desc),
          ]))
        .get();
  }

  /// 跨 session 获取最近 N 条诊断（按 timestamp DESC）
  /// 用于成长页用户级视图（不限定 sessionId）
  Future<List<DiagnosisRow>> listRecentDiagnoses({int limit = 10}) async {
    return (_db.select(_db.diagnosisResults)
          ..orderBy([
            (t) =>
                OrderingTerm(expression: t.timestamp, mode: OrderingMode.desc),
          ])
          ..limit(limit))
        .get();
  }

  /// 获取所有完整诊断记录（跨会话，含 syndromes JSON / feedbackSummary / confidence 等全字段）
  /// T-09 教学档案导出专用：返回 DiagnosisRow 列表，时间升序（旧→新）
  /// 与 getAllDiagnoses 区别：后者返回扁平症候条目（每症候一行），本方法返回完整诊断行
  Future<List<DiagnosisRow>> getAllDiagnosisRows({String? sessionId}) async {
    final query = _db.select(_db.diagnosisResults);
    if (sessionId != null) {
      query.where((t) => t.sessionId.equals(sessionId));
    }
    query.orderBy([
      (t) => OrderingTerm(expression: t.timestamp, mode: OrderingMode.asc),
    ]);
    return query.get();
  }

  /// 获取所有诊断的扁平症候条目（跨会话）
  /// 复刻 getAllDiagnoses(sessionId?)
  /// 注意：时间升序（ASC，旧→新）——对齐 RN 真源 ORDER BY timestamp ASC。
  /// computeSyndromeProfile 依赖正序（latestSeverity=last 取最新、computeTrend 最近窗口在末尾）。
  /// 批次 45 修复：原实现 DESC（新→旧）导致画像聚合 latestSeverity/趋势错位（last 取到最旧）。
  Future<List<SyndromeFlatEntry>> getAllDiagnoses({String? sessionId}) async {
    final query = _db.select(_db.diagnosisResults);
    if (sessionId != null) {
      query.where((t) => t.sessionId.equals(sessionId));
    }
    query.orderBy([
      (t) => OrderingTerm(expression: t.timestamp, mode: OrderingMode.asc),
    ]);
    final rows = await query.get();

    final entries = <SyndromeFlatEntry>[];
    for (final row in rows) {
      final syndromes = _parseSyndromes(row.syndromes);
      for (final s in syndromes) {
        entries.add(
          SyndromeFlatEntry(
            syndromeId: s['syndrome_id'] as String? ?? '',
            syndromeName: s['name'] as String? ?? '',
            severity: s['severity'] as String? ?? 'L2',
            timestamp: row.timestamp,
            sessionId: row.sessionId,
          ),
        );
      }
    }
    return entries;
  }

  /// 获取最新教学焦点
  /// 复刻 getLatestTeachingFocus(sessionId)
  Future<String?> getLatestTeachingFocus(String sessionId) async {
    final latest = await getLatestDiagnosis(sessionId);
    return latest?.currentTeachingFocusId;
  }

  // ════════════ 活跃问题 ════════════

  /// 列出会话的活跃问题
  /// 复刻 listActiveProblems(sessionId)
  Future<List<ActiveProblemView>> listActiveProblems(String sessionId) async {
    final rows =
        await (_db.select(_db.activeProblems)..where(
              (t) => t.sessionId.equals(sessionId) & t.status.equals('active'),
            ))
            .get();
    return rows
        .map(
          (r) => ActiveProblemView(
            syndromeId: r.syndromeId,
            syndromeName: r.syndromeName,
            severity: r.severity,
            confirmationStatus: r.confirmationStatus,
            teachingState: r.teachingState,
            confirmedAt: r.confirmedAt,
          ),
        )
        .toList();
  }

  /// 跨 session 聚合所有活跃问题（group by syndrome_id，取最新严重度）
  /// 用于成长页用户级视图
  ///
  /// 策略：
  ///   1. SELECT * WHERE status='active' ORDER BY created_at DESC
  ///   2. Dart 层 group by syndrome_id（保留最新一条，因已按 created_at DESC）
  ///   3. 按 severity DESC 排序（L3 > L2 > L1）
  Future<List<ActiveProblemView>> listAllActiveProblems() async {
    final rows =
        await (_db.select(_db.activeProblems)
              ..where((t) => t.status.equals('active'))
              ..orderBy([
                (t) => OrderingTerm(
                  expression: t.createdAt,
                  mode: OrderingMode.desc,
                ),
              ]))
            .get();

    // Dart 层 group by syndrome_id（保留最新一条）
    final grouped = <String, ActiveProblem>{};
    for (final r in rows) {
      if (!grouped.containsKey(r.syndromeId)) {
        grouped[r.syndromeId] = r;
      }
    }

    // 转 ActiveProblemView + 按 severity DESC 排序
    const order = {'L3': 0, 'L2': 1, 'L1': 2};
    final result =
        grouped.values
            .map(
              (r) => ActiveProblemView(
                syndromeId: r.syndromeId,
                syndromeName: r.syndromeName,
                severity: r.severity,
                confirmationStatus: r.confirmationStatus,
                teachingState: r.teachingState,
                confirmedAt: r.confirmedAt,
              ),
            )
            .toList()
          ..sort(
            (a, b) =>
                (order[a.severity] ?? 3).compareTo(order[b.severity] ?? 3),
          );

    return result;
  }

  /// 批量解决症候（resolved_at 的唯一写入入口）
  /// 复刻 resolveSyndromesBatch(sessionId, syndromeIds, resolvedAt?)
  /// 单一 Owner 原则：只有此方法写 resolved_at
  Future<int> resolveSyndromesBatch(
    String sessionId,
    List<String> syndromeIds, {
    int? resolvedAt,
  }) async {
    final resolved = resolvedAt ?? nowSec();
    final count =
        await (_db.update(_db.activeProblems)..where(
              (t) =>
                  t.sessionId.equals(sessionId) &
                  t.syndromeId.isIn(syndromeIds) &
                  t.status.equals('active'),
            ))
            .write(
              ActiveProblemsCompanion(
                status: const Value('resolved'),
                resolvedAt: Value(resolved),
                updatedAt: Value(resolved),
              ),
            );

    // 重算 diagnosis_summary
    await _updateDiagnosisSummary(sessionId);
    return count;
  }

  /// 解决单个症候
  /// 复刻 resolveProblem(sessionId, syndromeId)
  Future<void> resolveProblem(String sessionId, String syndromeId) async {
    await resolveSyndromesBatch(sessionId, [syndromeId]);
  }

  /// 批次75：移除单个活跃问题条目（物理删除行）。
  ///
  /// 「移除」与「完成」语义不同：完成走 resolveProblem 置 resolved（保留历史
  /// 供成长曲线/毕业制使用）；移除 = 学员主观不想再追踪该条目，直接删行并
  /// 重算 diagnosis_summary。下次诊断命中时按新证据重新插入。
  Future<void> removeProblem(String sessionId, String syndromeId) async {
    await (_db.delete(_db.activeProblems)..where(
          (t) =>
              t.sessionId.equals(sessionId) & t.syndromeId.equals(syndromeId),
        ))
        .go();
    await _updateDiagnosisSummary(sessionId);
  }

  /// M6 修复：跨 session 聚合已解决的症候（迁移环节源数据）
  /// 查 status='resolved' 的记录，按 syndrome_id 去重取最新
  Future<List<ActiveProblemView>> listAllResolvedProblems() async {
    final rows = await (_db.select(
      _db.activeProblems,
    )..where((t) => t.status.equals('resolved'))).get();
    final grouped = <String, ActiveProblem>{};
    for (final r in rows) {
      final existing = grouped[r.syndromeId];
      if (existing == null ||
          (r.resolvedAt ?? 0) > (existing.resolvedAt ?? 0)) {
        grouped[r.syndromeId] = r;
      }
    }
    return grouped.values
        .map(
          (r) => ActiveProblemView(
            syndromeId: r.syndromeId,
            syndromeName: r.syndromeName,
            severity: r.severity,
            confirmationStatus: r.confirmationStatus,
            teachingState: r.teachingState,
            confirmedAt: r.confirmedAt,
          ),
        )
        .toList();
  }

  /// D3（批次8）：该症候是否曾毕业（存在任意 status='resolved' 记录）——跨 session 复发信号。
  ///
  /// 配合 D1 永久毕业制：同 (session, syndrome) 的 resolved 症候不会被 UPSERT 复活，
  /// 故「当前 active + 存在历史 resolved」⇒ 本轮诊断是跨 session 复发，介入级别应回退脚手架。
  Future<bool> hasResolvedHistory(String syndromeId) async {
    final row =
        await (_db.select(_db.activeProblems)
              ..where(
                (t) =>
                    t.status.equals('resolved') &
                    t.syndromeId.equals(syndromeId),
              )
              ..limit(1))
            .getSingleOrNull();
    return row != null;
  }

  /// 确认诊断（升级 confirmation_status + 可能升级 severity）
  /// 复刻 confirmDiagnosis(sessionId, syndromeId, syndromeName, severity)
  Future<void> confirmDiagnosis(
    String sessionId,
    String syndromeId,
    String syndromeName,
    String severity,
  ) async {
    final now = nowSec();
    // CASE WHEN severity < ? THEN ? ELSE severity END
    // 注意：字符串比较 L1<L2<L3 恰好成立
    await (_db.update(_db.activeProblems)..where(
          (t) =>
              t.sessionId.equals(sessionId) & t.syndromeId.equals(syndromeId),
        ))
        .write(
          ActiveProblemsCompanion(
            syndromeName: Value(syndromeName),
            confirmationStatus: const Value('confirmed'),
            confirmedAt: Value(now),
            updatedAt: Value(now),
          ),
        );

    // severity 升级（字符串比较 L1<L2<L3 恰好成立）
    await _db.customStatement(
      'UPDATE active_problem SET severity = CASE WHEN severity < ? THEN ? ELSE severity END WHERE session_id = ? AND syndrome_id = ?',
      [severity, severity, sessionId, syndromeId],
    );
  }

  /// 驳回诊断（置 confirmation_status='rejected'）
  /// 复刻 disputeDiagnosis(sessionId, syndromeId, syndromeName)
  Future<void> disputeDiagnosis(
    String sessionId,
    String syndromeId,
    String syndromeName,
  ) async {
    await (_db.update(_db.activeProblems)..where(
          (t) =>
              t.sessionId.equals(sessionId) & t.syndromeId.equals(syndromeId),
        ))
        .write(
          ActiveProblemsCompanion(
            syndromeName: Value(syndromeName),
            confirmationStatus: const Value('rejected'),
            updatedAt: Value(nowSec()),
          ),
        );
  }

  /// 获取单个活跃问题的 DB 行（含 teaching_state）
  /// v19 教学状态机：优先读持久化状态，fallback 到推断
  Future<ActiveProblem?> getActiveProblem(
    String sessionId,
    String syndromeId,
  ) async {
    final rows =
        await (_db.select(_db.activeProblems)..where(
              (t) =>
                  t.sessionId.equals(sessionId) &
                  t.syndromeId.equals(syndromeId) &
                  t.status.equals('active'),
            ))
            .get();
    if (rows.isEmpty) return null;
    return rows.first;
  }

  /// 更新单个症候的教学状态（v19 FSM 持久化）
  /// 写入 teaching_state，与 TeachingState.value 字符串格式对齐
  Future<void> updateTeachingState(
    String sessionId,
    String syndromeId,
    String teachingStateValue,
  ) async {
    await _db.transaction(() async {
      await (_db.update(_db.activeProblems)..where(
            (t) =>
                t.sessionId.equals(sessionId) & t.syndromeId.equals(syndromeId),
          ))
          .write(
            ActiveProblemsCompanion(
              teachingState: Value(teachingStateValue),
              updatedAt: Value(nowSec()),
            ),
          );
    });
  }

  // ════════════ 内部辅助 ════════════

  /// 更新 sessions.diagnosis_summary（重算 total/resolved + top_syndromes）
  /// 复刻原项目 commitDiagnosis 内的 summary 更新逻辑
  Future<void> _updateDiagnosisSummary(String sessionId) async {
    final problems = await (_db.select(
      _db.activeProblems,
    )..where((t) => t.sessionId.equals(sessionId))).get();

    final total = problems.length;
    final resolved = problems.where((p) => p.status == 'resolved').length;
    final active = problems.where((p) => p.status == 'active').toList();
    final topSyndromes = _buildTopSyndromes(active);

    // 获取最新诊断的时间戳
    final latestDiag = await getLatestDiagnosis(sessionId);
    final latestDiagnosedAt = latestDiag?.timestamp ?? 0;

    // 获取当前教学阶段
    final state = await (_db.select(
      _db.teachingState,
    )..where((t) => t.sessionId.equals(sessionId))).getSingleOrNull();
    final currentPhase = state?.currentPhase ?? 'P0_ENGAGE';
    final beginnerLevel = state?.beginnerLevel;

    final summary = {
      'latest_diagnosed_at': latestDiagnosedAt,
      'current_phase': currentPhase,
      'total_problems': total,
      'resolved_problems': resolved,
      'top_syndromes': topSyndromes,
      'beginner_level': ?beginnerLevel,
    };

    await (_db.update(
      _db.sessions,
    )..where((t) => t.id.equals(sessionId))).write(
      SessionsCompanion(
        diagnosisSummary: Value(jsonEncode(summary)),
        updatedAt: Value(nowSec()),
      ),
    );
  }

  /// 按 L3>L2>L1 排序 active 取前 3，转 JSON-friendly map。
  /// 抽离自 _updateDiagnosisSummary（ADR-C73 §4：原 51 行超 R-019 硬上限）。
  List<Map<String, dynamic>> _buildTopSyndromes(List<ActiveProblem> active) {
    active.sort((a, b) {
      const order = {'L3': 0, 'L2': 1, 'L1': 2};
      return (order[a.severity] ?? 3).compareTo(order[b.severity] ?? 3);
    });
    return active.take(3).map((p) {
      return {
        'syndrome_id': p.syndromeId,
        'name': p.syndromeName,
        'severity': p.severity,
      };
    }).toList();
  }

  /// 安全解析 syndromes JSON
  /// 复刻 safeParseSyndromes
  List<Map<String, dynamic>> _parseSyndromes(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.whereType<Map<String, dynamic>>().toList();
      }
    } catch (e, st) {
      logDecodeFailure(field: 'diagnosis.syndromes', error: e, stack: st);
    }
    return [];
  }
}
