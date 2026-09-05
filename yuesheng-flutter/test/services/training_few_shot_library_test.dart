// ─────────────────────────────────────────────────────────────
// T-04 few-shot 借鉴：训练 few-shot 示例库单元测试
//
// 覆盖路径：
//   getTrainingFewShot:
//     1. 命中 P003 → 返回非空 + 含头部 + 含好/坏对比
//     2. 命中多个症候 → 拼接 + 分隔符 ---
//     3. 未命中症候（P999）→ 空字符串
//     4. 混合（命中 + 未命中）→ 仅返回命中部分
//     5. 空入参 → 空字符串
//
//   kTrainingFewShotLibrary:
//     6. 首批覆盖 5 个高频症候（P003/P004/P008/P011/P019）
//     7. 每条示例必含「❌ 问题版」+「✅ 改善版」对比
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/services/training_few_shot_library.dart';

void main() {
  group('T-04 getTrainingFewShot 检索', () {
    test('#1 命中 P003 → 返回非空 + 含头部 + 含好/坏对比', () {
      final result = getTrainingFewShot(['P003']);
      expect(result, isNotEmpty);
      expect(result, contains('教学示例参考'));
      expect(result, contains('❌ 问题版'));
      expect(result, contains('✅ 改善版'));
      // P003 情绪标签化示例特征
      expect(result, contains('情绪标签'));
    });

    test('#2 命中多个症候 → 拼接 + 分隔符', () {
      final result = getTrainingFewShot(['P003', 'P004']);
      expect(result, isNotEmpty);
      // 出现两次好/坏对比块
      expect('❌ 问题版'.allMatches(result).length, 2);
      expect('✅ 改善版'.allMatches(result).length, 2);
      // 中间分隔符
      expect(result, contains('---'));
    });

    test('#3 未命中症候（P999）→ 空字符串', () {
      final result = getTrainingFewShot(['P999']);
      expect(result, '');
    });

    test('#4 混合（命中 + 未命中）→ 仅返回命中部分', () {
      final result = getTrainingFewShot(['P003', 'P999', 'P008']);
      expect(result, isNotEmpty);
      // 用各症候 few-shot 中独有的原文片段断言
      expect(result, contains('她很难过')); // P003 问题版原文
      expect(result, contains('晨曦的金色光辉')); // P008 问题版原文
      // P999 不应出现 ID 字样
      expect(result.contains('P999'), false);
      // 两块命中 → 两次好/坏对比
      expect('❌ 问题版'.allMatches(result).length, 2);
    });

    test('#5 空入参 → 空字符串', () {
      expect(getTrainingFewShot([]), '');
      expect(getTrainingFewShot(['', '']), '');
    });

    test('#6 顺序保持（不重排）', () {
      final r1 = getTrainingFewShot(['P003', 'P008']);
      final r2 = getTrainingFewShot(['P008', 'P003']);
      // 用各症候独有原文片段判定顺序
      final idxP003R1 = r1.indexOf('她很难过');
      final idxP008R1 = r1.indexOf('晨曦的金色光辉');
      expect(idxP003R1 < idxP008R1, true, reason: 'r1 应 P003 在前');
      final idxP003R2 = r2.indexOf('她很难过');
      final idxP008R2 = r2.indexOf('晨曦的金色光辉');
      expect(idxP008R2 < idxP003R2, true, reason: 'r2 应 P008 在前');
    });
  });

  group('T-04 kTrainingFewShotLibrary 内容契约', () {
    test(
      '#7 覆盖 29 个高频症候（首批 5 + 第二批 5 + 第三批 3 + 第四批 3 + 第五批 3 + 第六批 3 + 第七批 3 + 第八批 4，全覆盖收官）',
      () {
        // 首批 5 个
        expect(kTrainingFewShotLibrary.keys, contains('P003'));
        expect(kTrainingFewShotLibrary.keys, contains('P004'));
        expect(kTrainingFewShotLibrary.keys, contains('P008'));
        expect(kTrainingFewShotLibrary.keys, contains('P011'));
        expect(kTrainingFewShotLibrary.keys, contains('P019'));
        // 第二批 5 个（2026-08-27 扩容）
        expect(kTrainingFewShotLibrary.keys, contains('P005'));
        expect(kTrainingFewShotLibrary.keys, contains('P006'));
        expect(kTrainingFewShotLibrary.keys, contains('P007'));
        expect(kTrainingFewShotLibrary.keys, contains('P009'));
        expect(kTrainingFewShotLibrary.keys, contains('P010'));
        // 第三批 3 个（2026-08-27 扩容）
        expect(kTrainingFewShotLibrary.keys, contains('P012'));
        expect(kTrainingFewShotLibrary.keys, contains('P013'));
        expect(kTrainingFewShotLibrary.keys, contains('P014'));
        // 第四批 3 个（2026-08-27 扩容）
        expect(kTrainingFewShotLibrary.keys, contains('P015'));
        expect(kTrainingFewShotLibrary.keys, contains('P016'));
        expect(kTrainingFewShotLibrary.keys, contains('P017'));
        // 第五批 3 个（2026-08-27 扩容）
        expect(kTrainingFewShotLibrary.keys, contains('P018'));
        expect(kTrainingFewShotLibrary.keys, contains('P020'));
        expect(kTrainingFewShotLibrary.keys, contains('P021'));
        // 第六批 3 个（2026-08-27 扩容）
        expect(kTrainingFewShotLibrary.keys, contains('P022'));
        expect(kTrainingFewShotLibrary.keys, contains('P023'));
        expect(kTrainingFewShotLibrary.keys, contains('P024'));
        // 第七批 3 个（2026-08-27 扩容）
        expect(kTrainingFewShotLibrary.keys, contains('P025'));
        expect(kTrainingFewShotLibrary.keys, contains('P026'));
        expect(kTrainingFewShotLibrary.keys, contains('P027'));
        // 第八批 4 个（2026-08-27 扩容，收官）
        expect(kTrainingFewShotLibrary.keys, contains('P028'));
        expect(kTrainingFewShotLibrary.keys, contains('P029'));
        expect(kTrainingFewShotLibrary.keys, contains('P030'));
        expect(kTrainingFewShotLibrary.keys, contains('P031'));
        expect(kTrainingFewShotLibrary.length, greaterThanOrEqualTo(29));
      },
    );

    test('#7e 第六批 P022/P023/P024 few-shot 命中检索（独有原文片段）', () {
      // 用各症候独有原文片段断言命中
      expect(getTrainingFewShot(['P022']), contains('往事往事'));
      expect(getTrainingFewShot(['P022']), contains('。。'));
      expect(getTrainingFewShot(['P023']), contains('保护费'));
      expect(getTrainingFewShot(['P023']), contains('哪只手打断的'));
      expect(getTrainingFewShot(['P024']), contains('改变一切'));
      expect(getTrainingFewShot(['P024']), contains('母亲'));
    });

    test('#7f 第七批 P025/P026/P027 few-shot 命中检索（独有原文片段）', () {
      // 用各症候独有原文片段断言命中
      expect(getTrainingFewShot(['P025']), contains('玄渊大陆'));
      expect(getTrainingFewShot(['P025']), contains('碎瓷片'));
      expect(getTrainingFewShot(['P025']), contains('四件套'));
      expect(getTrainingFewShot(['P026']), contains('大家早点休息'));
      expect(getTrainingFewShot(['P026']), contains('乱葬岗'));
      expect(getTrainingFewShot(['P027']), contains('四十章没提了'));
      expect(getTrainingFewShot(['P027']), contains('别找我'));
    });

    test('#7g 第八批 P028/P029/P030/P031 few-shot 命中检索（独有原文片段，收官）', () {
      // 用各症候独有原文片段断言命中
      expect(getTrainingFewShot(['P028']), contains('很悲伤地离开'));
      expect(getTrainingFewShot(['P028']), contains('豆腐摔了一地'));
      expect(getTrainingFewShot(['P028']), contains('碗边缺了一块瓷'));
      expect(getTrainingFewShot(['P029']), contains('三百字无分段'));
      expect(getTrainingFewShot(['P029']), contains('文字墙'));
      expect(getTrainingFewShot(['P030']), contains('铺垫十章'));
      expect(getTrainingFewShot(['P030']), contains('断流'));
      expect(getTrainingFewShot(['P030']), contains('跪在师父面前'));
      expect(getTrainingFewShot(['P031']), contains('筑基不能飞行'));
      expect(getTrainingFewShot(['P031']), contains('破境丹'));
    });

    test('#7d 第五批 P018/P020/P021 few-shot 命中检索（独有原文片段）', () {
      // 用各症候独有原文片段断言命中
      expect(getTrainingFewShot(['P018']), contains('握刀'));
      expect(getTrainingFewShot(['P018']), contains('刀身还是凉的'));
      expect(getTrainingFewShot(['P020']), contains('镜头一转'));
      expect(getTrainingFewShot(['P020']), contains('铁锤声'));
      expect(getTrainingFewShot(['P021']), contains('三个月后'));
      expect(getTrainingFewShot(['P021']), contains('茶棚'));
    });

    test('#7a 第二批 P005-P010 few-shot 命中检索（独有原文片段）', () {
      // 用各症候独有原文片段断言命中
      expect(getTrainingFewShot(['P005']), contains('他不知道的是'));
      expect(getTrainingFewShot(['P006']), contains('淅淅沥沥'));
      expect(getTrainingFewShot(['P007']), contains('他站起来'));
      expect(getTrainingFewShot(['P009']), contains('去北方'));
      expect(getTrainingFewShot(['P010']), contains('剪短了三寸'));
    });

    test('#7b 第三批 P012-P014 few-shot 命中检索（独有原文片段）', () {
      // 用各症候独有原文片段断言命中
      expect(getTrainingFewShot(['P012']), contains('卷刃'));
      expect(getTrainingFewShot(['P013']), contains('断手'));
      expect(getTrainingFewShot(['P014']), contains('雨停了'));
    });

    test('#7c 第四批 P015-P017 few-shot 命中检索（独有原文片段）', () {
      // 用各症候独有原文片段断言命中
      expect(getTrainingFewShot(['P015']), contains('停住'));
      expect(getTrainingFewShot(['P015']), contains('喂鸟'));
      expect(getTrainingFewShot(['P016']), contains('刚好'));
      expect(getTrainingFewShot(['P017']), contains('兰花'));
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
      // 简单 sanity：P003 示例不应提到 P008 的关键词「堆砌」
      final p003 = kTrainingFewShotLibrary['P003']!;
      expect(p003.contains('堆砌'), false, reason: 'P003 示例不应包含 P008 关键词');
      final p008 = kTrainingFewShotLibrary['P008']!;
      expect(p008.contains('情绪标签'), false, reason: 'P008 示例不应包含 P003 关键词');
    });
  });
}
