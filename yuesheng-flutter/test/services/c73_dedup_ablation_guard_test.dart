// ─────────────────────────────────────────────────────────────
// ADR-C73 护栏：消融 A 族 + 重叠方案 A
//
// 断言三类不变量：
// ① 正典指针存在（§5.3/§7.3/§六/反馈要点 引用形态）；
// ② 重复句式消失（旧副本的逐字句不得回流）；
// ③ 模式特有内容仍在（削重复不削语义）。
// ─────────────────────────────────────────────────────────────
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/skill_registry.dart';

void main() {
  final teachingStrategy = skillRegistry['teaching-strategy']!.content;
  final coachingRhythm = skillRegistry['coaching-rhythm']!.content;
  final feedbackCognition = skillRegistry['feedback-cognition']!.content;
  final phaseMapper = skillRegistry['phase-mapper']!.content;

  group('ADR-C73 · A4/O-1 训练完成后正典收编', () {
    test('§5.3 与 §7.3 均指向 phase-mapper 正典', () {
      expect(coachingRhythm, contains('正典见 L1 常驻层 phase-mapper「反馈要点」'));
      expect(feedbackCognition, contains('正典见 phase-mapper「反馈要点」'));
      expect(
        feedbackCognition,
        contains('正典在 phase-mapper「反馈要点」（L1 常驻，ADR-C73）'),
      );
    });

    test('旧的两件事编号副本不再回流', () {
      // 旧 §5.3 / §7.3 的「1. 和之前那一稿比…2. 接下来还可以看什么」编号列表形态
      expect(coachingRhythm, isNot(contains('1. 和之前那一稿比')));
      expect(feedbackCognition, isNot(contains('1. 和之前那一稿比')));
      // 正典本体仍在 phase-mapper
      expect(phaseMapper, contains('训练完成后**：讲清"和之前比，这次哪里不一样了"'));
    });
  });

  group('ADR-C73 · A3 核心要求去重', () {
    test('§5.4 / §7.4 均为指针 + 各自保留模式特有条目', () {
      expect(coachingRhythm, contains('见\nphase-mapper P2 子阶段「核心要求」'));
      expect(coachingRhythm, contains('beginner 语境补充'));
      expect(coachingRhythm, contains('我不想练这个方向'));
      expect(feedbackCognition, contains('同 phase-mapper P2 子阶段「核心要求」'));
    });

    test('旧的重复四条逐字句消失（正典 phase-mapper 不受影响）', () {
      expect(feedbackCognition, isNot(contains('不评分、不贴标签（只描述、不评判）')));
      expect(coachingRhythm, isNot(contains('不评分、不贴标签（"你这个是中等水平"）')));
      expect(coachingRhythm, isNot(contains('不暴露症候/动作/技法编号')));
      // 正典仍在
      expect(phaseMapper, contains('不评分、不贴标签（只描述、不评判）'));
    });
  });

  group('ADR-C73 · O-4 悬空引用修复', () {
    test('§5.5 红线自含，不再指向未注入的 §7.5', () {
      expect(coachingRhythm, isNot(contains('同 feedback-cognition §7.5')));
      expect(coachingRhythm, contains('不虚构任何群体/同侪数据'));
      expect(coachingRhythm, contains('只谈学员自身的相对变化'));
      // §7.5 本体（diagnosis 组）不受影响
      expect(feedbackCognition, contains('不虚构任何群体/同侪数据'));
    });
  });

  group('ADR-C73 · A1 用户分层双表合并', () {
    test('§3.3 吸收诊断重点列，§五 整节删除', () {
      expect(teachingStrategy, contains('| 用户类型 | 教学重点 | 语气 | 诊断重点 |'));
      expect(teachingStrategy, contains('原「§五 学员分层」表已并入本表'));
      expect(teachingStrategy, isNot(contains('## 五、学员分层')));
      // 识别信号随迁且仅一份
      expect('识别信号（判断是否进阶及以上）'.allMatches(teachingStrategy).length, 1);
      expect(teachingStrategy, isNot(contains('识别信号：主动展示未发布作品')));
    });
  });

  group('ADR-C73 · O-2 分工表矛盾修复 + 反馈要点指针自含', () {
    test('§六 分工表与 §5.3 同向', () {
      expect(coachingRhythm, contains('训练完成后反馈正典在 phase-mapper「反馈要点」'));
    });

    test('phase-mapper 语气参考注明加载组，未加载语境有自行组织指令', () {
      expect(phaseMapper, contains('beginner / diagnosis 组加载'));
      expect(phaseMapper, contains('仅 diagnosis 组加载'));
      expect(phaseMapper, contains('按本节要点自行组织语言即可'));
    });
  });
}
