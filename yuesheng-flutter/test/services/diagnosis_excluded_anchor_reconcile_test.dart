// ─────────────────────────────────────────────────────────────
// T-20261024-05 批 2 · excluded 字段全链 —— 判据 5「快照可对账」
//
// 本测试不重跑装配（既有 chat_service_message_sequence_anchor_test /
// skill_prompt_anchor_test / prompt_const_anchor_test 三套件负责「重冻后跑绿」），
// 只做**快照文件本身的逐键对账**：施工方重冻三份快照后，断言新基线
// 与报批稿 ④ 的先验逐键吻合。
//
// 钉值依据（锚点基线，02-前置实测 §1 现场实测）：
//   · message_sequence 对照组 7 组 user = (22, e44e287a4ac8d8f) —— suffix 只进诊断场景
//   · fulltext user 旧值 (1583, 100f00a384794e7d) / nofulltext 旧值 (1521, 49d7de888531ca6d)
//   · prompt_const_anchor kDiagnosisProtocolSuffix 旧值 (977, 609c7814d5bcc86d)
//   · skill_prompt diagnosis_p1_yuesheng 旧 fnv 4b6d0c4dc911feec
//   · skill_prompt diagnosis_yuesheng 旧 fnv 6eb12916ae7346a1
//   · skill_prompt beginner_p3_yuesheng_forceSceneFirst 旧 fnv 59d41af06ebfcd7f（force 组红线）
//
// 随动规则（报批稿 ④ 注 [5]）：若施工实测 force 组/对照组 7 组读数也变，
//   以实测为准一并上移钉值并逐键对账 —— 先验落空即登记偏离，不硬保旧值。
//
// 假绿纪律：isNot(旧 fnv) 与旧值距离非 0（16 位 hex 全量）⇒ 等值否定有效（⑦）；
//   每条「必变」断言同时钉 len>1000 下界做双保险（防退化成对照组 22 也蒙混）。
// ─────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// 锚点基线钉值（02-前置实测 §1 旧基线 + 施工方写模式重冻后 E1 新基线，
// 见 04-三面对账表.md 逐键 old→new）。
const int kControlUserLen = 22;
const String kControlUserFnv = 'e44e287a4ac8d8f';

// 诊断两 case user 消息新基线（重冻后钉死；未来任何漂移即红）。
const String kFulltextUserFnv = '4c74e83aee3f265c';
const int kFulltextUserLen = 1644;
const String kNoFulltextUserFnv = '6c29c09e0ac47f8c';
const int kNoFulltextUserLen = 1582;

// kDiagnosisProtocolSuffix 新基线（977→1038 = +61，与设计批吻合）。
const int kSuffixLen = 1038;
const String kSuffixFnv = 'b4ae395807abdc6';

// skill_prompt 受控组新基线（index 模板 +107 落 diagnosis 两组）。
const String kDiagP1Fnv = '7908a114a2935bb0';
const String kDiagYueFnv = '3d9b44d264788d0d';
// force 组红线：先验 +0，实测维持旧值（04-对账表面二对照组全 0）。
const String kForceFnv = '59d41af06ebfcd7f';

const String kFulltextCase = 'p2_yuesheng_diagnosis_fulltext';
const String kNoFulltextCase = 'p2_yuesheng_diagnosis_nofulltext';
const String kP1Case = 'p1_yuesheng_diagnosis';

Map<String, dynamic> _readJson(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

/// 从一条消息序列里取出 role=='user' 的条目（恰好 1 条，结构自洽断言）。
Map<String, dynamic> _userMsg(List<dynamic> seq, String caseName) {
  final users = seq
      .whereType<Map<String, dynamic>>()
      .where((m) => m['role'] == 'user')
      .toList();
  expect(users, hasLength(1), reason: '$caseName 的消息序列应恰好 1 条 user 消息（结构自洽）');
  return users.single;
}

void main() {
  group('判据 5 · 快照可对账（三份快照新基线逐键断言）', () {
    late Map<String, dynamic> msgSeq;
    late Map<String, dynamic> promptConst;
    late Map<String, dynamic> skillPrompt;

    setUpAll(() {
      msgSeq = _readJson('test/snapshots/message_sequence_anchor.json');
      promptConst = _readJson('test/snapshots/prompt_const_anchor.json');
      skillPrompt = _readJson('test/snapshots/skill_prompt_anchor.json');
    });

    test('S0 快照结构自洽：三份文件存在、键集合齐全', () {
      expect(msgSeq.containsKey(kFulltextCase), isTrue);
      expect(msgSeq.containsKey(kNoFulltextCase), isTrue);
      expect(promptConst.containsKey('kDiagnosisProtocolSuffix'), isTrue);
      final prompt = skillPrompt['prompt'] as Map<String, dynamic>;
      expect(prompt.containsKey('diagnosis_p1_yuesheng'), isTrue);
      expect(prompt.containsKey('diagnosis_yuesheng'), isTrue);
      expect(
        prompt.containsKey('beginner_p3_yuesheng_forceSceneFirst'),
        isTrue,
      );
    });

    test('S1 对照组红线：7 组非诊断 case 的 user 消息零漂移 (22, e44e287a4ac8d8f)', () {
      final controlCases = msgSeq.keys
          .where((k) => k != 'meta')
          .where((k) => k != kFulltextCase && k != kNoFulltextCase)
          .toList();
      expect(
        controlCases,
        hasLength(8),
        reason:
            '对照组应为 8 组（10 case − 诊断注入 2 case；'
            'p1/p2 普通诊断 case 的 user 消息实测仍 22 —— suffix 只注入完整章两 case）',
      );
      for (final c in controlCases) {
        final user = _userMsg(
          (msgSeq[c] as List).cast<Map<String, dynamic>>(),
          c,
        );
        expect(
          user['len'],
          kControlUserLen,
          reason:
              '$c user 消息 len 必须仍为 $kControlUserLen '
              '（suffix 只进诊断场景 —— 红线：注入扩散即红）',
        );
        expect(
          user['fnv'],
          kControlUserFnv,
          reason: '$c user 消息 fnv 必须仍为 $kControlUserFnv',
        );
      }
    });

    test('S2 诊断两 case：user 消息钉死新基线（重冻后逐键等值）', () {
      for (final entry in {
        kFulltextCase: (kFulltextUserLen, kFulltextUserFnv),
        kNoFulltextCase: (kNoFulltextUserLen, kNoFulltextUserFnv),
      }.entries) {
        final user = _userMsg(
          (msgSeq[entry.key] as List).cast<Map<String, dynamic>>(),
          entry.key,
        );
        expect(
          user['len'],
          entry.value.$1,
          reason:
              '${entry.key} user len 钉死新基线 ${entry.value.$1} '
              '（施工重冻后实测；未来漂移即红）',
        );
        expect(
          user['fnv'],
          entry.value.$2,
          reason: '${entry.key} user fnv 钉死新基线 ${entry.value.$2}',
        );
        expect(
          user['len'],
          greaterThan(1000),
          reason: '${entry.key} user 必须仍是含后缀的长消息（防退化成对照组短输入）',
        );
      }
    });

    test('S3 prompt_const_anchor：kDiagnosisProtocolSuffix 钉死新基线', () {
      final suffix =
          promptConst['kDiagnosisProtocolSuffix'] as Map<String, dynamic>;
      expect(
        suffix['len'],
        kSuffixLen,
        reason: 'suffix len 钉死 $kSuffixLen（977→1038 = +61，与设计批吻合）',
      );
      expect(suffix['fnv'], kSuffixFnv, reason: 'suffix fnv 钉死 $kSuffixFnv');
    });

    test('S4 skill_prompt_anchor：diagnosis 两组钉死新基线，force 组红线零漂移', () {
      final prompt = skillPrompt['prompt'] as Map<String, dynamic>;
      // index 新格式落点：diagnosis 两组逐键钉死（04-对账表面二）。
      expect(
        (prompt['diagnosis_p1_yuesheng'] as Map)['fnv'],
        kDiagP1Fnv,
        reason: 'diagnosis_p1_yuesheng fnv 钉死 $kDiagP1Fnv',
      );
      expect(
        (prompt['diagnosis_yuesheng'] as Map)['fnv'],
        kDiagYueFnv,
        reason: 'diagnosis_yuesheng fnv 钉死 $kDiagYueFnv',
      );
      // force 组红线：先验 +0，实测维持旧值。
      expect(
        (prompt['beginner_p3_yuesheng_forceSceneFirst'] as Map)['fnv'],
        kForceFnv,
        reason: 'force 组红线：误伤即红（04-对账表面二对照组全 0 已证）',
      );
    });

    test(
      'S5 跨快照同源对账：message_sequence 诊断组 system[0] 与 skill_prompt diagnosis 组同源相等',
      () {
        final prompt = skillPrompt['prompt'] as Map<String, dynamic>;
        // 防「只重冻一处」：两快照同源协议文本必须同步变化后仍相等。
        final p1System0 = (msgSeq[kP1Case] as List)
            .cast<Map<String, dynamic>>()
            .first;
        expect(
          p1System0['fnv'],
          (prompt['diagnosis_p1_yuesheng'] as Map)['fnv'],
          reason:
              '${kP1Case} system[0] 与 diagnosis_p1_yuesheng 同源，'
              '两快照必须同步重冻（漏冻任一侧即红）',
        );
        final fulltextSystem0 = (msgSeq[kFulltextCase] as List)
            .cast<Map<String, dynamic>>()
            .first;
        expect(
          fulltextSystem0['fnv'],
          (prompt['diagnosis_yuesheng'] as Map)['fnv'],
          reason:
              '$kFulltextCase system[0] 与 diagnosis_yuesheng 同源，'
              '两快照必须同步重冻',
        );
      },
    );
  });
}
