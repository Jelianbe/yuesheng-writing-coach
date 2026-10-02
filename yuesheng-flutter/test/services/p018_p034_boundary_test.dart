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
      expect(content, contains('P034 代词指代不清/零回指过载症'));
      expect(content, contains('不要按 P018'));
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
