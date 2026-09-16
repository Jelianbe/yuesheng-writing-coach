// ─────────────────────────────────────────────────────────────
// fact_protocol_reject_test — 拒绝记忆协议注入单元测试
//
// 批次：2026-09-16 设定资料库第一批
// 覆盖：buildFactProtocolContext 的拒绝清单段（源头抑制）
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/database/utils.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/reference_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/data/repositories/student_model_repository.dart';
import 'package:writingcoach/data/repositories/teaching_state_repository.dart';
import 'package:writingcoach/services/diagnosis_committer.dart';

void main() {
  late AppDatabase db;
  late SessionRepository sessionRepo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sessionRepo = SessionRepository(db);
    await sessionRepo.createBlankSession();
  });

  tearDown(() async => db.close());

  DiagnosisCommitter buildCommitter() {
    return DiagnosisCommitter(
      sessionRepo: sessionRepo,
      stateRepo: TeachingStateRepository(db),
      diagnosisRepo: DiagnosisRepository(db),
      studentModelRepo: StudentModelRepository(db),
      referenceRepo: ReferenceRepository(db),
      chapterRepo: ChapterRepository(db),
    );
  }

  test('#R1 空拒绝清单 → 不注入拒绝记忆段', () {
    final ctx = buildCommitter().buildFactProtocolContext();
    expect(ctx.contains('拒绝记忆'), isFalse, reason: '无拒绝记录时不得出现空段');
    expect(ctx.contains('[YS_FACT]'), isTrue, reason: '协议主体必须保持');
  });

  test('#R2 含拒绝清单 → 注入 (实体·属性=值) 三元组', () {
    final ctx = buildCommitter().buildFactProtocolContext(const [
      RejectedFact(entity: '阿禾', attribute: '职业', value: '郎中'),
      RejectedFact(entity: '大梁', attribute: '政体', value: '分封制'),
    ]);

    expect(ctx.contains('拒绝记忆'), isTrue);
    expect(ctx.contains('阿禾 · 职业 = 郎中'), isTrue);
    expect(ctx.contains('大梁 · 政体 = 分封制'), isTrue);
    expect(ctx.contains('不得再次作为新事实提议'), isTrue);
  });

  test('#R3 默认参数调用兼容（无参调用不破坏既有路径）', () {
    final ctx = buildCommitter().buildFactProtocolContext();
    expect(ctx.contains('[YS_FACT]'), isTrue);
  });
}
