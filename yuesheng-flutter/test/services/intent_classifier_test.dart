// ─────────────────────────────────────────────────────────────
// intent_classifier_test — 交互意图分类器单测（批次63 B62b）
//
// 覆盖：
//   classifyUserIntent:
//     1. 短句闲聊 → smalltalk（你好/谢谢/在吗）
//     2. 长句含社交词 → 不误判闲聊（"谢谢你的建议，我修改了这段"→ revise）
//     3. 疑问句 → ask（怎么/为什么/？）
//     4. 请求分析 → ask
//     5. 修改动作 → revise（改成/重写/删掉）
//     6. 创作内容 → compose（默认）
//     7. 空串 → compose
//     8. ask 优先于 revise（"这段怎么改更好" → ask）
//   buildIntentInstruction:
//     9. compose → null（不注入）
//     10. smalltalk/ask/revise → 有注入文本且含最近意图序列
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/intent_classifier.dart';

void main() {
  group('classifyUserIntent', () {
    test('#1 短句闲聊 → smalltalk', () {
      expect(classifyUserIntent('你好'), UserIntent.smalltalk);
      expect(classifyUserIntent('谢谢老师'), UserIntent.smalltalk);
      expect(classifyUserIntent('在吗'), UserIntent.smalltalk);
      expect(classifyUserIntent('好的，明白'), UserIntent.smalltalk);
    });

    test('#2 长句含社交词 → 不误判闲聊', () {
      // 超过 kSmalltalkMaxLength（20 字），社交词不生效 → 命中修改 → revise
      expect(
        classifyUserIntent('谢谢你的建议，我修改了这段对话，把动作描写加进去了'),
        UserIntent.revise,
      );
    });

    test('#3 疑问句 → ask', () {
      expect(classifyUserIntent('这段怎么改更好'), UserIntent.ask);
      expect(classifyUserIntent('为什么我的角色会出戏？'), UserIntent.ask);
      expect(classifyUserIntent('你觉得这个开头怎么样'), UserIntent.ask);
      expect(classifyUserIntent('如何营造紧张感'), UserIntent.ask);
    });

    test('#4 请求分析 → ask', () {
      expect(classifyUserIntent('帮我分析一下这段对话'), UserIntent.ask);
      expect(classifyUserIntent('教我什么是潜台词'), UserIntent.ask);
    });

    test('#5 修改动作 → revise', () {
      expect(classifyUserIntent('把这段改成动作描写'), UserIntent.revise);
      expect(classifyUserIntent('这一段我想重写'), UserIntent.revise);
      expect(classifyUserIntent('删掉这句话'), UserIntent.revise);
      expect(classifyUserIntent('帮我润色一下这个段落'), UserIntent.revise);
    });

    test('#6 创作内容 → compose（默认）', () {
      expect(classifyUserIntent('他推开门，风灌了进来'), UserIntent.compose);
      expect(classifyUserIntent('继续写下一章'), UserIntent.compose);
      expect(classifyUserIntent('今天想写一个关于重逢的故事'), UserIntent.compose);
    });

    test('#7 空串 → compose', () {
      expect(classifyUserIntent(''), UserIntent.compose);
      expect(classifyUserIntent('   '), UserIntent.compose);
    });

    test('#8 ask 优先于 revise（"这段怎么改更好" → ask）', () {
      // 含"怎么改"（ask 信号）与"改"（revise 动作），应判为询问而非修改
      expect(classifyUserIntent('这段怎么改更好'), UserIntent.ask);
    });

    test('#9 批次4（4.7 O3）：社交词短句含实质疑问 → ask（不吞为闲聊）', () {
      // "谢谢，你觉得我今天写得怎么样" 含社交词（谢谢）但实为教学提问
      expect(classifyUserIntent('谢谢，你觉得我今天写得怎么样'), UserIntent.ask);
      expect(classifyUserIntent('好的，那这个开头你觉得怎么样？'), UserIntent.ask);
    });

    test('#10 批次4（4.7 O3）：社交词短句含修改信号 → revise', () {
      expect(classifyUserIntent('谢谢，我改成动作描写试试'), UserIntent.revise);
    });

    test('#11 批次4（4.7 O3）：纯闲聊短句仍判 smalltalk', () {
      expect(classifyUserIntent('好的，谢谢'), UserIntent.smalltalk);
      expect(classifyUserIntent('老师辛苦了'), UserIntent.smalltalk);
    });

    test('#12 批次4（4.7 O3）：单字疑问词"吗"不触发二次校验', () {
      // "在吗"是闲聊，"你好吗"不是教学提问
      expect(classifyUserIntent('在吗'), UserIntent.smalltalk);
    });
  });

  group('buildIntentInstruction', () {
    test('#9 compose → null（不注入）', () {
      expect(
        buildIntentInstruction(UserIntent.compose, const ['compose']),
        isNull,
      );
    });

    test('#10 smalltalk → 注入文本且含最近意图序列', () {
      final note = buildIntentInstruction(UserIntent.smalltalk, const [
        'compose',
        'ask',
      ]);
      expect(note, isNotNull);
      expect(note, contains('闲聊'));
      expect(note, contains('不要发起诊断'));
      expect(note, contains('compose → ask'));
    });

    test('#11 ask → 注入文本', () {
      final note = buildIntentInstruction(UserIntent.ask, const []);
      expect(note, isNotNull);
      expect(note, contains('提问'));
      expect(note, contains('不要展开新的诊断'));
    });

    test('#12 revise → 注入文本（降诊断强度 + 不替写）', () {
      final note = buildIntentInstruction(UserIntent.revise, const []);
      expect(note, isNotNull);
      expect(note, contains('修改'));
      expect(note, contains('只提示最关键的问题'));
      expect(note, contains('不替学员改写正文'));
    });
  });

  group('UserIntent.fromValue', () {
    test('#13 非法值 → compose 兜底', () {
      expect(UserIntent.fromValue('unknown'), UserIntent.compose);
      expect(UserIntent.fromValue(null), UserIntent.compose);
      expect(UserIntent.fromValue('revise'), UserIntent.revise);
    });
  });

  group('detectReplyDetail', () {
    test('#14 压缩信号 → concise', () {
      expect(detectReplyDetail('长话短说'), ReplyDetail.concise);
      expect(detectReplyDetail('简单点，别太啰嗦'), ReplyDetail.concise);
      expect(detectReplyDetail('就说重点'), ReplyDetail.concise);
      expect(detectReplyDetail('能一句话说完吗'), ReplyDetail.concise);
    });

    test('#15 展开信号 → detailed', () {
      expect(detectReplyDetail('详细点'), ReplyDetail.detailed);
      expect(detectReplyDetail('再详细讲讲这个技巧'), ReplyDetail.detailed);
      expect(detectReplyDetail('能展开说吗'), ReplyDetail.detailed);
      expect(detectReplyDetail('具体点，我想听完整示范'), ReplyDetail.detailed);
    });

    test('#16 无信号 → standard（默认）', () {
      expect(detectReplyDetail('帮我分析这段'), ReplyDetail.standard);
      expect(detectReplyDetail(''), ReplyDetail.standard);
      expect(detectReplyDetail('   '), ReplyDetail.standard);
    });

    test('#17 压缩信号优先于展开信号', () {
      // "长话短说"（压缩）先命中，即使后文含"详细"
      expect(detectReplyDetail('长话短说，但再详细点'), ReplyDetail.concise);
    });
  });

  group('buildReplyDetailInstruction', () {
    test('#18 standard → null（不注入）', () {
      expect(buildReplyDetailInstruction(ReplyDetail.standard), isNull);
    });

    test('#19 concise → 压缩约束（一句话结论 + 极短示范）', () {
      final note = buildReplyDetailInstruction(ReplyDetail.concise);
      expect(note, isNotNull);
      expect(note, contains('压缩'));
      expect(note, contains('一句话结论'));
      expect(note, contains('删除一切铺垫'));
    });

    test('#20 detailed → 展开约束（完整示范 + 保持单焦点）', () {
      final note = buildReplyDetailInstruction(ReplyDetail.detailed);
      expect(note, isNotNull);
      expect(note, contains('展开'));
      expect(note, contains('完整示范'));
      expect(note, contains('一次一个焦点'));
    });
  });

  group('ReplyDetail.fromValue', () {
    test('#21 非法值 → standard 兜底', () {
      expect(ReplyDetail.fromValue('unknown'), ReplyDetail.standard);
      expect(ReplyDetail.fromValue(null), ReplyDetail.standard);
      expect(ReplyDetail.fromValue('concise'), ReplyDetail.concise);
      expect(ReplyDetail.fromValue('detailed'), ReplyDetail.detailed);
    });
  });
}
