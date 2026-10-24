// ─────────────────────────────────────────────────────────────
// C127 批：工程借鉴 B 形态落地内容存在性测试（P018 字样清理同步收口）
//
// 本测试断言 C125/C127 批「工程借鉴 B」新增的知识勾检内容确实落入了
// 症候正文 / 训练知识 / 技能注册表三处注入资产，防止后续重构误删。
// 风格镜像 p018_p034_boundary_test.dart。
//
// 覆盖：
//   1. P003 正文含「时点幻觉四分类」「QF130」
//   2. P015 正文含「崩塌根因二分」「QF131」「行为假设核验」
//   3. P016 正文含「场景四要素判据」「章际衔接人工三问」「QF100_C1」
//   4. P023 正文含「证据核验式诊断」「ATLAS」「RoleFact」「信息穿帮四分类」
//   5. P016 训练知识含「四要素换场自检」；P020 训练知识含「全书多维度回头自评」
//   6. 技能注册表 reader-awareness 含「读者反应复述的忠实性自查」
//   7. 守卫：P018 oneLine/trainingLine 不含「指代混乱/指代不清」，
//      P034 name 仍为「代词指代不清/零回指过载」（防回归/防误删）
//   8. C125 项 7/8 延后项施工（2026-10-22 · T-20261014-16 序 6）：
//      P023 训练知识含「时间线自查」+ 节点漏/边漏/跨轴混淆三信号；
//      P027 训练知识含「事件显著性删句测试」+ 承重墙双向判读。
//      两条诚实标注（不自动判矛盾 / 不自动评分）同步断言——
//      防「补内容时把 R-009 边界注记删掉」。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/syndrome_knowledge_base.dart';
import 'package:writingcoach/services/training_knowledge_base.dart';
import 'package:writingcoach/services/skill_registry.dart';
import 'package:writingcoach/services/syndrome_registry.dart';

void main() {
  group('C127 工程借鉴 B · 症候正文勾检标记存在性', () {
    test('#1 P003 正文含时点幻觉四分类 + QF130', () {
      final content = getSyndromeContent(['P003']);
      expect(content, contains('时点幻觉四分类'));
      expect(content, contains('QF130'));
    });

    test('#2 P015 正文含崩塌根因二分 + QF131 + 行为假设核验', () {
      final content = getSyndromeContent(['P015']);
      expect(content, contains('崩塌根因二分'));
      expect(content, contains('QF131'));
      expect(content, contains('行为假设核验'));
    });

    test('#3 P016 正文含场景四要素判据 + 章际衔接人工三问 + QF100_C1', () {
      final content = getSyndromeContent(['P016']);
      expect(content, contains('场景四要素判据'));
      expect(content, contains('章际衔接人工三问'));
      expect(content, contains('QF100_C1'));
    });

    test('#4 P023 正文含证据核验式诊断 + ATLAS + RoleFact + 信息穿帮四分类', () {
      final content = getSyndromeContent(['P023']);
      expect(content, contains('证据核验式诊断'));
      expect(content, contains('ATLAS'));
      expect(content, contains('RoleFact'));
      expect(content, contains('信息穿帮四分类'));
    });
  });

  group('C127 工程借鉴 B · 训练知识标记存在性', () {
    test('#5 P016 训练知识含四要素换场自检', () {
      final content = getTrainingContent(['P016']);
      expect(content, contains('四要素换场自检'));
    });

    test('#6 P020 训练知识含全书多维度回头自评', () {
      final content = getTrainingContent(['P020']);
      expect(content, contains('全书多维度回头自评'));
    });
  });

  group('C127 工程借鉴 B · 技能注册表标记存在性', () {
    test('#7 reader-awareness 技能含读者反应复述的忠实性自查', () {
      final skill = skillRegistry['reader-awareness'];
      expect(skill, isNotNull);
      expect(skill!.content, contains('读者反应复述的忠实性自查'));
    });
  });

  group('C127 P018 字样清理 · 守卫断言（防回归/防误删）', () {
    test('#8 P018 oneLine 不含「指代混乱」、trainingLine 不含「指代不清」', () {
      final p018 = syndromeRecordOf('P018');
      expect(p018, isNotNull);
      expect(p018!.oneLine, isNot(contains('指代混乱')));
      expect(p018.trainingLine, isNot(contains('指代不清')));
    });

    test('#9 P034 name 仍为「代词指代不清/零回指过载」（未被误删/误改）', () {
      final p034 = syndromeRecordOf('P034');
      expect(p034, isNotNull);
      expect(p034!.name, '代词指代不清/零回指过载');
    });
  });

  group('C125 项 7/8 延后项施工 · 训练知识标记存在性（T-20261014-16 序 6）', () {
    test('#10 P023 训练知识含时间线自查 + 三类信号 + 不自动判矛盾标注', () {
      final content = getTrainingContent(['P023']);
      expect(content, contains('时间线自查'));
      expect(content, contains('节点漏'));
      expect(content, contains('边漏'));
      expect(content, contains('跨轴混淆'));
      expect(content, contains('不自动判矛盾'));
    });

    test('#11 P027 训练知识含事件显著性删句测试 + 承重墙双向判读 + 不自动评分标注', () {
      final content = getTrainingContent(['P027']);
      expect(content, contains('事件显著性删句测试'));
      expect(content, contains('承重墙'));
      expect(content, contains('P039 删段测试'));
      expect(content, contains('不自动评分'));
    });
  });
}
