// ─────────────────────────────────────────────────────────────
// dialogue_tag_detector_test — 批次71 F02 对话标签过度检测单元测试
//
// 覆盖：
//   1. 空输入 → 空数组
//   2. 无对话文本（纯叙述）→ 空（不误报）
//   3. 同一修饰标签出现 1 次 → 不报（阈值 2）
//   4. 同一修饰标签「低声说」出现 3 次 → 观察项
//   5. 对话行太少（<3 行）→ 不报
//   6. 中性「说/道/应/答」标签多 → 不报（无修饰词根）
//   7. 不同词根修饰标签（低声/轻声/呢喃）→ 不报（词根各异）
//   8. buildDialogueTagContext：空 → null
//   9. buildDialogueTagContext：非空 → 含观察与措辞
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/chat_context_builder.dart';
import 'package:writingcoach/services/dialogue_tag_detector.dart';

void main() {
  test('#1 空输入 → 空数组', () {
    expect(detectDialogueTagIssues(''), isEmpty);
    expect(detectDialogueTagIssues('   '), isEmpty);
  });

  test('#2 无对话文本（纯叙述）→ 空（不误报）', () {
    const text =
        '他沉默地站在窗前，看着夜色一点一点漫上来。远处传来更夫的打更声，'
        '提醒着这座城已经入睡。他转过身，把桌上的信小心折好。';
    expect(detectDialogueTagIssues(text), isEmpty);
  });

  test('#3 同一修饰标签出现 1 次 → 不报（阈值 2）', () {
    const text = '「走吧。」她低声说。「好。」他点了点头。「嗯。」她看了看窗外。';
    final result = detectDialogueTagIssues(text);
    expect(result, isEmpty, reason: '「低声」仅 1 次，低于重复阈值');
  });

  test('#4 同一修饰标签「低声说」出现 3 次 → 观察项', () {
    const text =
        '「我等你很久了。」她低声说。「我也是。」他低声说。「那就好。」她低声说。'
        '他望着窗外的夜色，迟迟没有回答。';
    final result = detectDialogueTagIssues(text);
    final repeats = result
        .where((i) => i.kind == DialogueTagIssueKind.tagRepeat)
        .toList();
    expect(repeats, isNotEmpty);
    expect(repeats.first.description, '「低声」类对话标签出现 3 次');
    expect(repeats.first.evidence, contains('低声说'));
  });

  test('#5 对话行太少（<3 行）→ 不报', () {
    const text = '「走吧。」她低声说。「好。」他低声说。';
    expect(detectDialogueTagIssues(text), isEmpty);
  });

  test('#6 中性「说/道/应/答」标签多 → 不报（无修饰词根）', () {
    const text = '「吃饭了。」他说。「好。」她道。「坐吧。」他应。「谢了。」她答。';
    final result = detectDialogueTagIssues(text);
    expect(result, isEmpty, reason: '中性标签不带修饰词根，不属 F02 关注');
  });

  test('#7 不同词根修饰标签 → 不报（词根各异）', () {
    const text = '「走吧。」她低声说。「好。」他轻声说。「嗯。」她呢喃道。';
    final result = detectDialogueTagIssues(text);
    expect(result, isEmpty, reason: '三种词根各 1 次，无重复');
  });

  test('#8 buildDialogueTagContext 空 → null', () {
    expect(buildDialogueTagContext(const []), isNull);
  });

  test('#9 buildDialogueTagContext 非空 → 含观察与措辞', () {
    const text = '「我等你很久了。」她低声说。「我也是。」他低声说。「那就好。」她低声说。';
    final issues = detectDialogueTagIssues(text);
    expect(issues, isNotEmpty);

    final ctx = buildDialogueTagContext(issues);
    expect(ctx, isNotNull);
    expect(ctx, contains('对话标签观察'));
    expect(ctx, contains('P011'));
    expect(ctx, contains('只定位，不代改正文'));
  });
}
