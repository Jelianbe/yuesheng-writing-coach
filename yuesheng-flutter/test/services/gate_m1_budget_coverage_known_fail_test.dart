// ignore_for_file: avoid_print
// ─────────────────────────────────────────────────────────────
// 发布门槛 M1 — 预算覆盖完整性（2026-10-13 四任务书 §4-M1）
//
// 缺陷 C1（批 1 E2 四路印证）：TokenBudgetGuard.apply 全仓唯一调用点在
// prompt_assembly_service.appendHistoryAndConstraints 末尾（装配中段），
// 其后主链仍会追加：
//   - 诊断协议后缀 + 全貌块 + fading 块（DiagnosisInjectionService）
//   - 「## 待诊断全文」整章正文（SendMessageOptions.chapterFullText）
//   - 附件 contentBlocks（chat_service._attachUserAttachments）
// 这些内容不过第二道预算闸门 ⇒ 可把总估算推过 maxBudget 而无人裁剪。
//
// 现状即 FAIL → 显式 known-fail 基线（skip 标注，不让 CI 挂红）。
// 治理批次 S4 把闸门挪到追加链末尾（或对后追加内容二次计费）后，
// 去掉 skip 转绿。转绿判据：携带超大整章正文走真实发送主链，
// 最终发给 LLM 的消息总估算 ≤ TokenEstimate.maxBudget。
// ─────────────────────────────────────────────────────────────

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/config/shared_constants.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/reference_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/data/repositories/student_model_repository.dart';
import 'package:writingcoach/data/repositories/teacher_suggestion_repository.dart';
import 'package:writingcoach/data/repositories/teaching_state_repository.dart';
import 'package:writingcoach/services/chat_context_builder.dart'
    show MaterialCapabilityImpl;
import 'package:writingcoach/services/chat_message_types.dart'
    show SendMessageCallbacks, SendMessageOptions;
import 'package:writingcoach/services/chat_service.dart';
import 'package:writingcoach/services/diagnosis_committer.dart';
import 'package:writingcoach/services/diagnosis_flow_handler.dart';
import 'package:writingcoach/services/diagnosis_parser.dart'
    show DiagnosisCapabilityImpl;
import 'package:writingcoach/services/genui_parser.dart' show GenUiParser;
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/services/message_injector.dart';
import 'package:writingcoach/services/token_budget_guard.dart';
import 'package:writingcoach/types/teaching_types.dart';

const String _kUserContent = '帮我诊断一下这一章的节奏。';

/// 超大整章正文：估算 ≈ 200k tokens（charToTokenRatio=1.0，chars≈tokens），
/// 远超 maxBudget——若闸门覆盖后追加内容，必然触发裁剪。
final String _kHugeChapterFullText = '第一章 风起。' * 33334;

class _CaptureLlmClient extends LlmClient {
  List<ChatMessage> captured = <ChatMessage>[];

  @override
  Future<void> streamChat(
    List<ChatMessage> messages,
    void Function(LlmStreamResponse response) callback, {
    CancelToken? cancelToken,
    Map<String, dynamic>? extraBody,
  }) async {
    captured = List<ChatMessage>.from(messages);
    callback(const LlmStreamResponse(content: '收到，我们开始。', isDone: false));
    callback(const LlmStreamResponse(content: '', isDone: true));
  }
}

ChatService _buildChatService(AppDatabase db, LlmClient llmClient) {
  final sessionRepo = SessionRepository(db);
  DiagnosisCommitter committer() => DiagnosisCommitter(
    sessionRepo: sessionRepo,
    stateRepo: TeachingStateRepository(db),
    diagnosisRepo: DiagnosisRepository(db),
    studentModelRepo: StudentModelRepository(db),
    referenceRepo: ReferenceRepository(db),
    chapterRepo: ChapterRepository(db),
  );
  MessageInjector injector() => MessageInjector(
    sessionRepo: sessionRepo,
    diagnosisRepo: DiagnosisRepository(db),
    studentModelRepo: StudentModelRepository(db),
    referenceRepo: ReferenceRepository(db),
    chapterRepo: ChapterRepository(db),
    manuscriptRepo: ManuscriptRepository(db),
    diagnosisCommitter: committer(),
    material: const MaterialCapabilityImpl(),
  );
  return ChatService(
    sessionRepo: sessionRepo,
    stateRepo: TeachingStateRepository(db),
    diagnosisRepo: DiagnosisRepository(db),
    referenceRepo: ReferenceRepository(db),
    llmClient: llmClient,
    messageInjector: injector(),
    diagnosisFlowHandler: DiagnosisFlowHandler(
      sessionRepo: sessionRepo,
      stateRepo: TeachingStateRepository(db),
      diagnosisRepo: DiagnosisRepository(db),
      studentModelRepo: StudentModelRepository(db),
      referenceRepo: ReferenceRepository(db),
      chapterRepo: ChapterRepository(db),
      teacherSuggestionRepo: TeacherSuggestionRepository(db),
      llmClient: llmClient,
      messageInjector: injector(),
      diagnosisCommitter: committer(),
      diagnosis: const DiagnosisCapabilityImpl(),
      genUi: const GenUiParser(),
    ),
  );
}

Future<List<ChatMessage>> _capture({required String? chapterFullText}) async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  try {
    final sessionRepo = SessionRepository(db);
    final sessionId = await sessionRepo.createBlankSession();
    final llm = _CaptureLlmClient();
    final service = _buildChatService(db, llm);
    await service.sendMessage(
      sessionId,
      _kUserContent,
      SendMessageCallbacks(
        onStream: (_) {},
        onComplete: (_, _) {},
        onError: (_) {},
      ),
      SendMessageOptions(
        phase: TeachingPhase.p0Engage,
        attitude: AttitudeLevel.yuesheng,
        chapterFullText: chapterFullText,
      ),
    );
    return llm.captured;
  } finally {
    await db.close();
  }
}

void main() {
  group('发布门槛 M1：预算覆盖完整性（known-fail 基线，待 S4 转绿）', () {
    test(
      '闸门后追加的整章正文也须计入上限（超 maxBudget 必被裁剪）',
      skip:
          'known-fail M1: TokenBudgetGuard.apply 仅在装配中段执行，'
          '其后的「## 待诊断全文」/协议后缀/全貌块/fading 块/附件不过第二道预算'
          '（批 1 E2 四路印证）。治理批次 S4 落地后移除本 skip 转绿。',
      () async {
        final messages = await _capture(chapterFullText: _kHugeChapterFullText);
        var total = 0;
        for (final m in messages) {
          total += TokenBudgetGuard.estimate(m.content);
        }
        expect(
          total,
          lessThanOrEqualTo(TokenEstimate.maxBudget),
          reason:
              '闸门后追加的内容把总估算推到 $total > maxBudget='
              '${TokenEstimate.maxBudget} 且无人裁剪（= M1 现状缺陷）。\n'
              'S4 修复后此断言应成立：追加链末尾的闸门会裁掉可降级阶段。',
        );
      },
    );
  });
}
