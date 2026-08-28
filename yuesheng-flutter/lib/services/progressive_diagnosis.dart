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

import 'decode_guard.dart';
import 'llm_client.dart';

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

// ── 分块：按段落 + overlap 回溯（对齐 RN splitContent）──

/// 按段落切分文本为若干块，块间保留 overlap 字符的上下文重叠。
///
/// 算法：
///   1. 按 '\n\n' 切段落
///   2. 从 startIndex 累加段落，总长度接近 SIZE 时切块
///   3. overlap 从本块末尾段落向前回溯，累计长度 ≥ OVERLAP 停
///   4. 末块 < MIN_LAST_CHUNK 时合并到前一块
List<String> splitContent(String content) {
  if (content.length <= kDiagnosisChunkSize) {
    return [content];
  }

  final paragraphs = content.split('\n\n');
  final chunks = <String>[];
  var startIndex = 0;

  while (startIndex < paragraphs.length) {
    var endIndex = startIndex;
    var length = 0;
    var reachedThreshold = false;

    for (var i = startIndex; i < paragraphs.length; i++) {
      final pLen = paragraphs[i].length + 2; // +2 是 '\n\n' 分隔
      if (length + pLen >= kDiagnosisChunkSize) {
        reachedThreshold = true;
        break;
      }
      length += pLen;
      endIndex = i + 1;
    }

    if (!reachedThreshold) {
      chunks.add(paragraphs.sublist(startIndex).join('\n\n'));
      break;
    }

    final chunk = paragraphs.sublist(startIndex, endIndex).join('\n\n');
    chunks.add(chunk);

    // overlap 回溯：从 endIndex-1 向前累加，直到长度 >= OVERLAP
    var overlapLength = 0;
    var overlapStart = endIndex - 1;
    while (overlapStart > startIndex) {
      overlapLength += paragraphs[overlapStart].length + 2;
      if (overlapLength >= kDiagnosisChunkOverlap) {
        break;
      }
      overlapStart--;
    }

    startIndex = overlapStart > startIndex ? overlapStart : startIndex;
  }

  // 末块过小时合并
  if (chunks.length >= 2) {
    final last = chunks.last;
    if (last.length < kDiagnosisMinLastChunk) {
      final merged = '${chunks[chunks.length - 2]}\n\n$last';
      chunks[chunks.length - 2] = merged;
      chunks.removeLast();
    }
  }

  return chunks;
}

// ── 单块系统提示词（对齐 RN CHUNK_SYSTEM_PROMPT）──
const String kChunkSystemPrompt = '''你是一个专业的写作诊断助手。请阅读以下文本片段，识别其中存在的写作问题。

症候类型参考（仅用于标注，不要强行匹配）：
- P003 情绪标签化 / P004 信息倾泻症 / P005 视角漂移 / P006 节奏停滞
- P007 句式节奏单一 / P008 语言堆砌 / P009 角色动机缺失 / P010 OC平面化
- P011 对话疲劳症 / P012 张力不足症 / P013 开篇平庸症 / P014 结尾乏力症
- P015 高潮疲软症 / P016 情节巧合过多症 / P017 伏笔失效症 / P018 人设崩塌症
- P019 情感失真症 / P020 过渡生硬症 / P021 跳跃叙事/过度概括症

例外情况指引（以下场景通常不应判定为症候）：
- P003例外：隐喻表达（"冰冷的眼神""心头一热"）、有具体动作支撑的情绪词、紧凑叙事中的快速过渡
- P004例外：角色的内心自省（角色在评价自己，非作者补设定）、角色对地点/势力的随口判断
- P005例外：角色对自己所处环境的评价、角色对自身经历的回忆、有明确标记的视角切换
- P006例外：情绪沉淀段落、氛围描写的节奏变化、关键揭示前的屏息时刻
- P008例外：情感爆发点的浓墨重彩、作者刻意特定风格
- P009例外：悬疑叙事中动机故意模糊、功能性配角
- P011例外：剧本/对白主导文体、法庭剧/审讯场景
- P012例外：日常向/温馨向作品、悬疑铺垫章节
- P014例外：开放式结局的刻意留白、系列连载的"未完待续"设计
- P015例外：情绪高潮替代动作高潮的文学型叙事
- P016例外：喜剧/荒诞向作品中刻意设计的巧合（前提是风格一致）
- P018例外：角色因重大事件（如创伤、顿悟）导致的刻意转变，且有明确铺垫
- P019例外：非人类/非常规思维的角色设定
- P020例外：蒙太奇/意识流/碎片化叙事手法

请输出JSON格式的笔记，不要包含markdown代码块标记，只输出纯JSON对象：
{
  "notes": [
    {
      "syndromeId": "P003",
      "description": "简要描述观察到的问题，在原文中的位置",
      "evidence": ["具体例句1", "具体例句2"],
      "severity": "L1"
    }
  ]
}''';

// ── JSON 提取（对齐 RN extractJson：优先 code block，否则按括号平衡）──

/// 从 LLM 返回的文本中提取第一个顶层 JSON 对象字符串。
/// 返回 '{}' 表示未找到。
String extractJson(String text) {
  // 优先匹配 markdown 代码块内的 JSON
  final codeBlock = RegExp(
    r'```(?:json)?\s*\n?(\{[\s\S]*?\})\s*\n?```',
  ).firstMatch(text);
  if (codeBlock != null && codeBlock.groupCount >= 1) {
    return codeBlock.group(1)!;
  }
  // 按括号平衡匹配第一个顶层 {}
  var depth = 0;
  var start = -1;
  for (var i = 0; i < text.length; i++) {
    if (text[i] == '{') {
      if (depth == 0) start = i;
      depth++;
    } else if (text[i] == '}') {
      depth--;
      if (depth == 0 && start != -1) {
        return text.substring(start, i + 1);
      }
    }
  }
  return '{}';
}

// ── Merge prompt：注入 SKILL + 合并规则（对齐 RN buildMergePrompt）──

/// 构造跨分片合并的系统 prompt。
///
/// [diagnosisContext] 来自前次活跃症候累积（对齐 RN buildDiagnosisContext）。
String buildMergePrompt(
  List<ChunkAnalysisResult> chunkResults, {
  String diagnosisContext = '',
}) {
  final allNotesJson = <String>[];

  for (var i = 0; i < chunkResults.length; i++) {
    final r = chunkResults[i];
    if (r.success && r.notes.isNotEmpty) {
      final notes = r.notes
          .map(
            (n) => {
              'syndromeId': n.syndromeId,
              'description': n.description,
              'evidence': n.evidence,
              'severity': n.severity,
            },
          )
          .toList();
      // 用 toString() 近似 JSON.stringify；生产用 dart:convert jsonEncode 更严谨
      final encoded = '{"notes": ${_encodeJson(notes)}}';
      allNotesJson.add('## 分片 ${i + 1}\n```json\n$encoded\n```');
    }
  }

  final contextSection = diagnosisContext.isNotEmpty
      ? '$diagnosisContext\n---\n\n'
      : '';

  return '''$contextSection# SKILL: 症候诊断手册
（引用内置 syndrome-diagnosis 技能，请严格按照症候定义与例外规则进行裁决。）

---

以下是同一章节多个分片的诊断笔记。请综合所有笔记，做跨片段的统合分析，输出最终的结构化诊断结果：

${allNotesJson.join('\n\n')}

注意事项：
- 同一个症候在不同分片中出现的信号 → 合并为一条诊断，严重度取最高
- 某个症候只在单一分片出现但证据充分 → 保留
- 跨分片一致的信号（如 P005 在开头和结尾都出现）→ 说明这是个系统性问题，提升严重度
- 互相矛盾的信号 → 做权衡判断，只输出合理的结论

叙事合理性判定（最终裁决步骤）：
在输出每条症候之前，请先回答以下问题：
"如果这段文本不被修改，读者体验会显著受损吗？"
只有当答案是"是"时，这条症候才进入最终输出。

数量原则：不限制输出问题数量——识别到多少就报多少。候选较多时按以下优先级排序输出（排序而非截断）：
1. 对读者体验影响最大的问题优先
2. 学员最可能愿意改的问题优先
3. 更基础的问题优先（如 P003 情绪标签化优先于 P008 语言堆砌）

syndrome 对象格式要求：
- syndrome_id (string): 症候编号 P003-P027
- name (string): 症候名称
- severity (L1|L2|L3): 严重度
- evidence (string[]): 原文证据片段，每条症候至少 1 条证据
- explanation (string): 诊断解释
- reader_impact (string): 一句话说明"不改这段，读者会有什么体验影响"。示例："不改这段，读者会在前 200 字内走神，无法进入后续剧情"

请输出标准诊断格式，包含 [YS_DIAGNOSIS] 和 [/YS_DIAGNOSIS] 标记。''';
}

/// 简易 JSON 编码器（仅用于合并 prompt 中展示 notes，不做校验）。
String _encodeJson(Object? obj) {
  if (obj is String) return '"${_escapeJsonString(obj)}"';
  if (obj is num || obj is bool) return obj.toString();
  if (obj == null) return 'null';
  if (obj is List) {
    final items = obj.map((e) => _encodeJson(e)).join(', ');
    return '[$items]';
  }
  if (obj is Map) {
    final entries = obj.entries
        .map(
          (e) =>
              '"${_escapeJsonString(e.key.toString())}": ${_encodeJson(e.value)}',
        )
        .join(', ');
    return '{$entries}';
  }
  return '"${_escapeJsonString(obj.toString())}"';
}

String _escapeJsonString(String s) {
  return s
      .replaceAll(r'\', r'\\')
      .replaceAll('"', r'\"')
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\r')
      .replaceAll('\t', r'\t');
}

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
  } catch (e, st) {
    // LLM 返回结构不符预期 → 本块诊断结果降级为空（原行为保留）。
    // 此前静默吞掉，用户表现为「诊断结果少了/没有」且无从追溯。
    logDecodeFailure(
      field: 'progressive_diagnosis.chunk_notes',
      error: e,
      stack: st,
      category: 'api',
    );
  }
  return const [];
}
