// ─────────────────────────────────────────────────────────────
// session_export_service — 会话记录导出（v0.1 内测反馈通道，JSON）
//
// 依据：发布准备批任务 3 — 设置页导出「当前会话」的诊断块、教学轮次、
//   角色事实，落 share_plus 分享（用户主动发出即成为反馈数据）。
// 分层（对齐 archive_export_service.dart）：
//   1. 纯函数 buildSessionExportJson —— 组装 JSON，可单测，不含 IO；
//   2. IO 函数 collectLatestSessionExport —— 取最新会话并收集四类数据；
//   3. IO 函数 shareSessionExport —— **内存态**交给 share_plus
//      （T-20261031-03 §九 #6：改收内存，不落临时文件 ⇒ 本文件不含平台 io 依赖）。
// 隐私：导出含作品原文（messages.content / trainingResults.userContent），
//   由调用方在导出前弹确认框说明；脱敏由用户自行判断。
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:share_plus/share_plus.dart';

import '../data/database/database.dart';
import '../data/repositories/character_fact_repository.dart';
import '../data/repositories/diagnosis_repository.dart';
import '../data/repositories/session_repository.dart';
import '../data/repositories/training_result_repository.dart';
import 'decode_guard.dart';

/// 导出结果（JSON 内容 + 分享面板展示所需的元信息）
class SessionExportResult {
  final String json;
  final String fileName;
  final String sessionTitle;
  final int messageCount;
  final int diagnosisCount;

  const SessionExportResult({
    required this.json,
    required this.fileName,
    required this.sessionTitle,
    required this.messageCount,
    required this.diagnosisCount,
  });
}

/// 安全解码 JSON 字符串为 List（非法时留痕并返回空列表）
List<dynamic> _safeJsonList(String? raw, String field) {
  if (raw == null || raw.isEmpty) return [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is List) return decoded;
  } catch (e, st) {
    logDecodeFailure(field: 'session_export.$field', error: e, stack: st);
  }
  return [];
}

/// 安全解码 JSON 字符串为 Map（非法时留痕并返回空 Map）
Map<String, dynamic> _safeJsonMap(String? raw, String field) {
  if (raw == null || raw.isEmpty) return {};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
  } catch (e, st) {
    logDecodeFailure(field: 'session_export.$field', error: e, stack: st);
  }
  return {};
}

Map<String, dynamic> _messageToJson(Message m) {
  return {
    'id': m.id,
    'role': m.role,
    'content': m.content,
    'timestamp': m.timestamp,
    'messageType': m.messageType,
    'references': _safeJsonList(m.referencesJson, 'message.references'),
  };
}

Map<String, dynamic> _diagnosisToJson(DiagnosisRow d) {
  return {
    'id': d.id,
    'messageId': d.messageId,
    'timestamp': d.timestamp,
    'syndromes': _safeJsonList(d.syndromes, 'diagnosis.syndromes'),
    'suggestedActions': _safeJsonList(
      d.suggestedActions,
      'diagnosis.suggestedActions',
    ),
    'rootCauseAnalysis': d.rootCauseAnalysis,
    'nextFocus': d.nextFocus,
    'feedbackSummary': d.feedbackSummary,
    'confidence': d.confidence,
    'teachingProgress': _safeJsonMap(
      d.teachingProgress,
      'diagnosis.teachingProgress',
    ),
  };
}

Map<String, dynamic> _trainingToJson(TrainingResultRow t) {
  return {
    'syndromeId': t.syndromeId,
    'taskType': t.taskType,
    'userContent': t.userContent,
    'result': t.result,
    'score': t.score,
    'feedback': _safeJsonMap(t.feedbackJson, 'training.feedback'),
    'createdAt': t.createdAt,
  };
}

Map<String, dynamic> _characterToJson(CharacterFact c) {
  return {
    'name': c.name,
    'aliases': _safeJsonList(c.aliases, 'character.aliases'),
    'status': c.status,
    'firstSeenChapter': c.firstSeenChapter,
    'assertions': _safeJsonList(c.assertions, 'character.assertions'),
  };
}

/// 组装会话导出 JSON（纯函数，可单测）
///
/// 结构：
/// ```json
/// {
///   "meta": { "version": "1.0", "kind": "session-export",
///             "exportedAt": 123, "app": "yuesheng-writing-coach" },
///   "session": { "id", "title", "manuscriptId", "createdAt", "updatedAt" },
///   "messages": [...], "diagnoses": [...],
///   "trainingResults": [...], "characterFacts": [...]
/// }
/// ```
String buildSessionExportJson({
  required SessionRow session,
  required List<Message> messages,
  required List<DiagnosisRow> diagnoses,
  required List<TrainingResultRow> trainingResults,
  required List<CharacterFact> characterFacts,
  int? exportedAt,
}) {
  final now = exportedAt ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final export = {
    'meta': {
      'version': '1.0',
      'kind': 'session-export',
      'exportedAt': now,
      'app': 'yuesheng-writing-coach',
    },
    'session': {
      'id': session.id,
      'title': session.title,
      'manuscriptId': session.manuscriptId,
      'createdAt': session.createdAt,
      'updatedAt': session.updatedAt,
    },
    'messages': messages.map(_messageToJson).toList(),
    'diagnoses': diagnoses.map(_diagnosisToJson).toList(),
    'trainingResults': trainingResults.map(_trainingToJson).toList(),
    'characterFacts': characterFacts.map(_characterToJson).toList(),
  };
  return const JsonEncoder.withIndent('  ').convert(export);
}

/// 生成会话导出文件名（过滤文件系统非法字符）
String sessionExportFileName({String? sessionLabel}) {
  final stamp = DateTime.now().toIso8601String().substring(0, 10);
  final label = sessionLabel?.replaceAll(RegExp(r'[\\/:*?"<>|]'), '').trim();
  final base = (label == null || label.isEmpty) ? '会话记录' : '会话记录-$label';
  return '$base-$stamp.json';
}

/// 收集最新会话的全部导出数据（IO 编排：四次查询 + 组装）
///
/// 返回 null = 库中无任何会话；查询失败向上抛，由调用方提示。
Future<SessionExportResult?> collectLatestSessionExport(
  AppDatabase db, {
  int? exportedAt,
}) async {
  final sessionRepo = SessionRepository(db);
  final sessions = await sessionRepo.listSessions(); // updated_at DESC
  if (sessions.isEmpty) return null;
  final session = sessions.first;

  final messages = await sessionRepo.listMessages(session.id);
  final diagnoses = await DiagnosisRepository(
    db,
  ).getAllDiagnosisRows(sessionId: session.id);
  final trainingResults = await TrainingResultRepository(
    db,
  ).queryBySession(session.id);
  // 角色事实按作品维度存储：会话未关联作品时为空，不跨作品捞取
  final characterFacts = session.manuscriptId == null
      ? const <CharacterFact>[]
      : await CharacterFactRepository(db).listCharacters(session.manuscriptId!);

  return SessionExportResult(
    json: buildSessionExportJson(
      session: session,
      messages: messages,
      diagnoses: diagnoses,
      trainingResults: trainingResults,
      characterFacts: characterFacts,
      exportedAt: exportedAt,
    ),
    fileName: sessionExportFileName(sessionLabel: session.title),
    sessionTitle: session.title,
    messageCount: messages.length,
    diagnosisCount: diagnoses.length,
  );
}

/// 把导出 JSON 以**内存态**交给系统分享面板（平台通道，失败向上抛）。
///
/// ★ 移动端零行为变化：share_plus 在移动端会把 `XFile.fromData` 的字节
///   **内部落临时文件**后再交给系统分享 ⇒ 与拆分前「自己写临时目录再分享」
///   的最终产物一致（文件名取 [fileName]、mimeType 同为 `application/json`）。
Future<void> shareSessionExport({
  required String json,
  required String fileName,
  String? subject,
}) async {
  await SharePlus.instance.share(
    ShareParams(
      files: [
        XFile.fromData(
          utf8.encode(json),
          name: fileName,
          mimeType: 'application/json',
        ),
      ],
      // ★ `XFile.fromData` 的 `name` 在**非 web 平台会被 cross_file 忽略**
      //   （share_plus 12.0.2 `lib/share_plus.dart:216-219` 官方文档逐字：
      //   "name property will be ignored by cross_file on all platforms except on web"）
      //   ⇒ 必须显式传 `fileNameOverrides`，否则 share_plus 内部落临时文件时
      //   文件名退化成 `<uuid>.json` ⇒ **移动端分享出去的文件名变了**（判据 2 红）。
      fileNameOverrides: [fileName],
      subject: subject,
    ),
  );
}
