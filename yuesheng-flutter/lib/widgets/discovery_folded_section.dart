// ─────────────────────────────────────────────────────────────
// DiscoveryFoldedSection — 「本次未归类」可展开折叠条（S3 · T-20261108-02）
// 授权面 = .ai/reports/2026-11-08-S3-三态设计稿-报批单.md（R-027 已批，
//   2026-11-08 舰长「批」）。形态丙：不新开页面、不进 AppBar、不改主判区排布；
//   范围只出口三（observation 留作内部审计）。
// 三态判据（报批单 §二/§五）：①未配置 ⇒ 单行明示，不显空列表；②已配置+
//   零条目 ⇒ 「本次全部已归类」，文案与①逐字不同；③有条目 ⇒ 默认收起，展开逐条。
// 视觉 = excluded_folded_section 同族范式；引用块对齐 _EvidenceQuote（竹青竖线+斜体）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_motion.dart';
import '../config/app_palette.dart';
import '../config/app_theme.dart';
import '../services/discovery_card_payload.dart';
import '../theme/app_typography.dart';

/// 文案逐字真源 = 报批单 §四（R-027 已批）——**改一字须再报批**。
class _DiscoveryCopy {
  static const String notConfigured = '验证层未启用，本次无清单外发现';
  static const String allClassified = '本次全部已归类';
  static const String sectionTitle = '未归类现象';
  static const String bottomDeclaration = '这些现象暂不在症候清单内，仅记录，供你参考。';
  static const String expandFull = '展开全文';
  static const String collapse = '收起';
  const _DiscoveryCopy._();
}

/// reason 折叠阈值：约 3 行（12px/1.4/卡宽 ~360dp ≈ 60 汉字）。长度启发式：
/// 误判代价 = 多一个「展开全文」，不影响数据完整性（展开恒给全文，§四红线）。
const int _kReasonFoldChars = 60;

/// 展开态列表最大高度（dp）——竖屏一屏约束（报批单 §三；超出内滚不分页）。
const double _kMaxExpandedHeight = 240;

class DiscoveryFoldedSection extends StatefulWidget {
  /// null = 本轮未走到发现层（短文单次链路 / 旧消息无 key）⇒ S0 整体不渲染。
  final DiscoverySectionCard? section;

  const DiscoveryFoldedSection({super.key, this.section});

  @override
  State<DiscoveryFoldedSection> createState() => _DiscoveryFoldedSectionState();
}

class _DiscoveryFoldedSectionState extends State<DiscoveryFoldedSection> {
  /// 展开态：组件本地、不持久化（重建后回收起，对齐先例口径）。
  bool _expanded = false;

  /// reason 二次展开的条目下标（「展开全文」⇄「收起」，无第三层）。
  final Set<int> _fullReasonRows = {};

  final ScrollController _scroll = ScrollController();
  bool _canScroll = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_updateCanScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateCanScroll());
  }

  /// 内容超高（>240dp）才出现的底缘渐隐判据；不可滚时不挂遮罩，避免渐隐压到声明行。
  void _updateCanScroll() {
    final can = _scroll.hasClients && _scroll.position.maxScrollExtent > 0;
    if (can != _canScroll && mounted) setState(() => _canScroll = can);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.section;
    if (s == null) return const SizedBox.shrink(); // S0：未走到发现层 ⇒ 不渲染。
    // 态①/态②：单行静态文案（无展开符、无列表 —— 判据①②「不显空列表」）。
    if (!s.configured) return _buildStaticRow(_DiscoveryCopy.notConfigured);
    if (s.unclassified.isEmpty) {
      return _buildStaticRow(_DiscoveryCopy.allClassified);
    }
    // 态③：可展开折叠条，默认收起（判据③：不挤占主判）。
    final body = _expanded
        ? _buildExpandedBody(context)
        : const SizedBox(width: double.infinity);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFoldRow(context, s.unclassified.length),
          // prefers-reduced-motion：直接换子树（对齐先例，规避 RenderAnimatedSize 断言）。
          if (MediaQuery.disableAnimationsOf(context))
            body
          else
            AnimatedSize(
              duration: AppMotion.durationStandard,
              curve: AppMotion.curveFade,
              alignment: Alignment.topCenter,
              child: body,
            ),
        ],
      ),
    );
  }

  /// 态①/态②：单行静态文案（不可展开，无箭头无触控）。
  Widget _buildStaticRow(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Text(
        text,
        style: context.text.caption.copyWith(
          color: context.palette.textTertiary,
        ),
      ),
    );
  }

  /// 态③收起行：两行文案（标题 + 摘要）+ 展开符，触控区 ≥44。
  Widget _buildFoldRow(BuildContext context, int count) {
    final summary = '$count 条不在症候清单内';
    return Semantics(
      button: true,
      label: '$_DiscoveryCopy.sectionTitle $summary，${_expanded ? '收起' : '展开'}',
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _DiscoveryCopy.sectionTitle,
                      style: context.text.caption.copyWith(
                        color: context.palette.textTertiary,
                      ),
                    ),
                    Text(
                      summary,
                      style: context.text.caption.copyWith(
                        color: context.palette.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                _expanded ? Icons.expand_less : Icons.expand_more,
                size: 12,
                color: context.palette.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 态③展开体：240dp 内滚逐条 + 底部边界声明（仅展开态可见）。
  Widget _buildExpandedBody(BuildContext context) {
    final items = widget.section!.unclassified;
    Widget list = SingleChildScrollView(
      controller: _scroll,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < items.length; i++)
            _buildItem(context, i, items[i]),
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              _DiscoveryCopy.bottomDeclaration,
              style: context.text.caption.copyWith(
                color: context.palette.textTertiary,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
    if (_canScroll) {
      list = ShaderMask(
        shaderCallback: (bounds) => LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [
            Color(0xFFFFFFFF),
            Color(0xFFFFFFFF),
            Color(0x00FFFFFF),
          ],
          stops: [
            0,
            (bounds.height - 8).clamp(0.0, bounds.height) / bounds.height,
            1,
          ],
        ).createShader(bounds),
        blendMode: BlendMode.dstOut,
        child: list,
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xxs),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: _kMaxExpandedHeight),
        child: list,
      ),
    );
  }

  /// 逐条 item：`{n}. 原句：「…」`（多条逐行）+ `说明：{reason}`（默认限 3 行）。
  Widget _buildItem(BuildContext context, int index, DiscoveryNoteCard note) {
    final quoteStyle = context.text.caption.copyWith(
      color: context.palette.textDeep,
      fontStyle: FontStyle.italic,
      height: 1.4,
    );
    final reasonStyle = context.text.caption.copyWith(
      color: context.palette.textTertiary,
      fontSize: 11,
      height: 1.4,
    );
    final quotes = note.anchorQuotes.isEmpty ? <String>[''] : note.anchorQuotes;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var q = 0; q < quotes.length; q++)
            Padding(
              padding: EdgeInsets.only(top: q == 0 ? 0 : AppSpacing.xxs),
              child: Container(
                // 引用块：左 3dp 竹青竖线（对齐 _EvidenceQuote 同族，零新视觉语言）。
                padding: const EdgeInsets.only(left: 6),
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: context.palette.primary, width: 3),
                  ),
                ),
                child: Text(
                  "${q == 0 ? '${index + 1}. ' : ''}原句：「${quotes[q]}」",
                  style: quoteStyle,
                ),
              ),
            ),
          _buildReason(context, index, note.reason, reasonStyle),
        ],
      ),
    );
  }

  /// reason 行：默认限 3 行 + 省略（截断形态甲）；展开恒给全文（§四红线）。
  Widget _buildReason(
    BuildContext context,
    int index,
    String reason,
    TextStyle style,
  ) {
    final canFold = reason.length > _kReasonFoldChars;
    final isFull = _fullReasonRows.contains(index);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xxs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '说明：$reason',
            style: style,
            maxLines: isFull ? null : 3,
            overflow: isFull ? null : TextOverflow.ellipsis,
          ),
          if (canFold)
            GestureDetector(
              onTap: () => setState(
                () => isFull
                    ? _fullReasonRows.remove(index)
                    : _fullReasonRows.add(index),
              ),
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  isFull ? _DiscoveryCopy.collapse : _DiscoveryCopy.expandFull,
                  style: style.copyWith(color: context.palette.primaryDeep),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
