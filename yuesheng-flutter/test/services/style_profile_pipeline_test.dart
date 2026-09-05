// ─────────────────────────────────────────────────────────────
// 批次53 识别层测试 — style_profile 诊断协议解析 + 落库
//
// 覆盖：
//   parser 单元：#B53-R1..R4
//   集成链路：#B53-R5/R6（sendMessage 诊断带 style_profile → student_model 落库）
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/editor_observation_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/reference_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/data/repositories/student_model_repository.dart';
import 'package:writingcoach/data/repositories/teacher_suggestion_repository.dart';
import 'package:writingcoach/data/repositories/teaching_state_repository.dart';
import 'package:writingcoach/services/chat_service.dart';
import 'package:writingcoach/services/diagnosis_committer.dart';
import 'package:writingcoach/services/message_injector.dart';
import 'package:writingcoach/services/chat_context_builder.dart'
    show MaterialCapabilityImpl;
import 'package:writingcoach/services/diagnosis_parser.dart';
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/types/teaching_types.dart';

import 'package:writingcoach/services/diagnosis_flow_handler.dart';
import 'package:writingcoach/services/diagnosis_parser.dart'
    show DiagnosisCapabilityImpl;
import 'package:writingcoach/services/genui_parser.dart'
    show GenUiParser;
import 'package:writingcoach/services/chat_message_types.dart'
    show SendMessageCallbacks, SendMessageOptions;
/// 生成合法诊断块 JSON 文本（可附加 style_profile 等额外字段）
String buildDiagnosisBlock(Map<String, dynamic>? extra) {
  final base = <String, dynamic>{
    'syndromes': [
      {
        'syndrome_id': 'P003',
        'name': '情绪标签化',
        'severity': 'L2',
        'evidence': ['文中直接写"她很生气"'],
        'explanation': '情绪被直接陈述而非通过行为/细节呈现',
      },
    ],
    'suggested_actions': ['A006 感官全开'],
    'confidence': 0.8,
    ...?extra,
  };
  return '[YS_DIAGNOSIS]\n${jsonEncode(base)}\n[/YS_DIAGNOSIS]';
}

const styleJson = {
  'sensory': 'visual',
  'rhythm': 'short',
  'narrative_distance': 'intimate',
  'tone_texture': 'poetic',
  'structure': 'linear',
  'summary': '你的文字有一种画家的眼睛——颜色和光线的使用特别丰富。',
  'confidence': 0.7,
};

void main() {
  group('批次53: diagnosis_parser style_profile 解析', () {
    test('#B53-R1 合法 style_profile 解析出五维', () {
      final result = parseDiagnosis(
        '正文。\n${buildDiagnosisBlock({'style_profile': styleJson})}',
      );
      expect(result.diagnosis, isNotNull);
      final style = result.diagnosis!.styleProfile;
      expect(style, isNotNull);
      expect(style!.sensory, SensoryPreference.visual);
      expect(style.rhythm, RhythmPreference.short);
      expect(style.narrativeDistance, NarrativeDistance.intimate);
      expect(style.toneTexture, ToneTexture.poetic);
      expect(style.structure, StructureInstinct.linear);
      expect(style.summary, contains('画家的眼睛'));
      expect(style.confidence, 0.7);
    });

    test('#B53-R2 缺失 style_profile 时 diagnosis 正常解析、style 为 null', () {
      final result = parseDiagnosis('正文。\n${buildDiagnosisBlock(null)}');
      expect(result.diagnosis, isNotNull);
      expect(result.diagnosis!.styleProfile, isNull);
      expect(result.diagnosis!.syndromes.length, 1);
    });

    test('#B53-R3 非法 style_profile（缺 summary）不阻断诊断', () {
      final result = parseDiagnosis(
        buildDiagnosisBlock({
          'style_profile': {'sensory': 'visual'}, // 缺 summary
        }),
      );
      expect(result.diagnosis, isNotNull);
      expect(result.diagnosis!.styleProfile, isNull);
      expect(result.diagnosis!.syndromes.length, 1);
    });

    test('#B53-R4 style_profile 为非法类型（非 map）不阻断诊断', () {
      final result = parseDiagnosis(
        buildDiagnosisBlock({'style_profile': 'not-a-map'}),
      );
      expect(result.diagnosis, isNotNull);
      expect(result.diagnosis!.styleProfile, isNull);
    });
  });

  group('批次53: sendMessage 诊断链路 style_profile 落库', () {
    late AppDatabase db;
    late SessionRepository sessionRepo;
    late String sessionId;
    late StudentModelRepository studentModelRepo;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      sessionRepo = SessionRepository(db);
      sessionId = await sessionRepo.createBlankSession(title: '风格链路');
      studentModelRepo = StudentModelRepository(db);
    });

    tearDown(() async => db.close());

    ChatService buildChatService(LlmClient llm) {
      return ChatService(
        sessionRepo: sessionRepo,
        stateRepo: TeachingStateRepository(db),
        diagnosisRepo: DiagnosisRepository(db),
        studentModelRepo: studentModelRepo,
        referenceRepo: ReferenceRepository(db),
        chapterRepo: ChapterRepository(db),
        manuscriptRepo: ManuscriptRepository(db),
        llmClient: llm,
        teacherSuggestionRepo: TeacherSuggestionRepository(db),
        editorObservationRepo: EditorObservationRepository(db),
        // ADR-C74 K-5：诊断提交编排器收紧为 required
        diagnosisCommitter: DiagnosisCommitter(
          sessionRepo: sessionRepo,
          stateRepo: TeachingStateRepository(db),
          diagnosisRepo: DiagnosisRepository(db),
          studentModelRepo: studentModelRepo,
          referenceRepo: ReferenceRepository(db),
          chapterRepo: ChapterRepository(db),
        ),

        messageInjector: MessageInjector(
          sessionRepo: sessionRepo,

          diagnosisRepo: DiagnosisRepository(db),

          studentModelRepo: StudentModelRepository(db),

          referenceRepo: ReferenceRepository(db),

          chapterRepo: ChapterRepository(db),

          manuscriptRepo: ManuscriptRepository(db),

          diagnosisCommitter: DiagnosisCommitter(
            sessionRepo: sessionRepo,

            stateRepo: TeachingStateRepository(db),

            diagnosisRepo: DiagnosisRepository(db),

            studentModelRepo: studentModelRepo,

            referenceRepo: ReferenceRepository(db),

            chapterRepo: ChapterRepository(db),
          ),

          material: const MaterialCapabilityImpl(),
        ),
        diagnosisFlowHandler: DiagnosisFlowHandler(
          sessionRepo: SessionRepository(db),
          stateRepo: TeachingStateRepository(db),
          diagnosisRepo: DiagnosisRepository(db),
          studentModelRepo: StudentModelRepository(db),
          referenceRepo: ReferenceRepository(db),
          chapterRepo: ChapterRepository(db),
          teacherSuggestionRepo: TeacherSuggestionRepository(db),
          llmClient: llm,

          messageInjector: MessageInjector(
            sessionRepo: sessionRepo,

            diagnosisRepo: DiagnosisRepository(db),

            studentModelRepo: StudentModelRepository(db),

            referenceRepo: ReferenceRepository(db),

            chapterRepo: ChapterRepository(db),

            manuscriptRepo: ManuscriptRepository(db),

            diagnosisCommitter: DiagnosisCommitter(
              sessionRepo: sessionRepo,

              stateRepo: TeachingStateRepository(db),

              diagnosisRepo: DiagnosisRepository(db),

              studentModelRepo: studentModelRepo,

              referenceRepo: ReferenceRepository(db),

              chapterRepo: ChapterRepository(db),
            ),

            material: const MaterialCapabilityImpl(),
          ),
          diagnosisCommitter: DiagnosisCommitter(
            sessionRepo: sessionRepo,
            stateRepo: TeachingStateRepository(db),
            diagnosisRepo: DiagnosisRepository(db),
            studentModelRepo: studentModelRepo,
            referenceRepo: ReferenceRepository(db),
            chapterRepo: ChapterRepository(db),
          ),
          diagnosis: const DiagnosisCapabilityImpl(),
          genUi: const GenUiParser(),
        ),
      );
    }

    test('#B53-R5 诊断带 style_profile → student_model 落库', () async {
      final llm = _FakeLlm(
        '正文。\n${buildDiagnosisBlock({'style_profile': styleJson})}',
      );
      await buildChatService(llm).sendMessage(
        sessionId,
        '帮我看看这段',
        SendMessageCallbacks(
          onStream: (_) {},
          onComplete: (_, _) {},
          onError: (_) {},
        ),
        const SendMessageOptions(
          phase: TeachingPhase.p2PracticeLoop,
          attitude: AttitudeLevel.doubao,
        ),
      );

      final style = await studentModelRepo.getStyleProfile(sessionId);
      expect(style, isNotNull);
      expect(style!.sensory, SensoryPreference.visual);
      expect(style.rhythm, RhythmPreference.short);
      expect(style.summary, contains('画家的眼睛'));
    });

    test('#B53-R6 诊断不带 style_profile → 不落库（getStyleProfile null）', () async {
      final llm = _FakeLlm('正文。\n${buildDiagnosisBlock(null)}');
      await buildChatService(llm).sendMessage(
        sessionId,
        '帮我看看这段',
        SendMessageCallbacks(
          onStream: (_) {},
          onComplete: (_, _) {},
          onError: (_) {},
        ),
        const SendMessageOptions(
          phase: TeachingPhase.p2PracticeLoop,
          attitude: AttitudeLevel.doubao,
        ),
      );

      final style = await studentModelRepo.getStyleProfile(sessionId);
      expect(style, isNull);
    });
  });
}

/// Fake LLM：按 chunk 流式返回完整响应
class _FakeLlm extends LlmClient {
  final String _fullResponse;
  _FakeLlm(this._fullResponse);

  @override
  Future<void> streamChat(
    List<ChatMessage> messages,
    void Function(LlmStreamResponse response) callback, {
    CancelToken? cancelToken,
  }) async {
    for (int i = 0; i < _fullResponse.length; i += 20) {
      final end = i + 20 < _fullResponse.length ? i + 20 : _fullResponse.length;
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
