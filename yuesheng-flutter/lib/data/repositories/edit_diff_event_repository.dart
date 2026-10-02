// ─────────────────────────────────────────────────────────────
// EditDiffEventRepository — 写作修改事件埋点（ADR-C132 批1 地基，v43）
//
// 追加式事件日志（与 pilot_metric_event 同范式），供北极星「漏斗底端」
// 分析：反馈后用户是否在教练指认的位置做了修改（位置级 diff）。
//
// 事件类型（event_type）：
//   - diff       位置级 diff：章节保存时自动捕获（saveChapterContent 接线）
//   - anchor_ack 指认事件：用户确认教练指认的片段位置（UI 接线批 3）
//   - completion 成稿事件：章节被标记完成（UI 接线批 3）
//
// 埋点先行纪律（变体池验收⑤）：A/B 前必须有位置级 diff，无埋点不谈 A/B。
//
// ADR-C133 批2（M2 复述根因事件）——事件落库设计裁定（选项 A）：
//   M2 门槛事件 = 学员用自己的话复述诊断根因（非照抄）+ 教练确认「复述到位」。
//   本批**复用 anchor_ack 扩展语义**：eventType 仍写 'anchor_ack'，
//   以 payload.kind='M2_recall' 区分子类型，复述文本落 afterText、
//   被复述的诊断根因原文落 beforeText、确认结果落 payload.verdict。
//
// 为何选 A 不选 B（新增 eventType='M2_recall'）：
//   - B 需改 tables.dart CHECK 约束 + v43→v44 migration + build_runner 重生成
//     database.g.dart；而 v43 schema 刚由 C132 收口，批 1b 正并行施工，
//     动 schema 面风险与成本都高。
//   - A 零 schema 变更，复用同一条 append-only 事件日志（M3 聚合器已在消费），
//     payload.kind 在查询期即可把子类型与纯指认事件区分开。
//
// R-009（只记不判）：verdict 是教练教学交互结果的**如实记录**（confirmed/corrected），
// 本方法不计算「复述是否照抄」「是否到位」——「用自己的话」只作为复述文本原样留痕，
// 供里程碑证据卡由用户裁决；代码里无任何达标/打分/成败布尔。
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:drift/drift.dart';

import '../database/database.dart';
import '../database/utils.dart';
import 'repository_write_guard.dart';

/// 写作修改事件类型常量（单一真源；消费方不得裸写字符串）
class EditDiffEventTypes {
  static const String diff = 'diff';
  static const String anchorAck = 'anchor_ack';
  static const String completion = 'completion';
  const EditDiffEventTypes._();
}

/// ADR-C133 批2（M2）：anchor_ack 事件的子类型标记（写入 payload.kind）。
/// 不写该字段 = C132 纯指认事件；写 'M2_recall' = M2 复述根因事件。
class M2RecallKind {
  static const String recall = 'M2_recall';
  const M2RecallKind._();
}

/// ADR-C133 批2（M2）：教练对复述的确认结果（教学交互记录，非学员成败判定）。
///   confirmed = 教练确认「复述到位」→ 计 M2 候选；
///   corrected = 教练指出需修正 → 不计本格候选（事件仍落库，留证据卡）。
class M2RecallVerdict {
  static const String confirmed = 'confirmed';
  static const String corrected = 'corrected';
  const M2RecallVerdict._();

  /// 边界校验（R-028：边界层校验）：只认两值，其余拒绝写入，防脏数据。
  static bool isValid(String v) => v == confirmed || v == corrected;
}

/// ADR-C134 批3（M4a）：completion 成稿事件的来源标记（写入 payload.source）。
///
/// 复用 M2_recall 先例（零 schema 变更）：eventType 仍写 'completion'，
/// 以 payload.source 区分子场景。不写该字段 = C132 普通成稿事件；
/// 写 'independent_drafting' = 学员在「独立起稿模式」下达成写作目标。
///
/// R-009（只记不判）：本标记只如实记录「成稿时学员是否主动声明了独立起稿」，
/// 代码不计算「是否真的无教练介入」「是否达标」——是否计入 M4a 由用户在
/// 里程碑证据卡裁决（C133 四硬隔离：不设达标线 / 不展示学员 / 不打分 / 不加码）。
class CompletionSource {
  /// 学员主动声明「这次我自己来」（独立起稿模式开关）期间达成写作目标。
  static const String independentDrafting = 'independent_drafting';
  const CompletionSource._();
}

/// completion 事件 payload（JSON）编解码。
///
/// 字段：kind（恒 'completion'）/ source（independent_drafting 或省略）。
/// 无 source 字段 = C132 普通成稿事件（payload 可能为 null/空，须安全降级）。
class CompletionPayload {
  final String? source;

  const CompletionPayload({this.source});

  String? encode() => source == null
      ? null
      : jsonEncode({'kind': 'completion', 'source': source});

  /// 解码；null/空串/损坏 JSON/无 kind 字段均返回 null（按「普通成稿事件」处理）。
  static CompletionPayload? tryDecode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      if (map['kind'] != 'completion') return null;
      return CompletionPayload(source: map['source'] as String?);
    } catch (_) {
      return null; // 历史/损坏 payload：不抛，按「普通成稿事件」处理
    }
  }
}

/// M2 复述事件 payload（JSON）编解码。
///
/// 字段：kind（恒 'M2_recall'）/ verdict（confirmed|corrected）/
/// syndrome_id / syndrome_name。复述文本本身在 afterText，根因原文在 beforeText，
/// 不重复塞进 payload（避免双写漂移）。
class M2RecallPayload {
  final String verdict;
  final String syndromeId;
  final String? syndromeName;

  const M2RecallPayload({
    required this.verdict,
    required this.syndromeId,
    this.syndromeName,
  });

  String encode() => jsonEncode({
    'kind': M2RecallKind.recall,
    'verdict': verdict,
    'syndrome_id': syndromeId,
    if (syndromeName != null) 'syndrome_name': syndromeName,
  });

  /// 解码；非 M2_recall payload（kind 不符 / 非法 JSON）返回 null——
  /// 纯指认 anchor_ack 事件的 payload 不是本结构，须安全降级。
  static M2RecallPayload? tryDecode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      if (map['kind'] != M2RecallKind.recall) return null;
      final verdict = map['verdict'];
      final syndromeId = map['syndrome_id'];
      if (verdict is! String || syndromeId is! String) return null;
      return M2RecallPayload(
        verdict: verdict,
        syndromeId: syndromeId,
        syndromeName: map['syndrome_name'] as String?,
      );
    } catch (_) {
      return null; // 历史/损坏 payload：不抛，按「非 M2 事件」处理
    }
  }
}

/// 位置级 diff 事件入参（记录一次「反馈后修改」）。
class EditDiffInput {
  final String sessionId;
  final String chapterId;
  final String? messageId;
  final int anchorStart;
  final int anchorEnd;
  final String beforeText;
  final String afterText;
  final int diffSegments;

  const EditDiffInput({
    required this.sessionId,
    required this.chapterId,
    this.messageId,
    required this.anchorStart,
    required this.anchorEnd,
    required this.beforeText,
    required this.afterText,
    required this.diffSegments,
  });

  String encodePayload() => '{"diff_segments":$diffSegments}';

  static EditDiffInput decodePayload(
    String raw, {
    required String sessionId,
    required String chapterId,
    String? messageId,
    required int anchorStart,
    required int anchorEnd,
    required String beforeText,
    required String afterText,
  }) {
    var segments = 1;
    if (raw.contains('"diff_segments":')) {
      final v = raw.split('"diff_segments":').last.split(RegExp(r'[},]')).first;
      segments = int.tryParse(v) ?? 1;
    }
    return EditDiffInput(
      sessionId: sessionId,
      chapterId: chapterId,
      messageId: messageId,
      anchorStart: anchorStart,
      anchorEnd: anchorEnd,
      beforeText: beforeText,
      afterText: afterText,
      diffSegments: segments,
    );
  }
}

class EditDiffEventRepository {
  final AppDatabase _db;
  EditDiffEventRepository(this._db);

  /// 记录一条位置级 diff 事件（章节保存自动捕获）。
  Future<void> recordDiff(EditDiffInput input) =>
      guardRepoWrite('edit_diff_event', 'recordDiff', () async {
        await _db
            .into(_db.editDiffEvents)
            .insert(
              EditDiffEventsCompanion.insert(
                id: generateUuid(),
                sessionId: Value(input.sessionId),
                chapterId: input.chapterId,
                messageId: Value(input.messageId),
                eventType: EditDiffEventTypes.diff,
                anchorStart: Value(input.anchorStart),
                anchorEnd: Value(input.anchorEnd),
                beforeText: Value(input.beforeText),
                afterText: Value(input.afterText),
                payload: Value(input.encodePayload()),
              ),
            );
      });

  /// 记录一条指认事件（用户确认教练指认的片段，UI 接线批 3）。
  ///
  /// [anchorStart]/[anchorEnd] 可空（表 schema nullable）：诊断证据通常
  /// 只有「段落位置 + 原文摘录」，无字符级偏移——精确位置由 diff 事件承载，
  /// 指认事件记录「确认了哪个片段」（anchorText 必填）。
  Future<void> recordAnchorAcknowledged({
    required String sessionId,
    required String chapterId,
    String? messageId,
    int? anchorStart,
    int? anchorEnd,
    required String anchorText,
  }) => guardRepoWrite('edit_diff_event', 'recordAnchorAcknowledged', () async {
    await _db
        .into(_db.editDiffEvents)
        .insert(
          EditDiffEventsCompanion.insert(
            id: generateUuid(),
            sessionId: Value(sessionId),
            chapterId: chapterId,
            messageId: Value(messageId),
            eventType: EditDiffEventTypes.anchorAck,
            anchorStart: Value(anchorStart),
            anchorEnd: Value(anchorEnd),
            afterText: Value(anchorText),
          ),
        );
  });

  /// 记录一条成稿事件（章节被标记完成，UI 接线批 3）。
  ///
  /// [source] 可选：写 [CompletionSource.independentDrafting] = 学员在
  /// 「独立起稿模式」开关激活期间达成写作目标（ADR-C134 批3 M4a）。
  /// 复用 M2_recall 先例——零 schema 变更，子类型落 payload.source，
  /// 查询期即可与普通成稿事件区分。R-009：只记不判，不含成败判定。
  Future<void> recordCompletion({
    required String sessionId,
    required String chapterId,
    String? source,
  }) => guardRepoWrite('edit_diff_event', 'recordCompletion', () async {
    // source==null → 不写 payload（沿用 C132 旧行为，落列默认 ''）；
    // source!=null → 写 payload JSON（零 schema 变更，子类型查询期区分）。
    final payloadRaw = CompletionPayload(source: source).encode();
    await _db
        .into(_db.editDiffEvents)
        .insert(
          EditDiffEventsCompanion.insert(
            id: generateUuid(),
            sessionId: Value(sessionId),
            chapterId: chapterId,
            eventType: EditDiffEventTypes.completion,
            payload: payloadRaw == null
                ? const Value.absent()
                : Value(payloadRaw),
          ),
        );
  });

  /// 记录一条 M2 复述根因事件（ADR-C133 批2；选项 A：复用 anchor_ack 扩展语义）。
  ///
  /// 语义对齐 ADR-C133 §4.2：记录**学员复述文本**（[recallText]，用自己的话）
  /// + 被复述的**诊断根因原文**（[rootCauseText]，beforeText 锚点）+
  /// 教练确认结果（[verdict] = confirmed|corrected）。
  ///
  /// 列映射：eventType='anchor_ack'；afterText=复述文本；beforeText=根因原文；
  /// payload={kind:M2_recall, verdict, syndrome_id, syndrome_name}。
  ///
  /// R-009：本方法只如实落库，**不判定复述对错/达标**——[verdict] 是教练教学
  /// 交互结果的记录，「是否照抄」不自动计算（复述文本原样留痕供用户裁决）。
  Future<void> recordM2Recall({
    required String sessionId,
    required String chapterId,
    String? messageId,
    required String syndromeId,
    String? syndromeName,
    required String recallText,
    String? rootCauseText,
    required String verdict,
  }) => guardRepoWrite('edit_diff_event', 'recordM2Recall', () async {
    if (!M2RecallVerdict.isValid(verdict)) {
      throw ArgumentError.value(
        verdict,
        'verdict',
        'M2 复述确认结果只允许 confirmed|corrected',
      );
    }
    await _db
        .into(_db.editDiffEvents)
        .insert(
          EditDiffEventsCompanion.insert(
            id: generateUuid(),
            sessionId: Value(sessionId),
            chapterId: chapterId,
            messageId: Value(messageId),
            eventType: EditDiffEventTypes.anchorAck, // 选项 A：复用扩展语义
            beforeText: Value(rootCauseText), // 诊断根因原文（锚点）
            afterText: Value(recallText), // 学员用自己的话复述
            payload: Value(
              M2RecallPayload(
                verdict: verdict,
                syndromeId: syndromeId,
                syndromeName: syndromeName,
              ).encode(),
            ),
          ),
        );
  });

  /// 按章节查询事件（时间升序，北极星读数用）。
  Future<List<EditDiffEvent>> listByChapter(String chapterId) =>
      (_db.select(_db.editDiffEvents)
            ..where((t) => t.chapterId.equals(chapterId))
            ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
          .get();

  /// 按会话查询事件（时间升序）。
  Future<List<EditDiffEvent>> listBySession(String sessionId) =>
      (_db.select(_db.editDiffEvents)
            ..where((t) => t.sessionId.equals(sessionId))
            ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
          .get();

  /// 按事件类型查询（跨会话）。
  Future<List<EditDiffEvent>> listByType(String eventType) =>
      (_db.select(_db.editDiffEvents)
            ..where((t) => t.eventType.equals(eventType))
            ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
          .get();
}
