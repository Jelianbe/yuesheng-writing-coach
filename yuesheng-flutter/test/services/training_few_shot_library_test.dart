// ─────────────────────────────────────────────────────────────
// T-04 few-shot 借鉴：训练 few-shot 示例库单元测试
//
// 覆盖路径：
//   getTrainingFewShot:
//     1. 命中 P001 → 返回非空 + 含头部 + 含好/坏对比
//     2. 命中多个症候 → 拼接 + 分隔符 ---
//     3. 未命中症候（P999）→ 空字符串
//     4. 混合（命中 + 未命中）→ 仅返回命中部分
//     5. 空入参 → 空字符串
//
//   kTrainingFewShotLibrary:
//     6. 首批覆盖 5 个高频症候（P001/P002/P006/P009/P001）
//     7. 每条示例必含「❌ 问题版」+「✅ 改善版」对比
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/services/training_few_shot_library.dart';

void main() {
  group('T-04 getTrainingFewShot 检索', () {
    test('#1 命中 P001 → 返回非空 + 含头部 + 含好/坏对比', () {
      final result = getTrainingFewShot(['P001']);
      expect(result, isNotEmpty);
      expect(result, contains('教学示例参考'));
      expect(result, contains('❌ 问题版'));
      expect(result, contains('✅ 改善版'));
      // P001 情绪标签化示例特征
      expect(result, contains('情绪标签'));
    });

    test('#2 命中多个症候 → 拼接 + 分隔符', () {
      final result = getTrainingFewShot(['P001', 'P002']);
      expect(result, isNotEmpty);
      // P001 已吸收原 P001 子类型（2 个对比块），P002 1 个 → 共 3 个好/坏对比块
      expect('❌ 问题版'.allMatches(result).length, 3);
      expect('✅ 改善版'.allMatches(result).length, 3);
      // 中间分隔符
      expect(result, contains('---'));
    });

    test('#3 未命中症候（P999）→ 空字符串', () {
      final result = getTrainingFewShot(['P999']);
      expect(result, '');
    });

    test('#4 混合（命中 + 未命中）→ 仅返回命中部分', () {
      final result = getTrainingFewShot(['P001', 'P999', 'P006']);
      expect(result, isNotEmpty);
      // 用各症候 few-shot 中独有的原文片段断言
      expect(result, contains('她很难过')); // P001 问题版原文
      expect(result, contains('晨曦的金色光辉')); // P006 问题版原文
      // P999 不应出现 ID 字样
      expect(result.contains('P999'), false);
      // P001 吸收原 P001（2 块）+ P006（1 块）→ 共 3 个好/坏对比
      expect('❌ 问题版'.allMatches(result).length, 3);
    });

    test('#5 空入参 → 空字符串', () {
      expect(getTrainingFewShot([]), '');
      expect(getTrainingFewShot(['', '']), '');
    });

    test('#6 顺序保持（不重排）', () {
      final r1 = getTrainingFewShot(['P001', 'P006']);
      final r2 = getTrainingFewShot(['P006', 'P001']);
      // 用各症候独有原文片段判定顺序
      final idxP003R1 = r1.indexOf('她很难过');
      final idxP008R1 = r1.indexOf('晨曦的金色光辉');
      expect(idxP003R1 < idxP008R1, true, reason: 'r1 应 P001 在前');
      final idxP003R2 = r2.indexOf('她很难过');
      final idxP008R2 = r2.indexOf('晨曦的金色光辉');
      expect(idxP008R2 < idxP003R2, true, reason: 'r2 应 P006 在前');
    });
  });

  group('T-04 kTrainingFewShotLibrary 内容契约', () {
    test(
      '#7 覆盖高频症候（0.3.6+9 聚类去重后 24 条；原 P012/P001/P013/P019/P011/P005 示例块已并入其保留症候）',
      () {
        // 首批
        expect(kTrainingFewShotLibrary.keys, contains('P001'));
        expect(kTrainingFewShotLibrary.keys, contains('P002'));
        expect(kTrainingFewShotLibrary.keys, contains('P006'));
        expect(kTrainingFewShotLibrary.keys, contains('P009'));
        // 第二批
        expect(kTrainingFewShotLibrary.keys, contains('P003'));
        expect(kTrainingFewShotLibrary.keys, contains('P004'));
        expect(kTrainingFewShotLibrary.keys, contains('P005'));
        expect(kTrainingFewShotLibrary.keys, contains('P007'));
        expect(kTrainingFewShotLibrary.keys, contains('P008'));
        // 第三批
        expect(kTrainingFewShotLibrary.keys, contains('P010'));
        expect(kTrainingFewShotLibrary.keys, contains('P011'));
        expect(kTrainingFewShotLibrary.keys, contains('P012'));
        // 第四批
        expect(kTrainingFewShotLibrary.keys, contains('P013'));
        expect(kTrainingFewShotLibrary.keys, contains('P014'));
        // 第五批
        expect(kTrainingFewShotLibrary.keys, contains('P015'));
        expect(kTrainingFewShotLibrary.keys, contains('P016'));
        expect(kTrainingFewShotLibrary.keys, contains('P017'));
        // 第六批
        expect(kTrainingFewShotLibrary.keys, contains('P018'));
        // 第七批
        expect(kTrainingFewShotLibrary.keys, contains('P019'));
        expect(kTrainingFewShotLibrary.keys, contains('P020'));
        // 第八批
        expect(kTrainingFewShotLibrary.keys, contains('P021'));
        expect(kTrainingFewShotLibrary.keys, contains('P022'));
        expect(kTrainingFewShotLibrary.keys, contains('P023'));
        // 第九批 / C123（2026-10-02）：P034 指称歧义/零回指过载补正反例对
        expect(kTrainingFewShotLibrary.keys, contains('P034'));
        expect(kTrainingFewShotLibrary.length, 24);
      },
    );

    test('#7e P018/P013/P019 few-shot 命中检索（原 P013→P013、P019→P019）', () {
      // 用各症候独有原文片段断言命中
      expect(getTrainingFewShot(['P018']), contains('往事往事'));
      expect(getTrainingFewShot(['P018']), contains('。。'));
      expect(getTrainingFewShot(['P013']), contains('保护费'));
      expect(getTrainingFewShot(['P013']), contains('哪只手打断的'));
      expect(getTrainingFewShot(['P019']), contains('改变一切'));
      expect(getTrainingFewShot(['P019']), contains('母亲'));
    });

    test('#7f P011/P019/P020 few-shot 命中检索（原 P011→P011）', () {
      // 用各症候独有原文片段断言命中
      expect(getTrainingFewShot(['P011']), contains('玄渊大陆'));
      expect(getTrainingFewShot(['P011']), contains('碎瓷片'));
      expect(getTrainingFewShot(['P011']), contains('四件套'));
      expect(getTrainingFewShot(['P019']), contains('大家早点休息'));
      expect(getTrainingFewShot(['P019']), contains('乱葬岗'));
      expect(getTrainingFewShot(['P020']), contains('四十章没提了'));
      expect(getTrainingFewShot(['P020']), contains('别找我'));
    });

    test('#7g P021/P005/P022/P023 few-shot 命中检索（原 P005→P005）', () {
      // 用各症候独有原文片段断言命中
      expect(getTrainingFewShot(['P021']), contains('很悲伤地离开'));
      expect(getTrainingFewShot(['P021']), contains('豆腐摔了一地'));
      expect(getTrainingFewShot(['P021']), contains('碗边缺了一块瓷'));
      expect(getTrainingFewShot(['P005']), contains('三百字无分段'));
      expect(getTrainingFewShot(['P005']), contains('文字墙'));
      expect(getTrainingFewShot(['P022']), contains('铺垫十章'));
      expect(getTrainingFewShot(['P022']), contains('断流'));
      expect(getTrainingFewShot(['P022']), contains('跪在师父面前'));
      expect(getTrainingFewShot(['P023']), contains('筑基不能飞行'));
      expect(getTrainingFewShot(['P023']), contains('破境丹'));
    });

    test('#7d 第五批 P015/P016/P017 few-shot 命中检索（独有原文片段）', () {
      // 用各症候独有原文片段断言命中
      expect(getTrainingFewShot(['P015']), contains('握刀'));
      expect(getTrainingFewShot(['P015']), contains('刀身还是凉的'));
      expect(getTrainingFewShot(['P016']), contains('镜头一转'));
      expect(getTrainingFewShot(['P016']), contains('铁锤声'));
      expect(getTrainingFewShot(['P017']), contains('三个月后'));
      expect(getTrainingFewShot(['P017']), contains('茶棚'));
    });

    test('#7a 第二批 P003-P008 few-shot 命中检索（独有原文片段）', () {
      // 用各症候独有原文片段断言命中
      expect(getTrainingFewShot(['P003']), contains('他不知道的是'));
      expect(getTrainingFewShot(['P004']), contains('淅淅沥沥'));
      expect(getTrainingFewShot(['P005']), contains('他站起来'));
      expect(getTrainingFewShot(['P007']), contains('去北方'));
      expect(getTrainingFewShot(['P008']), contains('剪短了三寸'));
    });

    test('#7b 第三批 P010-P012 few-shot 命中检索（独有原文片段）', () {
      // 用各症候独有原文片段断言命中
      expect(getTrainingFewShot(['P010']), contains('卷刃'));
      expect(getTrainingFewShot(['P011']), contains('断手'));
      expect(getTrainingFewShot(['P012']), contains('雨停了'));
    });

    test('#7c 第四批 P013-P014 few-shot 命中检索（原 P012→P012）', () {
      // 用各症候独有原文片段断言命中
      expect(getTrainingFewShot(['P013']), contains('停住'));
      expect(getTrainingFewShot(['P013']), contains('喂鸟'));
      expect(getTrainingFewShot(['P014']), contains('刚好'));
      expect(getTrainingFewShot(['P012']), contains('兰花'));
    });

    test('#7h C3 守卫：P012 正文无英文残留、舞台提示已中文化', () {
      // ADR-C116 C3：P012 两处「（三 chapters 后）」英文残留中文化为「（三章之后）」。
      // 守卫：正文不得残留英文 'chapters'；舞台提示必须为中文措辞。
      final p012 = kTrainingFewShotLibrary['P012']!;
      expect(
        p012,
        isNot(contains('chapters')),
        reason: 'P012 few-shot 正文不得残留英文 chapters',
      );
      expect(p012, contains('三章之后'), reason: 'P012 舞台提示应为中文「（三章之后）」');
    });

    test('#8 每条示例必含好/坏对比 + 改善点说明', () {
      for (final entry in kTrainingFewShotLibrary.entries) {
        final content = entry.value;
        expect(content, contains('❌ 问题版'), reason: '${entry.key} 缺「❌ 问题版」段');
        expect(content, contains('✅ 改善版'), reason: '${entry.key} 缺「✅ 改善版」段');
        expect(content, contains('→ 问题点'), reason: '${entry.key} 缺「→ 问题点」说明');
        expect(content, contains('→ 改善点'), reason: '${entry.key} 缺「→ 改善点」说明');
      }
    });

    test('#9 示例不含跨症候内容（每个症候示例聚焦本症候）', () {
      // 简单 sanity：P001 示例不应提到 P006 的关键词「堆砌」
      final p001 = kTrainingFewShotLibrary['P001']!;
      expect(p001.contains('堆砌'), false, reason: 'P001 示例不应包含 P006 关键词');
      final p006 = kTrainingFewShotLibrary['P006']!;
      expect(p006.contains('情绪标签'), false, reason: 'P006 示例不应包含 P001 关键词');
    });
  });
}
