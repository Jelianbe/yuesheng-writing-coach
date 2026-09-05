// ─────────────────────────────────────────────────────────────
// Teacher Service
// 复刻 yuesheng-android/src/services/teacher-service.ts
//
// 用 streamChat 调 teacher skill，
// 流式拦截 [YS_TEACHER] 块（不转发给用户），
// 结束后 parseTeacherDecision + validateTeacherOutput 完整校验。
//
// 失败处理（不 throw，与 editor-service 一致）：
//   - API 错误 → 空 displayContent + null teacher
//   - 解析失败 → 去标记原文 displayContent + null teacher
//   - 校验失败 → 同解析失败
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:writingcoach/services/agent_skills.dart';
import 'package:writingcoach/services/editor_validator.dart';
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/services/teacher_parser.dart';
import 'package:writingcoach/services/teacher_validator.dart';
import 'package:writingcoach/types/teaching_types.dart';

/// Teacher 输入：Editor 分支或 Diagnosis 分支
/// 真源：teacher-service.ts TeacherInput
sealed class TeacherInput {
  const TeacherInput();
}

class TeacherEditorInput extends TeacherInput {
  final EditorResult editorResult;
  final String chapterContent;
  const TeacherEditorInput({
    required this.editorResult,
    required this.chapterContent,
  });
}

class TeacherDiagnosisInput extends TeacherInput {
  final ParsedDiagnosis diagnosis;
  final String chapterContent;
  const TeacherDiagnosisInput({
    required this.diagnosis,
    required this.chapterContent,
  });
}

class TeacherStreamResult {
  final String displayContent;
  final TeacherResult? teacher;
  const TeacherStreamResult({required this.displayContent, this.teacher});
}

/// 调用 Teacher Agent 做教学决策。
///
/// 真源：teacher-service.ts callTeacherStream
///
/// [onStream] 收到的是去除 [YS_TEACHER] 块的自然语言部分。
Future<TeacherStreamResult> callTeacherStream(
  LlmClient llmClient,
  TeacherInput input,
  void Function(String delta) onStream, {
  CancelToken? cancelToken,
}) async {
  try {
    final accumulator = _TeacherStreamAccumulator(
      onStream,
      messages: _buildTeacherMessages(input),
    );
    await llmClient.streamChat(accumulator.messages, (response) {
      if (response.isDone) return;
      if (response.content.isEmpty) return;
      accumulator.add(response.content);
    }, cancelToken: cancelToken);
    return _finalizeTeacherResult(accumulator.fullContent);
  } catch (_) {
    // API 错误 → 返回空 displayContent，不抛出
    return const TeacherStreamResult(displayContent: '', teacher: null);
  }
}

/// 构建教学请求消息（R-019 拆出：callTeacherStream）。
List<ChatMessage> _buildTeacherMessages(TeacherInput input) {
  return <ChatMessage>[
    ChatMessage(role: 'system', content: kTeacherSkillContent),
    ChatMessage(role: 'user', content: _buildTeacherUserPrompt(input)),
  ];
}

/// 流式结束收尾：解析 + consistency 校验 + 组装结果（R-019 拆出）。
TeacherStreamResult _finalizeTeacherResult(String fullContent) {
  final parsed = parseTeacherDecision(fullContent);
  final displayContent = parsed.displayContent;
  if (parsed.teacher == null) {
    return TeacherStreamResult(displayContent: displayContent, teacher: null);
  }
  // parser 已做 schema 校验，service 只做 consistency 校验
  final consistency = checkTeacherConsistency(parsed.teacher!);
  if (!consistency.passed) {
    return TeacherStreamResult(displayContent: displayContent, teacher: null);
  }
  return TeacherStreamResult(
    displayContent: displayContent,
    teacher: parsed.teacher,
  );
}

/// 流式累积器：拦截 [YS_TEACHER] 标记，转发标记前自然语言（R-019 拆出）。
/// 与 editor-service 的拦截模式一致。
class _TeacherStreamAccumulator {
  final void Function(String) onStream;
  final List<ChatMessage> messages;
  String fullContent = '';
  bool inTeacherBlock = false;
  int displayLength = 0;
  _TeacherStreamAccumulator(this.onStream, {required this.messages});

  void add(String content) {
    fullContent += content;
    if (inTeacherBlock) return;
    final markerIndex = fullContent.indexOf(kTeacherStart);
    if (markerIndex != -1) {
      final newDisplay = fullContent.substring(displayLength, markerIndex);
      if (newDisplay.isNotEmpty) onStream(newDisplay);
      displayLength = markerIndex;
      inTeacherBlock = true;
      return;
    }
    final pendingLen = getTeacherPendingMarkerPrefix(fullContent);
    final safeEnd = pendingLen > 0
        ? fullContent.length - pendingLen
        : fullContent.length;
    if (safeEnd > displayLength) {
      final newDisplay = fullContent.substring(displayLength, safeEnd);
      if (newDisplay.isNotEmpty) onStream(newDisplay);
      displayLength = safeEnd;
    }
  }
}

/// 根据 TeacherInput 构造 user prompt。
///
/// 真源：teacher-service.ts buildTeacherUserPrompt
String _buildTeacherUserPrompt(TeacherInput input) {
  if (input is TeacherEditorInput) {
    final obs = input.editorResult;
    return '请基于以下编辑观察做教学决策，输出 [YS_TEACHER] JSON。\n\n'
        '## 编辑观察\n\n${_serializeEditorResult(obs)}\n\n'
        '## 待观察文本\n\n${input.chapterContent}';
  } else if (input is TeacherDiagnosisInput) {
    final diag = input.diagnosis;
    final diagJson = jsonEncode({
      'syndromes': diag.syndromes.map((s) => s.toJson()).toList(),
      'suggested_actions': diag.suggestedActions,
      'confidence': diag.confidence,
      'feedback_summary': diag.feedbackSummary,
    });
    return '请基于以下诊断结果做教学决策，输出 [YS_TEACHER] JSON。\n\n'
        '## 诊断结果\n\n$diagJson\n\n'
        '## 待诊断文本\n\n${input.chapterContent}';
  }
  // 不可达
  return '';
}

/// 序列化 EditorResult 为可读 JSON（与 RN JSON.stringify(obs, null, 2) 对应）
String _serializeEditorResult(EditorResult obs) {
  final map = {
    'possible_intent': obs.possibleIntent,
    'intent_confidence': obs.intentConfidence,
    'observations': obs.observations
        .map(
          (o) => {
            'dimension': o.dimension,
            'dimension_name': o.dimensionName,
            'phenomenon': o.phenomenon,
            'evidence': o.evidence,
            'reader_impact': o.readerImpact,
            'observation_visibility': o.observationVisibility,
            'intent_alignment': o.intentAlignment,
          },
        )
        .toList(),
    'overall_impression': obs.overallImpression,
    'strengths': obs.strengths,
  };
  return const JsonEncoder.withIndent('  ').convert(map);
}
