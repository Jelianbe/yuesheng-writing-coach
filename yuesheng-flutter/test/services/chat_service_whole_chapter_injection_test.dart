// ignore_for_file: avoid_print
// ─────────────────────────────────────────────────────────────
// chat_service 按需介入块注入测试（ADR-C137 批2；覆盖 ADR §6 验收 3）
//
// 覆盖：
//   ① 完整章模式激活（wholeChapterModeActive=true）→ 消息序列末尾注入
//      「按需介入」system 块（内容 == kWholeChapterMinimalSupportBlock，且为末条）；
//   ② 非完整章路径（flag=false）→ 块缺席，序列与既有锚点逐字节一致（零漂移）；
//   ③ R-009 形态审计：块文案零代写/零打分/零处方措辞。
//
// 复用 message_sequence_anchor_test 的边界捕获 harness（_CaptureLlmClient
// 截获发给 LLM 的全部 messages）。本文件不起新锚点，只断言块的存在/缺席与形态。
// ─────────────────────────────────────────────────────────────

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:writingcoach/types/teaching_types.dart';

const String _kContent = '他推开门，风灌了进来，桌上的信纸被吹落在地。';

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
    studentModelRepo: StudentModelRepository(db),
    referenceRepo: ReferenceRepository(db),
    chapterRepo: ChapterRepository(db),
    manuscriptRepo: ManuscriptRepository(db),
    llmClient: llmClient,
    teacherSuggestionRepo: TeacherSuggestionRepository(db),
    diagnosisCommitter: committer(),
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

Future<List<ChatMessage>> _capture({required bool wholeChapterActive}) async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  try {
    final sessionRepo = SessionRepository(db);
    final sessionId = await sessionRepo.createBlankSession();
    final llm = _CaptureLlmClient();
    final service = _buildChatService(db, llm);
    await service.sendMessage(
      sessionId,
      _kContent,
      SendMessageCallbacks(
        onStream: (_) {},
        onComplete: (_, _) {},
        onError: (_) {},
      ),
      SendMessageOptions(
        phase: TeachingPhase.p0Engage,
        attitude: AttitudeLevel.yuesheng,
        wholeChapterModeActive: wholeChapterActive,
      ),
    );
    return llm.captured;
  } finally {
    await db.close();
  }
}

void main() {
  group('按需介入块注入（ADR-C137 批2）', () {
    test('① 完整章激活 → 末尾注入「按需介入」system 块（内容逐字匹配）', () async {
      final msgs = await _capture(wholeChapterActive: true);
      final blockMsgs = msgs
          .where(
            (m) =>
                m.content == ChatServiceSend.kWholeChapterMinimalSupportBlock,
          )
          .toList();
      expect(blockMsgs, hasLength(1), reason: '完整章激活时恰好注入一块');
      // 块是末尾追加（recency：纪律重申之后、发给 LLM 的最后一条）。
      expect(
        msgs.last.content,
        ChatServiceSend.kWholeChapterMinimalSupportBlock,
      );
      expect(msgs.last.role, 'system');
      // 块内容三要素在场。
      expect(
        ChatServiceSend.kWholeChapterMinimalSupportBlock,
        contains('我在，随时叫我'),
      );
      expect(ChatServiceSend.kWholeChapterMinimalSupportBlock, contains('求助'));
      expect(
        ChatServiceSend.kWholeChapterMinimalSupportBlock,
        contains('R-009'),
      );
    });

    test('② 非完整章路径 → 块缺席，序列比激活态少一条（零漂移）', () async {
      final inactive = await _capture(wholeChapterActive: false);
      final active = await _capture(wholeChapterActive: true);

      // 非激活路径不含块。
      expect(
        inactive.where(
          (m) => m.content == ChatServiceSend.kWholeChapterMinimalSupportBlock,
        ),
        isEmpty,
        reason: '非完整章路径不注入按需块',
      );
      // 激活态恰好比非激活态多一条（末尾那块），其余前缀逐字节一致。
      expect(active.length, inactive.length + 1);
      for (var i = 0; i < inactive.length; i++) {
        expect(active[i].role, inactive[i].role);
        expect(
          active[i].content,
          inactive[i].content,
          reason: '前 ${inactive.length} 条前缀逐字节一致（锚点零漂移）',
        );
      }
    });

    test('③ R-009 形态审计：块文案零代写/零打分/零处方措辞', () {
      final block = ChatServiceSend.kWholeChapterMinimalSupportBlock;
      // 正向：边界重申在场。
      expect(block, contains('不替学员写'));
      expect(block, contains('不打分'));
      expect(block, contains('不开处方'));
      // 反向：不含代写/打分/处方形态措辞（R-009 红线）。
      for (final banned in [
        '我来帮你写',
        '替你写一段',
        '给你写好',
        '评分：',
        '得分',
        '应该改成',
        '你必须',
        '直接改',
        '范文如下',
      ]) {
        expect(
          block,
          isNot(contains(banned)),
          reason: '按需介入块不得含代写/打分/处方形态：$banned',
        );
      }
    });
  });
}
