// ─────────────────────────────────────────────────────────────
// 批次54：会话级 teaching state 缓存测试
//
// 覆盖：
//   #1 读写 + 失效（纯函数）
//   #2 commitDiagnosis 落库后缓存失效（集成：诊断写入 → 缓存清空）
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/services/teaching_state_cache.dart';
import 'package:writingcoach/types/teaching_types.dart';

void main() {
  group('批次54 teaching state 缓存', () {
    test('#1 读写 + 失效（纯函数）', () {
      invalidateTeachingStates('s1');
      expect(readCachedTeachingStates('s1'), isNull);

      writeCachedTeachingStates('s1', {'P001': TeachingState.identified});
      expect(readCachedTeachingStates('s1'), {
        'P001': TeachingState.identified,
      });

      invalidateTeachingStates('s1');
      expect(readCachedTeachingStates('s1'), isNull);
    });

    test('#2 commitDiagnosis 落库后缓存失效（防读到旧画像）', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      final sessionId = await SessionRepository(db).createBlankSession();
      writeCachedTeachingStates(sessionId, {'S001': TeachingState.identified});
      expect(readCachedTeachingStates(sessionId), isNotNull);

      await DiagnosisRepository(db).commitDiagnosis(
        DiagnosisInput(
          sessionId: sessionId,
          messageId: 'm1',
          syndromes: [
            {'syndrome_id': 'S001', 'name': '情绪标签化', 'severity': 'L2'},
          ],
          suggestedActions: const [],
          confidence: 0.8,
        ),
      );

      expect(
        readCachedTeachingStates(sessionId),
        isNull,
        reason: '新诊断落库后缓存应被失效，保证 DiagnosisCard 重建读到最新画像',
      );
    });
  });
}
