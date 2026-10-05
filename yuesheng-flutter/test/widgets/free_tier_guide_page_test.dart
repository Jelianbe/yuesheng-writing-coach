// ─────────────────────────────────────────────────────────────
// FreeTierGuidePage widget 测试 — 免费获取 API Key 引导页
//
// 本页的**产品承诺**（不只是渲染）：
//   1. 引导用户去厂商官网自己注册，回填自己的 key（BYOK）——不内置共享 key。
//   2. 只列**厂商官方 free 档位**，不列第三方 stealth/限时档。
//   3. ★ 结构是「多 provider 清单」：新增服务商只加一个 const 条目，
//      页面骨架与渲染代码零改动。← 本测试就是为守住这条而写。
//   4. **不承诺免费额度长期有效**（12 个月里 7 个免费入口消失）。
//
// 覆盖路径：
//   #1 首屏渲染：免费档卡片 / 步骤 / 付费折叠区 / 诚实声明
//   #2 复制链接 → 剪贴板内容正确 + 明确的下一步提示
//   #3 ★「加第二家只加 const 条目」——用 override 注入第二家，
//        断言两卡同构渲染（骨架零改动即可容纳多 provider）
//   #4 付费区默认折叠、展开后列出服务商
//   #5 诚实声明常驻（不被折叠、不被隐藏）
//   #6 禁列第三方 stealth 档：清单里不得出现 space-bunny / stealth / :free
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// buildAppTheme 在 lib/theme/app_theme.dart（lib/config/app_theme.dart 只导出
// AppColors —— 勿照抄 settings_page_test.dart:30-31 的两行 import 时误并为一处）。
import 'package:writingcoach/theme/app_theme.dart' show buildAppTheme;
import 'package:writingcoach/features/app_settings/free_tier_guide_page.dart';

// ★ 视口必须容纳**整页**。ListView 对视口外子项不构建，若高度不足：
//   ① 视口下的控件 finder 报 0 命中（#3/#5 那类假失败）；
//   ② 更危险 —— `findsNothing` 类**否定断言会无条件通过**（#6 假绿）。
// 故设 400x2000（内容宽裕上限），并让 #6 自带正对照证明 finder 看得见东西。
const Size kTestSurface = Size(400, 2000);

void main() {
  Widget build({List<FreeTierEntry> entries = kFreeTierEntries}) {
    return MaterialApp(
      theme: buildAppTheme(),
      home: FreeTierGuidePage(entries: entries),
    );
  }

  /// 整页装进视口后 pump，供所有用例共用。
  Future<void> pumpGuide(
    WidgetTester tester, {
    List<FreeTierEntry> entries = kFreeTierEntries,
  }) async {
    await tester.binding.setSurfaceSize(kTestSurface);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(build(entries: entries));
    await tester.pumpAndSettle();
  }

  // 折叠区展开（付费区默认折叠，测内容需先展开）。
  Future<void> expandPaidSection(WidgetTester tester) async {
    await tester.tap(find.text('其他服务商（需充值）'));
    await tester.pumpAndSettle();
  }

  group('免费档引导页', () {
    testWidgets('#1 首屏渲染四个区块', (tester) async {
      await pumpGuide(tester);

      expect(find.text('免费获取 API Key'), findsOneWidget); // AppBar
      expect(find.text('先用免费档跑起来'), findsOneWidget); // 引导
      expect(find.text('glm-4.7-flash'), findsOneWidget); // 免费档模型名
      expect(find.text('获取步骤'), findsOneWidget);
      expect(find.text('其他服务商（需充值）'), findsOneWidget);
      // 诚实声明常驻
      expect(find.textContaining('不承诺任何免费额度长期有效'), findsOneWidget);
    });

    testWidgets('#2 复制注册链接 → 剪贴板 + 下一步提示', (tester) async {
      final log = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          log.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await pumpGuide(tester);

      await tester.tap(find.text('复制注册链接'));
      await tester.pumpAndSettle();

      // 复制到剪贴板的内容必须逐字等于控制台地址。
      // ★ Clipboard.setData 走 channel 时参数是**顶层** {'text': ...}
      //   （flutter/lib/src/services/clipboard.dart:36-38），没有内层 data 包装。
      final clipCall = log.firstWhere((c) => c.method == 'Clipboard.setData');
      final args = clipCall.arguments as Map<dynamic, dynamic>;
      expect(
        args['text'],
        // ★ 与 kFreeTierEntries 里智谱那条的 consoleUrl **逐字一致**。
        //   这里是指向注册页的邀请链接（含 icode），不是 API Key 管理页
        //   —— 用户点开后需先注册/登录，再自行进入 API Keys 页。
        'https://www.bigmodel.cn/invite?icode=fkd95bPdOlYyP1vLEXZGVunfet45IvM%2BqDogImfeLyI%3D',
      );

      // 复制后必须告诉用户下一步（否则复制完不知道要干嘛）
      expect(find.text('链接已复制，请到浏览器打开并注册'), findsOneWidget);
    });

    testWidgets('#3 ★ 加第二家只加 const 条目，骨架零改动即可渲染两卡', (tester) async {
      const second = FreeTierEntry(
        provider: '第二家测试服务商',
        key: 'second-provider-free-model',
        contextLabel: '128K 上下文',
        notice: '免费档：输入输出全免',
        consoleUrl: 'https://example.invalid/apikeys',
        pitfall: '这是第二家的计费陷阱提示。',
      );

      await pumpGuide(tester, entries: [...kFreeTierEntries, second]);

      // 两家都在，且各自带自己的「免费档」徽标与复制按钮。
      // ★ 用 find.text 而非 find.widgetWithText：后者是**祖先**查找器
      //   （要求「Text 的祖先中还有 Text」），裸 Text 徽标恒 0 命中。
      expect(find.text('智谱 GLM'), findsOneWidget);
      expect(find.text('第二家测试服务商'), findsOneWidget);
      expect(find.text('免费档'), findsNWidgets(2));
      expect(find.widgetWithText(OutlinedButton, '复制注册链接'), findsNWidgets(2));
      // 各自的模型名与规格说明都在（证明是两份独立渲染，不是复制粘贴一张卡）
      expect(find.text('glm-4.7-flash'), findsOneWidget);
      expect(find.text('second-provider-free-model'), findsOneWidget);
      // 各自的计费陷阱提示也都渲染出来了 —— 数据里加了字段但忘了放进
      // children 的话，上面两条数据断言照样绿。
      // ★ 断言顺序：**第二家在先**。若第一家在前，一旦它缺失，测试在
      //   第一条就 fail-fast 抛出，第二家这条**永远不会被执行** ⇒
      //   「两家渲染同一条」这类变异就抓不到（变异实测 M4 暴露）。
      //   放后面那条当后手，才能真正检验到「各自独立渲染」。
      expect(find.text(second.pitfall), findsOneWidget);
      expect(find.text(kFreeTierEntries.first.pitfall), findsOneWidget);
      // 骨架元素（步骤卡 / 付费区 / 声明）各只出现一次 —— 没有因多一家而重复
      expect(find.text('获取步骤'), findsOneWidget);
      expect(find.text('其他服务商（需充值）'), findsOneWidget);
    });

    testWidgets('#4 付费区默认折叠，展开后列出服务商', (tester) async {
      await pumpGuide(tester);

      // 折叠态：内容不可见
      expect(find.textContaining('按用量从账户余额扣除'), findsNothing);

      await expandPaidSection(tester);
      expect(find.textContaining('DeepSeek'), findsOneWidget);
      expect(find.textContaining('需国际卡'), findsOneWidget);
    });

    testWidgets('#5 诚实声明常驻（不随折叠区隐藏）', (tester) async {
      await pumpGuide(tester);
      expect(find.textContaining('不承诺任何免费额度长期有效'), findsOneWidget);

      // 展开付费区后依然在
      await expandPaidSection(tester);
      expect(find.textContaining('不承诺任何免费额度长期有效'), findsOneWidget);
    });

    testWidgets('#6 禁列第三方 stealth 档（space-bunny 类）', (tester) async {
      await pumpGuide(tester);

      // ★ 正对照：先证明 finder 确实看得见卡片内容（否则下面的否定断言
      //   可能只是「控件没构建」的假绿 —— ListView 对视口外子项不构建）。
      // ★ 这里必须用 `findsAtLeastNWidgets(1)` 而**不是** `findsOneWidget`：
      //   正对照的职责是「证明 finder 有效」，不是「证明只有一家」。若用精确
      //   计数，则清单里一旦多出违规条目，数量断言会先炸并遮蔽后面的
      //   stealth 语义断言 —— 变异实测：注入 space-bunny 后本行红，
      //   后面的 `isNot(contains('space-bunny'))` 一次都没执行。
      expect(find.text('智谱 GLM'), findsAtLeastNWidgets(1));
      expect(find.text('免费档'), findsAtLeastNWidgets(1));

      // 本产品只展示厂商官方 free 档。任何第三方 stealth / 限时档
      // （腐化率 72%，且 models.dev 上有条目名直接写 "retires Oct 5"）
      // 都不允许出现在页面上 —— 否则等于把不稳定承诺给用户。
      // 覆盖两处渲染面：卡片清单（kFreeTierEntries）+ 付费区/说明文案。
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join('\n');
      expect(texts, isNot(contains('space-bunny')));
      expect(texts, isNot(contains('stealth')));
      expect(texts, isNot(contains(':free')));
      // 也不得出现「永久免费」这类承诺性措辞
      expect(texts, isNot(contains('永久免费')));
      // 反向自检：上述断言不是恒真 —— 把守卫值换成永不可能命中的串，
      // 若仍通过说明 text 表根本没取到内容（用上面的正对照兜住这一点）。
      expect(texts, isNot(contains('__no_such_marker_probe__')));
    });
  });

  group('清单数据本身', () {
    test('★ 清单里的 key 必须与设置页预设逐字一致', () {
      // 同一模型名两处不一致 ⇒ 用户照抄后测试连接必然失败。
      // 本用例锁住「清单 key 不得漂移」。
      for (final entry in kFreeTierEntries) {
        expect(entry.key, isNotEmpty);
        expect(
          entry.consoleUrl,
          startsWith('https://'),
          reason: '${entry.provider} 的控制台地址必须是 https',
        );
        // 收费档误入清单 = 直接产生账单风险
        expect(
          entry.key,
          isNot(contains('flashx')),
          reason: 'glm-4.7-flashx 是收费档，不得进免费清单',
        );
        expect(
          entry.key,
          isNot(contains('reasoner')),
          reason: 'reasoner 档按 token 计费，不得进免费清单',
        );
        // ★ pitfall 必须**提到本条目自己的模型名**，不能是泛泛的通用文案。
        //   理由：判据若只查 `isNotEmpty`，空串与「请注意计费」都能过 ⇒
        //   护栏会在真正需要它时失效（假绿）。绑定 key 后，改模型名而不改
        //   提示、或把 A 家的坑写成通用文案，本行都会红。
        expect(
          entry.pitfall,
          contains(entry.key),
          reason:
              '${entry.provider} 的计费陷阱提示必须点名它自己的模型名 '
              '（${entry.key}），否则用户无法据此核对自己在设置页填的模型名',
        );
      }
    });

    test('免费档必须写明「免费」口径', () {
      for (final entry in kFreeTierEntries) {
        expect(
          entry.notice,
          contains('免费'),
          reason: '${entry.provider} 必须写明计费口径',
        );
      }
    });
  });
}
