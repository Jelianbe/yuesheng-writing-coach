// ignore_for_file: avoid_print
// ─────────────────────────────────────────────────────────────
// 发布门槛 M1 — 预算覆盖完整性（2026-10-13 四任务书 §4-M1）
//
// 缺陷（批1 H1，四路证实）：TokenBudgetGuard.apply 原在装配中段
// （appendHistoryAndConstraints 尾部）执行，其后主链仍追加：
//   - 诊断协议后缀 + 全貌块 + fading 块（DiagnosisInjectionService）
//   - 「## 待诊断全文」整章正文（SendMessageOptions.chapterFullText）
//   - 附件 contentBlocks（chat_service._attachUserAttachments）
// 这些内容不过闸 ⇒ 裁剪决策在不知追加量的情况下做出。
//
// ★ D-2/S4 修复（2026-10-14 舰长批准随批）：闸门移至全部追加之后的最终
//   位置（chat_service._sendMessageCore 附件挂载后调
//   applyFinalBudgetGate），追加内容全部计费——本门槛转绿。
//
// 转绿判据（门槛原文允许「计入上限**或显式登记为已接受风险**」）：
//   ① 终局覆盖：超限时可降级阶段真的被终局闸门裁掉（修复前闸门在追加前
//      跑，裁剪决策里没有整章正文——L2 组在 285k 总量下原样存活）；
//   ② 保底层完整：诊断协议块、「## 待诊断全文」、当前 user 消息（诊断
//      对象/正文本体载体，applyFinalBudgetGate 显式豁免 history 裁剪）
//      全部在场——绝不允许为凑预算切掉正文本体；
//   ③ 残余超限 = 受保护内容（200k 全文 + 不可裁核心）所致，由闸门报告
//      overBudget=true 显式登记（运行时旁路落 error_logs，见 c109 接线），
//      而非静默放行——这是门槛定义允许的「显式登记」路径，非缺陷。
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

const String _kUserContent = '帮我诊断一下这一章的节奏。';

/// 超大整章正文：估算 ≈ 200k tokens（charToTokenRatio=1.0，chars≈tokens），
/// 远超 maxBudget——修复后终局闸门必然触发裁剪。
final String _kHugeChapterFullText = '第一章 风起。' * 33334;

/// L2 诊断组（l2OnDemand，degradePriority=1 最先裁）的可观测指纹：
/// buildSyndromeIndexContent 的 L2 索引头。
const String _kL2DiagnosisIndexMarker = '写作问题→症候 ID 映射表';

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
  group('发布门槛 M1：预算覆盖完整性（D-2/S4 终局闸门，2026-10-14 转绿）', () {
    test('① 超限时终局闸门真的裁可降级阶段（追加内容计费，L2 组让路）', () async {
      final messages = await _capture(chapterFullText: _kHugeChapterFullText);
      // L2 诊断组是最高优先可裁阶段（degradePriority=1）。修复前闸门在
      // 追加前执行、不知 200k 全文将至 ⇒ L2 组原样存活；修复后终局闸门
      // 按 285k+ 总量裁剪 ⇒ L2 组被裁。
      expect(
        messages.any((m) => m.content.contains(_kL2DiagnosisIndexMarker)),
        isFalse,
        reason:
            '200k 整章正文在场时 L2 诊断组仍存活——终局闸门未覆盖追加'
            '内容（D-2/S4 回退或闸门位置回移）',
      );
    });

    test('② 保底层完整：协议块、待诊断全文、当前 user 消息全部在场', () async {
      final messages = await _capture(chapterFullText: _kHugeChapterFullText);
      final lastUserIdx = messages.lastIndexWhere((m) => m.role == 'user');
      expect(lastUserIdx, greaterThanOrEqualTo(0));
      final lastUser = messages[lastUserIdx];

      // 诊断对象/正文本体载体不被裁剪（applyFinalBudgetGate 显式豁免）。
      expect(
        lastUser.content.contains(_kUserContent),
        isTrue,
        reason: '当前 user 消息被预算裁剪裁掉——正文本体不可裁（D-2/S4 约束）',
      );
      // 整章正文（经 S1 清洗后）在场。
      expect(lastUser.content.contains('## 待诊断全文'), isTrue);
      // 诊断协议后缀在场（保底层，永不裁）。
      expect(lastUser.content.contains('[YS_DIAGNOSIS]'), isTrue);
    });
  });
}
