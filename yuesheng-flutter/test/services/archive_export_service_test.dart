// ─────────────────────────────────────────────────────────────
// T-09 教学档案导出：单元测试
//
// 覆盖路径：
//   buildArchiveJson:
//     #1 空数据（无画像 + 无诊断）→ 有效 JSON 含 meta + 空 profile + 空 diagnoses
//     #2 有画像无诊断 → profile 字段正确填充
//     #3 有诊断无画像 → diagnoses 字段正确填充
//     #4 完整数据 → 所有字段正确填充
//   #5 非法 JSON 字符串 → 防御性降级为空值，不抛出
//   #6 archiveExportFileName → 安全文件名生成
// ─────────────────────────────────────────────────────────────

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/archive_export_service.dart';

void main() {
  group('T-09 buildArchiveJson', () {
    test('#1 空数据（无画像 + 无诊断）→ 有效 JSON 含 meta + 空 profile + 空 diagnoses', () {
      final input = const ArchiveExportInput();
      final json = buildArchiveJson(input, exportedAt: 1700000000);

      final decoded = jsonDecode(json) as Map<String, dynamic>;
      expect(decoded['meta'], isNotNull);
      expect((decoded['meta'] as Map)['version'], '1.0');
      expect((decoded['meta'] as Map)['exportedAt'], 1700000000);
      expect((decoded['meta'] as Map)['app'], 'yuesheng-writing-coach');

      final profile = decoded['profile'] as Map<String, dynamic>;
      expect(profile['teachingHistory'], isEmpty);
      expect(profile['onboardingData'], isEmpty);
      expect(profile['styleProfile'], isEmpty);
      expect(profile['styleFingerprint'], isEmpty);

      expect(decoded['diagnoses'], isEmpty);
    });

    test('#2 有画像无诊断 → profile 字段正确填充', () {
      final input = ArchiveExportInput(
        teachingHistoryJson: jsonEncode([
          {'type': 'diagnosis', 'timestamp': 1699000000}
        ]),
        onboardingDataJson: jsonEncode({'level': 'beginner', 'goal': 'novel'}),
        styleProfileJson: jsonEncode({'narrative': 3.5, 'dialogue': 4.0}),
        styleFingerprintJson: jsonEncode({'avgSentenceLen': 12.5}),
      );
      final json = buildArchiveJson(input, exportedAt: 1700000000);

      final decoded = jsonDecode(json) as Map<String, dynamic>;
      final profile = decoded['profile'] as Map<String, dynamic>;

      final history = profile['teachingHistory'] as List;
      expect(history.length, 1);
      expect((history[0] as Map)['type'], 'diagnosis');

      final onboarding = profile['onboardingData'] as Map<String, dynamic>;
      expect(onboarding['level'], 'beginner');

      final style = profile['styleProfile'] as Map<String, dynamic>;
      expect(style['narrative'], 3.5);

      final fingerprint = profile['styleFingerprint'] as Map<String, dynamic>;
      expect(fingerprint['avgSentenceLen'], 12.5);

      expect(decoded['diagnoses'], isEmpty);
    });

    test('#3 有诊断无画像 → diagnoses 字段正确填充', () {
      final diagnoses = [
        DiagnosisExportEntry(
          id: 'd1',
          sessionId: 's1',
          timestamp: 1699000000,
          syndromesJson: jsonEncode([
            {'syndrome_id': 'P003', 'name': '情绪标签化', 'severity': 'L2'}
          ]),
          suggestedActionsJson: jsonEncode(['rewrite', 'explain']),
          feedbackSummary: '情绪描写偏抽象',
          rootCauseAnalysis: '依赖形容词而非场景',
          confidence: 0.85,
        ),
      ];
      final input = ArchiveExportInput(diagnoses: diagnoses);
      final json = buildArchiveJson(input, exportedAt: 1700000000);

      final decoded = jsonDecode(json) as Map<String, dynamic>;
      final dxList = decoded['diagnoses'] as List;
      expect(dxList.length, 1);

      final dx = dxList[0] as Map<String, dynamic>;
      expect(dx['id'], 'd1');
      expect(dx['sessionId'], 's1');
      expect(dx['timestamp'], 1699000000);
      expect(dx['confidence'], 0.85);
      expect(dx['feedbackSummary'], '情绪描写偏抽象');

      final syndromes = dx['syndromes'] as List;
      expect(syndromes.length, 1);
      expect((syndromes[0] as Map)['syndrome_id'], 'P003');

      final actions = dx['suggestedActions'] as List;
      expect(actions.length, 2);
      expect(actions[0], 'rewrite');
    });

    test('#4 完整数据（画像 + 诊断）→ 所有字段正确填充', () {
      final input = ArchiveExportInput(
        teachingHistoryJson: jsonEncode([
          {'type': 'diagnosis'},
          {'type': 'training'}
        ]),
        onboardingDataJson: jsonEncode({'level': 'intermediate'}),
        styleProfileJson: jsonEncode({'narrative': 4.0}),
        styleFingerprintJson: jsonEncode({'avgSentenceLen': 15.0}),
        diagnoses: [
          DiagnosisExportEntry(
            id: 'd1',
            sessionId: 's1',
            timestamp: 1699000000,
            syndromesJson: jsonEncode([{'syndrome_id': 'P005'}]),
            suggestedActionsJson: jsonEncode(['rewrite']),
            confidence: 0.9,
          ),
          DiagnosisExportEntry(
            id: 'd2',
            sessionId: 's1',
            timestamp: 1699001000,
            syndromesJson: jsonEncode([{'syndrome_id': 'P008'}]),
            suggestedActionsJson: jsonEncode(['explain']),
            confidence: 0.75,
            feedbackSummary: '语言堆砌',
          ),
        ],
      );
      final json = buildArchiveJson(input, exportedAt: 1700000000);

      final decoded = jsonDecode(json) as Map<String, dynamic>;

      // 画像填充
      final profile = decoded['profile'] as Map<String, dynamic>;
      expect((profile['teachingHistory'] as List).length, 2);
      expect((profile['onboardingData'] as Map)['level'], 'intermediate');

      // 诊断填充（2 条，时间升序）
      final dxList = decoded['diagnoses'] as List;
      expect(dxList.length, 2);
      expect((dxList[0] as Map)['id'], 'd1');
      expect((dxList[1] as Map)['id'], 'd2');
      expect((dxList[0] as Map)['timestamp'], lessThan((dxList[1] as Map)['timestamp']));
    });

    test('#5 非法 JSON 字符串 → 防御性降级为空值，不抛出', () {
      final input = ArchiveExportInput(
        teachingHistoryJson: 'not-json{{{',
        onboardingDataJson: '',
        styleProfileJson: 'null',
        styleFingerprintJson: null,
      );
      final json = buildArchiveJson(input, exportedAt: 1700000000);

      final decoded = jsonDecode(json) as Map<String, dynamic>;
      final profile = decoded['profile'] as Map<String, dynamic>;
      expect(profile['teachingHistory'], isEmpty);
      expect(profile['onboardingData'], isEmpty);
      expect(profile['styleProfile'], isEmpty);
      expect(profile['styleFingerprint'], isEmpty);
    });
  });

  group('T-09 archiveExportFileName', () {
    test('#6 文件名含「教学档案」前缀 + 日期 + .json 后缀', () {
      final name = archiveExportFileName();
      expect(name, startsWith('教学档案-'));
      expect(name, endsWith('.json'));
      expect(name.length, greaterThan(15));
    });

    test('#6b 带会话标签时含标签', () {
      final name = archiveExportFileName(sessionLabel: '第一本书');
      expect(name, contains('第一本书'));
      expect(name, endsWith('.json'));
    });

    test('#6c 非法字符被过滤', () {
      final name = archiveExportFileName(sessionLabel: 'a/b:c?d');
      expect(name, isNot(contains('/')));
      expect(name, isNot(contains(':')));
      expect(name, isNot(contains('?')));
    });
  });
}
