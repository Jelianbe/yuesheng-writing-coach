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

import 'package:flutter/foundation.dart';

import '../config/shared_constants.dart';
import 'decode_guard.dart';
import 'error_handler.dart';
import 'llm_client.dart';
import 'syndrome_registry.dart'; // ADR-C69：分块 prompt 的症候清单改由注册表派生

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

  /// 失败原因码（success=true 时恒为 null，ADR-C80）：
  /// [kChunkFailureEmptyContent]（重试后 content 仍为空）/
  /// [kChunkFailureException]（调用抛异常）。
  final String? failureReason;

  const ChunkAnalysisResult({
    required this.chunkIndex,
    required this.notes,
    required this.success,
    this.failureReason,
  });
}

/// 单块失败原因码：重试后 content 仍为空——推理型模型把 max_tokens 预算
/// 全部耗在 reasoning 上（ADR-C80 §1.2 探针实证）。
const String kChunkFailureEmptyContent = 'empty_content';

/// 单块失败原因码：调用抛异常（网络 / 超时等）。
const String kChunkFailureException = 'exception';

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
///
/// 原子性：单段超长（首段即 ≥ SIZE）时**整段成块**，不再按字符硬切——
/// 段落是分块算法的边界，段内不再切。修复批次 H 侦察的同步死循环缺陷
/// （ADR-C73 §2）。
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

    // 单段原子性：首段即超阈值时**整段成块并跳过 overlap**——
    // 段落是不可再分的原子单元（按 '\n\n' 分块，段内不再切）。
    // 修复批次 H 侦察的同步死循环缺陷（ADR-C73 §2）：
    // 若只推进 endIndex 而不推进 startIndex，overlap 回溯后会
    // 让 startIndex 不变 → while 永真。
    if (endIndex == startIndex) {
      chunks.add(paragraphs[startIndex]);
      startIndex = startIndex + 1;
      continue;
    }

    final chunk = paragraphs.sublist(startIndex, endIndex).join('\n\n');
    chunks.add(chunk);

    startIndex = _overlapStartIndex(paragraphs, endIndex, startIndex);
  }

  _mergeSmallLastChunk(chunks);
  return chunks;
}

/// overlap 回溯：从 endIndex-1 向前累加，直到长度 ≥ OVERLAP。
int _overlapStartIndex(List<String> paragraphs, int endIndex, int startIndex) {
  var overlapLength = 0;
  var overlapStart = endIndex - 1;
  while (overlapStart > startIndex) {
    overlapLength += paragraphs[overlapStart].length + 2;
    if (overlapLength >= kDiagnosisChunkOverlap) {
      break;
    }
    overlapStart--;
  }
  return overlapStart > startIndex ? overlapStart : startIndex;
}

/// 末块过小时合并到前一块（避免单句成块）。
void _mergeSmallLastChunk(List<String> chunks) {
  if (chunks.length < 2) return;
  final last = chunks.last;
  if (last.length < kDiagnosisMinLastChunk) {
    chunks[chunks.length - 2] = '${chunks[chunks.length - 2]}\n\n$last';
    chunks.removeLast();
  }
}

// ── 单块系统提示词（对齐 RN CHUNK_SYSTEM_PROMPT）──
//
// ADR-C69：症候清单原为硬编码 P003-P021（19 条），而注册表已有 39 条
// （P003-P041），导致分块路径漏掉后段 20 个症候——且 anchor 测试覆盖不到本
// 文件（不在 skill_registry 内），缺陷潜伏至今。现改由注册表派生，扩容自动
// 跟随；一致性由 progressive_chunk_syndrome_coverage_test.dart 兜底。

/// 注册表内全部未退役症候，按 ID 升序，形如 `P003 情绪标签化`。
List<String> _activeSyndromeLabels() {
  final rows =
      kSyndromeRegistry
          .where((s) => s.retired != true)
          .map((s) => '${s.id} ${s.name}')
          .toList()
        ..sort();
  return rows;
}

/// 症候 ID 的连续范围说明，形如 `P003-P041`。
///
/// ADR-C69：merge prompt 原硬编码「P003-P027」，与注册表（P003-P041）不符，
/// 会压制后段症候的输出。改由同一真源派生，杜绝两套范围。
String _syndromeIdRange() {
  final ids =
      kSyndromeRegistry
          .where((s) => s.retired != true)
          .map((s) => s.id)
          .toList()
        ..sort();
  if (ids.isEmpty) return '（无可用症候）';
  return '${ids.first}-${ids.last}';
}

/// 例外情况指引（RN 移植，逐字保留）。
///
/// 末条为 ADR-C69 新增的兜底：这些例外只覆盖 P003-P021，注册表扩到 P041 后
/// 后段症候没有对应例外，补一句通用兜底避免"零例外"导致的过度诊断。
const String _kChunkExceptionGuide = '''例外情况指引（以下场景通常不应判定为症候）：
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
- 上面未列出的症候：例外情况以症候诊断手册为准；判定尺度与上述一致——只在读者体验确实会受损时才算症候''';

/// 单块输出格式（纯静态，与症候清单分离）。
const String _kChunkOutputFormat = '''请输出JSON格式的笔记，不要包含markdown代码块标记，只输出纯JSON对象：
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

/// 构造单块系统提示词：症候清单由注册表派生（ADR-C69）。
///
/// 每行 4 个，沿用 RN 逐字移植时的紧凑排布，避免 39 条摊成 39 行。
String _buildChunkSystemPrompt() {
  final labels = _activeSyndromeLabels();
  final listBlock = <String>[];
  for (var i = 0; i < labels.length; i += 4) {
    final end = i + 4 > labels.length ? labels.length : i + 4;
    listBlock.add('- ${labels.sublist(i, end).join(' / ')}');
  }
  return '''你是一个专业的写作诊断助手。请阅读以下文本片段，识别其中存在的写作问题。

症候类型参考（仅用于标注，不要强行匹配）：
${listBlock.join('\n')}

$_kChunkExceptionGuide

$_kChunkOutputFormat''';
}

/// 单块系统提示词：症候清单由注册表派生，调用处无需感知（ADR-C69）。
final String kChunkSystemPrompt = _buildChunkSystemPrompt();

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
- syndrome_id (string): 症候编号 ${_syndromeIdRange()}（由注册表派生，ADR-C69）
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

  // 2. 逐块分析（非流式 chatCompletion；空内容分级降级见 ADR-C80）
  final chunkResults = <ChunkAnalysisResult>[];
  var failedChunks = 0;

  for (var i = 0; i < chunks.length; i++) {
    final result = await _analyzeSingleChunk(
      llmClient,
      title: title,
      chunk: chunks[i],
      chunkIndex: i,
      chunkCount: chunks.length,
      onProgress: onProgress,
    );
    if (!result.success) failedChunks++;
    chunkResults.add(result);
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

// ── 单块分析：空内容分级降级（ADR-C80）──

/// 单块分析的 messages（尝试 1 与兜底重试共用同一组消息）。
List<ChatMessage> _chunkMessages(
  String title,
  String chunk,
  int chunkIndex,
  int chunkCount,
) {
  return [
    // ADR-C69：kChunkSystemPrompt 改由注册表派生（非 const），此处 const 去掉
    ChatMessage(role: 'system', content: kChunkSystemPrompt),
    ChatMessage(
      role: 'user',
      content: '章节标题：$title\n\n文本片段 ${chunkIndex + 1}/$chunkCount：\n\n$chunk',
    ),
  ];
}

/// 单块分析（ADR-C80 分级降级）：
///
/// 尝试 1 = 应用现参数（推理开启，质量优先，成功路径零变更）；content 为空
/// → 尝试 2 = 兜底参数（8192 + thinking disabled，推理归零，实测见 ADR §1.2）；
/// 仍空 → 返回 success=false + [kChunkFailureEmptyContent] 并留痕。
/// 异常路径同样置 [kChunkFailureException] 并留痕（此前 catch 静默）。
///
/// 「空」判据是 `content.trim().isEmpty`：合法「零症候」是 notes 为空的
/// 非空 JSON（模型说了「没有」），与本缺陷（模型一个字没说）是两回事。
Future<ChunkAnalysisResult> _analyzeSingleChunk(
  LlmClient llmClient, {
  required String title,
  required String chunk,
  required int chunkIndex,
  required int chunkCount,
  required ProgressCallback? onProgress,
}) async {
  final messages = _chunkMessages(title, chunk, chunkIndex, chunkCount);
  try {
    var content = await llmClient.chatCompletion(messages);
    if (content.trim().isEmpty) {
      content = await llmClient.chatCompletion(
        messages,
        maxTokens: LlmConfig.chunkAnalysisFallbackMaxTokens,
        extraBody: LlmConfig.chunkAnalysisFallbackExtraBody,
      );
    }
    // 空块此前走成功路径会推进度，保持推进；异常块此前不推，保持不推
    onProgress?.call('分析分片', chunkIndex + 1, chunkCount);
    if (content.trim().isEmpty) {
      _logChunkFailure(chunkIndex, kChunkFailureEmptyContent);
      return ChunkAnalysisResult(
        chunkIndex: chunkIndex,
        notes: const [],
        success: false,
        failureReason: kChunkFailureEmptyContent,
      );
    }
    final jsonStr = extractJson(content);
    final notes = _parseChunkNotes(jsonStr);
    return ChunkAnalysisResult(
      chunkIndex: chunkIndex,
      notes: notes,
      success: true,
    );
  } catch (e, st) {
    _logChunkFailure(chunkIndex, kChunkFailureException, error: e, stack: st);
    return ChunkAnalysisResult(
      chunkIndex: chunkIndex,
      notes: const [],
      success: false,
      failureReason: kChunkFailureException,
    );
  }
}

/// 单块失败显式留痕（ADR-C63 范式：降级行为保留，可观测性补上）。
void _logChunkFailure(
  int chunkIndex,
  String reason, {
  Object? error,
  StackTrace? stack,
}) {
  debugPrint(
    '[progressive_diagnosis] 分块 $chunkIndex 失败 reason=$reason'
    '${error != null ? ' error=$error' : ''}',
  );
  ErrorHandler.instance.captureError(
    level: 'warn',
    category: 'api',
    message: '分块诊断失败，已按失败块降级',
    context: {
      'chunkIndex': chunkIndex,
      'reason': reason,
      if (error != null) 'error': '$error',
    },
    stack: stack?.toString(),
  );
}
