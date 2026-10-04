// ─────────────────────────────────────────────────────────────
// novice_mode_guide_test — 纯新手模式本地解析器单元测试（ADR-C122）
//
// 覆盖：parseProficiency（四档）/ parseFocusAreas（多选）/
// parseCognitiveStyle（三型）/ isNoviceAnswerComplete（完成判据）/
// buildNoviceOnboardingData（落库字段）/ isBeginnerGuide（分支判定）
//
// R-009 相关：本测试只验「解析 + 组装」，不生成任何写作内容。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/features/onboarding/novice_mode_guide.dart';
import 'package:writingcoach/types/teaching_types.dart';

void main() {
  group('parseProficiency', () {
    test('advanced：完整作品/长篇/熟练', () {
      expect(parseProficiency('我有完整作品，写过长篇'), ProficiencyLevel.advanced);
      expect(parseProficiency('熟练老手'), ProficiencyLevel.advanced);
      expect(parseProficiency('能写完整场景'), ProficiencyLevel.advanced);
    });

    test('intermediate：写到一半/中篇/卡在中段', () {
      expect(parseProficiency('写到一半，卡在中段'), ProficiencyLevel.intermediate);
      expect(parseProficiency('写过中篇'), ProficiencyLevel.intermediate);
    });

    test('elementary：写过片段/短篇/写不出来', () {
      expect(parseProficiency('写过一些片段'), ProficiencyLevel.elementary);
      expect(parseProficiency('短篇勉强能写'), ProficiencyLevel.elementary);
    });

    test('未命中 → beginner 兜底（新手上路）', () {
      expect(parseProficiency('我完全没写过'), ProficiencyLevel.beginner);
      expect(parseProficiency('刚开始想试试'), ProficiencyLevel.beginner);
    });

    // ★ 2026-10-04 新增：首条消息已改成只问「你之前有写作基础吗？」，
    // 学员最可能给的是**否定式**回答。原词表全是肯定式信号，
    // 否定回答靠 beginner 兜底「碰巧对」——但「有点基础但没写过完整小说」
    // 会被原表误判 beginner（该给 elementary）。这两条钉住新词表。
    group('否定式回答（2026-10-04 首条消息配套）', () {
      test('明确零基础 → beginner', () {
        expect(parseProficiency('没有'), ProficiencyLevel.beginner);
        expect(parseProficiency('没写过'), ProficiencyLevel.beginner);
        expect(parseProficiency('零基础'), ProficiencyLevel.beginner);
        expect(parseProficiency('完全没碰过'), ProficiencyLevel.beginner);
      });

      test('「没写过」+「基础」并存时，否定优先（不能被「基础」字面量抓走）', () {
        // 顺序判据：否定组必须先判。原实现若把 '有基础' 放在否定之前，
        // 这条会落到 elementary —— 而学员说的是「没写过完整小说」，
        // 语义上更接近 beginner/elementary 边界，但**否定优先**是我们
        // 明写的设计（见 novice_mode_guide.parseProficiency 注释①）。
        expect(parseProficiency('没写过完整小说'), ProficiencyLevel.beginner);
      });

      test('「有点基础」但无作品 → elementary（不是 beginner）', () {
        expect(parseProficiency('有点基础，写过一些'), ProficiencyLevel.elementary);
        expect(parseProficiency('有一些基础'), ProficiencyLevel.elementary);
      });
    });
  });

  group('parseFocusAreas', () {
    test('多选：人物+情节+文笔 各自命中', () {
      final areas = parseFocusAreas('人物塑造和情节设计，还有文笔');
      expect(areas, contains('人物塑造'));
      expect(areas, contains('情节设计'));
      expect(areas, contains('文笔修辞'));
      expect(areas, isNot(contains('世界观构建')));
    });

    test('世界观关键词 → 世界观构建', () {
      expect(parseFocusAreas('想搭世界观设定'), contains('世界观构建'));
    });

    test('未命中 → 空列表', () {
      expect(parseFocusAreas('随便说说'), isEmpty);
    });
  });

  group('parseCognitiveStyle', () {
    test('intuitive：多练少讲/直接写', () {
      expect(parseCognitiveStyle('多练少讲，动手写就行'), CognitiveStyle.intuitive);
    });

    test('analytical：先理解再练', () {
      expect(parseCognitiveStyle('我想先理解道理再练'), CognitiveStyle.analytical);
    });

    test('未命中 → mixed 兜底', () {
      expect(parseCognitiveStyle('不知道怎么说'), CognitiveStyle.mixed);
    });
  });

  group('isNoviceAnswerComplete', () {
    // ★ 2026-10-04 语义变更（甲方案，舰长裁定）：本函数从「三字段是否采齐」
    // 退化为「是否非空」。原断言里 '不知道'/'没想过'/'跳过' 期望false，
    // 那正是舰长反馈的「被强制了，必须全部答完」——**旧断言在保护旧缺陷**，
    // 故随实现同步翻转，不是「改测试迁就实现」。
    // 判据依据：采集是可选的，阻断学习才是问题；且下游画像段
    // student_profile_format.dart:102 是 `if (onboarding == null) return`，
    // 字段缺不缺都不会崩。

    test('任意非空回答 → 放行（不再要求三字段采齐）', () {
      expect(isNoviceAnswerComplete('刚开始写，想提升情节，喜欢先理解再练'), isTrue);
      expect(isNoviceAnswerComplete('我想多练少讲'), isTrue);
      expect(isNoviceAnswerComplete('想提升人物塑造'), isTrue);
      // 只有「有/没有基础」一句（首条消息现在只问这一句）
      expect(isNoviceAnswerComplete('没有'), isTrue);
      expect(isNoviceAnswerComplete('有点基础，写过一些片段'), isTrue);
    });

    test('空文本 → 不放行（唯一仍算不够用的情况）', () {
      expect(isNoviceAnswerComplete(''), isFalse);
      expect(isNoviceAnswerComplete('   '), isFalse);
    });

    test('「不知道」类回复 → **放行**（2026-10-04 翻转：不再追问）', () {
      // 旧期望是 false，配套的是「追问最多 2 轮」的重试机制。
      // 该机制已随kNoviceModeFollowUpMessage 一起 @Deprecated 退役
      // （State 局部计数器归零会导致复读循环）。
      expect(isNoviceAnswerComplete('不知道'), isTrue);
      expect(isNoviceAnswerComplete('没想过，随便吧'), isTrue);
      expect(isNoviceAnswerComplete('跳过'), isTrue);
    });
  });

  group('buildNoviceOnboardingData', () {
    test('字段组装：解析结果 + skipped=false（正式采集）', () {
      final data = buildNoviceOnboardingData('我是新手，想提升文笔和世界观，喜欢边练边讲');
      expect(data.proficiency, ProficiencyLevel.beginner);
      expect(data.focusAreas, containsAll(['文笔修辞', '世界观构建']));
      expect(data.cognitiveStyle, CognitiveStyle.mixed);
      expect(data.writingGoal, '');
      expect(data.skipped, isFalse);
      expect(data.completedAt, greaterThan(0));
    });
  });

  group('isBeginnerGuide', () {
    test('beginner / elementary → 小白分支（低门槛引导）', () {
      expect(isBeginnerGuide(ProficiencyLevel.beginner), isTrue);
      expect(isBeginnerGuide(ProficiencyLevel.elementary), isTrue);
    });

    test('intermediate / advanced → 有基础分支（资料区/直接开写）', () {
      expect(isBeginnerGuide(ProficiencyLevel.intermediate), isFalse);
      expect(isBeginnerGuide(ProficiencyLevel.advanced), isFalse);
    });
  });
}
