// ─────────────────────────────────────────────────────────────
// chat_context_builder_participating_test — 「其他」注入纯函数（第二批）
//
// buildParticipatingSettingsContext：勾选条目 → 诊断上下文。
// 覆盖：空输入 null / 正常渲染 / 正文截断 120 字 / 5 条封顶 + 截断提示 /
// 空类别降级「未分类」/ 空正文降级。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/chat_context_builder.dart';

void main() {
  test('#1 空输入 → null（零注入）', () {
    expect(buildParticipatingSettingsContext(const []), isNull);
  });

  test('#2 正常渲染：类别 + 名称 + 正文', () {
    final ctx = buildParticipatingSettingsContext(const [
      (category: '武器', name: '血月刃', description: '以血养刃，月圆时锋锐倍增。'),
    ]);
    expect(ctx, isNotNull);
    expect(ctx, contains('武器'));
    expect(ctx, contains('血月刃'));
    expect(ctx, contains('以血养刃'));
    expect(ctx, contains('用户勾选参与诊断'));
  });

  test('#3 正文超过 120 字 → 截断带省略号', () {
    final long = '长' * 300;
    final ctx = buildParticipatingSettingsContext([
      (category: '规则', name: '镜中人', description: long),
    ]);
    expect(ctx, isNotNull);
    expect(ctx!.length, lessThan(300 + 200), reason: '不得整段透传超长正文');
    expect(ctx, contains('…'));
  });

  test('#4 超过 5 条 → 只注入前 5 + 截断提示', () {
    final entries = List.generate(
      7,
      (i) => (category: '类别$i', name: '条目$i', description: '内容$i'),
    );
    final ctx = buildParticipatingSettingsContext(entries);
    expect(ctx, isNotNull);
    expect(ctx, contains('条目4'));
    expect(ctx, isNot(contains('条目5')), reason: '第 6 条不注入');
    expect(ctx, contains('另有 2 条勾选条目未注入'));
  });

  test('#5 空类别 → 降级「未分类」；空正文 → 占位', () {
    final ctx = buildParticipatingSettingsContext(const [
      (category: '', name: '无名设定', description: ''),
    ]);
    expect(ctx, isNotNull);
    expect(ctx, contains('未分类'));
    expect(ctx, contains('未填写正文'));
  });
}
