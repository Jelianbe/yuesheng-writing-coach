// ─────────────────────────────────────────────────────────────
// SettingsPage — 设置页（缺口清单第 6 项 / D 类独立页面）
// 真源：yuesheng-android/src/app/settings.tsx
//
// 结构（对齐 RN）：
//   1. API 配置卡片：3 输入框（API Key 密文 / Base URL / Model）
//      + 保存配置 / 测试连接 / 填充示例 / 清空配置 + 结果框 + 未配置警告
//   2. 维护卡片：清除缓存（删除无消息的孤儿会话）+ 反馈建议
//   3. 关于卡片：应用名称 / 版本 / 包名
//
// 数据：LlmConfigStorage（flutter_secure_storage）+ LlmClient.testLlmConnection
// 测试可注入 configStorage / llmClient（默认走真实存储与网络）
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
import '../../services/error_handler.dart';
import '../../services/llm_client.dart';
import '../../services/llm_config_storage.dart';
import '../../services/llm_cost.dart';
import '../../services/llm_usage_report.dart';
import '../../services/progress_service.dart';
import '../../services/session_export_service.dart';
import '../../widgets/privacy_notice_dialog.dart';
import '../../theme/app_typography.dart';

/// 与 pubspec.yaml version 同步（发布前人工核对）
const String _appVersion = '0.1.0';
const String _packageName = 'com.yuesheng.writingcoach';
const String _feedbackQQGroup = '470562649';

/// OpenAI 兼容供应商预设（ADR-C83：扩展多模型）。选中自动填 Base URL +
/// Model 默认值；API Key 各供应商独立，仍需用户自行填写（R-029 零硬编码）。
/// 模型时效性核验（2026-09-10，以各供应商官方 API 文档为准）：
/// - deepseek-v4-flash：DeepSeek 现行主模型（deepseek-chat/reasoner 已于
///   2026-07-24 弃用，分别映射至 v4-flash 非思考/思考模式）
/// - gpt-4.1：OpenAI chat/completions 稳定模型（gpt-4o 已从 ChatGPT 淘汰，
///   gpt-5 系为 reasoning-only，走 responses/max_completion_tokens 语义）
/// - kimi-k3：Kimi 现行旗舰（moonshot-v1 系列已于 2026-08-31 下线）
/// - qwen-plus：通义稳定别名，仍可用
/// - glm-4.6：智谱现行旗舰（glm-4 已过时，glm-4.5-X 即将下线）
/// - doubao-seed-2.1-turbo：火山方舟现行主力（doubao-pro-32k 已过时）
const List<({String name, String baseUrl, String model})> _llmPresets = [
  (
    name: 'DeepSeek',
    baseUrl: 'https://api.deepseek.com',
    model: 'deepseek-v4-flash',
  ),
  (name: 'OpenAI', baseUrl: 'https://api.openai.com/v1', model: 'gpt-4.1'),
  (name: 'Kimi（月之暗面）', baseUrl: 'https://api.moonshot.cn/v1', model: 'kimi-k3'),
  (
    name: '通义千问',
    baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    model: 'qwen-plus',
  ),
  (
    name: '智谱 GLM',
    baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
    model: 'glm-4.6',
  ),
  (
    name: '豆包（火山方舟）',
    baseUrl: 'https://ark.cn-beijing.volces.com/api/v3',
    model: 'doubao-seed-2.1-turbo',
  ),
];

class SettingsPage extends ConsumerStatefulWidget {
  /// LLM 配置存储（测试可注入 fake）
  final LlmConfigStorage? configStorage;

  /// LLM 客户端（测试可注入 fake，用于测试连接）
  final LlmClient? llmClient;

  const SettingsPage({super.key, this.configStorage, this.llmClient});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late final LlmConfigStorage _configStorage;
  late final LlmClient _llmClient;
  late final AIAccountRepository _accountRepo;

  final TextEditingController _apiKeyCtrl = TextEditingController();
  final TextEditingController _baseUrlCtrl = TextEditingController();
  final TextEditingController _modelCtrl = TextEditingController();

  bool _configLoaded = false;
  bool _apiKeyVisible = false;
  bool _isSaving = false;
  bool _isTestingConn = false;
  TestConnectionResult? _connResult;

  /// ADR-C91 多账号：账号列表 / 当前编辑账号（null=新增模式）
  List<AiAccountRow> _accounts = [];
  bool _accountsLoaded = false;
  String? _editingAccountId;
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
    _configStorage = widget.configStorage ?? LlmConfigStorage();
    _llmClient = widget.llmClient ?? LlmClient(_configStorage);
    _accountRepo = AIAccountRepository(ref.read(appDatabaseProvider));
    _loadApiConfig();
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

  @override
  void dispose() {
    _apiKeyCtrl.dispose();
    _baseUrlCtrl.dispose();
    _modelCtrl.dispose();
    super.dispose();
  }

  /// 加载 API 配置与账号列表（ADR-C91 多账号）
  /// 账号存在 → 载入默认账号表单；否则回退旧单键（兼容未迁移）
  Future<void> _loadApiConfig() async {
    try {
      final accounts = await _accountRepo.listAccounts();
      if (mounted) setState(() => _accounts = accounts);
      LlmConfigValues? config;
      if (accounts.isNotEmpty) {
        final def = accounts.firstWhere(
          (a) => a.isDefault,
          orElse: () => accounts.first,
        );
        final key = await _accountRepo.getApiKey(def.id);
        if (key != null && key.isNotEmpty) {
          config = LlmConfigValues(
            apiKey: key,
            baseUrl: def.baseUrl,
            model: def.model,
          );
          _editingAccountId = def.id;
        }
      }
      config ??= await _configStorage.getLlmConfig();
      if (config != null && mounted) {
        _apiKeyCtrl.text = config.apiKey;
        _baseUrlCtrl.text = config.baseUrl;
        _modelCtrl.text = config.model;
      }
    } catch (_) {
      // 加载失败保持空表单，静默（release 不暴露技术细节）
    } finally {
      if (mounted) {
        setState(() {
          _configLoaded = true;
          _accountsLoaded = true;
        });
      }
    }
  }

  bool get _hasFullConfig =>
      _apiKeyCtrl.text.trim().isNotEmpty &&
      _baseUrlCtrl.text.trim().isNotEmpty &&
      _modelCtrl.text.trim().isNotEmpty;

  void _notify(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? context.palette.danger : null,
      ),
    );
  }

  /// 保存配置：校验非空 → 写账号（ADR-C91 多账号：编辑中 → 更新；否则新建）
  Future<void> _handleSaveConfig() async {
    if (!_hasFullConfig) {
      _notify('请填写完整的 API 配置', error: true);
      return;
    }
    setState(() => _isSaving = true);
    try {
      await _saveCurrentForm(resetAfterCreate: true);
      await _reloadAccounts();
      _notify('API 配置已保存');
    } catch (_) {
      _notify('保存失败，请稍后再试', error: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// 保存当前表单到账号：编辑中 → updateAccount；否则 createAccount。
  /// [resetAfterCreate]：新建后回到「新增」起点（保存配置用，可连续新增多账号）。
  Future<void> _saveCurrentForm({bool resetAfterCreate = false}) async {
    final editingId = _editingAccountId;
    final name = _modelCtrl.text.trim();
    final baseUrl = _baseUrlCtrl.text.trim().replaceAll(RegExp(r'/$'), '');
    final model = _modelCtrl.text.trim();
    final apiKey = _apiKeyCtrl.text.trim();
    if (editingId != null) {
      await _accountRepo.updateAccount(
        id: editingId,
        name: name,
        baseUrl: baseUrl,
        model: model,
        apiKey: apiKey,
      );
    } else {
      await _accountRepo.createAccount(
        name: name,
        baseUrl: baseUrl,
        model: model,
        apiKey: apiKey,
      );
      if (resetAfterCreate) _editingAccountId = null;
    }
  }

  /// 重新加载账号列表（保存/删除后刷新；保留表单不动）
  Future<void> _reloadAccounts() async {
    final accounts = await _accountRepo.listAccounts();
    if (mounted) setState(() => _accounts = accounts);
  }

  /// 测试连接：直接测当前表单（所见即所得），不依赖已保存配置。
  /// 修复：此前「先保存再读存储默认账号」会让测试结果与表单脱节
  /// （未保存/多账号时永远测到旧配置，失败文案固定不随输入变化）。
  Future<void> _handleTestConnection() async {
    if (!_hasFullConfig) {
      setState(() {
        _connResult = const TestConnectionResult(
          success: false,
          message: '请先填写完整的 API 配置',
        );
      });
      return;
    }
    setState(() {
      _isTestingConn = true;
      _connResult = null;
    });
    try {
      final baseUrl = _baseUrlCtrl.text.trim().replaceAll(RegExp(r'/$'), '');
      final result = await _llmClient.testLlmConnection(
        config: LlmConfigValues(
          apiKey: _apiKeyCtrl.text.trim(),
          baseUrl: baseUrl,
          model: _modelCtrl.text.trim(),
        ),
      );
      if (mounted) setState(() => _connResult = result);
    } catch (_) {
      if (mounted) {
        setState(() {
          _connResult = const TestConnectionResult(
            success: false,
            message: '测试失败',
          );
        });
      }
    } finally {
      if (mounted) setState(() => _isTestingConn = false);
    }
  }

  /// 清空配置：确认对话框 → 清存储 + 清表单
  Future<void> _handleClearConfig() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('清空配置', style: context.text.titleLg),
        content: Text(
          '确定清空所有 API 配置吗？',
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
            child: Text('清空', style: TextStyle(color: context.palette.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _accountRepo.clearAll();
      await _configStorage.clearLlmConfig();
      if (mounted) {
        setState(() {
          _apiKeyCtrl.clear();
          _baseUrlCtrl.clear();
          _modelCtrl.clear();
          _connResult = null;
        });
        _notify('API 配置已清空');
      }
    } catch (_) {
      _notify('清空失败，请稍后再试', error: true);
    }
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

  /// ADR-C83：选中供应商预设 → 自动填 Base URL + Model（Key 不动）。
  void _applyPreset(({String name, String baseUrl, String model}) preset) {
    setState(() {
      _baseUrlCtrl.text = preset.baseUrl;
      _modelCtrl.text = preset.model;
    });
  }

  /// 如何获取 DeepSeek Key：平台路径 + 费用一句话（v0.1 发布批任务 2.3）
  void _handleShowKeyGuide() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('如何获取 API Key', style: context.text.titleLg),
        content: Text(
          '1. 在所选 AI 服务商官网注册 / 登录（DeepSeek 为 platform.deepseek.com）；\n'
          '2. 进入「API keys」页面，创建并复制你的密钥（多为 sk- 开头）；\n'
          '3. 回到本页，粘贴到上方 API Key 输入框保存。\n\n'
          '费用按实际用量计入你对应服务商账户余额，具体价格见各平台充值页。',
          style: context.text.body,
        ),
        actions: [
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
          _buildMaintenanceSection(),
          const SizedBox(height: 12),
          _buildAboutSection(),
        ],
      ),
    );
  }

  // ── API 配置 ──

  /// 账号列表（ADR-C91 多账号）：行 = 名称+model+默认徽标+设默认/删除
  Widget _buildAccountList() {
    if (!_accountsLoaded || _accounts.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FieldLabel('已保存的账号（${_accounts.length}）'),
        for (final account in _accounts) _buildAccountRow(account),
        const SizedBox(height: 4),
      ],
    );
  }

  /// 单账号行（ADR-C91）：编辑态高亮；默认徽标；设默认/删除操作
  Widget _buildAccountRow(AiAccountRow account) {
    final busy = _isSaving || _isTestingConn || _isDeleting;
    final editing = _editingAccountId == account.id;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.smx,
      ),
      decoration: BoxDecoration(
        color: editing ? context.palette.primarySoft : context.palette.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: editing ? context.palette.primary : context.palette.border,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              onTap: busy ? null : () => _editAccount(account),
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
              style: TextStyle(fontSize: 10, color: context.palette.primary),
            ),
          ),
        ],
      ],
    );
  }

  /// 点击「＋ 添加新账号」：清表单进入新增模式
  void _startNewAccount() {
    setState(() {
      _editingAccountId = null;
      _apiKeyCtrl.clear();
      _baseUrlCtrl.clear();
      _modelCtrl.clear();
      _connResult = null;
    });
  }

  /// 点击账号行：载入表单进入编辑模式
  Future<void> _editAccount(AiAccountRow account) async {
    final key = await _accountRepo.getApiKey(account.id);
    if (!mounted) return;
    setState(() {
      _editingAccountId = account.id;
      _apiKeyCtrl.text = key ?? '';
      _baseUrlCtrl.text = account.baseUrl;
      _modelCtrl.text = account.model;
      _connResult = null;
    });
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
      await _loadApiConfig(); // 刷新列表；默认被删 → 表单载入接管账号
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
    return _SectionCard(
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
    return _SectionCard(
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
    return _SectionCard(
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

  Widget _buildApiSection() {
    final hasConfig = _configLoaded && !_hasFullConfig;
    return _SectionCard(
      title: 'API 配置',
      description: '配置大语言模型连接参数，用于写作诊断与智能对话',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasConfig)
            Container(
              margin: const EdgeInsets.only(bottom: AppSpacing.md),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.smx,
              ),
              decoration: BoxDecoration(
                color: context.palette.dangerBg,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: context.palette.dangerBorder),
              ),
              child: Text(
                '尚未配置 API，当前为免费测试模式（离线示例）。填写以下信息以启用完整功能',
                style: TextStyle(fontSize: 13, color: context.palette.danger),
              ),
            ),
          _buildAccountList(),
          if (_editingAccountId != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  foregroundColor: context.palette.primary,
                ),
                onPressed: (_isSaving || _isTestingConn || _isDeleting)
                    ? null
                    : _startNewAccount,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('添加新账号', style: TextStyle(fontSize: 12)),
              ),
            ),
          _FieldLabel('API Key'),
          TextField(
            controller: _apiKeyCtrl,
            obscureText: !_apiKeyVisible,
            autocorrect: false,
            decoration: _inputDecoration('sk-...').copyWith(
              suffixIcon: IconButton(
                icon: Icon(
                  _apiKeyVisible ? Icons.visibility_off : Icons.visibility,
                  size: 18,
                ),
                tooltip: _apiKeyVisible ? '隐藏 API Key' : '显示 API Key',
                onPressed: () =>
                    setState(() => _apiKeyVisible = !_apiKeyVisible),
              ),
            ),
          ),
          _FieldLabel('Base URL'),
          TextField(
            controller: _baseUrlCtrl,
            autocorrect: false,
            keyboardType: TextInputType.url,
            decoration: _inputDecoration('https://api.deepseek.com'),
          ),
          _FieldLabel('Model'),
          TextField(
            controller: _modelCtrl,
            autocorrect: false,
            decoration: _inputDecoration('deepseek-v4-flash'),
          ),
          // ADR-C83：供应商预设快捷入口（点选自动填 Base URL + Model）
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final preset in _llmPresets)
                ActionChip(
                  label: Text(
                    preset.name,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.palette.textSecondary,
                    ),
                  ),
                  visualDensity: VisualDensity.compact,
                  side: BorderSide(color: context.palette.border),
                  backgroundColor: context.palette.surface,
                  onPressed: (_isSaving || _isTestingConn)
                      ? null
                      : () => _applyPreset(preset),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _isSaving ? null : _handleSaveConfig,
                  style: FilledButton.styleFrom(
                    backgroundColor: context.palette.primary,
                    foregroundColor: context.palette.onPrimary,
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.md,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                  ),
                  child: _isSaving
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: context.palette.onPrimary,
                          ),
                        )
                      : const Text(
                          '保存配置',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: _isTestingConn ? null : _handleTestConnection,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.palette.primary,
                    side: BorderSide(color: context.palette.primary),
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.md,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                  ),
                  child: _isTestingConn
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: context.palette.primary,
                          ),
                        )
                      : const Text(
                          '测试连接',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: (_isSaving || _isTestingConn)
                ? null
                : () {
                    setState(() {
                      _baseUrlCtrl.text = 'https://api.deepseek.com';
                      _modelCtrl.text = 'deepseek-v4-flash';
                    });
                  },
            style: OutlinedButton.styleFrom(
              foregroundColor: context.palette.textSecondary,
              side: BorderSide(color: context.palette.border),
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
            ),
            child: const Text('填充示例配置'),
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: (_isSaving || _isTestingConn)
                ? null
                : _handleClearConfig,
            child: Text(
              '清空配置',
              style: TextStyle(
                color: context.palette.danger,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          TextButton(
            onPressed: _handleShowKeyGuide,
            child: Text(
              '如何获取 API Key →',
              style: TextStyle(
                color: context.palette.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (_connResult != null)
            Container(
              margin: const EdgeInsets.only(top: AppSpacing.sm),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.smx,
              ),
              decoration: BoxDecoration(
                color: _connResult!.success
                    ? context.palette.primarySoft
                    : context.palette.dangerBg,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(
                  color: _connResult!.success
                      ? context.palette.primary
                      : context.palette.dangerBorder,
                ),
              ),
              child: Text(
                '${_connResult!.success ? '✓ ' : '✗ '}${_connResult!.message}',
                style: TextStyle(
                  fontSize: 13,
                  color: _connResult!.success
                      ? context.palette.primary
                      : context.palette.danger,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── 维护 ──
  Widget _buildMaintenanceSection() {
    return _SectionCard(
      title: '维护',
      child: Column(
        children: [
          _ActionRow(label: '导出会话记录（JSON）', onTap: _handleExportSession),
          Divider(height: 1, color: context.palette.borderSoft),
          _ActionRow(label: '清除缓存', onTap: _handleClearCache),
          Divider(height: 1, color: context.palette.borderSoft),
          _ActionRow(label: '反馈建议', onTap: _handleFeedback),
        ],
      ),
    );
  }

  // ── 关于 ──
  Widget _buildAboutSection() {
    return _SectionCard(
      title: '关于',
      child: Column(
        children: [
          const _AboutRow(label: '应用名称', value: '月笙写作教练'),
          Divider(height: 1, color: context.palette.borderSoft),
          _AboutRow(label: '版本', value: 'v$_appVersion'),
          Divider(height: 1, color: context.palette.borderSoft),
          const _AboutRow(label: '包名', value: _packageName),
          Divider(height: 1, color: context.palette.borderSoft),
          _ActionRow(
            label: '隐私与费用说明',
            onTap: () => showPrivacyNoticeDialog(context),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      // 批次 V-3：原为 context.palette.placeholder（#D8DCE0）—— 它是**图形/装饰**色，
      // 压在 filled 底 surface(#F2F4F2) 上仅 1.25:1，提示几乎不可见。
      // 提示是文字 ⇒ 改用 textTertiary（对 surface 4.80:1，达 AA 正文）。
      hintStyle: TextStyle(color: context.palette.textTertiary),
      filled: true,
      fillColor: context.palette.surface,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: BorderSide(color: context.palette.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: BorderSide(color: context.palette.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: BorderSide(color: context.palette.primary),
      ),
    );
  }
}

/// 区块卡片（对齐 RN section：bgCard + 圆角 + 边框）
class _SectionCard extends StatelessWidget {
  final String title;
  final String? description;
  final Widget child;

  const _SectionCard({
    required this.title,
    this.description,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: context.palette.surfaceWhite,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.palette.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: context.palette.textPrimary,
            ),
          ),
          if (description != null) ...[
            const SizedBox(height: 4),
            Text(
              description!,
              style: TextStyle(
                fontSize: 13,
                color: context.palette.textTertiary,
              ),
            ),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        top: AppSpacing.md,
        bottom: AppSpacing.xsm,
      ),
      child: Text(
        text,
        style: context.text.subBody.copyWith(fontWeight: FontWeight.w500),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _ActionRow({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  color: context.palette.textPrimary,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: context.palette.disabledText,
            ),
          ],
        ),
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

    return _SectionCard(
      title: '学习进度',
      description: '基于最近一次写作会话的进度概览',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 阶段徽章 + 完成度（对齐 RN phaseBadge + progressSection）
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.smx,
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
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '${progress.round()}%',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: context.palette.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text('完成度', style: context.text.caption),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 进度条
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.xs),
            child: LinearProgressIndicator(
              value: progress / 100,
              minHeight: 6,
              backgroundColor: context.palette.background,
              valueColor: AlwaysStoppedAnimation(context.palette.primary),
            ),
          ),
          const SizedBox(height: 12),
          // 统计行（对齐 RN statsRow）
          Container(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.smx),
            decoration: BoxDecoration(
              color: context.palette.background,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Row(
              children: [
                _ProgressStat(value: '${summary.totalProblems}', label: '总问题'),
                Container(width: 1, height: 28, color: context.palette.divider),
                _ProgressStat(
                  value: '${summary.resolvedProblems}',
                  label: '已解决',
                ),
                Container(width: 1, height: 28, color: context.palette.divider),
                _ProgressStat(value: '${summary.activeProblems}', label: '待改进'),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // 详情入口（对齐 RN footer）
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '诊断 ${summary.totalDiagnoses} 次',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.palette.disabledText,
                    ),
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
          ),
        ],
      ),
    );
  }
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
