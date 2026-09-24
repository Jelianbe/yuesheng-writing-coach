// ─────────────────────────────────────────────────────────────
// 画像段快照测试 — formatProfileText 字节级基线
//
// 目的：画像段（学员画像）是单独的 system message，不在 buildSystemPromptV2 里。
//      本测试冻结 formatProfileText 的输出（长度 + FNV-1a 指纹），
//      防止画像段改动意外影响 prompt 整体。
//
// 用法：
//   flutter test test/services/student_profile_anchor_test.dart
//   UPDATE_SNAPSHOTS=true flutter test test/services/student_profile_anchor_test.dart
// ─────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/student_profile_format.dart';
import 'package:writingcoach/types/teaching_types.dart';

const String kAnchorPath = 'test/snapshots/student_profile_anchor.json';

class ProfileCase {
  final String name;
  final StudentProfile profile;
  final OnboardingData? onboarding;

  const ProfileCase({
    required this.name,
    required this.profile,
    this.onboarding,
  });
}

// 构造测试用例
final kProfileCases = <ProfileCase>[
  // ── 用例 1：新手 + 无症候 + 无 onboarding（空画像）──
  ProfileCase(
    name: 'beginner_empty',
    profile: StudentProfile(
      proficiency: ProficiencyLevel.beginner,
      confidence: 0.3,
      syndromeProfile: {},
      totalSessions: 0,
    ),
  ),

  // ── 用例 2：新手 + 有 onboarding（填了问卷）──
  ProfileCase(
    name: 'beginner_with_onboarding',
    profile: StudentProfile(
      proficiency: ProficiencyLevel.beginner,
      confidence: 0.5,
      syndromeProfile: {},
      totalSessions: 1,
    ),
    onboarding: OnboardingData(
      proficiency: ProficiencyLevel.beginner,
      focusAreas: ['人物塑造', '情节设计'],
      cognitiveStyle: CognitiveStyle.mixed,
      writingGoal: '写网文赚钱',
      completedAt: 1727000000000,
    ),
  ),

  // ── 用例 3：进阶 + 有几个症候 ──
  ProfileCase(
    name: 'elementary_with_syndromes',
    profile: StudentProfile(
      proficiency: ProficiencyLevel.elementary,
      confidence: 0.6,
      syndromeProfile: {
        'P001': SyndromeAggregation(
          syndromeId: 'P001',
          syndromeName: '开篇节奏拖沓',
          occurrenceCount: 3,
          severityHistory: [Severity.l2, Severity.l2, Severity.l3],
          latestSeverity: Severity.l3,
          trend: Trend.worsening,
          lastSeenAt: 1727000000000,
          sessionCount: 3,
          teachingState: TeachingState.identified,
        ),
        'P003': SyndromeAggregation(
          syndromeId: 'P003',
          syndromeName: '描写冗余',
          occurrenceCount: 2,
          severityHistory: [Severity.l1, Severity.l2],
          latestSeverity: Severity.l2,
          trend: Trend.stable,
          lastSeenAt: 1727000000000,
          sessionCount: 2,
          teachingState: TeachingState.inProgress,
        ),
      },
      totalSessions: 5,
    ),
    onboarding: OnboardingData(
      proficiency: ProficiencyLevel.elementary,
      focusAreas: ['节奏把控'],
      cognitiveStyle: CognitiveStyle.mixed,
      writingGoal: '成为签约作者',
      completedAt: 1726000000000,
    ),
  ),
];

// FNV-1a 64位哈希（与 skill_prompt_anchor_test 同算法）
int _fnv1a(String s) {
  const int offset = 0xcbf29ce484222325;
  const int prime = 0x100000001b3;
  int hash = offset;
  for (final code in s.codeUnits) {
    hash ^= code;
    hash *= prime;
    hash &= 0xFFFFFFFFFFFFFFFF;
  }
  return hash;
}

void main() {
  group('画像段快照：formatProfileText 字节级不变', () {
    test('画像段输出与基线字节级一致', () {
      // 计算当前输出
      final current = <String, Map<String, dynamic>>{};
      for (final c in kProfileCases) {
        final text = formatProfileText(
          c.profile,
          null, // stagnation
          null, // effectivenessText
          c.onboarding,
          includeCognitiveStyle: false,
        );
        current[c.name] = {
          'length': text.length,
          'hash': _fnv1a(text).toRadixString(16),
        };
      }

      // 读取基线
      final update = Platform.environment['UPDATE_SNAPSHOTS'] == 'true';
      final file = File(kAnchorPath);

      if (update || !file.existsSync()) {
        // 写新基线
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
          'version': 1,
          'cases': current,
        }));
        print('[anchor] 已写入新基线：${kProfileCases.length} 个用例');
        return;
      }

      // 比对
      final baseline = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final baselineCases = baseline['cases'] as Map<String, dynamic>;

      for (final c in kProfileCases) {
        final base = baselineCases[c.name];
        if (base == null) {
          fail('基线缺失用例：${c.name}');
        }
        final cur = current[c.name]!;
        if (base['length'] != cur['length'] || base['hash'] != cur['hash']) {
          fail(
            '用例 ${c.name} 不一致：\n'
            '  基线：length=${base['length']}, hash=${base['hash']}\n'
            '  当前：length=${cur['length']}, hash=${cur['hash']}',
          );
        }
      }

      print('[anchor] 比对通过：${kProfileCases.length} 个画像用例与基线一致 ✓');
    });
  });
}
