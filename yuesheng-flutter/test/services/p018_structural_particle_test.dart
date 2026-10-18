// T-20261017-02 批（R-027 批准「都修」2026-10-18）：P018「结构助词误插」形态
// 三面锚定测试。批文锚 = 任务卡 §四 报批表：
//   ① manual_3 触发信号追加「结构助词误插」+ 判断原则豁免（不扩大到的/地混用）
//   ② few-shot 子情形 C 正反例 + 划界提示
//   ③ 首轮注入集 kFirstRoundCriteriaIds 扩容 P018（header 三条→四条）
// 改动批文锚串必须重走 R-027。

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/syndrome_knowledge_base.dart';
import 'package:writingcoach/services/training_few_shot_library.dart';

void main() {
  group('T-20261017-02 · 判据面（manual_3 P018）', () {
    test('#1 触发信号含「结构助词误插」批文锚串', () {
      final c = getSyndromeContent(['P018']);
      expect(c.contains('### P018 重复用词/基础语病'), isTrue);
      expect(c.contains('结构助词误插'), isTrue, reason: '批文锚：触发信号须含新形态');
      expect(c.contains('颇为的明亮'), isTrue, reason: '批文锚：GT 判定依据原文示例');
    });

    test('#2 判断原则含「不扩大到混用」豁免锚串', () {
      final c = getSyndromeContent(['P018']);
      expect(
        c.contains('的/地') && c.contains('单见不计'),
        isTrue,
        reason: '豁免须点名「的/地」状语混用不报（GT 判读者判定线对齐，防过修）',
      );
    });

    test('#3 既有触发信号不回退（A 类四信号 + P034 划界仍在）', () {
      final c = getSyndromeContent(['P018']);
      expect(c.contains('同一字紧邻重复'), isTrue);
      expect(c.contains('连续重复标点'), isTrue);
      expect(c.contains('同一词起头'), isTrue);
      expect(c.contains('高频连接词'), isTrue);
      expect(c.contains('与 P034 的划界'), isTrue, reason: 'C124 反向划界不因本批回退');
    });
  });

  group('T-20261017-02 · few-shot 面（子情形 C）', () {
    test('#4 子情形 C 问题版在场（误插三形态）', () {
      final fs = getTrainingFewShot(['P018']);
      expect(fs.contains('子情形 C'), isTrue, reason: '批文锚：子情形 C 标题');
      expect(fs.contains('颇为的明亮'), isTrue, reason: '批文锚：副词后误插示例');
      expect(fs.contains('慢慢的地'), isTrue, reason: '批文锚：双助词叠用示例');
      expect(fs.contains('被打的叫'), isTrue, reason: '批文锚：的/得错位示例');
    });

    test('#5 划界提示（防扩大到混用类）在场', () {
      final fs = getTrainingFewShot(['P018']);
      expect(
        fs.contains('满怀期待的看着') || fs.contains('乐颠颠儿'),
        isTrue,
        reason: '划界示例须引用判读者声明不标记的原文形态（X01 型），防过修',
      );
    });

    test('#6 改善版 + 既有 A/B 子情形不回退', () {
      final fs = getTrainingFewShot(['P018']);
      expect(fs.contains('颇为明亮'), isTrue, reason: 'C 改善版');
      expect(fs.contains('往事往事'), isTrue, reason: 'A 子情形（机械反复）不回退');
      expect(
        fs.contains('内容稀碎') || fs.contains('子情形 B'),
        isTrue,
        reason: 'B 子情形不回退',
      );
    });
  });

  group('T-20261017-02 · 首轮注入面（注入集扩容）', () {
    test('#7 kFirstRoundCriteriaIds 含 P018（注入集四条）', () {
      expect(kFirstRoundCriteriaIds.contains('P018'), isTrue);
      expect(kFirstRoundCriteriaIds.length, 4, reason: '三巨头 + P018');
    });

    test('#8 header 批文锚「四条」在场（三条→四条随批更新）', () {
      final block = buildFirstRoundCriteriaBlock();
      expect(
        block.startsWith('以下四条'),
        isTrue,
        reason: 'header 须与新注入集同数；改此串必须重走 R-027',
      );
    });

    test('#9 P018 判据段进首轮块（含新形态信号）', () {
      final block = buildFirstRoundCriteriaBlock();
      expect(block.contains('### P018 重复用词/基础语病'), isTrue);
      expect(block.contains('结构助词误插'), isTrue, reason: '新形态随段注入');
    });
  });
}
