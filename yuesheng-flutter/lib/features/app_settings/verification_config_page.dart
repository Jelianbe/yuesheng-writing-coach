// VerificationConfigPage — 独立核对（验证层）三键配置子页（S1）。
// 入口：设置页末尾 SectionCard → context.push(AppRoutes.verificationConfig)。
// 纯本地读写 / 零网络 / 零预设 / 零 plaintext；五态齐备；文案只落 UI（R-027）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../../config/app_palette.dart';
import '../../config/app_theme.dart';
import '../../config/svc_copy.dart';
import '../../services/verification_gate.dart';
import '../../theme/app_typography.dart';
import 'widgets/settings_cards.dart';

class VerificationConfigPage extends StatefulWidget {
  /// 存储源（可注入，供阶段三测 save/clear）。null ⇒ 生产默认。
  final VerificationKeysStorage? storage;

  const VerificationConfigPage({super.key, this.storage});

  @override
  State<VerificationConfigPage> createState() => _VerificationConfigPageState();
}

class _VerificationConfigPageState extends State<VerificationConfigPage> {
  final TextEditingController _baseUrlCtrl = TextEditingController();
  final TextEditingController _apiKeyCtrl = TextEditingController();
  final TextEditingController _modelCtrl = TextEditingController();

  late final VerificationKeysStorage _storage;
  bool _apiKeyVisible = false;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _loadError = false;

  @override
  void initState() {
    super.initState();
    _storage = widget.storage ?? VerificationKeysStorage();
    _load();
  }

  @override
  void dispose() {
    _baseUrlCtrl.dispose();
    _apiKeyCtrl.dispose();
    _modelCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _loadError = false;
    });
    try {
      final keys = await _storage.load();
      if (!mounted) return;
      _baseUrlCtrl.text = keys.baseUrl;
      _apiKeyCtrl.text = keys.apiKey;
      _modelCtrl.text = keys.model;
      setState(() => _isLoading = false);
    } catch (_) {
      // 非空 catch：留痕为可见错误态 + 重试入口，不静默吞、不打印键值。
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = true;
      });
    }
  }

  bool get _formComplete =>
      _baseUrlCtrl.text.trim().isNotEmpty &&
      _apiKeyCtrl.text.trim().isNotEmpty &&
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

  Future<void> _handleSave() async {
    if (_isSaving || !_formComplete) return;
    setState(() => _isSaving = true);
    try {
      await _storage.save(
        VerificationKeys(
          baseUrl: _baseUrlCtrl.text.trim(),
          apiKey: _apiKeyCtrl.text.trim(),
          model: _modelCtrl.text.trim(),
        ),
      );
      if (!mounted) return;
      _notify('配置已保存');
    } catch (_) {
      _notify(kOperationFailed('保存'), error: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _handleClear() async {
    if (_isSaving) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('清空配置', style: context.text.titleLg),
        content: const Text('确定清空独立核对的三项配置吗？'),
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
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _isSaving = true);
    try {
      await _storage.clear();
      if (!mounted) return;
      _baseUrlCtrl.clear();
      _apiKeyCtrl.clear();
      _modelCtrl.clear();
      setState(() {});
      _notify('配置已清空');
    } catch (_) {
      _notify(kOperationFailed('清空'), error: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.background,
      appBar: AppBar(
        title: const Text('独立核对配置'),
        backgroundColor: context.palette.background,
        foregroundColor: context.palette.textPrimary,
        toolbarHeight: 48,
        elevation: 0,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        if (_loadError) _buildLoadError(),
        _buildFormCard(),
        const SizedBox(height: AppSpacing.xl),
        _buildSaveButton(),
        const SizedBox(height: AppSpacing.sm),
        _buildClearButton(),
        const SizedBox(height: AppSpacing.lg),
        Text('配置保存在本机，离线也可修改。', style: context.text.caption),
      ],
    );
  }

  Widget _buildLoadError() => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: Row(
      children: [
        Expanded(
          child: Text(
            '读取失败',
            style: context.text.body.copyWith(color: context.palette.danger),
          ),
        ),
        TextButton(onPressed: _load, child: const Text('重试')),
      ],
    ),
  );

  Widget _buildFormCard() => SectionCard(
    title: '独立核对（验证层）配置',
    description: '独立的核对模型配置，与主对话、诊断所用的 API 配置分开，不影响主链。',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildField(
          '服务地址',
          _baseUrlCtrl,
          'https://...',
          keyboardType: TextInputType.url,
        ),
        _buildField(
          'API Key',
          _apiKeyCtrl,
          'sk-...',
          obscure: !_apiKeyVisible,
          suffix: _buildVisibilityToggle(),
        ),
        _buildField('模型', _modelCtrl, '模型 ID'),
      ],
    ),
  );

  Widget _buildVisibilityToggle() => IconButton(
    icon: Icon(
      _apiKeyVisible ? Icons.visibility_off : Icons.visibility,
      size: 18,
    ),
    tooltip: _apiKeyVisible ? '隐藏 API Key' : '显示 API Key',
    onPressed: () => setState(() => _apiKeyVisible = !_apiKeyVisible),
  );

  Widget _buildField(
    String label,
    TextEditingController controller,
    String hint, {
    bool obscure = false,
    Widget? suffix,
    TextInputType? keyboardType,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FieldLabel(label),
      TextField(
        controller: controller,
        obscureText: obscure,
        autocorrect: false,
        keyboardType: keyboardType,
        decoration: AppBoxStyles.standardInput(
          hintText: hint,
          suffixIcon: suffix,
        ),
        onChanged: (_) => setState(() {}),
      ),
    ],
  );

  Widget _buildSaveButton() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FilledButton(
        onPressed: _isSaving || !_formComplete ? null : _handleSave,
        style: FilledButton.styleFrom(
          backgroundColor: context.palette.primary,
          foregroundColor: context.palette.onPrimary,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
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
            : const Text('保存'),
      ),
      if (!_formComplete && !_isSaving)
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: Text('请填齐三项', style: context.text.caption),
        ),
    ],
  );

  Widget _buildClearButton() => OutlinedButton(
    onPressed: _isSaving ? null : _handleClear,
    style: OutlinedButton.styleFrom(
      foregroundColor: context.palette.danger,
      side: BorderSide(color: context.palette.dangerBorder),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
    ),
    child: const Text('清空配置'),
  );
}
