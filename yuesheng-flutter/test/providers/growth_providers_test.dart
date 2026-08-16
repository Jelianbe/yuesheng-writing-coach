import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/providers/growth_providers.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() {
    container.dispose();
    db.close();
  });

  group('GrowthStore', () {
    test('初始状态: isLoading=true, profile=null', () {
      final state = container.read(growthStoreProvider);
      expect(state.isLoading, true);
      expect(state.profile, isNull);
      expect(state.activeProblems, isEmpty);
      expect(state.diagnosisHistory, isEmpty);
    });

    test(
      'loadGrowthData: 空 DB → profile.proficiency=beginner, activeProblems 空',
      () async {
        await container.read(growthStoreProvider.notifier).loadGrowthData();

        final state = container.read(growthStoreProvider);
        expect(state.isLoading, false);
        expect(state.profile, isNotNull);
        expect(state.profile!.proficiency.value, 'beginner');
        expect(state.activeProblems, isEmpty);
      },
    );

    test('loadGrowthData: 有诊断 → activeProblems 非空', () async {
      // 准备数据
      final sessionRepo = SessionRepository(db);
      final diagRepo = DiagnosisRepository(db);
      final sid = await sessionRepo.createBlankSession();
      await diagRepo.commitDiagnosis(
        DiagnosisInput(
          sessionId: sid,
          messageId: 'msg-1',
          syndromes: [
            {'syndrome_id': 'S001', 'name': '视角跳跃', 'severity': 'L2'},
          ],
          suggestedActions: [],
          confidence: 0.8,
        ),
      );

      await container.read(growthStoreProvider.notifier).loadGrowthData();

      final state = container.read(growthStoreProvider);
      expect(state.activeProblems.length, 1);
      expect(state.activeProblems.first.syndromeId, 'S001');
      expect(state.diagnosisHistory.length, 1);
    });

    test('loadGrowthData: 多次诊断 → diagnosisHistory 按 timestamp DESC', () async {
      final sessionRepo = SessionRepository(db);
      final diagRepo = DiagnosisRepository(db);
      final sid = await sessionRepo.createBlankSession();

      // 第一条诊断(旧)
      await diagRepo.commitDiagnosis(
        DiagnosisInput(
          sessionId: sid,
          messageId: 'msg-1',
          syndromes: [
            {'syndrome_id': 'S001', 'name': 'A', 'severity': 'L1'},
          ],
          suggestedActions: [],
          confidence: 0.7,
        ),
      );
      await Future.delayed(const Duration(seconds: 1));
      // 第二条诊断(新)
      await diagRepo.commitDiagnosis(
        DiagnosisInput(
          sessionId: sid,
          messageId: 'msg-2',
          syndromes: [
            {'syndrome_id': 'S002', 'name': 'B', 'severity': 'L2'},
          ],
          suggestedActions: [],
          confidence: 0.8,
        ),
      );

      await container.read(growthStoreProvider.notifier).loadGrowthData();

      final state = container.read(growthStoreProvider);
      expect(state.diagnosisHistory.length, 2);
      // 新的在前
      expect(state.diagnosisHistory.first.messageId, 'msg-2');
    });
  });
}
