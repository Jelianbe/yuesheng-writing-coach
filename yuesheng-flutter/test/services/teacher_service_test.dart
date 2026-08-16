// ─────────────────────────────────────────────────────────────
// teacher_service_test — callTeacherStream 测试
//
// 覆盖路径：
//   TeacherEditorInput:
//     1. 成功：guide + task → displayContent + teacher
//     2. 成功：encourage（无 task）→ displayContent + teacher
//     3. 无 [YS_TEACHER] 标记 → displayContent=原文，teacher=null
//     4. schema 校验失败（缺字段）→ teacher=null
//     5. consistency 失败（guide 但 task=null）→ teacher=null
//     6. consistency 失败（natural_language 含判决词）→ teacher=null
//     7. LLM 抛异常 → 空 displayContent + teacher=null
//
//   TeacherDiagnosisInput:
//     8. 成功：基于诊断结果做教学决策 → displayContent + teacher
//
//   流式跨 chunk 标记:
//     9. [YS_TEACHER] 被拆分到多个 chunk → 仍能正确拦截
//
// 设计：FakeLlmClient 继承 LlmClient override streamChat。
// ─────────────────────────────────────────────────────────────

// ignore_for_file: prefer_initializing_formals

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/editor_validator.dart';
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/services/teacher_service.dart';
import 'package:writingcoach/types/teaching_types.dart';

/// Fake LLM 客户端：预设 streamChat 响应
class FakeLlmClient extends LlmClient {
  final String _fullResponse;
  final Exception? _error;
  final int _chunkSize;

  FakeLlmClient(this._fullResponse, {Exception? error, int chunkSize = 10})
    : _error = error,
      _chunkSize = chunkSize;

  @override
  Future<void> streamChat(
    List<ChatMessage> messages,
    void Function(LlmStreamResponse response) callback, {
    CancelToken? cancelToken,
  }) async {
    if (_error != null) throw _error;

    for (int i = 0; i < _fullResponse.length; i += _chunkSize) {
      final end = i + _chunkSize < _fullResponse.length
          ? i + _chunkSize
          : _fullResponse.length;
      callback(
        LlmStreamResponse(
          content: _fullResponse.substring(i, end),
          isDone: false,
        ),
      );
    }
    callback(const LlmStreamResponse(content: '', isDone: true));
  }
}

// ─── 合法 TeacherResult JSON ──────────────────────────────────

/// guide + task（合法）
const String kGuideWithTaskJson = '''{
  "teaching_decision": "guide",
  "teaching_reason": "需要引导人物能动性",
  "natural_language": "这段文字的意象很独特，可以试着让主角更主动地推动情节。",
  "training_task": {
    "target_syndrome_id": "P001",
    "target_dimension": "character_agency",
    "task_type": "rewrite",
    "task_description": "重写第三段，让主角主动做决定",
    "difficulty": "medium",
    "evaluation_criteria": ["主角是否主动做决定"]
  }
}''';

/// encourage（合法，无 task）
const String kEncourageJson = '''{
  "teaching_decision": "encourage",
  "teaching_reason": "整体表现良好",
  "natural_language": "这段文字的节奏感很好，继续保持。"
}''';

/// schema 失败（缺 teaching_reason）
const String kSchemaFailJson = '''{
  "teaching_decision": "guide",
  "natural_language": "反馈"
}''';

/// consistency 失败（guide 但无 training_task）
const String kConsistencyFailNoTaskJson = '''{
  "teaching_decision": "guide",
  "teaching_reason": "需要引导",
  "natural_language": "这段文字可以进一步打磨。"
}''';

/// consistency 失败（natural_language 含判决词"应该"）
const String kConsistencyFailVerdictJson = '''{
  "teaching_decision": "encourage",
  "teaching_reason": "整体良好",
  "natural_language": "这段文字应该更精炼一些。"
}''';

// ─── 测试 fixtures ────────────────────────────────────────────

EditorResult _editorResult() {
  return EditorResult(
    possibleIntent: '表达情绪',
    intentConfidence: 'moderate',
    observations: [
      EditorObservation(
        dimension: 'character_agency',
        dimensionName: '人物能动性',
        phenomenon: '主角缺乏主动选择',
        evidence: const ['第3段'],
        readerImpact: '读者难以代入',
        observationVisibility: 'pronounced',
        intentAlignment: 'against',
      ),
      EditorObservation(
        dimension: 'pacing_control',
        dimensionName: '节奏',
        phenomenon: '场景推进偏快',
        evidence: const ['第5段'],
        readerImpact: '情绪未铺垫',
        observationVisibility: 'moderate',
        intentAlignment: 'unclear',
      ),
      EditorObservation(
        dimension: 'dialogue_dynamics',
        dimensionName: '对话',
        phenomenon: '对话密度高',
        evidence: const ['对话段'],
        readerImpact: '信息过载',
        observationVisibility: 'subtle',
        intentAlignment: 'aligned',
      ),
    ],
    overallImpression: '有潜力',
    strengths: const ['意象独特'],
  );
}

ParsedDiagnosis _parsedDiagnosis() {
  return ParsedDiagnosis(
    syndromes: [
      Syndrome(
        syndromeId: 'P001',
        name: '能动性不足',
        severity: Severity.l2,
        evidence: const ['第3段'],
        explanation: '主角缺乏主动选择',
      ),
    ],
    suggestedActions: const ['增加主动决策'],
    confidence: 0.85,
    feedbackSummary: '整体有潜力，需加强人物能动性',
  );
}

void main() {
  group('callTeacherStream — TeacherEditorInput', () {
    test('#1 成功：guide + task', () async {
      final raw = '给用户的反馈\n[YS_TEACHER]\n$kGuideWithTaskJson\n[/YS_TEACHER]';
      final llm = FakeLlmClient(raw);
      final input = TeacherEditorInput(
        editorResult: _editorResult(),
        chapterContent: '测试文本',
      );

      final deltas = <String>[];
      final result = await callTeacherStream(llm, input, (d) => deltas.add(d));

      expect(result.teacher, isNotNull);
      expect(result.teacher!.teachingDecision, 'guide');
      expect(result.teacher!.trainingTask, isNotNull);
      expect(result.teacher!.trainingTask!.taskType, 'rewrite');
      expect(result.displayContent, contains('给用户的反馈'));
      // [YS_TEACHER] 块不应转发给 onStream
      expect(deltas.join(''), isNot(contains('[YS_TEACHER]')));
      expect(deltas.join(''), isNot(contains('teaching_decision')));
    });

    test('#2 成功：encourage（无 task）', () async {
      final raw = '[YS_TEACHER]\n$kEncourageJson\n[/YS_TEACHER]';
      final llm = FakeLlmClient(raw);
      final input = TeacherEditorInput(
        editorResult: _editorResult(),
        chapterContent: '测试文本',
      );

      final result = await callTeacherStream(llm, input, (_) {});

      expect(result.teacher, isNotNull);
      expect(result.teacher!.teachingDecision, 'encourage');
      expect(result.teacher!.trainingTask, isNull);
    });

    test('#3 无 [YS_TEACHER] 标记 → displayContent=原文，teacher=null', () async {
      final raw = '纯文本回复';
      final llm = FakeLlmClient(raw);
      final input = TeacherEditorInput(
        editorResult: _editorResult(),
        chapterContent: '测试文本',
      );

      final result = await callTeacherStream(llm, input, (_) {});

      expect(result.teacher, isNull);
      expect(result.displayContent, '纯文本回复');
    });

    test('#4 schema 校验失败（缺字段）→ teacher=null', () async {
      final raw = '[YS_TEACHER]\n$kSchemaFailJson\n[/YS_TEACHER]';
      final llm = FakeLlmClient(raw);
      final input = TeacherEditorInput(
        editorResult: _editorResult(),
        chapterContent: '测试文本',
      );

      final result = await callTeacherStream(llm, input, (_) {});

      expect(result.teacher, isNull);
    });

    test('#5 consistency 失败（guide 但 task=null）→ teacher=null', () async {
      final raw = '[YS_TEACHER]\n$kConsistencyFailNoTaskJson\n[/YS_TEACHER]';
      final llm = FakeLlmClient(raw);
      final input = TeacherEditorInput(
        editorResult: _editorResult(),
        chapterContent: '测试文本',
      );

      final result = await callTeacherStream(llm, input, (_) {});

      expect(result.teacher, isNull);
    });

    test(
      '#6 consistency 失败（natural_language 含判决词"应该"）→ teacher=null',
      () async {
        final raw = '[YS_TEACHER]\n$kConsistencyFailVerdictJson\n[/YS_TEACHER]';
        final llm = FakeLlmClient(raw);
        final input = TeacherEditorInput(
          editorResult: _editorResult(),
          chapterContent: '测试文本',
        );

        final result = await callTeacherStream(llm, input, (_) {});

        expect(result.teacher, isNull);
      },
    );

    test('#7 LLM 抛异常 → 空 displayContent + teacher=null', () async {
      final llm = FakeLlmClient('', error: Exception('网络错误'));
      final input = TeacherEditorInput(
        editorResult: _editorResult(),
        chapterContent: '测试文本',
      );

      final result = await callTeacherStream(llm, input, (_) {});

      expect(result.teacher, isNull);
      expect(result.displayContent, '');
    });
  });

  group('callTeacherStream — TeacherDiagnosisInput', () {
    test('#8 成功：基于诊断结果做教学决策', () async {
      final raw = '诊断反馈\n[YS_TEACHER]\n$kGuideWithTaskJson\n[/YS_TEACHER]';
      final llm = FakeLlmClient(raw);
      final input = TeacherDiagnosisInput(
        diagnosis: _parsedDiagnosis(),
        chapterContent: '测试文本',
      );

      final result = await callTeacherStream(llm, input, (_) {});

      expect(result.teacher, isNotNull);
      expect(result.teacher!.teachingDecision, 'guide');
      expect(result.displayContent, contains('诊断反馈'));
    });
  });

  group('流式跨 chunk 标记', () {
    test('#9 [YS_TEACHER] 被拆分到多个 chunk → 仍能正确拦截', () async {
      final raw = '反馈\n[YS_TEACHER]\n$kGuideWithTaskJson\n[/YS_TEACHER]';
      final llm = FakeLlmClient(raw, chunkSize: 3);
      final input = TeacherEditorInput(
        editorResult: _editorResult(),
        chapterContent: '测试文本',
      );

      final deltas = <String>[];
      final result = await callTeacherStream(llm, input, (d) => deltas.add(d));

      expect(result.teacher, isNotNull);
      final combined = deltas.join('');
      expect(combined, isNot(contains('[YS_TEACHER]')));
      expect(combined, isNot(contains('teaching_decision')));
      expect(combined, contains('反馈'));
    });
  });
}
