// ─────────────────────────────────────────────────────────────
// chat_context_builder_observation_test — 诊断注入专项（S1 批次）
//
// 覆盖：
//   1. S3（R1）：world 摘录 120 字截断三态（>120 截断带省略号 / ≤120 原样 /
//      边界 121）+ 摘录格式与 character 侧逐字一致（R1-AC4）
//   2. R8/R3-AC3 锚点：四个事实表观察构建器在「未超限」小样本下的输出
//      **逐字节冻结**——S2（T03）接入 ObservationBudget 后本组断言必须
//      原样通过（未超限 → kept==输入、dropped==0、无截断提示段）。
//      样本刻意保持：条数 ≤ 12、每段可变行 ≤ 900 chars。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/config/shared_constants.dart';
import 'package:writingcoach/services/chat_context_builder.dart';
import 'package:writingcoach/services/conflict_detector.dart';
import 'package:writingcoach/services/event_causality_detector.dart';
import 'package:writingcoach/services/subplot_closure_detector.dart';
import 'package:writingcoach/types/character_types.dart';

/// 构造一条冲突断言（两个不同值构成观察项的最小输入）
List<CharacterAssertion> _pair(String attribute, String a, String b) => [
  CharacterAssertion(attribute: attribute, value: a, chapter: 1, timestamp: 1),
  CharacterAssertion(attribute: attribute, value: b, chapter: 9, timestamp: 2),
];

WorldConflictObservation _world(String theme, String excerpt) =>
    WorldConflictObservation(
      themeName: theme,
      attribute: '灵气浓度',
      orderedValues: _pair('灵气浓度', '稀薄', '充沛'),
      description: '第1章「稀薄」→ 第20章「充沛」',
      excerpt: excerpt,
    );

void main() {
  group('S3：world 摘录 120 字截断（R1）', () {
    test('R1-AC1：evidence > 120 字 → 摘录 = 前 119 字 + 「…」，总长 ≤ 120', () {
      final long = '甲' * 140;
      final ctx = buildWorldSettingObservationsContext([_world('灵气体系', long)])!;
      final expectedHead = '${'甲' * 119}…';
      expect(ctx, contains('（原文：「$expectedHead」）'));
      // 摘录总长 = 119 + 1（省略号）= 120
      expect(expectedHead.length, 120);
      // 原文第 120 字起（被截掉的部分）不得出现
      expect(ctx, isNot(contains('「${'甲' * 120}')));
    });

    test('R1-AC1 边界：121 字 → 截断为 120（含省略号）', () {
      final s121 = '乙' * 121;
      final ctx = buildWorldSettingObservationsContext([_world('灵气体系', s121)])!;
      expect(ctx, contains('（原文：「${'乙' * 119}…」）'));
      expect(ctx, contains('${'乙' * 119}…'));
    });

    test('R1-AC2：evidence 恰 120 字 → 原样保留（不截断）', () {
      final s120 = '丙' * 120;
      final ctx = buildWorldSettingObservationsContext([_world('灵气体系', s120)])!;
      expect(ctx, contains('（原文：「$s120」）'));
    });

    test('R1-AC2：evidence ≤ 120 字（119）→ 原样保留', () {
      final s119 = '丁' * 119;
      final ctx = buildWorldSettingObservationsContext([_world('灵气体系', s119)])!;
      expect(ctx, contains('（原文：「$s119」）'));
    });

    test('R1-AC4：截断后仍走 _excerptSuffix，与 character 侧格式逐字一致', () {
      final long = '戊' * 200;
      final ctx = buildWorldSettingObservationsContext([_world('灵气体系', long)])!;
      // 与 F05 侧同款格式「（原文：「…」）」（R1-AC4 / §7-5）
      expect(ctx, contains('（原文：「${'戊' * 119}…」）'));
      // 省略号必须是单字符 …（U+2026），不是三点 ...
      expect(ctx, isNot(contains('${'戊' * 119}...')));
    });
  });

  group('R8/R3-AC3 未超限锚点（字节级冻结）', () {
    test('buildConflictObservationsContext：单条输出逐字节一致', () {
      final ctx = buildConflictObservationsContext([
        ConflictObservation(
          characterName: '阿禾',
          attribute: '性情',
          orderedValues: _pair('性情', '冷静', '暴烈'),
          description: '第1章「冷静」→ 第9章「暴烈」',
          excerpt: '他是家中的独生子，父亲常年在远方',
        ),
      ]);
      expect(
        ctx,
        '## 时序矛盾观察（F05 补充）\n\n'
        '以下是作品中已记录的人物属性前后不一致（同属性不同值，按出现章节标注）。'
        '若这些矛盾确属事实性错误（而非角色刻意隐瞒或剧情转折），请结合 P018 人设崩塌症'
        '的判断原则提示学员，温和指出矛盾位置与前后差异（只定位，不代改正文）。\n\n'
        '- 阿禾「性情」：第1章「冷静」→ 第9章「暴烈」'
        '（原文：「他是家中的独生子，父亲常年在远方」）',
      );
    });

    test('buildWorldSettingObservationsContext：单条短摘录输出逐字节一致', () {
      final ctx = buildWorldSettingObservationsContext([
        _world('灵气体系', '山间灵气稀薄，凡人难以修行'),
      ]);
      expect(
        ctx,
        '## 设定不一致观察（设定层）\n\n'
        '以下是作品中同一设定主题（世界规则 / 体系 / 势力）在不同章节的取值记录。'
        '若确属**规则与例外**（同一主题在不同范围或时期下的层次，如整体灵气稀薄但'
        '某地有灵脉），请忽略；若确属设定漂移，请温和提示学员（只定位，不代改正文）。\n\n'
        '- 「灵气体系」灵气浓度：第1章「稀薄」→ 第20章「充沛」'
        '（原文：「山间灵气稀薄，凡人难以修行」）',
      );
    });

    test('buildCausalityBreakContext：单条输出逐字节一致', () {
      final ctx = buildCausalityBreakContext([
        CausalityBreakObservation(
          name: '阿禾决定去金陵',
          chapter: 5,
          eventType: '决定',
          description: '第5章「阿禾决定去金陵」（决定类）缺触发事件',
          excerpt: '第5章，阿禾决定去金陵',
        ),
      ]);
      expect(
        ctx,
        '## 因果链断裂观察（F07 补充）\n\n'
        '以下是作品中已记录的关键事件（决定/转折/突发类）缺少触发事件（因果前驱缺失）。'
        '若确属「突然发生」而读者无法理解动机（而非有意留白或后续章节揭示），请结合 P021 跳跃叙事'
        '/ P016 情节巧合的判断原则提示学员，温和指出事件位置与缺位的前因（只定位，不代改正文）。\n\n'
        '- 第5章「阿禾决定去金陵」（决定类）缺触发事件'
        '（原文：「第5章，阿禾决定去金陵」）',
      );
    });

    test('buildSubplotClosureContext：两条输出（含共 N 条汇总行）逐字节一致', () {
      final ctx = buildSubplotClosureContext([
        UnclosedSubplotObservation(
          name: '钥匙的秘密',
          introducedChapter: 3,
          currentChapter: 12,
          description: '第3章引入的支线「钥匙的秘密」至今（第12章）未回收',
          excerpt: '钥匙的秘密始终没有下文',
        ),
        UnclosedSubplotObservation(
          name: '断剑之谜',
          introducedChapter: 5,
          currentChapter: 15,
          description: '第5章引入的支线「断剑之谜」至今（第15章）未回收',
          excerpt: '那柄断剑再也没有出现',
        ),
      ]);
      expect(
        ctx,
        '## 情节闭环观察（F11 补充）\n\n'
        '以下是作品中已引入多章但至今未回收的支线。若这些支线并非有意留待后续收束，'
        '请结合 P014 结尾仓促 / P017 伏笔埋设回收问题的判断原则提示学员，'
        '温和指出各支线的引入位置与未回收现状（只定位，不代改正文）。\n\n'
        '- 第3章引入的支线「钥匙的秘密」至今（第12章）未回收'
        '（原文：「钥匙的秘密始终没有下文」）\n'
        '- 第5章引入的支线「断剑之谜」至今（第15章）未回收'
        '（原文：「那柄断剑再也没有出现」）'
        '\n\n共 2 条支线收束滞后。',
      );
    });
  });

  group('S2：观察段两级预算接入（R3/R4）', () {
    ConflictObservation _conflict(int i, {int excerptLen = 10}) =>
        ConflictObservation(
          characterName: '角色${i.toString().padLeft(2, '0')}',
          attribute: '性情',
          orderedValues: _pair('性情', '冷静', '暴烈'),
          description: '第1章「冷静」→ 第9章「暴烈」（样本$i）',
          excerpt: '摘录${'字' * excerptLen}$i',
        );

    WorldConflictObservation _worldShort(int i) =>
        _world('灵气体系${i.toString().padLeft(2, '0')}', '短依据$i');

    test('R3-AC1/AC2：20 条 character 观察 → 恰 12 条注入 + 提示「另有 8 条」', () {
      final ctx = buildConflictObservationsContext(
        List.generate(20, _conflict),
      )!;
      final keptLines = ctx.split('\n').where((l) => l.startsWith('- '));
      expect(keptLines, hasLength(ContextBudget.observationMaxItems));
      // 条数上限砍尾（Q3 甲）：字典序前 12 条保留，尾部被裁
      expect(ctx, contains('- 角色01「性情」'));
      expect(ctx, isNot(contains('- 角色13「性情」')));
      // 知情截断：提示数 == 实际丢弃数（20 − 12）
      expect(ctx, contains('另有 8 条观察未列出'));
    });

    test('R3：world 观察 14 条 → 12 条 + 「另有 2 条」', () {
      final ctx = buildWorldSettingObservationsContext(
        List.generate(14, _worldShort),
      )!;
      final keptLines = ctx.split('\n').where((l) => l.startsWith('- '));
      expect(keptLines, hasLength(12));
      expect(ctx, contains('另有 2 条观察未列出'));
    });

    test('R4-AC3 叠加态：条数砍尾后字符预算继续生效（causality 长摘录）', () {
      final ctx = buildCausalityBreakContext(
        List.generate(15, (i) {
          return CausalityBreakObservation(
            name: '事件$i',
            chapter: i + 2,
            eventType: '转折',
            description: '第${i + 2}章「事件$i」（转折类）缺触发事件（样本$i）',
            excerpt: '字' * 130,
          );
        }),
      )!;
      final keptLines = ctx
          .split('\n')
          .where((l) => l.startsWith('- '))
          .toList();
      // 15 条触发条数砍尾；长摘录使单行 ~190 chars，字符预算在 12 条前
      // 即耗尽 → kept 行数必须 < 12（叠加生效的证据）
      expect(keptLines.length, lessThan(12));
      expect(keptLines, isNotEmpty);
      // R4-AC1（可变行口径）：保留行总字符 ≤ 段级预算
      expect(
        keptLines.join('\n').length,
        lessThanOrEqualTo(ContextBudget.observationSectionBudgetChars),
      );
      expect(ctx, contains('### 观察截断提示'));
    });

    test('R3：subplot 14 条 → 12 条；summary 仍报全部 14 条 + 提示互补', () {
      final ctx = buildSubplotClosureContext(
        List.generate(14, (i) {
          return UnclosedSubplotObservation(
            name: '支线${i.toString().padLeft(2, '0')}',
            introducedChapter: i + 1,
            currentChapter: i + 12,
            description: '第${i + 1}章引入的支线「支线$i」至今未回收',
            excerpt: '短摘录$i',
          );
        }),
      )!;
      final keptLines = ctx.split('\n').where((l) => l.startsWith('- '));
      expect(keptLines, hasLength(12));
      expect(ctx, contains('共 14 条支线收束滞后'));
      expect(ctx, contains('另有 2 条观察未列出'));
    });

    test('防御：单条观察行即超字符预算 → 整段降级为 null（等效无观察）', () {
      final ctx = buildConflictObservationsContext([
        ConflictObservation(
          characterName: '角色超长',
          attribute: '性情',
          orderedValues: _pair('性情', '冷静', '暴烈'),
          description: '描' * 1000,
          excerpt: '摘录',
        ),
      ]);
      expect(ctx, isNull);
    });
  });
}
