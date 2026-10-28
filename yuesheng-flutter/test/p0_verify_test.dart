// P0 验证三件套的验收测试
//
// 对应规格：`.ai/reports/2026-10-20-语文知识体系研究/05-P0规格-断言粒度与锚定.md`
//   §1.5 反例表（逐条必须一致）
//   §5   验收样例与通过线（能离线做的部分）
//
// ⚠️ 本文件只证明「实现符合规格」，**不产生任何能力读数**。
//    §5 里需要真实语料的项（20 条真引用 / 20 条编造 / 人工 κ）本文件不覆盖 ——
//    那些样例不存在，用合成语料凑出来的合格率是自证，不是验收。

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/p0_verify/anchor.dart';
import 'package:writingcoach/services/p0_verify/assertion.dart';
import 'package:writingcoach/services/p0_verify/code_census.dart';

/// 从磁盘加载词表真源（测试可以用 IO；库本身不用）。
AssertionLexicon _loadLexicon() {
  final f = File('lib/services/p0_verify/data/assertion_lexicon.json');
  expect(f.existsSync(), isTrue, reason: '词表真源缺失：${f.path}');
  return AssertionLexicon.fromJsonString(f.readAsStringSync());
}

void main() {
  late AssertionLexicon lex;

  setUpAll(() {
    lex = _loadLexicon();
  });

  // ─────────────────────────────────────────────────────────────
  // 词表：counts 必须由文件派生（§1.3.1 约束 1）
  // ─────────────────────────────────────────────────────────────
  group('assertion_lexicon', () {
    test('counts 与各数组实际长度逐键相等', () {
      final raw =
          jsonDecode(
                File(
                  'lib/services/p0_verify/data/assertion_lexicon.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final counts = raw['counts'] as Map<String, dynamic>;
      for (final entry in counts.entries) {
        final arr = raw[entry.key];
        if (arr is List) {
          expect(entry.value, arr.length, reason: 'counts.${entry.key} 漂移');
        }
      }
    });

    test('counts 写错 ⇒ 加载失败（不许只警告）', () {
      final raw =
          jsonDecode(
                File(
                  'lib/services/p0_verify/data/assertion_lexicon.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      (raw['counts'] as Map<String, dynamic>)['nouns'] = 1;
      expect(
        () => AssertionLexicon.fromJsonString(jsonEncode(raw)),
        throwsFormatException,
      );
    });

    test('空词表 ⇒ 加载失败（空表会静默跑出一堆 0）', () {
      final raw =
          jsonDecode(
                File(
                  'lib/services/p0_verify/data/assertion_lexicon.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      raw['transitive_verbs'] = <String>[];
      (raw['counts'] as Map<String, dynamic>)['transitive_verbs'] = 0;
      expect(
        () => AssertionLexicon.fromJsonString(jsonEncode(raw)),
        throwsFormatException,
      );
    });
  });

  // ─────────────────────────────────────────────────────────────
  // §1.5 反例表 —— 14 条逐条必须一致
  // ─────────────────────────────────────────────────────────────
  group('§1.5 反例表', () {
    void expectVerdict(String s, bool assertion, {String? rule}) {
      final v = classifySentence(s, lex);
      expect(
        v.isAssertion,
        assertion,
        reason:
            '「$s」应判${assertion ? "断言" : "非断言"}，实际 [${v.rule}] ${v.isAssertion}',
      );
      if (rule != null) {
        expect(v.rule, rule, reason: '「$s」规则应为 $rule，实际 ${v.rule}');
      }
    }

    test('他生于青云山下。 → 断言', () => expectVerdict('他生于青云山下。', true));
    test('青云山下。 → 非（A5）', () => expectVerdict('青云山下。', false, rule: 'A5'));
    test('「你走吧。」 → 断言', () => expectVerdict('「你走吧。」', true));
    test('冷。 → 非（A5）', () => expectVerdict('冷。', false, rule: 'A5'));
    test('半晌。 → 非（A5）', () => expectVerdict('半晌。', false, rule: 'A5'));
    test('三年前，城南。 → 非（无谓词）', () => expectVerdict('三年前，城南。', false));
    test('三年前他离开城南。 → 断言', () => expectVerdict('三年前他离开城南。', true));
    test(
      '一是天赋，二是心性。 → 断言（A1）',
      () => expectVerdict('一是天赋，二是心性。', true, rule: 'A1'),
    );
    test('剑断了。 → 断言（A3）', () => expectVerdict('剑断了。', true, rule: 'A3'));

    test(
      '你是谁？ → 非（A6 未被 A1 短路）',
      () => expectVerdict('你是谁？', false, rule: 'A6'),
    );
    test(
      '谁是对的？ → 非（含「是」仍不短路成 A1）',
      () => expectVerdict('谁是对的？', false, rule: 'A6'),
    );
    test('这不就是你？ → 非（A6）', () => expectVerdict('这不就是你？', false, rule: 'A6'));
    test('谁？ → 非（A6）', () => expectVerdict('谁？', false, rule: 'A6'));

    test('「你走吧。天要亮了。」 → 2 个断言（引号不阻断切分）', () {
      final c = countAssertions('「你走吧。天要亮了。」', lex);
      expect(c.total, 2);
    });
  });

  // ─────────────────────────────────────────────────────────────
  // §5 对白粒度：3 句对白 + 2 句叙述（对白内 1 处嵌套引号）⇒ 断言数 = 5
  // ─────────────────────────────────────────────────────────────
  group('§5 对白粒度', () {
    test('3 句对白 + 2 句叙述，嵌套引号不改变切分，不得整段计 1', () {
      const text =
          '「你走吧。」「我不走。」「他说『快走』的时候，声音在抖。」'
          '他握紧了剑。天亮了。';
      final count = countAssertions(text, lex);
      expect(
        count.total,
        5,
        reason: '实际切分：${count.verdicts.map((v) => v.toString()).join("\n")}',
      );
      expect(count.isDialogueHeavy, isFalse);
    });
  });

  // ─────────────────────────────────────────────────────────────
  // §1.1 段：只以空行分段；零空行才 line 兜底
  // ─────────────────────────────────────────────────────────────
  group('段切分', () {
    test('空行分段，段内单换行并入同段', () {
      final r = splitSegments('第一行\n第二行\n\n第三段');
      expect(r.mode, 'blank');
      expect(r.segments, ['第一行\n第二行', '第三段']);
    });

    test('整篇零空行 ⇒ line 兜底并如实报出 mode', () {
      final r = splitSegments('第一行\n第二行\n第三行');
      expect(r.mode, 'line');
      expect(r.isLineFallback, isTrue);
      expect(r.segments.length, 3);
    });
  });

  // ─────────────────────────────────────────────────────────────
  // §2 P0-a 全状态
  // ─────────────────────────────────────────────────────────────
  group('P0-a 锚定状态', () {
    const chunk =
        '他握紧了青玉牌，指节发白。'
        '窗外的雪落了一夜，天亮时屋檐下挂满冰凌。'
        '他握紧了青玉牌，指节发白。'
        '他握紧了青玉牌，指节发白。'
        '他握紧了青玉牌，指节发白。'
        '后来他说，那晚他梦见城南的旧宅。';

    test('L0 精确命中 ⇒ ok_exact，span 是原文坐标', () {
      final a = anchorOne(chunk, '窗外的雪落了一夜');
      expect(a.status, AnchorStatus.okExact);
      expect(a.span, isNotNull);
      final span = a.span!;
      expect(chunk.substring(span[0], span[1]), '窗外的雪落了一夜');
    });

    // O-1（`.ai/DECISIONS §4-365`）：锚定只证"原文确有这句"，不证"这句能支撑该症候"。
    // 该标注须随裁决一起走；删掉它就等于让 ok_exact 被读成"判据成立"。
    test('命中也不等于语义已验证 ⇒ 仍带 not_performed（O-1）', () {
      final a = anchorOne(chunk, '窗外的雪落了一夜');
      expect(a.status, AnchorStatus.okExact);
      expect(a.semanticCheck, kAnchorSemanticCheck);
      expect(kAnchorSemanticCheck, 'not_performed');
      // 反例守门：任何"已验证"读法都无对应取值。
      expect(kAnchorSemanticCheck, isNot('verified'));
    });

    test('L1 空白折叠 ⇒ ok_ws，且 span 回填到原文（不是归一化坐标）', () {
      // 原文有换行，evidence 里写成空格
      const withNewline = '他握紧了青玉牌，\n指节发白，窗外雪落了一夜。';
      final a = anchorOne(withNewline, '青玉牌， 指节发白');
      expect(a.status, AnchorStatus.okWs);
      final span = a.span!;
      final slice = withNewline.substring(span[0], span[1]);
      expect(
        slice.contains('指节发白'),
        isTrue,
        reason: '回填后应覆盖原文对应片段，实际切片=$slice',
      );
      expect(
        slice.contains('\n'),
        isTrue,
        reason: 'span 必须覆盖原文的换行，若按归一化坐标会漏掉它',
      );
    });

    test('L2 全半角 ⇒ ok_width', () {
      final a = anchorOne('他说，“走吧”，然后转身。', '他说,"走吧",然后转身.');
      expect(a.status, AnchorStatus.okWidth);
    });

    test('命中 4 处（> AMBIGUOUS_OCCURRENCES=3）⇒ ambiguous', () {
      final a = anchorOne(chunk, '他握紧了青玉牌，指节发白');
      expect(a.occurrences, 4);
      expect(a.status, AnchorStatus.ambiguous);
    });

    test('短引文 ⇒ too_short（进分母，不判 ok 也不判 fail）', () {
      final a = anchorOne(chunk, '他');
      expect(a.status, AnchorStatus.tooShort);
      final agg = aggregateEvidence([a]);
      expect(agg.denominator, 1, reason: 'too_short 必须进分母');
      expect(
        agg.aer,
        isNull,
        reason: '单条 too_short ⇒ too_short_rate=1.0 超限 ⇒ 必须输出 未测',
      );
    });

    test('改 1–2 字的编造 ⇒ fail（不许判"差不多对"）', () {
      final a = anchorOne(chunk, '他握紧了白玉牌，指节发白');
      expect(a.status, AnchorStatus.fail);
    });

    test('省略号拼段 ⇒ ok_joined，首段必须命中', () {
      final a = anchorOne(chunk, '他握紧了青玉牌……后来他说，那晚他梦见城南的旧宅');
      expect(a.status, AnchorStatus.okJoined);
      expect(a.matchLevel, 'joined');
    });

    test('省略号首段未命中 ⇒ fail_joined', () {
      final a = anchorOne(chunk, '他握紧了白玉牌……后来他说，那晚他梦见城南的旧宅');
      expect(a.status, AnchorStatus.failJoined);
    });

    test('引号由外向内剥离后再锚', () {
      final a = anchorOne(chunk, '「窗外的雪落了一夜」');
      expect(a.status, AnchorStatus.okExact);
    });
  });

  // ─────────────────────────────────────────────────────────────
  // §2.4/§2.5 分母口径：调用方不得自算
  // ─────────────────────────────────────────────────────────────
  group('分母口径', () {
    test('too_short_rate 超限 ⇒ AER 判 未测（不是给一个数）', () {
      const text = '他握紧了青玉牌，指节发白。窗外的雪落了一夜。';
      final items = [
        for (var i = 0; i < 4; i++) anchorOne(text, '他'),
        anchorOne(text, '窗外的雪落了一夜'),
      ];
      final agg = aggregateEvidence(items);
      expect(agg.tooShortRate, 0.8);
      expect(agg.aer, isNull, reason: '超限必须输出 未测（null），不许当有效读数');
    });

    test('ELA 分母排除 ambiguous 与 ok_joined', () {
      const chunk =
          '他握紧了青玉牌，指节发白。他握紧了青玉牌，指节发白。'
          '他握紧了青玉牌，指节发白。他握紧了青玉牌，指节发白。';
      bool isEla(AnchoredEvidence e) => e.status.isElaEligible;

      final amb = anchorOne(chunk, '他握紧了青玉牌，指节发白');
      final ok = anchorOne('窗外雪落了一夜。', '窗外雪落了一夜');
      expect(amb.status, AnchorStatus.ambiguous);
      expect(isEla(amb), isFalse, reason: 'ambiguous 首处不一定是金标那处');
      expect(isEla(ok), isTrue);
    });

    test('NCR-anchored 只认锚上的 evidence', () {
      final okAgg = aggregateEvidence([
        anchorOne('窗外的雪落了一夜。他握紧了青玉牌。', '窗外的雪落了一夜'),
      ]);
      expect(okAgg.ncrAnchored, isTrue);

      final failAgg = aggregateEvidence([
        anchorOne('他握紧了青玉牌，指节发白。', '他握紧了白玉牌，指节发白'),
      ]);
      expect(failAgg.ncrAnchored, isFalse);
    });
  });

  // ─────────────────────────────────────────────────────────────
  // §3 G8④ 处置三分
  // ─────────────────────────────────────────────────────────────
  group('G8④ 空码处置', () {
    const chunk = '段一的内容在这里。\n\n段二的内容在这里。\n\n段三的内容在这里。';
    final segmentCount = splitSegments(chunk).segments.length;

    CodeCensusReport run({
      List<GoldRow> gold = const [],
      Set<String> history = const {},
      bool scanned = false,
    }) => censusGoldCodes(
      gold: gold,
      segmentCount: segmentCount,
      chunkText: chunk,
      historyIndex: history,
      historyScanned: scanned,
      historyFileCount: scanned ? 1 : 0,
      historyScannedAt: scanned ? '2026-10-20T21:00:00+08:00' : null,
      segmentMode: splitSegments(chunk).mode,
    );

    test('合法实例 ≥ 1 ⇒ keep', () {
      final r = run(
        gold: const [
          GoldRow(
            relationCode: 'R_reuse',
            target: 1,
            relationEvidence: ['段一的内容在这里'],
          ),
        ],
      );
      expect(r.stats['R_reuse']!.disposition, 'keep');
      expect(r.stats['R_reuse']!.entersM17aDenominator, isTrue);
    });

    test('target 越界 ⇒ reserved（不得 remove，非法行单列）', () {
      final r = run(
        gold: const [
          GoldRow(
            relationCode: 'R_reuse',
            target: 99,
            relationEvidence: ['段一的内容在这里'],
          ),
        ],
      );
      final s = r.stats['R_reuse']!;
      expect(s.rawCount, 1);
      expect(s.legalCount, 0);
      expect(s.invalidTargetRows, 1);
      expect(s.disposition, 'reserved');
      expect(r.invalidTargetRows, 1);
    });

    test('证据编造 ⇒ reserved 且 unanchored_rows 单列', () {
      final r = run(
        gold: const [
          GoldRow(
            relationCode: 'R_shared_ref',
            target: 2,
            relationEvidence: ['段二的内容不在这里'],
          ),
        ],
      );
      final s = r.stats['R_shared_ref']!;
      expect(s.legalCount, 0);
      expect(s.unanchoredRows, 1);
      expect(s.disposition, 'reserved');
      expect(r.unanchoredRows, 1);
    });

    test('历史集未扫描 ⇒ 零实例只能 reserved，不得 remove', () {
      final r = run(scanned: false);
      expect(r.stats['R_info_gap']!.disposition, 'reserved');
    });

    test('历史集已扫描且无 ⇒ remove', () {
      final r = run(scanned: true);
      expect(r.stats['R_info_gap']!.disposition, 'remove');
    });

    test('历史集已扫描但含该码 ⇒ reserved', () {
      final r = run(scanned: true, history: {'R_time_offset'});
      expect(r.stats['R_time_offset']!.disposition, 'reserved');
    });

    test('R_none 是兜底 ⇒ 不进任何分支', () {
      final r = run(
        gold: const [
          GoldRow(relationCode: 'R_none', target: null, relationEvidence: []),
        ],
      );
      expect(r.stats['R_none']!.disposition, 'exception');
      expect(r.stats['R_none']!.entersM17aDenominator, isFalse);
    });
  });

  // ─────────────────────────────────────────────────────────────
  // §5 三件共同：完全确定性（同输入同输出，无随机）
  // ─────────────────────────────────────────────────────────────
  group('确定性', () {
    test('同一份样本跑两遍完全一致', () {
      const text = '「你走吧。」他握紧了剑。天亮了，雪还在下。\n\n后来他说，那晚梦见旧宅。';
      final a1 = countAssertions(text, lex);
      final a2 = countAssertions(text, lex);
      expect(a1.total, a2.total);
      expect(
        a1.verdicts.map((v) => v.toString()).join('|'),
        a2.verdicts.map((v) => v.toString()).join('|'),
      );

      final b1 = anchorEvidence(text, ['他握紧了剑', '天亮了']);
      final b2 = anchorEvidence(text, ['他握紧了剑', '天亮了']);
      expect(
        b1.map((e) => '${e.status.code}${e.span}').join('|'),
        b2.map((e) => '${e.status.code}${e.span}').join('|'),
      );
    });
  });
}
