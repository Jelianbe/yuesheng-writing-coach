// ─────────────────────────────────────────────────────────────
// SettingsPage — 设置页（缺口清单第 6 项 / D 类独立页面）
// 真源：yuesheng-android/src/app/settings.tsx
//
// 结构（对齐 RN）：
//   1. API 配置卡片：**账号列表**（查看 / 设默认 / 删除）+ 进入
//      `/settings/api-config` 子页的入口行
//   2. 维护卡片：清除缓存（删除无消息的孤儿会话）+ 反馈建议
//   3. 关于卡片：应用名称 / 版本 / 包名
//
// ★ **表单不在本页**（B5 第三批）：「填表单 + 测试 + 保存」整块已下沉为
//   子页 `api_config_page.dart`。原因：360x640 竖屏（平台唯一形态）下
//   主 CTA「测试并保存」实测 bottom=721，超首屏 81dp ⇒ 用户看不到它。
//   本页只保留账号列表（轻量、无表单状态）与一个入口行。
//
// 数据：账号读写走 AIAccountRepository（ADR-C91 多账号）
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/app_palette.dart';
import '../../config/app_theme.dart';
import '../../config/reasoning_tier.dart';
import '../../data/database/database.dart';
import '../../data/repositories/ai_account_repository.dart';
import '../../data/repositories/session_repository.dart';
import '../../providers/app_providers.dart';
import '../../providers/reasoning_tier_provider.dart';
import '../../providers/session_providers.dart';
import '../../theme/theme_controller.dart';
import '../../theme/theme_registry.dart';
import '../../router/app_routes.dart';
import '../../features/onboarding/onboarding_flow.dart';
import '../../services/error_handler.dart';
import '../../services/llm_config_resolver.dart';
import '../../services/llm_config_storage.dart';
import '../../services/llm_cost.dart';
import '../../services/llm_usage_report.dart';
import '../../services/progress_service.dart';
import '../../services/session_export_service.dart';
import '../../widgets/privacy_notice_dialog.dart';
import '../../theme/app_typography.dart';
import 'coach_settings_page.dart';
import 'widgets/settings_cards.dart';

/// 与 pubspec.yaml version 同步（发布前人工核对）
const String _appVersion = '0.4.1';
const String _packageName = 'com.yuesheng.writingcoach';
const String _feedbackQQGroup = '470562649';

class SettingsPage extends ConsumerStatefulWidget {
  /// 旧单键配置存储（测试可注入 fake）。
  ///
  /// ★ 本页**没有输入框**，故不需要为预填而读存储；这里只为「是否已有可用
  ///   配置」这一判据（决定要不要弹未配置警告）留一个注入口。生产路径恒为
  ///   null ⇒ `resolveLlmConfig` 内部自建真实 secure storage。
  final LlmConfigStorage? configStorage;

  const SettingsPage({super.key, this.configStorage});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late final AIAccountRepository _accountRepo;

  bool _accountsLoaded = false;

  /// 账号列表首次加载完成（未完成时不渲染「未配置」警告——否则加载态
  /// 会闪一下「尚未配置」，与加载完的真实状态相矛盾）
  bool _configLoaded = false;

  /// 是否已解析出**任一**可用配置（默认账号，或兼容旧单键）。
  ///
  /// ★ 不能按「账号列表为空」判未配置：ADR-C91 之前的用户只有旧三键存储、
  ///   没有账号行，按账号数判会对**已配好**的用户弹「尚未配置」假警报。
  bool _hasResolvedConfig = false;

  /// ADR-C91 多账号：账号列表（查看 / 设默认 / 删除；**不含表单**）
  List<AiAccountRow> _accounts = [];
  bool _isDeleting = false;

  /// 批次 38：最新会话的学习进度概览（学习进度从书架移至设置）
  ProgressSummary? _progressSummary;

  /// 进度对应的会话 ID（点击进入 progress-detail）
  String? _progressSessionId;

  /// `N7`：本周 LLM 用量 / 花费（数据源 = error_logs 的 llm_call 埋点，纯读取）
  LlmUsageReport? _usageReport;

  @override
  void initState() {
    super.initState();
    _accountRepo = AIAccountRepository(ref.read(appDatabaseProvider));
    _loadAccounts();
    _loadProgressSummary();
    _loadUsageReport();
    // 推理档位：读 app_state 水合到共享 provider（与聊天页同源，故不存本地副本）
    ref.read(reasoningTierProvider.notifier).hydrate();
  }

  /// `N7`：加载「本周调用统计」。
  ///
  /// 失败**静默降级**（与 `_loadProgressSummary` 同纪律：不阻塞设置页其他区块），
  /// 但**不塞一个 0 凑数** —— 加载失败时该区块整体不渲染，避免把
  /// 「查不到」显示成「这周没调用」（两者外观相同，本仓已栽过多次）。
  Future<void> _loadUsageReport() async {
    try {
      final report = await loadWeekLlmUsage(
        ref.read(appDatabaseProvider),
        nowUtc: DateTime.now().toUtc(),
      );
      if (!mounted) return;
      setState(() => _usageReport = report);
    } catch (_) {
      // 静默：区块不渲染
    }
  }

  /// 批次 38：加载最新会话的学习进度（对齐 RN bookshelf handleProgressPress 来源）
  Future<void> _loadProgressSummary() async {
    try {
      final sessionRepo = SessionRepository(ref.read(appDatabaseProvider));
      final sessions = await sessionRepo.listSessions(); // updated_at DESC
      if (sessions.isEmpty || !mounted) return;
      final latestId = sessions.first.id;
      final service = ProgressService(ref.read(appDatabaseProvider));
      final summary = await service.getProgressSummary(latestId);
      if (!mounted) return;
      setState(() {
        _progressSummary = summary;
        _progressSessionId = latestId;
      });
    } catch (_) {
      // 进度摘要加载失败静默（不阻塞设置页其他区块）
    }
  }

  /// 切换推理档位：写共享 provider（乐观更新 + 落 app_state + 失败回滚）。
  /// 聊天页头部「更多」菜单与输入框开关走同一 notifier ⇒ 改一处两处同步。
  Future<void> _handleSelectReasoningTier(String tierKey) async {
    final ok = await ref.read(reasoningTierProvider.notifier).setTier(tierKey);
    if (!ok) _notify('档位保存失败，已恢复原设置', error: true);
  }

  /// 批次 38：点击进度区块 → 学习进度详情页
  void _openProgressDetail() {
    final sessionId = _progressSessionId;
    if (sessionId == null) return;
    context.push(
      AppRoutes.progressDetail,
      extra: <String, dynamic>{'sessionId': sessionId},
    );
  }

  /// 加载账号列表（ADR-C91）。
  ///
  /// ★ 只读列表，**不填任何表单** —— 表单已下沉到 api_config_page.dart。
  /// 失败静默（不阻塞设置页其他区块）。
  Future<void> _loadAccounts() async {
    try {
      final accounts = await _accountRepo.listAccounts();
      // 有无「可用配置」交给解析器判定（含旧单键回退），不要按账号数硬判 ——
      // ADR-C91 之前的用户只有旧三键、没有账号行。
      final config = await resolveLlmConfig(
        ref.read(appDatabaseProvider),
        legacyStorage: widget.configStorage,
      );
      if (mounted) {
        setState(() {
          _accounts = accounts;
          _hasResolvedConfig = config != null;
        });
      }
    } catch (_) {
      // 静默：列表区保持空
    } finally {
      if (mounted) {
        setState(() {
          _accountsLoaded = true;
          _configLoaded = true;
        });
      }
    }
  }

  /// 重新加载账号列表（子页保存/删除后返回时刷新；R-009：用户要立刻看到新账号）
  Future<void> _reloadAccounts() async {
    final accounts = await _accountRepo.listAccounts();
    if (mounted) setState(() => _accounts = accounts);
  }

  /// 进入 API 配置子页，返回后**无条件重载账号列表**。
  ///
  /// 为什么用「返回后重载」而不是子页回传结果值：子页除了保存，还会
  /// **删除账号**与**清空配置**——回传一个 bool 覆盖不到这两条路径，
  /// 用户会看到已删的账号还在列表里。重载对所有路径都正确。
  /// `await context.push` 的先例：features/character/character_detail_page.dart。
  Future<void> _openApiConfigPage() async {
    await context.push(AppRoutes.apiConfig);
    if (!mounted) return;
    await _reloadAccounts();
  }

  void _notify(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? context.palette.danger : null,
      ),
    );
  }

  /// 清除缓存：删除无消息的孤儿会话（对齐 RN handleClearCache SQL）
  Future<void> _handleClearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('清除缓存', style: context.text.titleLg),
        content: Text(
          '这将清除所有本地缓存数据（不包括作品和章节内容）。确定继续吗？',
          textAlign: TextAlign.center,
          style: context.text.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('清除', style: TextStyle(color: context.palette.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final sessionRepo = SessionRepository(ref.read(appDatabaseProvider));
      final deleted = await sessionRepo.deleteOrphanSessions();
      // 保障：删除孤儿会话后，若 LAST_SESSION_KEY 指向被删会话则同步清除，
      // 避免下次启动 bootstrap 恢复死会话 ID（发送消息 FK 失败根因二配套）。
      final lastStorage = ref.read(lastSessionStorageProvider);
      final lastId = await lastStorage.getLastSessionId();
      if (lastId != null) {
        final remaining = await sessionRepo.listSessions();
        if (!remaining.any((s) => s.id == lastId)) {
          await lastStorage.clearLastSessionId();
        }
      }
      _notify(deleted > 0 ? '缓存已清除（移除 $deleted 个空会话）' : '缓存已清除');
    } catch (_) {
      _notify('清除失败，请稍后再试', error: true);
    }
  }

  /// 反馈建议：联系方式对话框（QQ 群，群号可一键复制）
  void _handleFeedback() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('反馈', style: context.text.titleLg),
        content: Text(
          '遇到问题或有建议？欢迎加入 QQ 群交流反馈：\n\nQQ 群：$_feedbackQQGroup',
          textAlign: TextAlign.center,
          style: context.text.body,
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _feedbackQQGroup));
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('群号已复制')));
              }
            },
            child: const Text('复制群号'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  /// 导出会话记录（JSON）：确认（含作品内容提示）→ 收集最新会话 → 系统分享
  Future<void> _handleExportSession() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('导出会话记录', style: context.text.titleLg),
        content: Text(
          '将导出最近一个会话的完整记录（JSON 文件），其中包含你的作品原文与练习内容。\n\n'
          '是否脱敏由你自行判断；文件发给谁也由你决定。继续导出吗？',
          style: context.text.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('导出'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final result = await collectLatestSessionExport(
        ref.read(appDatabaseProvider),
      );
      if (!mounted) return;
      if (result == null) {
        _notify('还没有可导出的会话');
        return;
      }
      await shareSessionExport(
        json: result.json,
        fileName: result.fileName,
        subject: '月笙写作教练 — 会话记录（${result.sessionTitle}）',
      );
    } catch (e, st) {
      ErrorHandler.instance.captureError(
        level: 'error',
        category: 'general',
        message: '会话导出失败: $e',
        stack: st.toString(),
      );
      if (mounted) _notify('导出失败，请稍后再试', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 思考档位读共享 provider（与聊天页同源；本页不持本地副本，避免双真源）
    final reasoningTier = ref.watch(reasoningTierProvider);
    final themeId = ref.watch(themeControllerProvider);
    return Scaffold(
      backgroundColor: context.palette.background,
      appBar: AppBar(
        title: const Text('设置'),
        backgroundColor: context.palette.background,
        foregroundColor: context.palette.textPrimary,
        toolbarHeight: 48,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 22),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/bookshelf'),
          tooltip: '返回',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          // 批次 38：学习进度区块（学习进度从书架移至设置，书架保持纯洁）
          if (_progressSummary != null) ...[
            _ProgressSection(
              summary: _progressSummary!,
              onTap: _openProgressDetail,
            ),
            const SizedBox(height: 12),
          ],
          _buildApiSection(),
          const SizedBox(height: 12),
          _buildUsageSection(),
          const SizedBox(height: 12),
          _buildAppearanceSection(themeId),
          const SizedBox(height: 12),
          _buildModelBehaviorSection(reasoningTier),
          const SizedBox(height: 12),
          _buildCoachEntrySection(),
          const SizedBox(height: 12),
          _buildMaintenanceSection(),
          const SizedBox(height: 12),
          _buildAboutSection(),
        ],
      ),
    );
  }

  // ── API 配置 ──

  /// 账号列表（ADR-C91 多账号）：行 = 名称+model+默认徽标+设默认/删除
  ///
  /// ★ 本页**没有表单**，故账号行不再「载入表单进编辑态」，而是
  ///   **进入 API 配置子页**去编辑（那里才有输入框）。
  Widget _buildAccountList() {
    if (!_accountsLoaded || _accounts.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FieldLabel('已保存的账号（${_accounts.length}）'),
        for (final account in _accounts) _buildAccountRow(account),
        const SizedBox(height: 4),
      ],
    );
  }

  /// 单账号行（ADR-C91）：默认徽标；设默认/删除操作；点行进子页编辑
  Widget _buildAccountRow(AiAccountRow account) {
    final busy = _isDeleting;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: context.palette.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              onTap: busy ? null : _openApiConfigPage,
              child: _buildAccountInfo(account),
            ),
          ),
          if (!account.isDefault)
            TextButton(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                foregroundColor: context.palette.primary,
              ),
              onPressed: busy ? null : () => _handleSetDefault(account.id),
              child: const Text('设默认', style: TextStyle(fontSize: 12)),
            ),
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            tooltip: '删除账号',
            icon: Icon(Icons.delete_outline, color: context.palette.danger),
            onPressed: busy ? null : () => _handleDeleteAccount(account),
          ),
        ],
      ),
    );
  }

  /// 账号行信息区：名称 + 默认徽标 + model·baseUrl 摘要
  Widget _buildAccountInfo(AiAccountRow account) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAccountTitle(account),
          const SizedBox(height: 2),
          Text(
            '${account.model} · ${account.baseUrl}',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: context.palette.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  /// 账号行标题：名称 + 默认徽标
  Widget _buildAccountTitle(AiAccountRow account) {
    return Row(
      children: [
        Flexible(
          child: Text(
            account.name,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: context.palette.textPrimary,
            ),
          ),
        ),
        if (account.isDefault) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: context.palette.primarySoft,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '默认',
              style: TextStyle(fontSize: 11, color: context.palette.primary),
            ),
          ),
        ],
      ],
    );
  }

  /// 设默认（应用层保证全局唯一默认）
  Future<void> _handleSetDefault(String accountId) async {
    try {
      await _accountRepo.setDefault(accountId);
      await _reloadAccounts();
      _notify('已设为默认账号');
    } catch (_) {
      _notify('操作失败，请稍后再试', error: true);
    }
  }

  /// 删除账号：确认 → 至少保留一个（最后账号拒绝）→ 默认被删时表单载入新默认
  Future<void> _handleDeleteAccount(AiAccountRow account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除账号', style: context.text.titleLg),
        content: Text(
          '确定删除账号「${account.name}」吗？',
          textAlign: TextAlign.center,
          style: context.text.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.palette.danger,
              foregroundColor: context.palette.onPrimary,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _isDeleting = true);
    try {
      await _accountRepo.deleteAccount(account.id);
      await _reloadAccounts(); // 刷新列表
      _notify('账号已删除');
    } catch (_) {
      _notify('删除失败：至少保留一个账号', error: true);
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  // ── 外观（手动主题选择） ──

  /// 外观区块：从主题注册表列出所有可用主题，二选一（不跟随系统）。
  ///
  /// 主题经 [themeControllerProvider] 单一真源驱动，写操作乐观更新 + 落 app_state。
  /// 注册表加新主题后，此处自动出现新选项（无需改本 widget）。
  Widget _buildAppearanceSection(ThemeId current) {
    return SectionCard(
      title: '外观',
      description: '手动选择配色主题（不跟随系统深色）',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final id in ThemeId.values)
            ChoiceChip(
              label: Text(_themeLabel(id)),
              selected: current == id,
              onSelected: (_) => _handleSelectTheme(id),
            ),
        ],
      ),
    );
  }

  static String _themeLabel(ThemeId id) => switch (id) {
    ThemeId.light => '亮色',
    ThemeId.dark => '暗色',
  };

  Future<void> _handleSelectTheme(ThemeId id) async {
    await ref.read(themeControllerProvider.notifier).select(id);
  }

  // ── 模型行为（推理档位） ──

  /// 推理档位选择（用户可调「思考开关」）：决定回复的速度 / 深度 / 消耗。
  /// [tier] 由 build 从共享 provider 读取后传入（本页不再持本地副本）。
  Widget _buildModelBehaviorSection(String tier) {
    return SectionCard(
      title: '模型行为',
      description: '控制模型回复时的思考深度（影响速度、质量与 token 消耗）',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final preset in reasoningTierPresets)
                ChoiceChip(
                  label: Text(preset.label),
                  selected: tier == preset.key,
                  onSelected: (_) => _handleSelectReasoningTier(preset.key),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            reasoningTierOf(tier).hint,
            style: TextStyle(fontSize: 12, color: context.palette.textTertiary),
          ),
        ],
      ),
    );
  }

  // ── 教练设置入口（教练人格/教学方式收进二级页） ──

  Widget _buildCoachEntrySection() {
    return SectionCard(
      title: '教练',
      child: Column(
        children: [
          ActionRow(
            label: '教练人格与教学方式',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const CoachSettingsPage(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 本周调用统计（`N7`，2026-09-20 改全模型通用口径） ──

  /// 注脚统一样式（12px 三级灰）—— 抽出来避免同一字面量重复四次。
  /// 取运行期调色板色 → 随主题翻；故为实例 getter（依赖 State.context），非 static const。
  TextStyle get _usageNoteStyle =>
      TextStyle(fontSize: 12, color: context.palette.textTertiary);

  /// 本周调用统计卡片（**全模型通用**：次数 / token 消耗 / 缓存命中率）。
  ///
  /// ★ 2026-09-20 改造：不再显示折算金额。原「峰时 = 闲时 ×2」只对
  /// DeepSeek 成立，套到其它厂商会**凭空捏造费用**（详见 `llm_cost.dart`
  /// 文件头）。现只统计**不依赖厂商计价规则**的客观量。
  ///
  /// 读数**未就绪时整块不渲染**（加载中或查询失败）—— 不用 0 占位，
  /// 否则「查不到」与「这周没调用」外观完全相同。
  Widget _buildUsageSection() {
    final report = _usageReport;
    if (report == null) return const SizedBox.shrink();
    return SectionCard(
      title: '本周调用统计',
      description:
          '${_weekStartLabel(report.sinceEpochSec)} 起本机调用统计 · '
          '按各厂商实际返回的 token 计量，不折算金额',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _usageHeadline(report),
          const SizedBox(height: 10),
          _UsageStatRow(
            stats: [
              ('输入命中', _compactTokens(report.cachedTokens)),
              ('输入未命中', _compactTokens(report.missTokens)),
              ('输出', _compactTokens(report.completionTokens)),
              ('缓存命中率', '${(report.cacheHitRate * 100).toStringAsFixed(0)}%'),
            ],
          ),
          ..._usageNotes(report),
        ],
      ),
    );
  }

  /// 卡片首行：**总消耗 token**（主读数）+ 调用次数（次级）。
  Widget _usageHeadline(LlmUsageReport report) => Row(
    crossAxisAlignment: CrossAxisAlignment.baseline,
    textBaseline: TextBaseline.alphabetic,
    children: [
      Text(_compactTokens(report.totalTokens), style: context.text.titleLg),
      const SizedBox(width: 4),
      Text('tokens', style: _usageNoteStyle),
      const SizedBox(width: 8),
      Text('${report.calls} 次调用', style: _usageNoteStyle),
    ],
  );

  /// 一条**条件**注脚：坏行条数。
  ///
  /// 无内容时返回空列表（由调用点 `...` 展开），故卡片不会留空行。
  List<Widget> _usageNotes(LlmUsageReport report) => [
    if (report.skippedRows > 0) ...[
      const SizedBox(height: 8),
      Text(
        '另有 ${report.skippedRows} 条调用埋点缺少 token 明细，未计入（不是 0 消耗）',
        style: _usageNoteStyle,
      ),
    ],
    if (report.nonCallApiRows > 0) ...[
      const SizedBox(height: 8),
      Text(
        '另有 ${report.nonCallApiRows} 条 API 层告警（模型输出解析降级等），未计入调用统计',
        style: _usageNoteStyle,
      ),
    ],
  ];

  /// 周起点（UTC epoch 秒）→ 「M月d日」的**北京时间**表述。
  static String _weekStartLabel(int sinceEpochSec) {
    final cst = DateTime.fromMillisecondsSinceEpoch(
      sinceEpochSec * 1000,
      isUtc: true,
    ).add(kCstOffset);
    return '${cst.month}月${cst.day}日';
  }

  /// token 数的紧凑写法（千 / 百万），避免长数字撑破窄屏。
  static String _compactTokens(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(2)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }

  /// API 配置卡：**只有账号列表 + 进入子页的入口行**。
  ///
  /// ★ 表单整块在 `api_config_page.dart`。此处保留列表是因为「我配了几个账号 /
  ///   当前默认是谁 / 删掉不要的那个」是**回访型**需求，用户在设置页就该看到，
  ///   不该为了看一眼账号先进子页。
  Widget _buildApiSection() {
    return SectionCard(
      title: 'API 配置',
      description: '配置大语言模型连接参数，用于写作诊断与智能对话',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_configLoaded && !_hasResolvedConfig) _buildApiWarning(),
          _buildAccountList(),
          const Divider(height: 20, color: Color(0x00000000)),
          ActionRow(label: '添加 / 编辑 API 配置', onTap: _openApiConfigPage),
        ],
      ),
    );
  }

  /// 未配置 API 时的「免费测试模式」提示条
  ///
  /// 判据从「表单三项是否填全」改为「**有没有账号**」——本页已无表单。
  /// 文案指向下方的入口行（「添加 / 编辑 API 配置」）而非「填写以下信息」。
  Widget _buildApiWarning() => Container(
    margin: const EdgeInsets.only(bottom: AppSpacing.md),
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.sm,
    ),
    decoration: BoxDecoration(
      color: context.palette.dangerBg,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      border: Border.all(color: context.palette.dangerBorder),
    ),
    child: Text(
      // 与 api_config_page 的同类警告条同源（共享常量 `buildUnconfiguredWarning`）：
      // 前半句逐字相同，只有行动指引随表单位置而异（设置页表单在别处、本页在正下方）。
      buildUnconfiguredWarning(onSettingsPage: true),
      style: TextStyle(fontSize: 13, color: context.palette.danger),
    ),
  );

  // ── 维护 ──
  Widget _buildMaintenanceSection() {
    return SectionCard(
      title: '维护',
      child: Column(
        children: [
          ActionRow(label: '导出会话记录（JSON）', onTap: _handleExportSession),
          Divider(height: 1, color: context.palette.borderSoft),
          ActionRow(label: '清除缓存', onTap: _handleClearCache),
          Divider(height: 1, color: context.palette.borderSoft),
          ActionRow(label: '反馈建议', onTap: _handleFeedback),
        ],
      ),
    );
  }

  // ── 关于 ──
  Widget _buildAboutSection() {
    return SectionCard(
      title: '关于',
      child: Column(
        children: [
          const _AboutRow(label: '应用名称', value: '月笙写作教练'),
          Divider(height: 1, color: context.palette.borderSoft),
          _AboutRow(label: '版本', value: 'v$_appVersion'),
          Divider(height: 1, color: context.palette.borderSoft),
          const _AboutRow(label: '包名', value: _packageName),
          Divider(height: 1, color: context.palette.borderSoft),
          ActionRow(
            label: '隐私与费用说明',
            onTap: () => showPrivacyNoticeDialog(context),
          ),
          ActionRow(label: '重看新手引导', onTap: _replayOnboarding),
        ],
      ),
    );
  }

  /// 重看新手引导（设置页「关于」区块入口）。
  /// 仅以全屏路由覆盖层重新展示 [OnboardingFlow]，关闭即消失；
  /// **不回写** `onboarding_completed`（该 flag 由首启门管理，且 SEED_DEMO 也写它，
  /// 重看逻辑必须独立，避免误触发或无法关闭）。
  void _replayOnboarding() {
    final ctx = context;
    Navigator.of(ctx).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            OnboardingFlow(onComplete: () => Navigator.of(ctx).pop()),
      ),
    );
  }
}

class _AboutRow extends StatelessWidget {
  final String label;
  final String value;
  const _AboutRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        children: [
          Expanded(child: Text(label, style: context.text.body)),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              color: context.palette.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// 学习进度区块（批次 38：从书架移至设置，对齐 RN bookshelf ProgressCard）
/// 展示最新会话的学习进度概览，点击进入 progress-detail 页
class _ProgressSection extends StatelessWidget {
  final ProgressSummary summary;
  final VoidCallback onTap;
  const _ProgressSection({required this.summary, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final progress = summary.totalProblems > 0
        ? summary.resolvedProblems * 100 / summary.totalProblems
        : 0.0;
    final phaseLabel =
        progressPhaseLabels[summary.currentPhase] ?? summary.currentPhase.value;

    return SectionCard(
      title: '学习进度',
      description: '基于最近一次写作会话的进度概览',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildProgressHeader(context, phaseLabel, progress),
          const SizedBox(height: 10),
          _buildProgressBar(context, progress),
          const SizedBox(height: 12),
          _buildProgressStats(context),
          const SizedBox(height: 4),
          _buildProgressDetailEntry(context),
        ],
      ),
    );
  }

  Widget _buildProgressHeader(
    BuildContext context,
    String phaseLabel,
    double progress,
  ) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      _buildPhaseBadge(context, phaseLabel),
      _buildCompletionLabel(context, progress),
    ],
  );

  Widget _buildPhaseBadge(BuildContext context, String phaseLabel) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.sm,
      vertical: AppSpacing.xs,
    ),
    decoration: BoxDecoration(
      color: context.palette.primarySoft,
      borderRadius: BorderRadius.circular(AppRadius.sm),
    ),
    child: Text(
      phaseLabel,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: context.palette.primary,
      ),
    ),
  );

  Widget _buildCompletionLabel(BuildContext context, double progress) => Row(
    crossAxisAlignment: CrossAxisAlignment.baseline,
    textBaseline: TextBaseline.alphabetic,
    children: [
      Text(
        '${progress.round()}%',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: context.palette.textPrimary,
        ),
      ),
      const SizedBox(width: 4),
      Text('完成度', style: context.text.caption),
    ],
  );

  Widget _buildProgressBar(BuildContext context, double progress) => ClipRRect(
    borderRadius: BorderRadius.circular(AppRadius.xs),
    child: LinearProgressIndicator(
      value: progress / 100,
      minHeight: 6,
      backgroundColor: context.palette.background,
      valueColor: AlwaysStoppedAnimation(context.palette.primary),
    ),
  );

  Widget _buildProgressStats(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
    decoration: BoxDecoration(
      color: context.palette.background,
      borderRadius: BorderRadius.circular(AppRadius.md),
    ),
    child: Row(
      children: [
        _ProgressStat(value: '${summary.totalProblems}', label: '总问题'),
        Container(width: 1, height: 28, color: context.palette.divider),
        _ProgressStat(value: '${summary.resolvedProblems}', label: '已解决'),
        Container(width: 1, height: 28, color: context.palette.divider),
        _ProgressStat(value: '${summary.activeProblems}', label: '待改进'),
      ],
    ),
  );

  /// 详情入口（对齐 RN footer）：诊断次数 + 查看详情
  Widget _buildProgressDetailEntry(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(AppRadius.sm),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '诊断 ${summary.totalDiagnoses} 次',
            style: TextStyle(fontSize: 12, color: context.palette.disabledText),
          ),
          Row(
            children: [
              Text(
                '查看详情',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: context.palette.primary,
                ),
              ),
              SizedBox(width: 2),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: context.palette.primary,
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

/// 进度区块统计项（对齐 RN statItem）
class _ProgressStat extends StatelessWidget {
  final String value;
  final String label;
  const _ProgressStat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: context.text.titleLg),
          const SizedBox(height: 2),
          Text(label, style: context.text.caption),
        ],
      ),
    );
  }
}

/// `N7` 本周调用统计：四格统计行（token 拆解 + 缓存命中率）。
///
/// 与 [_ProgressStat] 同形但**不共用**：后者的 `value` 是主读数、字号 `titleLg`，
/// 这里四格并排是**次级明细**，用 `body` 级字号才不会与卡片首行的主读数抢层级。
class _UsageStatRow extends StatelessWidget {
  /// (标签, 值) 四元组，顺序即展示顺序
  final List<(String, String)> stats;

  const _UsageStatRow({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (label, value) in stats)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: context.text.body),
                const SizedBox(height: 2),
                Text(label, style: context.text.caption),
              ],
            ),
          ),
      ],
    );
  }
}
