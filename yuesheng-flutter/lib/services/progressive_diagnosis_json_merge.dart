// ─────────────────────────────────────────────────────────────
// progressive_diagnosis 拆分：progressive_diagnosis_json_merge.dart（R-019 ≤300 行）
// JSON 提取与合并：extractJson/buildMergePrompt/_encodeJson/_escapeJsonString。迁移自 progressive_diagnosis.dart，行为零变更。
// ─────────────────────────────────────────────────────────────
part of 'progressive_diagnosis.dart';
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

