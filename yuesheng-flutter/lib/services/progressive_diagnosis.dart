// ─────────────────────────────────────────────────────────────
// ProgressiveDiagnosis — 长文本分块诊断
//
// 移植 RN progressive-diagnosis.ts
// 核心职责：
//   1. splitContent：按段落 + overlap 分块（SIZE=3000 / OVERLAP=200 / MIN_LAST_CHUNK=500）
//   2. analyzeChunk：每块用 CHUNK_SYSTEM_PROMPT 识别症候（输出 JSON notes）
//   3. buildMergePrompt：注入 SYNDROME_DIAGNOSIS_SKILL + 前次活跃症候上下文 + 合并规则
//   4. runProgressiveDiagnosis：按 THRESHOLD=4000 路由，超长走分块，否则返回 null
//
// 与 ChatService 的整合（D2 WritingCoachPanel 调用）：
//   - runProgressiveDiagnosis 返回非 null → 走分块链路
//   - 返回 null → 走 ChatService.sendMessage 单次链路（D1 已接通）
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'llm_client.dart';

part 'progressive_diagnosis_chunking.dart';
part 'progressive_diagnosis_json_merge.dart';
part 'progressive_diagnosis_entry.dart';

// ── 常量（对齐 RN shared-constants.ts DIAGNOSIS_CHUNK）──
/// 触发分块诊断的字符阈值
const int kDiagnosisChunkThreshold = 4000;

/// 单块字符大小
const int kDiagnosisChunkSize = 3000;

/// 块间重叠字符数（保证跨块上下文连续）
const int kDiagnosisChunkOverlap = 200;

/// 末块最小字符数（<此值时与前块合并，避免末块只有一两句）
const int kDiagnosisMinLastChunk = 500;

// ── 数据类型（对齐 RN ChunkNote / ChunkAnalysisResult）──

/// 单块识别到的一条症候笔记
class ChunkNote {
  final String syndromeId;
  final String description;
  final List<String> evidence;
  final String severity; // L1 / L2 / L3

  const ChunkNote({
    required this.syndromeId,
    required this.description,
    required this.evidence,
    required this.severity,
  });
}

/// 单块分析结果
class ChunkAnalysisResult {
  final int chunkIndex;
  final List<ChunkNote> notes;
  final bool success;

  const ChunkAnalysisResult({
    required this.chunkIndex,
    required this.notes,
    required this.success,
  });
}

/// runProgressiveDiagnosis 返回值
class ProgressiveResult {
  final String fullContent;
  final int chunkCount;
  final int failedChunks;

  const ProgressiveResult({
    required this.fullContent,
    required this.chunkCount,
    required this.failedChunks,
  });
}
