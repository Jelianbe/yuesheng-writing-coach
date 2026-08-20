// ─────────────────────────────────────────────────────────────
// progressive_diagnosis 拆分：progressive_diagnosis_entry.dart（R-019 ≤300 行）
// 主入口：runProgressiveDiagnosis。迁移自 progressive_diagnosis.dart，行为零变更。
// ─────────────────────────────────────────────────────────────
part of 'progressive_diagnosis.dart';
// ── 主入口：runProgressiveDiagnosis（对齐 RN，超长时分块，否则 null）──

typedef ProgressCallback = void Function(String phase, int current, int total);

/// 渐进式诊断入口。
///
/// 返回 [ProgressiveResult] 表示成功走了分块链路；返回 null 表示内容 <= THRESHOLD，
/// 应交给外部走单次诊断链路（ChatService.sendMessage，D1 已接通）。
///
/// 调用方提供的 [onContent] 在分块链路的 merge 阶段会收到流式增量文本（对齐
/// RN streamChat）。[onProgress] 可选，用于 UI 进度展示。
///
/// D4-A 真链路：通过注入 [llmClient] 实现完整分块链路——
///   - analyzeChunk（单块分析）走 LlmClient.chatCompletion（非流式）
///   - merge 阶段走 LlmClient.streamChat（流式）
Future<ProgressiveResult?> runProgressiveDiagnosis({
  required String content,
  required String title,
  required void Function(String content) onContent,
  required LlmClient llmClient,
  ProgressCallback? onProgress,
  String? sessionId,
  String diagnosisContext = '',
}) async {
  if (content.length <= kDiagnosisChunkThreshold) {
    return null;
  }

  // 1. 分块
  final chunks = splitContent(content);
  onProgress?.call('分块完成', 0, chunks.length);

  // 2. 逐块分析（非流式 chatCompletion）
  final chunkResults = <ChunkAnalysisResult>[];
  var failedChunks = 0;

  for (var i = 0; i < chunks.length; i++) {
    try {
      final response = await llmClient.chatCompletion([
        const ChatMessage(role: 'system', content: kChunkSystemPrompt),
        ChatMessage(
          role: 'user',
          content:
              '章节标题：$title\n\n文本片段 ${i + 1}/${chunks.length}：\n\n${chunks[i]}',
        ),
      ]);

      final jsonStr = extractJson(response);
      final notes = _parseChunkNotes(jsonStr);
      chunkResults.add(
        ChunkAnalysisResult(chunkIndex: i, notes: notes, success: true),
      );
      onProgress?.call('分析分片', i + 1, chunks.length);
    } catch (e) {
      chunkResults.add(
        ChunkAnalysisResult(chunkIndex: i, notes: const [], success: false),
      );
      failedChunks++;
    }
  }

  // 3. 合并：用 streamChat 流式输出
  final mergePrompt = buildMergePrompt(
    chunkResults,
    diagnosisContext: diagnosisContext,
  );
  var fullContent = '';

  await llmClient.streamChat(
    [
      const ChatMessage(role: 'system', content: '你是一个专业的写作诊断助手。'),
      ChatMessage(role: 'user', content: mergePrompt),
    ],
    (response) {
      if (response.isDone || response.content.isEmpty) return;
      fullContent += response.content;
      onContent(response.content);
    },
  );

  return ProgressiveResult(
    fullContent: fullContent,
    chunkCount: chunks.length,
    failedChunks: failedChunks,
  );
}

/// 解析单块分析返回的 JSON 为 ChunkNote 列表
List<ChunkNote> _parseChunkNotes(String jsonStr) {
  try {
    final decoded = jsonDecode(jsonStr);
    if (decoded is Map<String, dynamic> && decoded['notes'] is List) {
      return (decoded['notes'] as List)
          .whereType<Map<String, dynamic>>()
          .map(
            (n) => ChunkNote(
              syndromeId: n['syndromeId'] as String? ?? '',
              description: n['description'] as String? ?? '',
              evidence:
                  (n['evidence'] as List?)?.map((e) => e.toString()).toList() ??
                  const [],
              severity: n['severity'] as String? ?? 'L1',
            ),
          )
          .toList();
    }
  } catch (_) {}
  return const [];
}
