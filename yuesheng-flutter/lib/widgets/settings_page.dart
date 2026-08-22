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

import '../config/app_theme.dart';
import '../data/repositories/session_repository.dart';
import '../providers/app_providers.dart';
import '../router/app_routes.dart';
import '../services/llm_client.dart';
import '../services/llm_config_storage.dart';
import '../services/progress_service.dart';

const String _appVersion = '1.0.0';
const String _packageName = 'com.yuesheng.writingcoach';
const String _feedbackEmail = 'feedback@yuesheng.app';

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

  final TextEditingController _apiKeyCtrl = TextEditingController();
  final TextEditingController _baseUrlCtrl = TextEditingController();
  final TextEditingController _modelCtrl = TextEditingController();

  bool _configLoaded = false;
  bool _isSaving = false;
  bool _isTestingConn = false;
  TestConnectionResult? _connResult;

  /// 批次 38：最新会话的学习进度概览（学习进度从书架移至设置）
  ProgressSummary? _progressSummary;

  /// 进度对应的会话 ID（点击进入 progress-detail）
  String? _progressSessionId;

  @override
  void initState() {
    super.initState();
    _configStorage = widget.configStorage ?? LlmConfigStorage();
    _llmClient = widget.llmClient ?? LlmClient(_configStorage);
    _loadApiConfig();
    _loadProgressSummary();
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

  Future<void> _loadApiConfig() async {
    try {
      final config = await _configStorage.getLlmConfig();
      if (config != null && mounted) {
        _apiKeyCtrl.text = config.apiKey;
        _baseUrlCtrl.text = config.baseUrl;
        _modelCtrl.text = config.model;
      }
    } catch (_) {
      // 加载失败保持空表单，静默（release 不暴露技术细节）
    } finally {
      if (mounted) setState(() => _configLoaded = true);
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
        backgroundColor: error ? AppColors.danger : null,
      ),
    );
  }

  /// 保存配置：校验非空 → trim + baseUrl 去尾部斜杠 → 写入
  Future<void> _handleSaveConfig() async {
    if (!_hasFullConfig) {
      _notify('请填写完整的 API 配置', error: true);
      return;
    }
    setState(() => _isSaving = true);
    try {
      await _configStorage.saveLlmConfig(
        LlmConfigValues(
          apiKey: _apiKeyCtrl.text.trim(),
          baseUrl: _baseUrlCtrl.text.trim().replaceAll(RegExp(r'/$'), ''),
          model: _modelCtrl.text.trim(),
        ),
      );
      _notify('API 配置已保存');
    } catch (_) {
      _notify('保存失败，请稍后再试', error: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// 测试连接：先保存当前表单，再发起连通性测试
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
      await _configStorage.saveLlmConfig(
        LlmConfigValues(
          apiKey: _apiKeyCtrl.text.trim(),
          baseUrl: _baseUrlCtrl.text.trim().replaceAll(RegExp(r'/$'), ''),
          model: _modelCtrl.text.trim(),
        ),
      );
      final result = await _llmClient.testLlmConnection();
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
        title: const Text(
          '清空配置',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        content: const Text(
          '确定清空所有 API 配置吗？',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
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
        title: const Text(
          '清除缓存',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        content: const Text(
          '这将清除所有本地缓存数据（不包括作品和章节内容）。确定继续吗？',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清除', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final sessionRepo = SessionRepository(ref.read(appDatabaseProvider));
      final deleted = await sessionRepo.deleteOrphanSessions();
      _notify(deleted > 0 ? '缓存已清除（移除 $deleted 个空会话）' : '缓存已清除');
    } catch (_) {
      _notify('清除失败，请稍后再试', error: true);
    }
  }

  /// 反馈建议：联系方式对话框（批次78 L3：邮箱可一键复制）
  void _handleFeedback() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          '反馈',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        content: Text(
          '遇到问题或有建议？请通过以下方式联系我们：\n\n邮箱：$_feedbackEmail',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _feedbackEmail));
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('邮箱已复制')));
              }
            },
            child: const Text('复制邮箱'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('设置'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        toolbarHeight: 48,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
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
          _buildMaintenanceSection(),
          const SizedBox(height: 12),
          _buildAboutSection(),
        ],
      ),
    );
  }

  // ── API 配置 ──
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
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.dangerBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.dangerBorder),
              ),
              child: const Text(
                '尚未配置 API，请填写以下信息以启用对话功能',
                style: TextStyle(fontSize: 13, color: AppColors.danger),
              ),
            ),
          _FieldLabel('API Key'),
          TextField(
            controller: _apiKeyCtrl,
            obscureText: true,
            autocorrect: false,
            decoration: _inputDecoration('sk-...'),
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
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _isSaving ? null : _handleSaveConfig,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.onPrimary,
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
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isTestingConn
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
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
              foregroundColor: AppColors.textSecondary,
              side: const BorderSide(color: AppColors.border),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('填充示例配置'),
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: (_isSaving || _isTestingConn)
                ? null
                : _handleClearConfig,
            child: const Text(
              '清空配置',
              style: TextStyle(
                color: AppColors.danger,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (_connResult != null)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: _connResult!.success
                    ? AppColors.primarySoft
                    : AppColors.dangerBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _connResult!.success
                      ? AppColors.primary
                      : AppColors.dangerBorder,
                ),
              ),
              child: Text(
                '${_connResult!.success ? '✓ ' : '✗ '}${_connResult!.message}',
                style: TextStyle(
                  fontSize: 13,
                  color: _connResult!.success
                      ? AppColors.primary
                      : AppColors.danger,
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
          _ActionRow(label: '清除缓存', onTap: _handleClearCache),
          const Divider(height: 1, color: AppColors.borderSoft),
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
          const Divider(height: 1, color: AppColors.borderSoft),
          _AboutRow(label: '版本', value: 'v$_appVersion'),
          const Divider(height: 1, color: AppColors.borderSoft),
          const _AboutRow(label: '包名', value: _packageName),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.placeholder),
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.primary),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          if (description != null) ...[
            const SizedBox(height: 4),
            Text(
              description!,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textTertiary,
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
      padding: const EdgeInsets.only(top: 12, bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: AppColors.textSecondary,
        ),
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
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right,
              size: 20,
              color: AppColors.disabledText,
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
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 14, color: AppColors.textTertiary),
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
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text(
                  phaseLabel,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.primary,
                  ),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '${progress.round()}%',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    '完成度',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textTertiary,
                    ),
                  ),
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
              backgroundColor: AppColors.background,
              valueColor: const AlwaysStoppedAnimation(AppColors.primary),
            ),
          ),
          const SizedBox(height: 12),
          // 统计行（对齐 RN statsRow）
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Row(
              children: [
                _ProgressStat(value: '${summary.totalProblems}', label: '总问题'),
                Container(width: 1, height: 28, color: AppColors.divider),
                _ProgressStat(
                  value: '${summary.resolvedProblems}',
                  label: '已解决',
                ),
                Container(width: 1, height: 28, color: AppColors.divider),
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
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '诊断 ${summary.totalDiagnoses} 次',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.disabledText,
                    ),
                  ),
                  const Row(
                    children: [
                      Text(
                        '查看详情',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.primary,
                        ),
                      ),
                      SizedBox(width: 2),
                      Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: AppColors.primary,
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
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}
