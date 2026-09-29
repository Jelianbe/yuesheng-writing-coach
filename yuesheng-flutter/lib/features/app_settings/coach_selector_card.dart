// ─────────────────────────────────────────────────────────────
// coach_selector_card — 教练人格（全局，设置页）
//
// D1/D2 Phase 2：选人卡动态化 —— 列表 = 系统预设（doubao/月笙如歌/sensei，
// 来自 CoachPersona 内置 seed）+ 用户自定义预设（来自 app_state KV
// coach_personas_custom）。选择写入 coach_persona_active KV（系统预设双写
// coach_attitude 兼容旧行为），下次启动自动沿用。
// 系统预设态度色沿用 App 既有语义：doubao=l1Text / yuesheng=l2Text / sensei=l3Text；
// 用户预设统一 primary。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:writingcoach/config/shared_constants.dart';

import '../../config/app_palette.dart';
import '../../widgets/yue_sheet.dart';
import '../../config/app_theme.dart';
import '../../data/repositories/app_state_repository.dart';
import '../../providers/app_providers.dart';
import '../../providers/session_providers.dart';
import '../../services/llm_client.dart';
import '../../services/llm_config_storage.dart';
import '../../types/coach_persona.dart';
import '../../types/coach_persona_seed.dart';
import '../../types/teaching_types.dart';

class CoachSelectorCard extends ConsumerStatefulWidget {
  const CoachSelectorCard({super.key});

  @override
  ConsumerState<CoachSelectorCard> createState() => _CoachSelectorCardState();
}

class _CoachSelectorCardState extends ConsumerState<CoachSelectorCard> {
  String? _activeId;
  List<CoachPersona> _customs = const [];
  TeachingMode _mode = TeachingMode.socratic;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final repo = AppStateRepository(ref.read(appDatabaseProvider));
      final activeId = await repo.getActiveCoachPersonaId();
      final customs = await repo.getCustomCoachPersonas();
      final modeRaw = await repo.getCoachTeachingMode();
      final mode = TeachingMode.fromString(modeRaw) ?? TeachingMode.socratic;
      if (!mounted) return;
      setState(() {
        _activeId = activeId ?? 'doubao';
        _customs = customs;
        _mode = mode;
        _loading = false;
      });
    } catch (_) {
      // 读不到（测试/异常）→ 不渲染卡片，不阻塞设置页
    }
  }

  /// 展示列表：系统预设在前，用户预设在后。
  List<CoachPersona> get _all => [...builtInCoachPersonas, ..._customs];

  Future<void> _select(String personaId) async {
    try {
      await AppStateRepository(
        ref.read(appDatabaseProvider),
      ).setActiveCoachPersona(personaId);
      if (mounted) setState(() => _activeId = personaId);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('教练切换失败，请稍后再试')));
      }
    }
  }

  Future<void> _selectMode(TeachingMode mode) async {
    try {
      await AppStateRepository(
        ref.read(appDatabaseProvider),
      ).setCoachTeachingMode(mode.value);
      if (mounted) setState(() => _mode = mode);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('教学方式切换失败，请稍后再试')));
      }
    }
  }

  /// 打开新建/编辑自定义教练对话框；保存后刷新列表。
  Future<void> _openPersonaEditor([CoachPersona? existing]) async {
    final result = await showYueModalBottomSheet<CoachPersona>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CustomPersonaDialog(existing: existing),
    );
    if (result == null || !mounted) return;
    try {
      final repo = AppStateRepository(ref.read(appDatabaseProvider));
      await repo.saveCustomCoachPersona(result);
      final customs = await repo.getCustomCoachPersonas();
      if (!mounted) return;
      setState(() => _customs = customs);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('保存失败，请稍后再试')));
      }
    }
  }

  Future<void> _deletePersona(CoachPersona persona) async {
    try {
      final repo = AppStateRepository(ref.read(appDatabaseProvider));
      await repo.removeCustomCoachPersona(persona.id);
      // 删除的正是当前激活项 → 回退系统预设 doubao。
      if (_activeId == persona.id) {
        await repo.setActiveCoachPersona('doubao');
      }
      final customs = await repo.getCustomCoachPersonas();
      if (!mounted) return;
      setState(() {
        _customs = customs;
        if (_activeId == persona.id) _activeId = 'doubao';
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('删除失败，请稍后再试')));
      }
    }
  }

  /// 删除自定义教练前二次确认（不可逆操作，避免误触垃圾桶一键删除）。
  Future<void> _confirmDeletePersona(CoachPersona persona) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除自定义教练'),
        content: Text(
          '确认删除「${persona.name}」？此操作不可恢复。'
          '${persona.id == _activeId ? '\n\n当前正在使用，删除后将回退到系统预设「豆包」。' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _deletePersona(persona);
    }
  }

  /// 打开系统预设的直接说明阈值编辑对话框（Part A 补：系统预设可编辑阈值）。
  Future<void> _openThresholdEditor(CoachPersona persona) async {
    final repo = AppStateRepository(ref.read(appDatabaseProvider));
    final current =
        await repo.getCoachPersonaDirectThreshold(persona.id) ??
        persona.directExplainThreshold;
    if (!mounted) return;
    final controller = TextEditingController(text: current.toString());
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${persona.name} · 症候直接说明阈值'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '症候数超过该值时，当轮直接逐条说明全部症候',
            helperText: '默认 5，填 1 及以上',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final v = int.tryParse(controller.text.trim());
              if (v == null || v < 1) {
                Navigator.of(ctx).pop();
                return;
              }
              Navigator.of(ctx).pop(v);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;
    try {
      await repo.setCoachPersonaDirectThreshold(persona.id, result);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('保存失败，请稍后再试')));
      }
    }
  }

  Color _personaColor(AppPalette p, CoachPersona persona) {
    if (persona.isSystem) {
      return switch (persona.attitudeLevel) {
        AttitudeLevel.doubao => p.l1Text,
        AttitudeLevel.yuesheng => p.l2Text,
        AttitudeLevel.sensei => p.l3Text,
      };
    }
    return p.primary;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: palette.surfaceWhite,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: palette.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _headerRow(palette),
          const SizedBox(height: 4),
          Text(
            '换一种说话方式。切换后下次启动沿用。',
            style: TextStyle(fontSize: 13, color: palette.textTertiary),
          ),
          const SizedBox(height: 12),
          for (final persona in _all)
            _personaRow(
              context,
              persona: persona,
              selected: persona.id == _activeId,
              onTap: () => _select(persona.id),
              onEdit: persona.isSystem
                  ? null
                  : () => _openPersonaEditor(persona),
              onDelete: persona.isSystem
                  ? null
                  : () => _confirmDeletePersona(persona),
              onEditThreshold: persona.isSystem
                  ? () => _openThresholdEditor(persona)
                  : null,
            ),
          const SizedBox(height: 4),
          TextButton.icon(
            onPressed: () => _openPersonaEditor(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('自定义教练'),
            style: TextButton.styleFrom(alignment: Alignment.centerLeft),
          ),
          const SizedBox(height: 12),
          _modeSection(palette),
        ],
      ),
    );
  }

  /// R-019 拆出：build 的教学方式区块（正交于人格档）。
  Widget _modeSection(AppPalette palette) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _modeHeaderRow(palette),
      const SizedBox(height: 4),
      Text(
        '决定教练用提问引导，还是直接给答案。与上方人格正交。',
        style: TextStyle(fontSize: 13, color: palette.textTertiary),
      ),
      const SizedBox(height: 10),
      _modeToggle(palette),
    ],
  );

  Widget _headerRow(AppPalette palette) => Row(
    children: [
      Icon(Icons.psychology_outlined, size: 18, color: palette.primary),
      const SizedBox(width: 6),
      Text(
        '教练人格',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: palette.textPrimary,
        ),
      ),
      const SizedBox(width: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: palette.primarySoft,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Text(
          '全局',
          style: TextStyle(fontSize: 11, color: palette.primary),
        ),
      ),
    ],
  );

  Widget _personaRow(
    BuildContext context, {
    required CoachPersona persona,
    required bool selected,
    required VoidCallback onTap,
    required VoidCallback? onEdit,
    required VoidCallback? onDelete,
    VoidCallback? onEditThreshold,
  }) {
    final palette = context.palette;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: selected ? palette.primarySoft : palette.surface,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(
            color: selected ? palette.primary : palette.border,
          ),
        ),
        child: Row(
          children: [
            _personaDot(palette, persona),
            const SizedBox(width: 10),
            _coachNameDesc(
              palette,
              persona.name,
              '${persona.isSystem ? '' : '自定义 · '}${persona.label}',
            ),
            ..._personaTrailing(
              palette,
              selected,
              persona,
              onEdit,
              onDelete,
              onEditThreshold,
            ),
          ],
        ),
      ),
    );
  }

  Widget _personaDot(AppPalette palette, CoachPersona persona) => Container(
    width: 10,
    height: 10,
    decoration: BoxDecoration(
      color: _personaColor(palette, persona),
      shape: BoxShape.circle,
    ),
  );

  /// R-019 拆出：_personaRow 的尾随操作图标（勾选/删除/阈值调音）。
  List<Widget> _personaTrailing(
    AppPalette palette,
    bool selected,
    CoachPersona persona,
    VoidCallback? onEdit,
    VoidCallback? onDelete,
    VoidCallback? onEditThreshold,
  ) {
    final isCustom = !persona.isSystem;
    final list = <Widget>[
      if (selected) Icon(Icons.check_circle, size: 18, color: palette.primary),
    ];
    if (isCustom && onEdit != null)
      list.add(_personaEditButton(palette, onEdit));
    if (isCustom && onDelete != null) {
      list.add(_personaDeleteButton(palette, onDelete));
    }
    if (onEditThreshold != null) {
      list.add(_personaThresholdButton(palette, onEditThreshold));
    }
    return list;
  }

  /// R-019 拆出：自定义人格「编辑」入口（铅笔图标）。
  Widget _personaEditButton(AppPalette palette, VoidCallback onEdit) =>
      _personaIconButton(
        palette,
        icon: Icons.edit_outlined,
        onTap: onEdit,
        tooltip: '编辑',
      );

  /// R-019 拆出：自定义人格「删除」入口。
  Widget _personaDeleteButton(AppPalette palette, VoidCallback onDelete) =>
      _personaIconButton(
        palette,
        icon: Icons.delete_outline,
        onTap: onDelete,
        tooltip: '删除',
      );

  /// R-019 拆出：系统预设「阈值调音」入口。
  Widget _personaThresholdButton(
    AppPalette palette,
    VoidCallback onEditThreshold,
  ) => _personaIconButton(
    palette,
    icon: Icons.tune,
    onTap: onEditThreshold,
    tooltip: '阈值调音',
  );

  Widget _personaIconButton(
    AppPalette palette, {
    required IconData icon,
    required VoidCallback onTap,
    required String tooltip,
  }) => Padding(
    padding: const EdgeInsets.only(left: 4),
    child: Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Icon(icon, size: 18, color: palette.textTertiary),
      ),
    ),
  );

  Widget _coachNameDesc(AppPalette palette, String name, String desc) =>
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              desc,
              style: TextStyle(fontSize: 12, color: palette.textSecondary),
            ),
          ],
        ),
      );

  Widget _modeHeaderRow(AppPalette palette) => Row(
    children: [
      Icon(Icons.help_outline, size: 18, color: palette.primary),
      const SizedBox(width: 6),
      Text(
        '教学方式',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: palette.textPrimary,
        ),
      ),
      const SizedBox(width: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: palette.primarySoft,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Text(
          '全局',
          style: TextStyle(fontSize: 11, color: palette.primary),
        ),
      ),
    ],
  );

  Widget _modeToggle(AppPalette palette) => Row(
    children: [
      _modeChip(
        context,
        mode: TeachingMode.socratic,
        name: '疑问式',
        desc: '用提问引导你自己发现，不直接给答案',
        selected: _mode == TeachingMode.socratic,
        onTap: () => _selectMode(TeachingMode.socratic),
      ),
      const SizedBox(width: 8),
      _modeChip(
        context,
        mode: TeachingMode.direct,
        name: '直接说',
        desc: '直接指出问题与改法，不绕弯',
        selected: _mode == TeachingMode.direct,
        onTap: () => _selectMode(TeachingMode.direct),
      ),
    ],
  );

  Widget _modeChip(
    BuildContext context, {
    required TeachingMode mode,
    required String name,
    required String desc,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final palette = context.palette;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: _modeChipDecoration(palette, selected),
          child: _modeChipBody(palette, name, desc, selected),
        ),
      ),
    );
  }

  BoxDecoration _modeChipDecoration(AppPalette palette, bool selected) =>
      BoxDecoration(
        color: selected ? palette.primarySoft : palette.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: selected ? palette.primary : palette.border),
      );

  Widget _modeChipBody(
    AppPalette palette,
    String name,
    String desc,
    bool selected,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Text(
            name,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: palette.textPrimary,
            ),
          ),
          const Spacer(),
          if (selected)
            Icon(Icons.check_circle, size: 18, color: palette.primary),
        ],
      ),
      const SizedBox(height: 2),
      Text(desc, style: TextStyle(fontSize: 12, color: palette.textSecondary)),
    ],
  );
}

/// AI 润色专用提示词（独立于诊断/对话 prompt，单独调用）。
/// 仅辅助丰满用户自己填的「语气设定」，不代写教练对用户的输出（R-009）。
const String _kCoachPolishSystemPrompt = '''
你正在帮一位写作者配置「自定义写作教练」的语气设定。
用户会给你：教练的名字（可能为空），以及他随手写的几句语气想法（可能为空）。
请据此生成一段精炼、生动、可直接用作「教练语气设定」的中文描述（1-3 句）。
要求：
- 只描述「这位教练该怎么说话、带什么腔调」，不要写教学动作或诊断流程；
- 口语化、有画面感，避免「专业」「优秀」「有耐心」这类空泛词；
- 只输出描述本身，不要引号、不要前缀、不要解释。
''';

/// 拼装润色用户消息（名字 + 当前语气想法，空者标「未填写」）。
String _buildPolishUserMessage(String name, String tone) => [
  '教练名字：${name.isEmpty ? '（未填写）' : name}',
  '用户当前填写的语气想法：${tone.isEmpty ? '（未填写）' : tone}',
].join('\n');

/// 新建/编辑自定义教练对话框。
///
/// 2026-09-28 重构（UI + 生效机制）：
///  - 名称 = 唯一必填；语气设定选填，留空 → 注入层自动回退默认态度档
///    （skill_dispatcher._injectPersonaOrAttitude 的 else 分支，机制现成）；
///  - 原「一句话声音描述」实为纯展示副标题（不注入 prompt）→ 改名
///    「列表简介（仅展示）」并移入高级区，消除「在调语气其实没用」的误导；
///  - 原「人设层（D2）」并入语气段（对自定义教练两者都是用户自由文本，
///    注入时相邻两段 ⇒ 合并一段语义等价；注入代码不动，旧数据编辑后自然迁移）；
///  - 阈值与简介一起收进默认收起的「高级选项」折叠区。
class _CustomPersonaDialog extends ConsumerStatefulWidget {
  final CoachPersona? existing;

  const _CustomPersonaDialog({this.existing});

  @override
  ConsumerState<_CustomPersonaDialog> createState() =>
      _CustomPersonaDialogState();
}

class _CustomPersonaDialogState extends ConsumerState<_CustomPersonaDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _labelCtrl;
  late final TextEditingController _promptCtrl;
  late final TextEditingController _thresholdCtrl;
  bool _advancedOpen = false;
  bool _isPolishing = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _labelCtrl = TextEditingController(text: e?.label ?? '');
    // 旧数据的 personaLayer 合并进语气框（该字段自 2026-09-28 起不再单独收集）。
    final promptParts = <String>[
      if (e != null && e.systemPromptFragment.trim().isNotEmpty)
        e.systemPromptFragment.trim(),
      if (e != null && (e.personaLayer ?? '').trim().isNotEmpty)
        e.personaLayer!.trim(),
    ];
    _promptCtrl = TextEditingController(text: promptParts.join('\n'));
    _thresholdCtrl = TextEditingController(
      text: (e?.directExplainThreshold ?? kDefaultDirectExplainThreshold)
          .toString(),
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _labelCtrl.dispose();
    _promptCtrl.dispose();
    _thresholdCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先给教练起个名字')));
      return;
    }
    final label = _labelCtrl.text.trim();
    final threshold =
        int.tryParse(_thresholdCtrl.text.trim()) ??
        kDefaultDirectExplainThreshold;
    final e = widget.existing;
    final persona = CoachPersona(
      id: e?.id ?? 'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      label: label.isEmpty ? '自定义教练' : label,
      isSystem: false,
      attitudeLevel: AttitudeLevel.doubao,
      // 语气选填：留空存 '' → 注入层回退默认态度档（见类注释）。
      systemPromptFragment: _promptCtrl.text.trim(),
      // 人设层已并入语气段，不再单独写值；旧数据读侧仍兼容。
      personaLayer: null,
      iconKey: e?.iconKey,
      directExplainThreshold: threshold < 1
          ? kDefaultDirectExplainThreshold
          : threshold,
    );
    Navigator.of(context).pop(persona);
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// AI 润色：把用户粗糙的「名字 + 语气想法」发给独立模板，
  /// 返回丰满后的语气设定回填 _promptCtrl。用户仍审阅、可改、可弃（R-009）。
  Future<void> _polish() async {
    final name = _nameCtrl.text.trim();
    final tone = _promptCtrl.text.trim();
    if (name.isEmpty && tone.isEmpty) {
      _snack('先填个名字或几句语气，AI 才能帮你润色');
      return;
    }
    // 免费测试模式检测：未配置 API Key 时无法真调用，提前给引导。
    // 经 provider 读取，失败（如安全存储不可用）按「未配置」降级。
    LlmConfigValues? cfg;
    try {
      cfg = await ref.read(llmConfigResolvedProvider.future);
    } catch (_) {
      _snack('请先在「设置 → API 配置」填好 Key，才能用 AI 润色');
      return;
    }
    if (!mounted) return;
    if (cfg == null) {
      _snack('请先在「设置 → API 配置」填好 Key，才能用 AI 润色');
      return;
    }
    setState(() => _isPolishing = true);
    try {
      final client = ref.read(llmClientProvider);
      final result = await client.chatCompletion([
        const ChatMessage(role: 'system', content: _kCoachPolishSystemPrompt),
        ChatMessage(role: 'user', content: _buildPolishUserMessage(name, tone)),
      ], maxTokens: 300);
      if (!mounted) return;
      final polished = result.trim();
      if (polished.isEmpty) {
        _snack('AI 未返回内容，请重试或手动填写');
      } else {
        _promptCtrl
          ..text = polished
          ..selection = TextSelection.fromPosition(
            TextPosition(offset: polished.length),
          );
        _snack('已填好「语气设定」，可继续修改后保存');
      }
    } catch (_) {
      if (!mounted) return;
      _snack('AI 润色失败，请稍后重试或手动填写');
    } finally {
      if (mounted) setState(() => _isPolishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return YueSheetScaffold(
      title: _isEdit ? '编辑自定义教练' : '新建自定义教练',
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('取消', style: TextStyle(color: palette.textSecondary)),
        ),
        TextButton(onPressed: _save, child: const Text('保存')),
      ],
      child: _fields(),
    );
  }

  /// R-019 拆出：对话框字段列（名称 / 语气选填 / 高级选项折叠区）。
  /// 名称是唯一主字段；大多数用户到此为止，其余收进折叠区。
  Widget _fields() => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _field(_nameCtrl, '名称', '给教练起个名字，如：毒舌编辑'),
      const SizedBox(height: 12),
      _toneField(),
      const SizedBox(height: 4),
      _advancedToggle(),
      if (_advancedOpen) ..._advancedFields(),
    ],
  );

  /// R-019 拆出：语气设定段（文本框 + AI 润色辅助按钮）。
  /// 按钮仅辅助丰满用户自己填的内容，不代写教练对用户的输出（R-009）。
  Widget _toneField() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        controller: _promptCtrl,
        maxLines: 3,
        decoration: const InputDecoration(
          labelText: '语气设定（选填）',
          hintText: '希望教练怎么说话？如：犀利直接，不许废话。留空则用默认语气',
        ),
      ),
      const SizedBox(height: 6),
      _polishButton(context.palette),
    ],
  );

  /// R-019 拆出：AI 润色按钮（加载态内联转圈）。
  Widget _polishButton(AppPalette palette) => Align(
    alignment: Alignment.centerLeft,
    child: TextButton.icon(
      onPressed: _isPolishing ? null : _polish,
      icon: _isPolishing
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.auto_awesome, size: 18),
      label: Text(_isPolishing ? '润色中…' : 'AI 润色'),
      style: TextButton.styleFrom(
        padding: EdgeInsets.zero,
        foregroundColor: palette.primary,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ),
  );

  /// R-019 拆出：「高级选项」折叠开关行。
  Widget _advancedToggle() {
    final palette = context.palette;
    return InkWell(
      onTap: () => setState(() => _advancedOpen = !_advancedOpen),
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(
              _advancedOpen ? Icons.expand_less : Icons.expand_more,
              size: 18,
              color: palette.textTertiary,
            ),
            const SizedBox(width: 4),
            Text(
              '高级选项',
              style: TextStyle(fontSize: 13, color: palette.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  /// R-019 拆出：折叠区字段（列表简介仅展示 + 直接讲解阈值）。
  List<Widget> _advancedFields() => [
    _field(_labelCtrl, '列表简介（选填，仅展示）', '显示在教练列表的副标题，如：犀利、直给'),
    const SizedBox(height: 12),
    TextField(
      controller: _thresholdCtrl,
      keyboardType: TextInputType.number,
      decoration: const InputDecoration(
        labelText: '直接讲解阈值',
        helperText: '一次诊断超过该数量的症候时，当轮逐条直接说明（默认 5）',
      ),
    ),
    const SizedBox(height: 12),
  ];

  Widget _field(TextEditingController ctrl, String label, String hint) =>
      TextField(
        controller: ctrl,
        decoration: InputDecoration(labelText: label, hintText: hint),
      );
}
