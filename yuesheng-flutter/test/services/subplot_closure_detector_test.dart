// ─────────────────────────────────────────────────────────────
// subplot_closure_detector_test — 批次67 B62j F11 情节闭环检测单元测试
//
// 覆盖：
//   1. 空输入 → 空数组
//   2. 未回收且超阈值（>=3章）→ 情节闭环观察项
//   3. 已回收 → 不误报
//   4. 未到阈值（<3章）→ 不误报（留回收空间）
//   5. 无引入章节 → 保守跳过
//   6. 多条 → 按引入章节升序输出
//   7. buildSubplotClosureContext：空 → null
//   8. buildSubplotClosureContext：非空 → 含观察、措辞与汇总
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/chat_context_builder.dart';
import 'package:writingcoach/services/subplot_closure_detector.dart';

void main() {
  test('#1 空输入 → 空数组', () {
    expect(detectUnclosedSubplots(const [], currentChapter: 12), isEmpty);
  });

  test('#2 未回收且超阈值（>=3章）→ 情节闭环观察项', () {
    final result = detectUnclosedSubplots([
      (name: '钥匙的秘密', introducedChapter: 3, resolvedChapter: null),
    ], currentChapter: 12);

    expect(result.length, 1);
    final obs = result.first;
    expect(obs.name, '钥匙的秘密');
    expect(obs.introducedChapter, 3);
    expect(obs.currentChapter, 12);
    expect(obs.description, '第3章引入的支线「钥匙的秘密」至今（第12章）未回收');
  });

  test('#3 已回收 → 不误报', () {
    final result = detectUnclosedSubplots([
      (name: '钥匙的秘密', introducedChapter: 3, resolvedChapter: 8),
    ], currentChapter: 12);

    expect(result, isEmpty);
  });

  test('#4 未到阈值（<3章）→ 不误报（留回收空间）', () {
    final result = detectUnclosedSubplots([
      (name: '新支线', introducedChapter: 11, resolvedChapter: null),
    ], currentChapter: 12);

    expect(result, isEmpty, reason: '引入不足3章，不判定收束滞后');
  });

  test('#5 无引入章节 → 保守跳过', () {
    final result = detectUnclosedSubplots([
      (name: '无锚点支线', introducedChapter: null, resolvedChapter: null),
    ], currentChapter: 12);

    expect(result, isEmpty, reason: '无时间锚点，无法判定收束滞后');
  });

  test('#6 多条 → 按引入章节升序输出', () {
    final result = detectUnclosedSubplots([
      (name: '后来的支线', introducedChapter: 10, resolvedChapter: null),
      (name: '早先的支线', introducedChapter: 2, resolvedChapter: null),
    ], currentChapter: 15);

    expect(result.length, 2);
    expect(result.first.name, '早先的支线');
    expect(result.first.description, '第2章引入的支线「早先的支线」至今（第15章）未回收');
    expect(result.last.name, '后来的支线');
  });

  test('#7 buildSubplotClosureContext 空 → null', () {
    expect(buildSubplotClosureContext(const []), isNull);
  });

  test('#8 buildSubplotClosureContext 非空 → 含观察、措辞与汇总', () {
    final observations = detectUnclosedSubplots([
      (name: '钥匙的秘密', introducedChapter: 3, resolvedChapter: null),
      (name: '妹妹的身世', introducedChapter: 5, resolvedChapter: null),
    ], currentChapter: 12);

    final ctx = buildSubplotClosureContext(observations);
    expect(ctx, isNotNull);
    expect(ctx, contains('情节闭环观察'));
    expect(ctx, contains('第3章引入的支线「钥匙的秘密」至今（第12章）未回收'));
    expect(ctx, contains('P014'));
    expect(ctx, contains('共 2 条支线收束滞后'));
  });
}
