// ─────────────────────────────────────────────────────────────
// C124 批：P018 ↔ P034 划界修复测试（R-027 停线批准，2026-10-02）
//
// 批准文本：在 P018 判据内反向加划界句——「若读者的困难是『他指谁』
// 而非『他他连写/连接词重复』，改判 P034」。
//
// 覆盖（文本锚点层；真实 LLM 翻标签由 C124 批模拟器往返验证）：
//   1. P018 判据三面（syndrome content / training content / few-shot）
//      均含反向划界句语义（「改判 P034」+ 区分「他指谁」vs「他他连写/连接词重复」）
//   2. P3 最短锚点原文（「林远把刀递给李梅…他点点头」）在 few-shot 中锚定 P034，
//      且 P018 判据内出现反向改判指引（防 LLM 再锁 P018）
//   3. P018 典型样本（他他连写/连接词重复类）仍属 P018——判据未过度扩大
//   4. P034 负向（正常单主角链）不报 P034——负向守卫仍在
//   5. prompt 内联索引（progressive_diagnosis P034 判界行）与新增划界语义一致
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/syndrome_knowledge_base.dart';
import 'package:writingcoach/services/training_knowledge_base.dart';
import 'package:writingcoach/services/training_few_shot_library.dart';

void main() {
  group('C124 P018↔P034 划界 · 判据三面锚点', () {
    test('#1 P018 syndrome 判据含反向划界句（改判 P034）', () {
      final content = getSyndromeContent(['P018']);
      expect(content, contains('### P018 重复用词/基础语病'));
      // 批准文本语义：区分「他指谁」（P034）vs「他他连写/连接词重复」（P018）
      expect(content, contains('与 P034 的划界'));
      expect(content, contains('改判 P034'));
      expect(content, contains('他/她/它指谁'));
      expect(content, contains('他他连写/连接词重复'));
      expect(content, contains('不要报 P018'));
    });

    test('#2 P018 training 知识含划界提示（常见误区）', () {
      final content = getTrainingContent(['P018']);
      expect(content, contains('## P018 重复用词/基础语病'));
      expect(content, contains('指称解歧'));
      expect(content, contains('P034 代词指代不清/零回指过载'));
      expect(content, contains('不要按 P018'));
      // ── T-20261103-01 P018 词条内容牙（报批稿 §6 J4–J7；R-027 舰长 2026-11-04 批）
      // getTrainingContent(['P018']) 即 P018 词条切片（## P018 起至下一词条）。
      // J4 自查锚点牙：教学要点四步自查行（「三类例外」引用的宿主）
      expect(
        content,
        contains('错别字误字自查'),
        reason: 'P018 词条缺「错别字误字自查」教学要点行（报批稿 §6 J4）',
      );
      expect(
        content,
        contains('再自行查证定夺'),
        reason: 'P018 词条自查行缺尾锚「再自行查证定夺」（报批稿 §6 J4）',
      );
      // J5 例外行牙：常见误区三段例外行（「三类例外」的被引用方）
      expect(
        content,
        contains('把专有名词/方言记音/修辞性谐音当错别字误字'),
        reason: 'P018 词条缺三段例外行（报批稿 §6 J5）',
      );
      // J6 成对牙：J4 自查行尾句引用「三类例外」= J5 例外行；两者必须同批落地，
      // 只落其一即引用悬空 ⇒ 红。落法 = J4 与 J5 在本 test 内连续断言（∧ 语义）：
      // 删自查行红在 J4；只删例外行红在 J5。
      // J7 P034 划界不动牙：划界行原文钉住（报批稿 §10-3「逐字不动」）。
      // 注：行内引号为直引号 U+0022（2026-11-04 现场码点核验），勿改写为弯引号。
      expect(
        content,
        contains(
          '那是 P034 代词指代不清/零回指过载（困难是"他指谁"，'
          '不是"他他连写/连接词重复"），训练时按 P034 处理，不要按 P018',
        ),
        reason: 'J7 P034 划界行原文变动（报批稿 §10-3 逐字不动）',
      );
    });

    test('#3 P018 few-shot 含划界提示', () {
      final content = getTrainingFewShot(['P018']);
      expect(content, contains('划界提示'));
      expect(content, contains('同一主角'));
      expect(content, contains('不要报 P018'));
    });

    test('#4 P3 最短锚点原文在 few-shot 锚定 P034（防再锁 P018）', () {
      final p034 = getTrainingFewShot(['P034']);
      expect(p034, contains('林远把刀递给李梅'));
      expect(p034, contains('他点点头，转身出了门'));
      // P034 few-shot 已含「不是用词重复（P018 的"他他"是打字连写）」划界（C123 引入）
      expect(p034, contains('P018'));
    });

    test('#5 P018 典型样本仍属 P018（判据未过度扩大）', () {
      final p018 = getSyndromeContent(['P018']);
      // 他他连写/连续标点/相邻字重复的触发信号仍在
      expect(p018, contains('他他'));
      expect(p018, contains('连续重复标点'));
      expect(p018, isNot(contains('往事往事'))); // 往事往事 在 few-shot 侧
      final fs = getTrainingFewShot(['P018']);
      expect(fs, contains('往事往事'));
      expect(fs, contains('。。'));
      expect(fs, contains('他走进了房间'));
      // ★ T-20261102-01 B1c 批 2 内容牙（J3/J4）：错字判据主句 + 例外三段在位
      // （报批稿 §6 · R-027 舰长 2026-11-02 23:21「都批」）。getSyndromeContent(['P018'])
      // 即 P018 段切片，同形句不会从其它症候段混入；段标题锚点失效即红不跳过。
      expect(p018, contains('### P018 重复用词/基础语病'));
      expect(
        p018,
        contains('错别字/误字——文本中出现的二字组合不构成通行词'),
        reason: 'P018 触发信号缺错字判据主句（T-20261102-01 B1c 改动 2 · J3）',
      );
      expect(
        p018,
        contains('指不出支撑条件'),
        reason: 'P018 例外三段缺「指不出支撑条件 ⇒ 例外不成立」后果牙（J4）',
      );
      expect(p018, contains('修辞性谐音'), reason: 'P018 例外三段缺③修辞性谐音段（J4）');
    });

    test('#6 P034 负向（正常单主角链）不报 P034——守卫仍在', () {
      final p034 = getSyndromeContent(['P034']);
      // 单主角行动链（就近候选恒为 1）不得报 P034
      expect(p034, contains('就近候选'));
      expect(p034, contains('不构成'));
      expect(p034, contains('不得报 P034'));
      expect(p034, contains('推开门，看见屋里没人'));
      // P034 few-shot 负向样例仍锚定「不触发」
      final fs = getTrainingFewShot(['P034']);
      expect(fs, contains('单主角行动链'));
      expect(fs, contains('不得报 P034'));
    });
  });

  group(
    'C124 P018↔P034 划界 · 三面一致性（prompt 内联索引 / 注册 skillContent / 系统消息序列）',
    () {
      test('#7 划界语义在所有注入资产中方向一致（P018 侧反向 + P034 侧正向）', () {
        // P018 侧（本批新增）：困难是「他指谁」→ 改判 P034
        final p018 = getSyndromeContent(['P018']);
        expect(p018, contains('改判 P034'));
        // P034 侧（C123 已有）：同句两个"他"分属不同人物 → 必须报 P034
        final p034 = getSyndromeContent(['P034']);
        expect(p034, contains('必须报 P034'));
        expect(p034, contains('不是 P018'));
        // 两侧划界词汇同域（他他连写 vs 指称解歧），无方向冲突
        expect(p018.contains('他他连写/连接词重复'), true);
        expect(p034.contains('他他'), true);
      });

      test('#8 few-shot 双侧划界不互相吞并', () {
        // P018 few-shot：读者不困惑「指谁」→ 仍是 P018
        final p018 = getTrainingFewShot(['P018']);
        expect(p018, contains('不困惑「指谁」'));
        // P034 few-shot：读者需回看确认「他指谁」→ P034
        final p034 = getTrainingFewShot(['P034']);
        expect(p034, contains('读者必须回看上段才能确定'));
      });
    },
  );
}
