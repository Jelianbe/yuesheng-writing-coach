// ─────────────────────────────────────────────────────────────
// FreeTierGuidePage — 免费获取 API Key 引导页
//
// 目的：让**没充过值**的用户也能用上月笙（当前 AI 能力是付费墙后的
// 第一个流失点）。做法不是内置共享 key（不可行：APK 可反编译、
// 抓包可提取，见 .ai/reports/2026-10-04-免费LLM供给生态调研.md），
// 而是**引导用户去服务商官网自己注册、回填自己的 key**。
//
// 定位纪律（重要，改文案前先读）：
//   本页**不承诺**任何免费额度长期有效。只列**厂商官方 free 档位**
//   （有官方文档背书 + 老档下线自动路由到新免费档），**不列**第三方
//   聚合站的 stealth/限时档（space-bunny 一类：实测腐化率 72%，
//   models.dev 上 kilo 的条目名甚至直接写着 "retires Oct 5"）。
//   依据：12 个月里 7 个免费入口消失，含 GitHub Models
//   （2026-07-30 整体退役，官方逐字 "has been fully retired"）。
//
// 形态约束：仓内**无 url_launcher**（pubspec.yaml 与全仓 launchUrl
// 零命中），且项目规则禁止引入当前未使用的新依赖 ⇒ 一键跳官网做不了，
// 改为「显示 URL + 一键复制」（沿用 _handleFeedback 的复制交互范式）。
//
// 入口：设置页 API 配置卡 `_buildConfigActions`（settings_page.dart:1206）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config/app_palette.dart';
import '../../config/app_theme.dart';

/// 一条官方免费档位。
///
/// 字段全部有据（2026-10-04 核验，见文件头注释）：
/// - [key] 预设 chip 用的模型名，必须与 `settings_page.dart` 的 `_llmPresets`
///   逐字一致，否则用户照抄后测试连接必然失败。
/// - [consoleUrl] 用户注册并创建密钥的控制台地址。
class FreeTierEntry {
  const FreeTierEntry({
    required this.provider,
    required this.key,
    required this.contextLabel,
    required this.notice,
    required this.consoleUrl,
  });

  /// 服务商名（如「智谱 GLM」）。
  final String provider;

  /// 官方文档归入 free 分类的模型 ID。
  final String key;

  /// 上下文/输出规格的简短说明。
  final String contextLabel;

  /// 计费口径的通俗说明。
  final String notice;

  /// 注册 + 创建密钥的控制台地址。
  final String consoleUrl;
}

/// 官方免费档位清单。
///
/// ★ 结构是「多 provider 清单」而非单家专页：新增服务商只追加一个
///   const 元素，页面骨架与渲染代码零改动。
const List<FreeTierEntry> kFreeTierEntries = [
  FreeTierEntry(
    provider: '智谱 GLM',
    key: 'glm-4.7-flash',
    contextLabel: '200K 上下文 · 128K 最大输出',
    notice: '免费档：输入 / 输出 / 缓存全免',
    consoleUrl: 'https://open.bigmodel.cn/usercenter/proj-mgmt/apikeys',
  ),
];

class FreeTierGuidePage extends StatelessWidget {
  const FreeTierGuidePage({super.key, this.entries = kFreeTierEntries});

  /// 待展示的免费档清单。生产路径恒为 [kFreeTierEntries]；
  /// 做成参数是为了让「新增服务商只需追加一个 const 条目、骨架零改动」
  /// 这条产品承诺**可被测试证伪**（测试注入第二家，断言两卡同构渲染）。
  final List<FreeTierEntry> entries;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('免费获取 API Key'), toolbarHeight: 48),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.page),
        children: [
          const _IntroCard(),
          for (final entry in entries) ...[
            SizedBox(height: AppSpacing.md),
            _FreeTierCard(entry: entry),
          ],
          const SizedBox(height: AppSpacing.md),
          const _StepsCard(),
          const SizedBox(height: AppSpacing.md),
          const _PaidProvidersSection(),
          const SizedBox(height: AppSpacing.md),
          const _DisclaimerCard(),
        ],
      ),
    );
  }
}

/// 开场说明：讲清「额度属于你」这件事（R-009 语境下的用户主权，
/// 同时消除「我是不是在给这个 app 交钱」的疑虑）。
class _IntroCard extends StatelessWidget {
  const _IntroCard();

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '先用免费档跑起来',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: context.palette.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '密钥由你自己在服务商官网注册获取，属于你自己的账号，'
            '本应用不经手、不存储到服务器、也不消耗你任何配额。',
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: context.palette.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// 单个免费档位卡片。
class _FreeTierCard extends StatelessWidget {
  const _FreeTierCard({required this.entry});

  final FreeTierEntry entry;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ProviderHeader(name: entry.provider),
          const SizedBox(height: AppSpacing.sm),
          Text(
            entry.key,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: context.palette.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${entry.contextLabel} · ${entry.notice}',
            style: TextStyle(fontSize: 12, color: context.palette.textTertiary),
          ),
          const SizedBox(height: AppSpacing.md),
          _CopyLinkButton(url: entry.consoleUrl),
        ],
      ),
    );
  }
}

/// 卡片头部：服务商名 + 「免费档」徽标。
///
/// 独立成组件而非留在 [_FreeTierCard.build] 里 —— 后者会因此超 50 行
/// （R-019 硬上限）。新增 provider 时这张卡的结构不用动。
class _ProviderHeader extends StatelessWidget {
  const _ProviderHeader({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            name,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: context.palette.textPrimary,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: 2,
          ),
          decoration: BoxDecoration(
            color: context.palette.successBg,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Text(
            '免费档',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: context.palette.success,
            ),
          ),
        ),
      ],
    );
  }
}

/// 「复制注册链接」按钮。
///
/// 无 url_launcher 可用 ⇒ 只能复制。复制后给明确的下一步提示，
/// 避免用户复制完不知道要干什么。
class _CopyLinkButton extends StatelessWidget {
  const _CopyLinkButton({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () async {
        await Clipboard.setData(ClipboardData(text: url));
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('链接已复制，请到浏览器打开并注册')));
      },
      icon: const Icon(Icons.link, size: 16),
      label: const Text('复制注册链接'),
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        foregroundColor: context.palette.primary,
      ),
    );
  }
}

/// 获取步骤。
class _StepsCard extends StatelessWidget {
  const _StepsCard();

  @override
  Widget build(BuildContext context) {
    const steps = <String>[
      '复制上面的链接，到浏览器打开并注册账号（手机号验证，不需要绑卡）',
      '进入「API keys」页面，创建并复制你的密钥',
      '回到设置页把密钥粘贴进「API Key」输入框',
      '点「测试连接」确认可用，再点「保存」',
    ];
    return _Card(
      title: '获取步骤',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: EdgeInsets.only(
                bottom: i == steps.length - 1 ? 0 : AppSpacing.sm,
              ),
              child: Text(
                '${i + 1}. ${steps[i]}',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: context.palette.textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 需付费的服务商名（默认折叠区内容）。
///
/// 独立成顶层常量：渲染逻辑与清单解耦，新增一家只改这一行。
const List<String> _kPaidProviders = [
  'DeepSeek',
  'Kimi（月之暗面）',
  '通义千问',
  '豆包（火山方舟）',
];

/// 折叠区内部：付费服务商逐行 + OpenAI 提示。
///
/// 抽成独立组件是为了把 [_PaidProvidersSection.build] 压到 50 行以内
/// （R-019 硬上限），不是纯为了凑行数 —— 它本身就是一个语义单元。
class _PaidProviderList extends StatelessWidget {
  const _PaidProviderList();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final name in _kPaidProviders)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Text(
              '· $name（按用量从账户余额扣除，需先充值）',
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: context.palette.textSecondary,
              ),
            ),
          ),
        Text(
          '· OpenAI 需国际卡，国内用户暂不建议',
          style: TextStyle(
            fontSize: 13,
            height: 1.5,
            color: context.palette.textTertiary,
          ),
        ),
      ],
    );
  }
}

/// 需要付费的服务商（默认折叠）。
///
/// ★ **刻意不给具体价格数字** —— 计价随时会变，我们也没有逐字核实过
///   官方价目页；给数字就要承担「数字漂移后被当作承诺」的风险。
///   写「按量计费，需先充值」既诚实又不会过期。
class _PaidProvidersSection extends StatelessWidget {
  const _PaidProvidersSection();

  @override
  Widget build(BuildContext context) {
    return _Card(
      padding: EdgeInsets.zero,
      child: Theme(
        // 去掉 ExpansionTile 默认的下划线分隔，与本页其他卡片统一。
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        // ★ 必须自带 Material：ExpansionTile 内部是 ListTile，而 _Card 是带
        // 背景色的 Container（DecoratedBox）。不包这一层 Flutter 会断言
        // "ListTile background color or ink splashes may be invisible"
        // —— 折叠区点击的涟漪会被卡片背景吞掉，debug 下直接抛异常。
        child: Material(
          type: MaterialType.transparency,
          child: ExpansionTile(
            title: Text(
              '其他服务商（需充值）',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: context.palette.textPrimary,
              ),
            ),
            childrenPadding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            children: const [_PaidProviderList()],
          ),
        ),
      ),
    );
  }
}

/// 诚实声明：免费档会消失。
///
/// 这不是免责套话，是**功能性文案** —— 12 个月里 7 个免费入口消失
/// （含 GitHub Models 2026-07-30 整体退役）。不给预期管理，
/// 用户遇到变更时会以为应用在骗人。
class _DisclaimerCard extends StatelessWidget {
  const _DisclaimerCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: context.palette.warningBg,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.palette.warning),
      ),
      child: Text(
        '免费档由服务商提供，会随其策略调整而变化。'
        '若某天该模型不可用，换用设置页里的其他模型即可 —— '
        '本应用不承诺任何免费额度长期有效。',
        style: TextStyle(
          fontSize: 12,
          height: 1.5,
          color: context.palette.textSecondary,
        ),
      ),
    );
  }
}

/// 通用卡片壳（与 settings_page 的 _SectionCard 同形，但本文件独立）。
class _Card extends StatelessWidget {
  const _Card({this.title, this.padding, required this.child});

  final String? title;
  final EdgeInsets? padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: context.palette.surfaceWhite,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.palette.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(
              title!,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: context.palette.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          child,
        ],
      ),
    );
  }
}
