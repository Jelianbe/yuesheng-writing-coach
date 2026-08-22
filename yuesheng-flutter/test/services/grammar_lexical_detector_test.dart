// ─────────────────────────────────────────────────────────────
// grammar_lexical_detector_test — 批次70 F12 文法与重复用词检测单元测试
//
// 覆盖：
//   1. 空输入 → 空数组
//   2. 相邻重复虚词（的了了/他他）→ 观察项
//   3. 实词叠词（人人/天天）不误报
//   4. 连续重复标点（。。/，，）→ 观察项
//   5. 连续多句同一词起头（≥3 句）→ 观察项
//   6. 短文本（<200 字）高频词不判定（避免误报）
//   7. 长文本高频连接词（≥3 次）→ 观察项
//   8. buildGrammarLexicalContext：空 → null
//   9. buildGrammarLexicalContext：非空 → 含观察与措辞
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/chat_context_builder.dart';
import 'package:writingcoach/services/grammar_lexical_detector.dart';

void main() {
  test('#1 空输入 → 空数组', () {
    expect(detectGrammarLexicalIssues(''), isEmpty);
    expect(detectGrammarLexicalIssues('   '), isEmpty);
  });

  test('#2 相邻重复虚词 → 观察项', () {
    final result = detectGrammarLexicalIssues('他的了了，心里很不是滋味。');
    expect(result, isNotEmpty);
    final dup = result.firstWhere((i) => i.kind == GrammarIssueKind.dupChar);
    expect(dup.description, '相邻重复字「了」');
    expect(dup.evidence, contains('了了'));
  });

  test('#3 实词叠词（人人/天天）不误报', () {
    final result = detectGrammarLexicalIssues('人人都在努力，天天都有进步。');
    expect(
      result.where((i) => i.kind == GrammarIssueKind.dupChar),
      isEmpty,
      reason: '实词叠词是合法表达，不检测',
    );
  });

  test('#4 连续重复标点 → 观察项', () {
    final result = detectGrammarLexicalIssues('他沉默了很久。。然后转身离开，，');
    final puncts = result
        .where((i) => i.kind == GrammarIssueKind.dupPunct)
        .toList();
    expect(puncts, isNotEmpty);
    expect(puncts.first.description, contains('连续重复标点'));
  });

  test('#5 连续多句同一词起头 → 观察项', () {
    const text = '忽然他站起来。忽然又坐下。忽然把桌上的信揉成一团。他这才看向窗外。';
    final result = detectGrammarLexicalIssues(text);
    final repeat = result.firstWhere(
      (i) => i.kind == GrammarIssueKind.sentenceStartRepeat,
    );
    expect(repeat.description, '连续 3 句以「忽然」开头');
    expect(repeat.evidence, contains('忽然他站起来'));
  });

  test('#6 短文本（<200 字）高频词不判定（避免误报）', () {
    // 180 字文本中「然后」出现多次，但低于 200 字阈值 → 不判定
    final text = '然后走。' * 45;
    final result = detectGrammarLexicalIssues(text);
    expect(
      result.where((i) => i.kind == GrammarIssueKind.frequentWord),
      isEmpty,
    );
  });

  test('#7 长文本高频连接词（≥3 次）→ 观察项', () {
    // 构造 ≥200 字且「然后」出现 ≥3 次
    final filler = '他穿过空荡荡的街道，看着昏黄的路灯一盏盏亮起，远处的山影在暮色里渐渐模糊。';
    final text =
        '然后他走进巷子。然后他停在门前。然后他敲了敲门。'
        '$filler$filler$filler$filler$filler';
    expect(text.length, greaterThanOrEqualTo(200));
    final result = detectGrammarLexicalIssues(text);
    final freq = result.where((i) => i.kind == GrammarIssueKind.frequentWord);
    expect(freq, isNotEmpty);
    expect(freq.first.description, contains('「然后」出现'));
  });

  test('#8 buildGrammarLexicalContext 空 → null', () {
    expect(buildGrammarLexicalContext(const []), isNull);
  });

  test('#9 buildGrammarLexicalContext 非空 → 含观察与措辞', () {
    final issues = detectGrammarLexicalIssues('他沉默了很久。。');
    expect(issues, isNotEmpty);

    final ctx = buildGrammarLexicalContext(issues);
    expect(ctx, isNotNull);
    expect(ctx, contains('基础文法观察'));
    expect(ctx, contains('P022'));
    expect(ctx, contains('只定位，不代改正文'));
  });
}
