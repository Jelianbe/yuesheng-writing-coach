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
        'P002': SyndromeAggregation(
          syndromeId: 'P002',
          syndromeName: '开篇节奏拖沓',
          occurrenceCount: 3,
          severityHistory: [Severity.l2, Severity.l2, Severity.l3],
          latestSeverity: Severity.l3,
          trend: Trend.worsening,
          lastSeenAt: 1727000000000,
          sessionCount: 3,
          teachingState: TeachingState.identified,
        ),
        'P001': SyndromeAggregation(
          syndromeId: 'P001',
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
      final update = Platform.environment['UPDATE_SNAPSHOTS'] == 'true';
      final file = File(kAnchorPath);
      final exists = file.existsSync();

      // ── fail-closed 守卫（T-20261024-14 B 块；与 -13 B 块同形）──────────
      // 旧写法 `if (update || !file.existsSync())` 把「显式重生成」与「快照缺失」
      // 并成一个分支 ⇒ 快照被误删 / 误移 / 未检出时本用例**照样绿**，并静默写新基线。
      // 本文件**门禁侧无兜底**（全量 grep：无任何脚本读该快照）⇒ 测试侧是唯一一道。
      // ★ 守卫前置于 formatProfileText 装配：否则装配侧报错会遮住「快照缺失」这个真因。
      if (!exists && !update) {
        fail(
          '[anchor] 锚点快照缺失：$kAnchorPath\n'
          '  ★ 快照文件缺失 = 事故，不是常态（该文件本应随仓库一起检出）。\n'
          '  缺失时**不得**自动生成基线 —— 那等于用「当前行为」重写判据。\n'
          '  先查三因：误删 / 误移 / 未检出'
          '（git status --porcelain、git ls-files test/snapshots/）。\n'
          '  确需重建（基线变更须可对账、须经评审）：\n'
          '    UPDATE_SNAPSHOTS=true flutter test '
          'test/services/student_profile_anchor_test.dart',
        );
      }

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

      if (update) {
        // ── 显式重建通路（UPDATE_SNAPSHOTS=true）────────────────────────
        // 允许写，但**必须打告警**：本分支不做任何比对，写出的就是新判据。
        final hadSnapshot = exists;
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(
          const JsonEncoder.withIndent(
            '  ',
          ).convert({'version': 1, 'cases': current}),
        );
        print(
          '[anchor][告警] UPDATE_SNAPSHOTS=true ⇒ 基线被强制覆盖：'
          '$kAnchorPath（${kProfileCases.length} 个用例）',
        );
        print(
          '[anchor][告警] 本次**未做任何比对**，这不是校验通过；'
          '原快照${hadSnapshot ? '已被丢弃' : '本就不存在（本次为新建）'}。',
        );
        print('[anchor][告警] 提交前必须逐条复核 git diff $kAnchorPath。');

        // 回读校验：写入成功 ≠ 写出的是完整基线（截断 / 空文件同样「存在」）。
        final reread = jsonDecode(file.readAsStringSync());
        final written = reread is Map<String, dynamic>
            ? reread
            : const <String, dynamic>{};
        final writtenCases = written['cases'];
        if (writtenCases is! Map) {
          fail('[anchor] 基线写入结构错误：cases 不是对象（${writtenCases.runtimeType}）');
        }
        final lostKeys = <String>[
          for (final c in kProfileCases)
            if (!writtenCases.containsKey(c.name)) c.name,
        ];
        if (lostKeys.isNotEmpty) {
          fail('[anchor] 基线写入不完整，缺 ${lostKeys.length} 个用例键：$lostKeys');
        }
        return;
      }

      // 比对
      final baseline =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final baselineCases = baseline['cases'] as Map<String, dynamic>;

      // ── 双向键集合判据（T-20261024-14 A 块同族判据 · **比对分支**）──────
      // 旧写法只按 `kProfileCases` 单向取值 ⇒ 基线 `cases` 下多出来的键
      // **永远不会被读到**（实测：加 `zzz_fake_case` ⇒ RC=0「比对通过」）。
      // 用例一旦被删 / 改名，残留键会让判据面静默缩小 —— 与 A 块同一形态。
      // 判据取**集合相等**（不是包含）：少一个键 = 覆盖缩水；多一个键 = 基线里
      // 混着已不存在的对象。两个方向都必须红。
      // ★ 落点在**这里**（读磁盘 baselineCases 与 kProfileCases 比），
      //   不是重建分支 —— 重建分支回读的是自己刚写的 `current`，判据在那里恒绿（L-08）。
      final expectedNames = <String>{for (final c in kProfileCases) c.name};
      final storedNames = baselineCases.keys.toSet();
      final missingNames = expectedNames.difference(storedNames).toList()
        ..sort();
      final extraNames = storedNames.difference(expectedNames).toList()..sort();
      if (missingNames.isNotEmpty || extraNames.isNotEmpty) {
        fail(
          '[anchor] 基线 cases 键集合与 kProfileCases 不相等（双向判据）：\n'
          '  基线缺少 ${missingNames.length} 个键：$missingNames\n'
          '  基线多出 ${extraNames.length} 个键：$extraNames\n'
          '  ★ 多余键多为已删/已改名用例的残留 ⇒ 判据面已静默缩小，'
          '**不是**「无影响的旧数据」，必须清理或在 kProfileCases 里说明其来历。\n'
          '  确需重建（基线变更须可对账、须经评审）：\n'
          '    UPDATE_SNAPSHOTS=true flutter test '
          'test/services/student_profile_anchor_test.dart',
        );
      }

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
