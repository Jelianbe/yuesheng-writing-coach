// ─────────────────────────────────────────────────────────────
// student_model_style_fingerprint_test — 批次64 B62f 定量指纹存储
//
// 覆盖：
//   1. updateStyleFingerprint → getStyleFingerprint 往返
//   2. 未存储 → null
//   3. student_model 含 style_fingerprint 列（v15）
//   4. 非法 JSON → null（不抛出）
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/data/repositories/student_model_repository.dart';
import 'package:writingcoach/services/style_fingerprint.dart';

StyleFingerprint _sample() {
  return StyleFingerprint(
    avgSentenceLength: 15.3,
    sentenceLengthVariance: 8.4,
    shortParaRatio: 0.4,
    mediumParaRatio: 0.4,
    longParaRatio: 0.2,
    dialogueRatio: 0.25,
    narrativeRatio: 0.75,
    simpleSentenceRatio: 0.6,
    metaphorDensity: 1.2,
    rhetoricalQuestionDensity: 0.3,
    ellipsisDensity: 2.0,
    exclamationDensity: 0.8,
    topWords: const {'他说': 12, '她看': 9, '风雪': 6},
    sentencesCount: 24,
  );
}

void main() {
  late AppDatabase db;
  late SessionRepository sessionRepo;
  late String sessionId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sessionRepo = SessionRepository(db);
    sessionId = await sessionRepo.createBlankSession();
  });

  tearDown(() async => db.close());

  test('#1 update → get 往返一致', () async {
    final repo = StudentModelRepository(db);
    final fp = _sample();

    await repo.updateStyleFingerprint(sessionId, fp);

    final restored = await repo.getStyleFingerprint(sessionId);
    expect(restored, isNotNull);
    expect(restored!.avgSentenceLength, fp.avgSentenceLength);
    expect(restored.sentenceLengthVariance, fp.sentenceLengthVariance);
    expect(restored.dialogueRatio, fp.dialogueRatio);
    expect(restored.topWords, fp.topWords);
    expect(restored.sentencesCount, fp.sentencesCount);
  });

  test('#2 未存储 → null', () async {
    final repo = StudentModelRepository(db);
    expect(await repo.getStyleFingerprint(sessionId), isNull);
  });

  test('#3 student_model 含 style_fingerprint 列（v15）', () async {
    final cols = await db
        .customSelect('PRAGMA table_info(student_model)')
        .get();
    final names = cols.map((r) => r.read<String>('name')).toSet();
    expect(names.contains('style_fingerprint'), true);
  });

  test('#4 非法 JSON → null（不抛出）', () async {
    // 先正常写入建行，再覆盖为非法 JSON
    final repo = StudentModelRepository(db);
    await repo.updateStyleFingerprint(sessionId, _sample());
    await db.customStatement(
      'UPDATE student_model SET style_fingerprint = ? WHERE session_id = ?',
      ['not-json', sessionId],
    );

    expect(await repo.getStyleFingerprint(sessionId), isNull);
  });
}
