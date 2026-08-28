// ─────────────────────────────────────────────────────────────
// archive_export_service — 教学档案导出（T-09，JSON 便携格式）
//
// 依据：架构真源 T-09 — 导出教学档案（五维画像+历史诊断→JSON），
//   保留 SQLite 但增加便携格式，隐私靠架构（本地）而非加密。
// 分层（借鉴 export_service.dart）：
//   1. 纯函数 buildArchiveJson —— 组装 JSON，可单测，不含 IO；
//   2. IO 函数 shareArchiveExport —— 写临时目录后 SharePlus。
// 格式约定：
//   JSON 结构含 meta（版本/时间/app）+ profile（五维画像）+ diagnoses（历史诊断）
// ─────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/database/database.dart';
import 'decode_guard.dart';

/// 诊断记录 DTO（导出专用，不依赖 drift 类型，便于纯函数单测）
class DiagnosisExportEntry {
  final String id;
  final String sessionId;
  final int timestamp;
  final String syndromesJson;
  final String suggestedActionsJson;
  final String? feedbackSummary;
  final String? rootCauseAnalysis;
  final double confidence;

  const DiagnosisExportEntry({
    required this.id,
    required this.sessionId,
    required this.timestamp,
    required this.syndromesJson,
    required this.suggestedActionsJson,
    this.feedbackSummary,
    this.rootCauseAnalysis,
    required this.confidence,
  });

  /// 从 drift DiagnosisRow 转换
  factory DiagnosisExportEntry.fromRow(DiagnosisRow row) {
    return DiagnosisExportEntry(
      id: row.id,
      sessionId: row.sessionId,
      timestamp: row.timestamp,
      syndromesJson: row.syndromes,
      suggestedActionsJson: row.suggestedActions,
      feedbackSummary: row.feedbackSummary,
      rootCauseAnalysis: row.rootCauseAnalysis,
      confidence: row.confidence,
    );
  }

  /// 转为导出 JSON Map
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sessionId': sessionId,
      'timestamp': timestamp,
      'syndromes': _safeJsonDecodeList(syndromesJson),
      'suggestedActions': _safeJsonDecodeList(suggestedActionsJson),
      'feedbackSummary': feedbackSummary,
      'rootCauseAnalysis': rootCauseAnalysis,
      'confidence': confidence,
    };
  }
}

/// 教学档案导出数据入参
class ArchiveExportInput {
  /// 学员画像 JSON 字符串（来自 student_model 表）
  final String? teachingHistoryJson;
  final String? onboardingDataJson;
  final String? styleProfileJson;
  final String? styleFingerprintJson;

  /// 历史诊断记录列表
  final List<DiagnosisExportEntry> diagnoses;

  const ArchiveExportInput({
    this.teachingHistoryJson,
    this.onboardingDataJson,
    this.styleProfileJson,
    this.styleFingerprintJson,
    this.diagnoses = const [],
  });
}

/// 安全解码 JSON 字符串为 List（非法时返回空列表）
List<dynamic> _safeJsonDecodeList(String? raw) {
  if (raw == null || raw.isEmpty) return [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is List) return decoded;
  } catch (e, st) {
    logDecodeFailure(field: 'archive_export.json_list', error: e, stack: st);
  }
  return [];
}

/// 安全解码 JSON 字符串为 Map（非法时返回空 Map）
Map<String, dynamic> _safeJsonDecodeMap(String? raw) {
  if (raw == null || raw.isEmpty) return {};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
  } catch (e, st) {
    logDecodeFailure(field: 'archive_export.json_map', error: e, stack: st);
  }
  return {};
}

/// 组装教学档案 JSON（纯函数，可单测）
///
/// 结构：
/// ```
/// {
///   "meta": { "version": "1.0", "exportedAt": 123, "app": "yuesheng-writing-coach" },
///   "profile": {
///     "teachingHistory": [...],
///     "onboardingData": {...},
///     "styleProfile": {...},
///     "styleFingerprint": {...}
///   },
///   "diagnoses": [...]
/// }
/// ```
String buildArchiveJson(ArchiveExportInput input, {int? exportedAt}) {
  final now = exportedAt ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final archive = {
    'meta': {
      'version': '1.0',
      'exportedAt': now,
      'app': 'yuesheng-writing-coach',
    },
    'profile': {
      'teachingHistory': _safeJsonDecodeList(input.teachingHistoryJson),
      'onboardingData': _safeJsonDecodeMap(input.onboardingDataJson),
      'styleProfile': _safeJsonDecodeMap(input.styleProfileJson),
      'styleFingerprint': _safeJsonDecodeMap(input.styleFingerprintJson),
    },
    'diagnoses': input.diagnoses.map((d) => d.toJson()).toList(),
  };
  return const JsonEncoder.withIndent('  ').convert(archive);
}

/// 生成教学档案导出文件名
String archiveExportFileName({String? sessionLabel}) {
  final stamp = DateTime.now().toIso8601String().substring(0, 10);
  final label = sessionLabel?.replaceAll(RegExp(r'[\\/:*?"<>|]'), '').trim();
  final base = (label == null || label.isEmpty) ? '教学档案' : '教学档案-$label';
  return '$base-$stamp.json';
}

/// 写入临时目录并调起系统分享面板
Future<void> shareArchiveExport({
  required String json,
  required String fileName,
  String? subject,
}) async {
  final dir = await getTemporaryDirectory();
  final file = File(p.join(dir.path, fileName));
  await file.writeAsString(json, flush: true);
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: 'application/json')],
      subject: subject,
    ),
  );
}
