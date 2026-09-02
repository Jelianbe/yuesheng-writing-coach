// ignore_for_file: avoid_print
// ─────────────────────────────────────────────────────────────
// N19 枚举一致性 —— 双向校验（由「建议」升级为验收项）
//
// 台账：docs/audits/Skill话术与提示词-综合审阅（合并版）-2026-08-30.md
//       §「顺带核实 8 条（N13~N20）」N19
// 同族：C58（prompt 侧观察）/ N11（ADR 代码侧）/ N21（前测实测侧，已修 A.12.23）
//       —— 三向印证的是同一件事：prompt 声明的取值集合窄于代码白名单。
//
// P 系与 N 系取值有**四份真源**，任一处漏改都会留下幽灵状态：
//   ① 解析白名单   services/diagnosis_parser.dart（kValidPhases / kValidBeginnerLevels）
//   ② Dart 枚举    types/teaching_types.dart（TeachingPhase / BeginnerLevel 的 value）
//   ③ DB CHECK     data/database/tables.dart（TeachingState.currentPhase / .beginnerLevel）
//   ④ prompt 声明  services/skills_*.dart 里全部注册 skill 的正文
//
// 本测试断言四份真源**双向相等**（不是单向包含）：
//   方向 A（无幽灵值）：prompt 出现过的每个取值，①②③ 都必须认下。
//       —— 防止再出现 P5_* 那种「prompt 承诺、代码静默丢弃、该轮零迁移」。
//   方向 B（无死枚举）：①②③ 的每个取值，prompt 里都必须至少声明一次。
//       —— 防止新增阶段只在代码/DB 侧落地，而学员侧 prompt 从不提及。
//
// 范围外（登记在案，不纳入本护栏）：
//   - severity（L1/L2/L3）：取值与「L1 层 / L2 层」等章节名同形，正则无法区分。
//   - teaching_mode（socratic/mirror/conflict/direct）：prompt 侧为中文表述，
//     无稳定 token 可抽，强行正则会全是假阳性。
// ─────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/diagnosis_parser.dart';
import 'package:writingcoach/services/skill_registry.dart';
import 'package:writingcoach/types/teaching_types.dart';

/// tables.dart 相对项目根的路径（flutter test 以项目根为 cwd）
const String kTablesPath = 'lib/data/database/tables.dart';

/// prompt 语料：注册表里**全部** skill 的正文（未切片，含 L1 常驻 + 3 态度 +
/// L2 各组 + 2 个虚拟索引）。取未切片的 content 是为了让方向 A 覆盖到
/// 「任何语境下可能被注入」的全文。
String get promptCorpus =>
    skillRegistry.values.map((s) => s.content).join('\n');

/// P 系 token：P0_ENGAGE / P2_PRACTICE_LOOP …
final RegExp kPhaseToken = RegExp(r'P\d_[A-Z]+(?:_[A-Z]+)*');

/// N 系 token：N0_ENGAGE / N4_INDEPENDENT …
final RegExp kLevelToken = RegExp(r'N\d_[A-Z]+(?:_[A-Z]+)*');

/// DB CHECK 里的取值字面量（'P0_ENGAGE' / 'N0_ENGAGE'）
final RegExp kDbLiteral = RegExp(r"'([A-Z]\d_[A-Z]+(?:_[A-Z]+)*)'");

Set<String> tokensOf(String src, RegExp re) =>
    re.allMatches(src).map((m) => m.group(0)!).toSet();

/// 从 tables.dart 抽取指定列的 CHECK 取值集合。
///
/// CHECK 是编译期常量列表，drift 未对外暴露可读取取值的 API，只能退回源码
/// 文本解析。定位方式：从 `TextColumn get <column>` 起，截到下一个列定义
/// 或 `@override` 之前，再取其中全部形如 'P0_ENGAGE' 的字面量。
/// 解析不出任何取值时**直接 fail**——静默放行会让护栏形同虚设。
Set<String> dbCheckValues(String column) {
  final file = File(kTablesPath);
  if (!file.existsSync()) {
    fail('找不到 $kTablesPath（flutter test 的 cwd 应为项目根目录）');
  }
  final src = file.readAsStringSync();
  final head = 'TextColumn get $column';
  final start = src.indexOf(head);
  if (start == -1) {
    fail('$kTablesPath 中找不到列定义：$column（列名是否改过？）');
  }
  final rest = src.substring(start + head.length);
  final bounds = <String>['TextColumn get ', 'IntColumn get ', '@override'];
  final cuts = bounds.map(rest.indexOf).where((i) => i > 0).toList()..sort();
  final body = cuts.isEmpty ? rest : rest.substring(0, cuts.first);
  final values = kDbLiteral.allMatches(body).map((m) => m.group(1)!).toSet();
  if (values.isEmpty) {
    fail(
      '$kTablesPath 的列 $column 未解析出任何 CHECK 取值，'
      '护栏无法成立（约束被删了还是格式变了？）',
    );
  }
  return values;
}

String fmt(Set<String> s) => (s.toList()..sort()).join(', ');

void main() {
  // 语料自检放在最前：若注册表塌了，后面四向断言会「两边都空」而假绿。
  test('语料自检：注册表非空、L1 常驻层齐全、正文长度达标', () {
    expect(skillRegistry, isNotEmpty, reason: 'Skill 注册表为空，护栏失去意义');
    for (final id in const [
      'core-iron-triangle',
      'core-product-identity',
      'writing-anchors',
      'teaching-strategy',
      'phase-mapper',
      'scenario-rules',
      'validation-rules',
      'teaching-modes',
      'reply-voice',
    ]) {
      expect(
        skillRegistry.containsKey(id),
        isTrue,
        reason: 'L1 常驻 skill 缺失: $id',
      );
    }
    expect(
      promptCorpus.length,
      greaterThan(10000),
      reason: 'prompt 语料过短（${promptCorpus.length}），方向 B 会假绿',
    );
    print(
      '[N19] 语料：${skillRegistry.length} 个 skill / '
      '${promptCorpus.length} 字符',
    );
  });

  test('P 系四向相等：prompt ↔ 解析白名单 ↔ TeachingPhase 枚举 ↔ DB CHECK', () {
    final fromPrompt = tokensOf(promptCorpus, kPhaseToken);
    final fromParser = kValidPhases.toSet();
    final fromEnum = TeachingPhase.values.map((e) => e.value).toSet();
    final fromDb = dbCheckValues('currentPhase');

    // 代码侧三份真源必须逐值相等（单向包含不足：多一个值 = 幽灵，少一个 = 静默丢弃）
    expect(
      fromParser,
      fromEnum,
      reason:
          '① 解析白名单 ≠ ② TeachingPhase 枚举\n'
          '  ① ${fmt(fromParser)}\n  ② ${fmt(fromEnum)}',
    );
    expect(
      fromDb,
      fromEnum,
      reason:
          '③ DB CHECK ≠ ② TeachingPhase 枚举\n'
          '  ③ ${fmt(fromDb)}\n  ② ${fmt(fromEnum)}',
    );

    // 方向 A：prompt 不得声明代码不认的取值（P5_* 同款幽灵）
    final ghosts = fromPrompt.difference(fromParser);
    expect(
      ghosts,
      isEmpty,
      reason:
          '方向 A 失败：prompt 声明了代码不认的阶段值 ${fmt(ghosts)}。'
          '\n  若为有意新增，须四处同步：枚举 / 白名单 / DB CHECK / prompt。',
    );

    // 方向 B：代码认的取值，prompt 必须至少声明一次（否则学员侧从不知情）
    final orphans = fromParser.difference(fromPrompt);
    expect(
      orphans,
      isEmpty,
      reason:
          '方向 B 失败：阶段值 ${fmt(orphans)} 在 prompt 全文里从未出现，'
          '\n  学员永远不会被告知该阶段存在（死枚举）。',
    );

    expect(fromPrompt, fromParser);
    print('[N19] P 系四向相等（${fromParser.length} 值）：${fmt(fromParser)}');
  });

  test('N 系四向相等：prompt ↔ 解析白名单 ↔ BeginnerLevel 枚举 ↔ DB CHECK', () {
    final fromPrompt = tokensOf(promptCorpus, kLevelToken);
    final fromParser = kValidBeginnerLevels.toSet();
    final fromEnum = BeginnerLevel.values.map((e) => e.value).toSet();
    final fromDb = dbCheckValues('beginnerLevel');

    expect(
      fromParser,
      fromEnum,
      reason:
          '① 解析白名单 ≠ ② BeginnerLevel 枚举\n'
          '  ① ${fmt(fromParser)}\n  ② ${fmt(fromEnum)}',
    );
    expect(
      fromDb,
      fromEnum,
      reason:
          '③ DB CHECK ≠ ② BeginnerLevel 枚举\n'
          '  ③ ${fmt(fromDb)}\n  ② ${fmt(fromEnum)}',
    );

    final ghosts = fromPrompt.difference(fromParser);
    expect(
      ghosts,
      isEmpty,
      reason: '方向 A 失败：prompt 声明了代码不认的零基础等级 ${fmt(ghosts)}',
    );

    final orphans = fromParser.difference(fromPrompt);
    expect(
      orphans,
      isEmpty,
      reason: '方向 B 失败：零基础等级 ${fmt(orphans)} 在 prompt 全文里从未出现',
    );

    expect(fromPrompt, fromParser);
    print('[N19] N 系四向相等（${fromParser.length} 值）：${fmt(fromParser)}');
  });
}
