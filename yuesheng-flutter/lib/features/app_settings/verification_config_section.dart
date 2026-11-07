// ─────────────────────────────────────────────────────────────
// VerificationConfigSection — 独立核对（验证层）三键配置入口（S1）
//
// 落点：设置页 ListView.children 末尾（_buildAboutSection() 之后）。
// 状态判据只认 VerificationKeys.isComplete（storage 回读），与主链
// _hasResolvedConfig / 「尚未配置 API」警告条完全隔离。
//
// 可注入读取源（02-派单 §九.6 硬约束①，L4 优先，防阶段三返工）：
//   · [keysLoader] 优先 → 阶段三可直接注入三空串负例；
//   · [storage] 次之 → 可注入 VerificationKeysStorage(fakeSecureStorage)；
//   · 两者皆 null → 生产默认 VerificationKeysStorage()。
//
// 五态：空「未启用」/ 齐「已启用」/ 加载「读取中…」/ 错误「读取失败」+重试
//   / 离线（纯本地读写，说明落在卡描述）。空态不出现空列表 /「暂无」。
// 文案只落 UI 层，不进任何模型消息 / prompt（R-027 边界）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../config/app_palette.dart';
import '../../config/app_theme.dart';
import '../../router/app_routes.dart';
import '../../services/verification_gate.dart';
import '../../theme/app_typography.dart';
import 'widgets/settings_cards.dart';

/// 设置页末尾的独立核对配置卡：常驻状态行 + 通往子页的 [ActionRow]。
class VerificationConfigSection extends StatefulWidget {
  /// 读取源函数（可注入，优先级最高）。null ⇒ 见 [storage] / 生产默认。
  final Future<VerificationKeys> Function()? keysLoader;

  /// 读取源实例（可注入）。null ⇒ 生产默认 `VerificationKeysStorage()`。
  final VerificationKeysStorage? storage;

  const VerificationConfigSection({super.key, this.keysLoader, this.storage});

  @override
  State<VerificationConfigSection> createState() =>
      _VerificationConfigSectionState();
}

class _VerificationConfigSectionState extends State<VerificationConfigSection> {
  late Future<VerificationKeys> _future;

  @override
  void initState() {
    super.initState();
    _future = _read();
  }

  Future<VerificationKeys> _read() async {
    final injected = widget.keysLoader;
    if (injected != null) return injected();
    return (widget.storage ?? VerificationKeysStorage()).load();
  }

  void _retry() => setState(() => _future = _read());

  /// 与 `_openApiConfigPage()` 同构（settings_page.dart:217-221）：
  /// 子页保存/清空后返回 ⇒ 重新读取 storage，状态行翻为「已启用 / 未启用」。
  Future<void> _openPage() async {
    await context.push(AppRoutes.verificationConfig);
    if (!mounted) return;
    setState(() => _future = _read());
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: SectionCard(
        title: '独立核对（验证层）配置',
        description:
            '独立的核对模型配置，与主对话、诊断所用的 API 配置分开，不影响主链；'
            '配置保存在本机，离线也可修改。',
        child: FutureBuilder<VerificationKeys>(
          future: _future,
          builder: (context, snapshot) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StatusLine(snapshot: snapshot, onRetry: _retry),
              ActionRow(label: '配置独立核对', onTap: _openPage),
            ],
          ),
        ),
      ),
    );
  }
}

/// 状态行：加载「读取中…」/ 错误「读取失败」+重试 / 空「未启用」/ 齐「已启用」。
/// 不显示空列表、不显示「暂无数据」；入口 [ActionRow] 在父级常驻，四态均保留。
class _StatusLine extends StatelessWidget {
  final AsyncSnapshot<VerificationKeys> snapshot;
  final VoidCallback onRetry;

  const _StatusLine({required this.snapshot, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    if (snapshot.hasError) {
      return _StatusBanner(
        label: '读取失败',
        background: context.palette.dangerBg,
        border: context.palette.dangerBorder,
        foreground: context.palette.danger,
        onRetry: onRetry,
      );
    }
    // 加载态（waiting / none）一律「读取中…」，绝不误报「未启用」。
    if (!snapshot.hasData) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Text('读取中…', style: context.text.caption),
      );
    }
    final complete = snapshot.data!.isComplete;
    return _StatusBanner(
      label: complete ? '已启用' : '未启用',
      background: complete
          ? context.palette.successBg
          : context.palette.dangerBg,
      border: complete
          ? context.palette.successBg
          : context.palette.dangerBorder,
      foreground: complete ? context.palette.success : context.palette.danger,
    );
  }
}

/// 复用已上线警告条的四段形态（淡底 → 边框 → 文字 → 行动指引），零新令牌。
class _StatusBanner extends StatelessWidget {
  final String label;
  final Color background;
  final Color border;
  final Color foreground;
  final VoidCallback? onRetry;

  const _StatusBanner({
    required this.label,
    required this.background,
    required this.border,
    required this.foreground,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: context.text.subBody.copyWith(color: foreground),
            ),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}
