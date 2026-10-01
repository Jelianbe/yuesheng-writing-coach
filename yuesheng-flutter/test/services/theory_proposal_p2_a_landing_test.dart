// ADR-C120 理论提案 P2 批A（SUGGEST-068/069/071/072/073/074/075/078）落地护栏
// 守卫：8 条豁免 A 档批判边界登记知识库数据层（syndrome 手册「边界纪律」列表）。
//       纯数据层，零注册表改动（不触 syndrome_registry / technique_knowledge_base /
//       training_knowledge_base / skill_registry / skills_*.dart / few-shot / skills_training_p4）。
// 落点：068→P023/P016/P017；069→P023/P015；071→P023；072→P023/P015；
//       073→P023/P015；074→P023/P020/P027；075→P027；078→P027/P020。
// 注记：T055/T056 为理论卡路由标记非技法块（不建技法块）；C|H 定理名不入正文；
//       074 边界独立于 343 vs 344 章数冲突值；075 只取三条禁止、A013 仅关联不写 training。
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/syndrome_knowledge_base.dart';

void main() {
  group('theory-proposal-p2-a-landing', () {
    test('SUGGEST-068 -> P023/P016/P017 页码/章节位置非故事时间真值、省略空隙不补写', () {
      for (final id in ['P023', 'P016', 'P017']) {
        final c = getSyndromeContent([id]);
        expect(c, contains('禁止把页码/章节位置当故事时间真值'));
      }
    });

    test('SUGGEST-069 -> P023/P015 时间循环/穿越/多世界不得压单条 fabula 轴', () {
      for (final id in ['P023', 'P015']) {
        final c = getSyndromeContent([id]);
        expect(c, contains('把所有事件排进单条 fabula 轴'));
      }
    });

    test('SUGGEST-071 -> P023 单本诊断不引入跨作品实体键账本、不自动修设定矛盾', () {
      final c = getSyndromeContent(['P023']);
      expect(c, contains('禁止单本网文诊断时引入跨作品实体键账本'));
    });

    test('SUGGEST-072 -> P023/P015 线性小说愿望/假设/倒叙不得升格为分支/多结局', () {
      for (final id in ['P023', 'P015']) {
        final c = getSyndromeContent([id]);
        expect(c, contains('自动标注为"互动分支/多结局/平行世界"'));
      }
    });

    test('SUGGEST-073 -> P023/P015 未声明体制不得混用三种时间线、L4 不得自修悖论', () {
      for (final id in ['P023', 'P015']) {
        final c = getSyndromeContent([id]);
        expect(c, contains('禁止在未声明一致性体制时混用'));
      }
    });

    test('SUGGEST-074 -> P023/P020/P027 代表日期非完整起止、两章同日非严格同时', () {
      for (final id in ['P023', 'P020', 'P027']) {
        final c = getSyndromeContent([id]);
        expect(c, contains('禁止把某章"代表日期"写成完整起止'));
      }
    });

    test('SUGGEST-075 -> P027 反复出现名词≠strand、对照回忆≠并行线、L3 不自唤醒', () {
      final c = getSyndromeContent(['P027']);
      expect(c, contains('禁止把任何反复出现的人物/名词都登记为"并行线 strand"'));
    });

    test('SUGGEST-078 -> P027/P020 同章出场/同地点/同日≠情节会合或状态同步', () {
      for (final id in ['P027', 'P020']) {
        final c = getSyndromeContent([id]);
        expect(c, contains('自动等同于情节会合或人物状态同步'));
      }
    });
  });
}
