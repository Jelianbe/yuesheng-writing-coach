// ignore_for_file: avoid_print
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

import '../helpers/anchor_content_floor.dart';

const String kAnchorPath = 'test/snapshots/student_profile_anchor.json';

// ─────────────────────────────────────────────────────────────
// 重建下限判据（T-20261024-15 · L4 支撑层）
//
// 由来：`T-20261024-14` 在重建分支只保证「**写完整**没有」（回读 `cases` 键齐，
//   见本文件下方 `lostKeys`）——**没有下限**。每例都格式化成空串同样算
//   「写完整」，于是写出的基线与「内容全空」的产物一致，此后长期绿：
//   判据在跑，比的是空对空。
//
// 口径（`DECISIONS §4-260⑤` 舰长 2026-10-24 23:31 已裁，不得改）：
//   ① 量什么 = 每例**非空** + 总数 ≥ 旧基线 **50%**（不设精确 N：精确 N 会随
//      语料反复调参，而「腰斩」是可解释的异常信号）；
//   ② 越限 = **fail**（重建出塌陷基线的代价是此后长期假绿，比一次红贵得多）。
//
// 落点只在**重建分支**：比对分支的判据面是「与基线逐字节一致」，塌陷基线在那里
//   表现为「当前 ≠ 基线」⇒ 本来就会红，不需要第二道。
// ★ 判据在**写盘之前**：失败必须**不写**，否则「红了但文件已脏」，
//   下一个人只会再跑一次 UPDATE_SNAPSHOTS 把它盖回去。
// ─────────────────────────────────────────────────────────────

/// F1 + F2：每例非空。不过即 `fail`（**不写盘**）。
///
/// F1 = 该例的核心条数 ≥ 1（本文件的核心量是 `length`，即画像文本字符数）；
/// F2 = 该例内不得出现空载体（`hash` 为空串）。
/// ★ 只查 F1 不够：「length 为 0 的一例」在 JSON 里确实是一个键、也确实
///   「非空」，塌陷照样过关 —— 这是本卡把「每例非空」拆成两层的原因。
/// ⚠️ 诚实边界：本文件的 F2 近恒绿（FNV 指纹不可能为空串），真正接住
///   「内容清空」的是 F1（`length` 归 0）与 F3（体积腰斩）。F2 留作写入
///   侧被改坏（截断 / 换了载体）时的兜底，**不构成「判据有牙」的证据**。
void _assertPerCaseNonEmpty(Map<String, Map<String, dynamic>> current) {
  final emptyCases = <String>[
    for (final e in current.entries)
      if ((e.value['length']! as int) < 1) e.key,
  ];
  final emptyLeaves = <String>[
    for (final e in current.entries)
      if ((e.value['hash']! as String).isEmpty) '${e.key}.hash',
  ];
  if (emptyCases.isEmpty && emptyLeaves.isEmpty) return;
  fail(
    '[anchor] 重建下限不过（F1 每例条数 / F2 叶值非空），**已拒绝写盘**：\n'
    '  F1 整例为空 ${emptyCases.length} 例：$emptyCases\n'
    '  F2 叶值为空 ${emptyLeaves.length} 处：$emptyLeaves\n'
    '  ★ 这多半是装配塌陷（formatProfileText 返回空串 / 用例表被清空），'
    '**不是**「画像变小了」。空壳基线一旦落盘，此后长期绿。\n'
    '  排查真因后确需重写基线：UPDATE_SNAPSHOTS=true。',
  );
}

/// 读旧基线的 `cases` 子树；返回 `null` = 无可比基线。
///
/// 三种「不可解析」一律**默认 fail**（除非显式豁免）：① 非 JSON（截断 / 手改坏）；
/// ② 顶层非对象；③ 缺 `cases` 对象。
/// ★ 为什么默认 fail：`旧快照损坏 + UPDATE_SNAPSHOTS=true` 是**洗白基线最省力的
///   入口**（比装配塌陷更容易发生）。默认放行等于把下限判据的钥匙交给
///   「先弄坏、再重冻」。
/// ★ 为什么留开关：快照真坏了还得能修 —— 否则判据变成死锁。
Map<String, dynamic>? _loadBaselineCases(File file, {required bool exists}) {
  if (!exists) return null; // 首次生成：F3 不生效（调用处打告警）
  final raw = file.readAsStringSync();
  String? why;
  Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException catch (e) {
    why = '${e.message}（偏移 ${e.offset}）';
  }
  if (why == null) {
    if (decoded is! Map<String, dynamic>) {
      why = '顶层应为 JSON 对象，实际为 ${decoded.runtimeType}';
    } else {
      final cases = decoded['cases'];
      if (cases is! Map<String, dynamic>) {
        why = '`cases` 应为 JSON 对象，实际为 ${cases.runtimeType}';
      } else {
        return cases;
      }
    }
  }
  final waived =
      (Platform.environment['ALLOW_FLOORLESS_REBUILD'] ?? '') == 'true';
  if (!waived) {
    fail(
      '[anchor] 旧基线不可解析 ⇒ 比率下限无法生效：$kAnchorPath\n'
      '  解析器原文：$why\n'
      '  两条出口：\n'
      '    ① 恢复基线：git checkout -- $kAnchorPath\n'
      '    ② 确认要丢弃旧基线：ALLOW_FLOORLESS_REBUILD=true'
      '（会打双重告警，且本次不设任何下限）',
    );
  }
  print(
    '[anchor][告警] 已放弃比率下限：旧基线不可解析（$why）'
    '⇒ 本次未做任何比对，这不是校验通过。',
  );
  print('[anchor][告警] 路径：$kAnchorPath；本次为「无下限重建」，须人工复核体量。');
  return null;
}

/// F3：总数（**内容体积（单调代理）**）≥ 旧基线 50%。不过即 `fail`（**不写盘**）。
///
/// 口径见 `test/helpers/anchor_content_floor.dart`：叶字符串长度 + 仅 `len` /
/// `length` 键的整数值；其余整数单列 `nonContentInt`，**不计体积**。
/// ⚠️ 该指标**不得当作字节数 / token 成本引用**。
void _assertVolumeFloor(
  Map<String, Map<String, dynamic>> current, {
  required File file,
  required bool exists,
}) {
  final newMeasure = anchorMeasureVolume(current);
  final newVolume = newMeasure.content;
  final baseline = _loadBaselineCases(file, exists: exists);
  if (baseline == null) {
    if (!exists) {
      print(
        '[anchor][告警] 本次为首次生成，比率下限未生效：$kAnchorPath\n'
        '  ★ 首次生成是合法通路，故不拦；但**不静默** —— 否则「删掉旧快照再重冻」'
        '就成了绕过下限的最短路径。\n'
        '  提交前请人工复核该基线的体量是否合理'
        '（本次内容体积（单调代理）$newVolume；'
        '非长度整数（不计体积）${newMeasure.nonContentInt}）。',
      );
    }
    return;
  }
  final baselineMeasure = anchorMeasureVolume(baseline);
  final baselineVolume = baselineMeasure.content;
  final floor = (baselineVolume / 2).ceil();
  if (newVolume < floor) {
    fail(
      '[anchor] 重建内容体积（单调代理）低于比率下限，**已拒绝写盘**：\n'
      '  实际：$newVolume\n'
      '  下限：$floor（旧基线 $baselineVolume 的 50%）\n'
      '  非长度整数（不计体积）：${newMeasure.nonContentInt}'
      '（旧基线 ${baselineMeasure.nonContentInt}）\n'
      '  ★ 键齐但内容腰斩 = 装配塌陷的典型形态（fixture 失效 / 注入异常被吞）。\n'
      '  ★ 该指标是「内容体积（单调代理）」，**不得当作字节数 / token 成本引用**。\n'
      '  确为有意的语料缩减须经评审并在 .ai/DECISIONS.md 登记；'
      '确认不设下限时：ALLOW_FLOORLESS_REBUILD=true。',
    );
  }
  print(
    '[anchor] 重建下限通过：内容体积（单调代理）$newVolume ≥ 下限 $floor'
    '（旧基线 $baselineVolume 的 50%）；'
    '非长度整数（不计体积）${newMeasure.nonContentInt}。',
  );
}

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
        // ── 基线非退化判据（T-20261024-15 · 重建分支专属）──────────────
        // 顺序：F1/F2（纯内存，先拦最明显的塌陷）→ F3（要读旧基线，含 IO 与
        // 「不可解析」分支）。两者都在 `writeAsStringSync` **之前**。
        _assertPerCaseNonEmpty(current);
        _assertVolumeFloor(current, file: file, exists: exists);

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
