// ─────────────────────────────────────────────────────────────
// ApiConfigPage — API 配置子页（路由 /settings/api-config）
//
// 为什么把这块从设置页下沉（形态约束，非代码洁癖）：
//   手机 Android 竖屏是**唯一平台形态**。设置页 API 卡里塞着
//   3 输入框 + 6 个预设 chips + 「测试并保存」主 CTA + 次行两按钮 +
//   4 个文字操作，实测 360x640 下保存/测试按钮 bottom=721（超首屏 81dp）
//   ⇒ 首屏看不到主 CTA。加子页后设置页只留「账号列表 + 一个入口行」，
//   表单整块在本页滚动呈现，首屏即可见主 CTA。
//
// 职责边界：
//   · 本页 = 填表单 + 测试 + 保存（**有本地表单状态**）
//   · 设置页 = 账号列表（查看 / 设默认 / 删除）+ 进入本页的入口
//   点账号行在本页 = 载入该账号进表单编辑；在设置页点账号行 = 进本页。
//
// 保存语义（B5 第二批）：「测试并保存」测连接通过才落库 —— 不通的密钥若
// 落库会成为僵尸账号，用户之后要手动去列表删它，且它会占掉「默认」标记。
//
// R-029：零硬编码 API Key。模型/BaseURL 预设是**公开**的兼容端点常量，
// 不含任何密钥。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/app_palette.dart';
import '../../config/app_theme.dart';
import '../../data/database/database.dart';
import '../../data/repositories/ai_account_repository.dart';
import '../../providers/app_providers.dart';
import '../../router/app_routes.dart';
import '../../services/llm_call_log_sink.dart';
import '../../services/llm_client.dart';
import '../../services/llm_config_storage.dart';
import '../../theme/app_typography.dart';
import 'widgets/settings_cards.dart';

/// OpenAI 兼容供应商预设（ADR-C83：扩展多模型）。选中自动填 Base URL +
/// Model 默认值；API Key 各供应商独立，仍需用户自行填写（R-029 零硬编码）。
/// 模型时效性核验（2026-10-04，以各供应商官方 API 文档为准）：
/// - deepseek-v4-flash：DeepSeek 现行主模型（deepseek-chat/reasoner 已于
///   2026-07-24 弃用，分别映射至 v4-flash 非思考/思考模式）
/// - gpt-4.1：OpenAI chat/completions 稳定模型（gpt-4o 已从 ChatGPT 淘汰，
///   gpt-5 系为 reasoning-only，走 responses/max_completion_tokens 语义）
/// - kimi-k3：Kimi 现行旗舰（moonshot-v1 系列已于 2026-08-31 下线）
/// - qwen-plus：通义稳定别名，仍可用
/// - glm-4.7-flash：智谱**免费档**（2026-10-04 核验：官方文档归入 free 分类，
///   输入/输出/缓存全免，非「新用户赠额」——赠额烧完不影响本档；200K 上下文 /
///   128K 最大输出）。选它而非付费的 glm-4.7（¥0.6/¥2.2 每 M token），让用户
///   无需充值即可先体验。三个注意点：
///   ① 旧免费档下线会自动路由（glm-4.5-flash 已于 2026-01-30 下线 → 路由至
///      glm-4.7-flash），故只写当前档位 ID 即可，无需跟随换代改代码；
///   ② glm-4.7-**flashx** 是**收费**档（¥0.07/¥0.4），与本档仅差一个字母 x
///      且上下文同为 200K —— 引导文案必须给全模型名，勿简称「flash 档」；
///   ③ 智谱另有 glm-4.6v-flash 同样免费（128K，仅文本/视觉），按需另加预设。
///   另注：网传「GLM-4-Flash 永久免费」在官方当前文档已查无此 ID
///   （zhipuai provider 下不存在 glm-4-flash），勿填该旧名。
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
    model: 'glm-4.7-flash',
  ),
  (
    name: '豆包（火山方舟）',
    baseUrl: 'https://ark.cn-beijing.volces.com/api/v3',
    model: 'doubao-seed-2.1-turbo',
  ),
];

class ApiConfigPage extends ConsumerStatefulWidget {
  /// LLM 配置存储（测试可注入 fake）
  final LlmConfigStorage? configStorage;

  /// LLM 客户端（测试可注入 fake，用于测试连接）
  final LlmClient? llmClient;

  const ApiConfigPage({super.key, this.configStorage, this.llmClient});

  @override
  ConsumerState<ApiConfigPage> createState() => _ApiConfigPageState();
}

class _ApiConfigPageState extends ConsumerState<ApiConfigPage> {
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

  /// 是否已解析出**任一**可用配置（默认账号，或兼容旧单键）。
  ///
  /// ★ 判「未配置」必须用它而不是「账号列表为空」：ADR-C91 之前的用户
  ///   只有旧三键存储、没有账号行，若按账号数判会对着**已配好**的用户
  ///   弹「尚未配置」警告（假警报）。
  bool _hasResolvedConfig = false;

  /// ADR-C91 多账号：账号列表 / 当前编辑账号（null=新增模式）
  List<AiAccountRow> _accounts = [];
  bool _accountsLoaded = false;
  String? _editingAccountId;
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    _configStorage = widget.configStorage ?? LlmConfigStorage();
    // B2：设置页自建的 LlmClient 同样接持久 sink ⇒ 连通性测试用量落 error_logs。
    _llmClient =
        widget.llmClient ??
        LlmClient(
          _configStorage,
          null,
          null,
          null,
          null,
          LlmCallLogSink().call,
        );
    _accountRepo = AIAccountRepository(ref.read(appDatabaseProvider));
    _loadApiConfig();
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
      _hasResolvedConfig = config != null;
      if (config != null && mounted) {
        _apiKeyCtrl.text = config.apiKey;
        _baseUrlCtrl.text = config.baseUrl;
        _modelCtrl.text = config.model;
      }
      // ADR-C121-2：无已存配置时预填 DeepSeek 预设——修复「hintText 看似已填实为空」
      // 导致的『填了还提示没填完整』（占位符易被误读为已填值）。
      if (config == null && mounted) {
        final preset = _llmPresets.first;
        _baseUrlCtrl.text = preset.baseUrl;
        _modelCtrl.text = preset.model;
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
      final result = await _llmClient.testLlmConnection(
        config: _currentFormConfig(),
      );
      if (mounted) setState(() => _connResult = result);
    } catch (_) {
      if (mounted) _setConnFailed();
    } finally {
      if (mounted) setState(() => _isTestingConn = false);
    }
  }

  /// 「测试并保存」主 CTA：测连接 → 成功才落库 → 刷新列表。
  ///
  /// 为什么失败**不**保存：不通的密钥若落库会成为僵尸账号，用户之后要手动去
  /// 列表删它，且它会占掉「默认」标记。让用户为一次失败的试探付清理成本。
  Future<void> _handleTestAndSave() async {
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
      final result = await _llmClient.testLlmConnection(
        config: _currentFormConfig(),
      );
      if (!mounted) return;
      if (!result.success) {
        setState(() => _connResult = result);
        return;
      }
      // 测试通过 ⇒ 落库（编辑中→更新；否则新建并回到新增起点）
      await _saveCurrentForm(resetAfterCreate: true);
      await _reloadAccounts();
      if (!mounted) return;
      setState(() => _connResult = result);
      _notify('连接成功，配置已保存');
    } catch (_) {
      if (mounted) _setConnFailed();
    } finally {
      if (mounted) setState(() => _isTestingConn = false);
    }
  }

  /// 当前表单 → 配置值（尾斜杠清洗；所见即所得，不读存储）。
  LlmConfigValues _currentFormConfig() => LlmConfigValues(
    apiKey: _apiKeyCtrl.text.trim(),
    baseUrl: _baseUrlCtrl.text.trim().replaceAll(RegExp(r'/$'), ''),
    model: _modelCtrl.text.trim(),
  );

  /// 连接测试抛异常时的统一失败态（两个 handler 共用，避免重复字面量）。
  void _setConnFailed() {
    setState(() {
      _connResult = const TestConnectionResult(success: false, message: '测试失败');
    });
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
          _editingAccountId = null;
        });
        _notify('API 配置已清空');
      }
    } catch (_) {
      _notify('清空失败，请稍后再试', error: true);
    }
  }

  /// ADR-C83：选中供应商预设 → 自动填 Base URL + Model（Key 不动）。
  void _applyPreset(({String name, String baseUrl, String model}) preset) {
    setState(() {
      _baseUrlCtrl.text = preset.baseUrl;
      _modelCtrl.text = preset.model;
    });
  }

  /// 如何获取 API Key：平台路径 + 费用一句话
  void _handleShowKeyGuide() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('如何获取 API Key', style: context.text.titleLg),
        content: Text(
          '1. 在所选 AI 服务商官网注册 / 登录（DeepSeek 为 platform.deepseek.com）；\n'
          '2. 进入「API keys」页面，创建并复制你的密钥（多为 sk- 开头）；\n'
          '3. 回到本页，粘贴到上方 API Key 输入框保存。\n\n'
          '费用：取决于你选的模型与服务商。\n'
          '· 智谱 GLM 的 glm-4.7-flash 为免费档，输入/输出/缓存全免，无需充值；\n'
          '· 其余服务商通常按实际用量从你的账户余额扣除，请先充值再用。\n'
          '免费档会随服务商策略调整而变化，若某天不可用，换用上表其他模型即可。',
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

  /// 「填充示例配置」：从独立满宽按钮降级为文字按钮（B5）——
  /// 省下的高度精确抵消主 CTA 的增量（360x640 竖屏实测，见文件头注释）。
  void _fillExampleConfig() {
    setState(() {
      _baseUrlCtrl.text = 'https://api.deepseek.com';
      _modelCtrl.text = 'deepseek-v4-flash';
    });
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.background,
      appBar: AppBar(
        title: const Text('API 配置'),
        backgroundColor: context.palette.background,
        foregroundColor: context.palette.textPrimary,
        toolbarHeight: 48,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          if (_configLoaded && !_hasResolvedConfig) _buildApiWarning(),
          _buildAccountList(),
          if (_editingAccountId != null) _buildAddAccountButton(),
          _buildApiKeyField(),
          _buildBaseUrlField(),
          _buildModelField(),
          const SizedBox(height: 8),
          _buildPresetChips(),
          const SizedBox(height: 12),
          // ★ 结果框必须在主 CTA **正上方**（R-009：操作要有即时可见反馈）。
          //   2026-10-04 实机取证：本项原排在 `_buildConfigActions()` 之后 ⇒
          //   恒在页面最底部（实测 bounds y=2104~2230，而主 CTA 在 y≈1550）
          //   ⇒ 用户点完「测试并保存」/「测试连接」后视线内**零反馈**，
          //   需手动滚两屏才看得到结果。渲染本身正常，位置错了。
          if (_connResult != null) _buildConnResultBox(),
          _buildSaveTestRow(),
          const SizedBox(height: 4),
          _buildConfigActions(),
        ],
      ),
    );
  }

  /// 未配置 API 时的「免费测试模式」提示条
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
      // 文案与 settings_page 的同类警告条同源（共享常量 `buildUnconfiguredWarning`）：
      // 前半句逐字相同，只有行动指引随表单位置而异（设置页表单在别处、本页在正下方）。
      buildUnconfiguredWarning(onSettingsPage: false),
      style: TextStyle(fontSize: 13, color: context.palette.danger),
    ),
  );

  /// 账号列表（ADR-C91 多账号）：行 = 名称+model+默认徽标+设默认/删除
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

  /// 单账号行（ADR-C91）：编辑态高亮；默认徽标；设默认/删除操作
  Widget _buildAccountRow(AiAccountRow account) {
    final busy = _isSaving || _isTestingConn || _isDeleting;
    final editing = _editingAccountId == account.id;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
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
              style: TextStyle(fontSize: 11, color: context.palette.primary),
            ),
          ),
        ],
      ],
    );
  }

  /// 「添加新账号」按钮（编辑某账号时显示，回到新增模式）
  Widget _buildAddAccountButton() => Align(
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
  );

  Widget _buildApiKeyField() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FieldLabel('API Key'),
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
            onPressed: () => setState(() => _apiKeyVisible = !_apiKeyVisible),
          ),
        ),
      ),
    ],
  );

  Widget _buildBaseUrlField() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FieldLabel('Base URL'),
      TextField(
        controller: _baseUrlCtrl,
        autocorrect: false,
        keyboardType: TextInputType.url,
        decoration: _inputDecoration('https://api.deepseek.com'),
      ),
    ],
  );

  Widget _buildModelField() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FieldLabel('Model'),
      TextField(
        controller: _modelCtrl,
        autocorrect: false,
        decoration: _inputDecoration('deepseek-v4-flash'),
      ),
    ],
  );

  /// ADR-C83：供应商预设快捷入口（点选自动填 Base URL + Model）
  Widget _buildPresetChips() => Wrap(
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
  );

  /// 主 CTA「测试并保存」+ 次行「保存配置 / 测试连接」。
  ///
  /// 布局容量实测（360dp竖屏 = 平台唯一形态，探针 2026-10-04，探针已回收）：
  ///   · 容器可用宽 294dp
  ///   · **三并排不可行**：每按钮仅 90~92.7dp，「测试并保存」5 字自然宽 71.25dp
  ///     加按钮内边距后溢出 ⇒ 实测文字高 40/60dp（换行）
  ///   · **主+次可行**：主按钮满宽、文字单行 20dp；次行各 141dp；总高 104dp
  ///   · 4 字 CJK @14px 自然宽 57dp —— 文案超 5 字须重新量
  Widget _buildSaveTestRow() => Column(
    children: [
      SizedBox(width: double.infinity, child: _buildTestAndSaveButton()),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(child: _buildSaveButton()),
          const SizedBox(width: 12),
          Expanded(child: _buildTestButton()),
        ],
      ),
    ],
  );

  /// 主 CTA：测连接 → 成功才落库 → 刷新列表。
  /// 满宽而非三并排的理由见 [_buildSaveTestRow] 的容量实测注释。
  Widget _buildTestAndSaveButton() => FilledButton(
    onPressed: (_isSaving || _isTestingConn) ? null : _handleTestAndSave,
    style: FilledButton.styleFrom(
      backgroundColor: context.palette.primary,
      foregroundColor: context.palette.onPrimary,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
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
              color: context.palette.onPrimary,
            ),
          )
        : const Text('测试并保存', style: TextStyle(fontWeight: FontWeight.w600)),
  );

  /// 次级「保存配置」：只落库不测连接（主 CTA 的逃生口：
  /// 用户已有把握时不必等一次网络往返）。
  Widget _buildSaveButton() => OutlinedButton(
    onPressed: _isSaving ? null : _handleSaveConfig,
    style: OutlinedButton.styleFrom(
      foregroundColor: context.palette.primary,
      side: BorderSide(color: context.palette.primary),
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
              color: context.palette.primary,
            ),
          )
        : const Text('保存配置', style: TextStyle(fontWeight: FontWeight.w600)),
  );

  /// 次级「测试连接」：只测不存（想先试探某个密钥又不想留账号时用）。
  Widget _buildTestButton() => OutlinedButton(
    onPressed: _isTestingConn ? null : _handleTestConnection,
    style: OutlinedButton.styleFrom(
      foregroundColor: context.palette.primary,
      side: BorderSide(color: context.palette.primary),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
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
        : const Text('测试连接', style: TextStyle(fontWeight: FontWeight.w600)),
  );

  /// 「填充示例配置」+「清空配置」+「如何获取 API Key」+「免费获取」四个文字按钮。
  Widget _buildConfigActions() => Column(
    children: [
      _buildFillExampleButton(),
      TextButton(
        onPressed: (_isSaving || _isTestingConn) ? null : _handleClearConfig,
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
      TextButton(
        onPressed: () => context.push(AppRoutes.freeTierGuide),
        child: Text(
          '免费获取 API Key →',
          style: TextStyle(
            color: context.palette.primary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    ],
  );

  Widget _buildFillExampleButton() => TextButton(
    onPressed: (_isSaving || _isTestingConn) ? null : _fillExampleConfig,
    child: Text(
      '填充示例配置',
      style: TextStyle(
        color: context.palette.textSecondary,
        fontWeight: FontWeight.w500,
      ),
    ),
  );

  Widget _buildConnResultBox() => Container(
    margin: const EdgeInsets.only(top: AppSpacing.sm),
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.sm,
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
  );
}
