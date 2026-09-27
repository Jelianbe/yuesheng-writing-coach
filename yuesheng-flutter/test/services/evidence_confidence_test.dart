import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/services/evidence_confidence.dart';

void main() {
  group('computeEvidenceConfidence — 证据强度分量', () {
    test('无证据 → 0.0（弱，必待确认）', () {
      expect(
        computeEvidenceConfidence(evidence: const [], recurrenceOccurrences: 0),
        0.0,
      );
    });

    test('单条短证据（<6字）→ 0.35（弱）', () {
      expect(
        computeEvidenceConfidence(
          evidence: const ['卡顿'],
          recurrenceOccurrences: 0,
        ),
        0.35,
      );
    });

    test('单条具体证据（>=6字）→ 0.55（非弱）', () {
      expect(
        computeEvidenceConfidence(
          evidence: const ['这一段读起来节奏忽快忽慢'],
          recurrenceOccurrences: 0,
        ),
        0.55,
      );
    });

    test('两条证据 → 0.65', () {
      expect(
        computeEvidenceConfidence(
          evidence: const ['第一处证据原文片段', '第二处证据原文片段'],
          recurrenceOccurrences: 0,
        ),
        0.65,
      );
    });

    test('三条证据 → 0.70（每多一条 +0.05）', () {
      expect(
        computeEvidenceConfidence(
          evidence: const ['证据一具体原文', '证据二具体原文', '证据三具体原文'],
          recurrenceOccurrences: 0,
        ),
        0.70,
      );
    });

    test('证据强度封顶 0.8', () {
      // 8 条 → 0.65 + 0.05*6 = 0.95 → clamp 0.8
      expect(
        computeEvidenceConfidence(
          evidence: List.filled(8, '具体原文证据片段足够长'),
          recurrenceOccurrences: 0,
        ),
        0.8,
      );
    });
  });

  group('computeEvidenceConfidence — 复现加成', () {
    test('出现 >=2 次 → +0.15', () {
      expect(
        computeEvidenceConfidence(
          evidence: const ['一条具体证据原文'],
          recurrenceOccurrences: 2,
        ),
        0.70, // 0.55 + 0.15
      );
    });

    test('出现 >=4 次 → +0.20', () {
      expect(
        computeEvidenceConfidence(
          evidence: const ['一条具体证据原文'],
          recurrenceOccurrences: 4,
        ),
        0.75, // 0.55 + 0.20
      );
    });

    test('出现 1 次不加成', () {
      expect(
        computeEvidenceConfidence(
          evidence: const ['一条具体证据原文'],
          recurrenceOccurrences: 1,
        ),
        0.55,
      );
    });

    test('综合 clamp 上限 1.0', () {
      expect(
        computeEvidenceConfidence(
          evidence: List.filled(8, '具体原文证据片段足够长'),
          recurrenceOccurrences: 4,
        ),
        1.0, // 0.8 + 0.2
      );
    });
  });

  group('isWeakEvidence', () {
    test('低于阈值 → 弱', () {
      expect(isWeakEvidence(0.0), isTrue);
      expect(isWeakEvidence(0.35), isTrue);
      expect(isWeakEvidence(0.39), isTrue);
    });

    test('达到阈值及以上 → 非弱', () {
      expect(isWeakEvidence(0.4), isFalse);
      expect(isWeakEvidence(0.55), isFalse);
      expect(isWeakEvidence(0.65), isFalse);
    });
  });
}
