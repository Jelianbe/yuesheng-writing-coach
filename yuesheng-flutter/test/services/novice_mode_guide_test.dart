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
    test('三字段都给了 → 完整', () {
      expect(isNoviceAnswerComplete('刚开始写，想提升情节，喜欢先理解再练'), isTrue);
    });

    test('只有偏好命中 → 也完整（proficiency 有兜底值）', () {
      expect(isNoviceAnswerComplete('我想多练少讲'), isTrue);
    });

    test('只有方向命中 → 完整', () {
      expect(isNoviceAnswerComplete('想提升人物塑造'), isTrue);
    });

    test('空文本 → 不完整', () {
      expect(isNoviceAnswerComplete(''), isFalse);
      expect(isNoviceAnswerComplete('   '), isFalse);
    });

    test('「不知道」类回复 → 不完整（不放行）', () {
      expect(isNoviceAnswerComplete('不知道'), isFalse);
      expect(isNoviceAnswerComplete('没想过，随便吧'), isFalse);
      expect(isNoviceAnswerComplete('跳过'), isFalse);
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
