// ─────────────────────────────────────────────────────────────
// P2-9：injectReviewSchedule（FSRS 复习调度注入段）测试
//
// 验证点：
//   1. P3 档 + 到期症候 → 注入「症候复习调度」段（含到期优先指引）
//   2. P3 档 + 全部 fresh → 不注入（P3 指引：无到期则继续当前循环）
//   3. 非 P3 档（P0）→ 不注入
// ─────────────────────────────────────────────────────────────

// ignore_for_file: prefer_initializing_formals

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/database/utils.dart' show nowSec;
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/reference_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/data/repositories/student_model_repository.dart';
import 'package:writingcoach/data/repositories/teaching_state_repository.dart';
import 'package:writingcoach/services/chat_context_builder.dart'
    show MaterialCapabilityImpl;
import 'package:writingcoach/services/diagnosis_committer.dart';
import 'package:writingcoach/services/llm_client.dart' show ChatMessage;
import 'package:writingcoach/services/message_injector.dart';
import 'package:writingcoach/types/teaching_types.dart';

void main() {
  late AppDatabase db;
  late SessionRepository sessionRepo;
  late DiagnosisRepository diagnosisRepo;
  late StudentModelRepository studentModelRepo;
  late String sessionId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sessionRepo = SessionRepository(db);
    diagnosisRepo = DiagnosisRepository(db);
    studentModelRepo = StudentModelRepository(db);
    sessionId = await sessionRepo.createBlankSession();
  });

  tearDown(() async => db.close());

  MessageInjector buildInjector() {
    return MessageInjector(
      sessionRepo: sessionRepo,
      diagnosisRepo: diagnosisRepo,
      studentModelRepo: studentModelRepo,
      referenceRepo: ReferenceRepository(db),
      chapterRepo: ChapterRepository(db),
      manuscriptRepo: ManuscriptRepository(db),
      diagnosisCommitter: DiagnosisCommitter(
        sessionRepo: sessionRepo,
        stateRepo: TeachingStateRepository(db),
        diagnosisRepo: diagnosisRepo,
        studentModelRepo: studentModelRepo,
        referenceRepo: ReferenceRepository(db),
        chapterRepo: ChapterRepository(db),
      ),
      material: const MaterialCapabilityImpl(),
    );
  }

  /// 造一个活跃症候（诊断提交）
  Future<void> seedSyndrome(String id, String name) async {
    final msgId = await sessionRepo.addMessage(sessionId, 'assistant', '诊断');
    await diagnosisRepo.commitDiagnosis(
      DiagnosisInput(
        sessionId: sessionId,
        messageId: msgId,
        syndromes: [
          {
            'syndrome_id': id,
            'name': name,
            'severity': 'L2',
            'evidence': <String>[],
            'explanation': '',
          },
        ],
        suggestedActions: const [],
        confidence: 0.8,
      ),
    );
  }

  test('#P2-9-1 P3 档 + 到期症候 → 注入复习调度段', () async {
    await seedSyndrome('P003', '目标模糊');
    // 连续通过 5 次（间隔 14 天），最后训练 20 天前 → due
    for (var i = 0; i < 5; i++) {
      await studentModelRepo.appendTeachingHistory(sessionId, {
        'type': 'training',
        'syndromeId': 'P003',
        'result': 'passed',
        'timestamp': nowSec() - 20 * 86400,
      });
    }
    // 再补一条「最近」的记录用于 daysSince——直接取 20 天前即可（上面已是）
    final injector = buildInjector();
    final messages = <ChatMessage>[];
    await injector.injectReviewSchedule(
      sessionId: sessionId,
      phase: TeachingPhase.p3Training,
      messages: messages,
      markStage: (_) {},
    );

    expect(messages, isNotEmpty);
    final content = messages.map((m) => m.content).join('\n');
    expect(content, contains('症候复习调度'));
    expect(content, contains('到期需复习'));
    expect(content, contains('P003'));
  });

  test('#P2-9-2 P3 档 + 全部 fresh → 不注入', () async {
    await seedSyndrome('P007', '叙述视角');
    // 连续通过 2 次（间隔 2 天），最后训练 0 天前 → fresh
    for (var i = 0; i < 2; i++) {
      await studentModelRepo.appendTeachingHistory(sessionId, {
        'type': 'training',
        'syndromeId': 'P007',
        'result': 'passed',
        'timestamp': nowSec(),
      });
    }
    final injector = buildInjector();
    final messages = <ChatMessage>[];
    await injector.injectReviewSchedule(
      sessionId: sessionId,
      phase: TeachingPhase.p3Training,
      messages: messages,
      markStage: (_) {},
    );

    expect(messages, isEmpty);
  });

  test('#P2-9-3 非 P3 档（P0）→ 不注入', () async {
    await seedSyndrome('P003', '目标模糊');
    for (var i = 0; i < 5; i++) {
      await studentModelRepo.appendTeachingHistory(sessionId, {
        'type': 'training',
        'syndromeId': 'P003',
        'result': 'passed',
        'timestamp': nowSec() - 20 * 86400,
      });
    }
    final injector = buildInjector();
    final messages = <ChatMessage>[];
    await injector.injectReviewSchedule(
      sessionId: sessionId,
      phase: TeachingPhase.p0Engage,
      messages: messages,
      markStage: (_) {},
    );

    expect(messages, isEmpty);
  });
}
