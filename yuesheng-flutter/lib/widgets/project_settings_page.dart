// ─────────────────────────────────────────────────────────────
// ProjectSettingsPage — 项目设置页
// 真源：yuesheng-android/src/app/project-settings.tsx
//
// 内容（对齐 RN loadManuscript → handleSave → handleDelete）：
//   1. 作品信息：名称 / 体裁 chips（长篇小说/中篇/短篇）/ 简介
//   2. 标签：chips + 删除 + 「+ 添加标签」+ 热门预设（批次94-5：落库 JSON string[]）
//   3. 统计信息：创建时间
//   4. 危险区：删除项目（二次确认 → deleteManuscript → 回书架）
//   5. 保存：名称非空校验 → updateManuscript → 提示 → 800ms 后返回
//
// 入口：稿件详情更多菜单「项目设置」（对齐 RN MoreMenuSheet）
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../config/app_theme.dart';
import '../data/repositories/manuscript_repository.dart';
import '../providers/app_providers.dart';
import '../providers/manuscript_providers.dart';

/// 体裁选项（对齐 RN project-settings.tsx GENRES：长篇小说/中篇/短篇）
const List<String> _genres = ['长篇小说', '中篇', '短篇'];

/// 热门标签预设（批次94-5：点击即加入，已含则不再显示）
const List<String> _tagPresets = [
  '重生',
  '系统',
  '甜宠',
  '虐恋',
  '穿越',
  '爽文',
  '悬疑',
  '修仙',
];

/// 项目设置页
class ProjectSettingsPage extends ConsumerStatefulWidget {
  final String manuscriptId;
  final String? initialTitle;

  const ProjectSettingsPage({
    super.key,
    required this.manuscriptId,
    this.initialTitle,
  });

  @override
  ConsumerState<ProjectSettingsPage> createState() =>
      _ProjectSettingsPageState();
}

class _ProjectSettingsPageState extends ConsumerState<ProjectSettingsPage> {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();

  String _genre = '';
  List<String> _tags = [];
  String? _createdAtText;
  bool _loading = true;
  bool _saving = false;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.initialTitle ?? '';
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadManuscript());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  /// 加载作品信息（对齐 RN loadManuscript）
  Future<void> _loadManuscript() async {
    try {
      final repo = ManuscriptRepository(ref.read(appDatabaseProvider));
      final m = await repo.getManuscript(widget.manuscriptId);
      if (m != null && mounted) {
        setState(() {
          _nameController.text = m.title;
          _genre = m.genre;
          _descController.text = m.description;
          // 批次94-5：标签从落库读取；无落库标签时回退 [genre]（兼容旧行为）
          _tags = ManuscriptRepository.parseTags(m);
          if (_tags.isEmpty && m.genre.isNotEmpty) _tags = [m.genre];
          _createdAtText = _formatDate(m.createdAt);
        });
      }
    } catch (_) {
      // 加载失败保持初始状态（静默，对齐 RN console.warn）
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static String _formatDate(int sec) {
    final d = DateTime.fromMillisecondsSinceEpoch(sec * 1000);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  /// 保存（对齐 RN handleSave：校验 → updateManuscript → 提示 → 800ms 返回）
  Future<void> _handleSave() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入作品名称')));
      return;
    }
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(manuscriptStoreProvider.notifier)
          .updateManuscript(
            widget.manuscriptId,
            title: name,
            description: _descController.text.trim(),
            genre: _genre,
            tags: _tags,
          );
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('设置已保存')));
      // 对齐 RN setTimeout(() => router.back(), 800)
      await Future<void>.delayed(const Duration(milliseconds: 800));
      if (mounted) context.canPop() ? context.pop() : context.go('/bookshelf');
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('保存失败，请稍后重试')));
      }
    }
  }

  /// 删除项目（对齐 RN handleDelete：Alert 确认 → deleteManuscript → replace /bookshelf）
  /// （批次59：确认文案对齐真实软删语义——archived 数据保留，与书架删除作品一致）
  Future<void> _handleDelete() async {
    if (_deleting) return;
    final title = _nameController.text.trim().isEmpty
        ? '未命名作品'
        : _nameController.text.trim();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除作品'),
        content: Text(
          '确定删除《$title》吗？删除后将不再显示，章节和诊断记录会保留。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      await ref
          .read(manuscriptStoreProvider.notifier)
          .deleteManuscript(widget.manuscriptId);
      if (!mounted) return;
      context.go('/bookshelf');
    } catch (_) {
      if (mounted) {
        setState(() => _deleting = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('删除失败，请稍后重试')));
      }
    }
  }

  /// 添加标签（对齐 RN addTag：Alert.prompt 输入）
  Future<void> _handleAddTag() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('添加标签'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '输入标签名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    // 延后 dispose：dialog 关闭动画仍可能引用 controller
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    if (text == null || text.isEmpty || _tags.contains(text)) return;
    setState(() => _tags.add(text));
  }

  void _handleRemoveTag(int index) {
    setState(() => _tags.removeAt(index));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('项目设置'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        toolbarHeight: 48,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 22),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/bookshelf'),
          tooltip: '返回',
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : _handleSave,
            child: const Text(
              '保存',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoSection(),
                    const SizedBox(height: 24),
                    _buildTagsSection(),
                    if (_createdAtText != null) ...[
                      const SizedBox(height: 24),
                      _buildStatsSection(),
                    ],
                    const SizedBox(height: 24),
                    _buildDangerSection(),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
    );
  }

  /// 作品信息区（对齐 RN「作品信息」section）
  Widget _buildInfoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('作品信息'),
        const Text(
          '作品名称',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.textBody,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _nameController,
          enabled: !_saving,
          decoration: _inputDecoration('作品名称'),
        ),
        const SizedBox(height: 14),
        const Text(
          '体裁',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.textBody,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final g in _genres)
              InkWell(
                onTap: _saving ? null : () => setState(() => _genre = g),
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: _genre == g
                        ? AppColors.primarySoft
                        : AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    border: Border.all(
                      color: _genre == g
                          ? AppColors.primary
                          : AppColors.divider,
                    ),
                  ),
                  child: Text(
                    g,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: _genre == g
                          ? AppColors.primary
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        const Text(
          '简介',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.textBody,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _descController,
          enabled: !_saving,
          maxLines: 3,
          minLines: 3,
          decoration: _inputDecoration('简要描述...'),
        ),
      ],
    );
  }

  /// 标签区（对齐 RN「标签」section：本地状态，不落库）
  Widget _buildTagsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('标签'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < _tags.length; i++)
              Container(
                padding: const EdgeInsets.only(
                  left: 12,
                  right: 4,
                  top: 4,
                  bottom: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _tags[i],
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.primary,
                      ),
                    ),
                    InkWell(
                      onTap: _saving ? null : () => _handleRemoveTag(i),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      child: const Padding(
                        padding: EdgeInsets.all(5),
                        child: Icon(
                          Icons.close,
                          size: 13,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            // 添加标签（虚线框，对齐 RN addTagBtn）
            InkWell(
              onTap: _saving ? null : _handleAddTag,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(
                    color: AppColors.border,
                    style: BorderStyle.solid,
                  ),
                ),
                child: const Text(
                  '+ 添加标签',
                  style: TextStyle(fontSize: 13, color: AppColors.textTertiary),
                ),
              ),
            ),
          ],
        ),
        // 批次94-5：热门标签预设（点击即加入，已含不再显示）
        const SizedBox(height: 14),
        const Text(
          '热门标签',
          style: TextStyle(fontSize: 13, color: AppColors.textTertiary),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final preset in _tagPresets)
              if (!_tags.contains(preset))
                InkWell(
                  onTap: _saving ? null : () => setState(() => _tags.add(preset)),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Text(
                      '+ $preset',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
          ],
        ),
      ],
    );
  }

  /// 统计信息区（对齐 RN「统计信息」section）
  Widget _buildStatsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('统计信息'),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: AppColors.divider),
          ),
          child: Text(
            '创建于 $_createdAtText',
            style: const TextStyle(fontSize: 14, color: AppColors.textTertiary),
          ),
        ),
      ],
    );
  }

  /// 危险区（对齐 RN「危险区」section）
  Widget _buildDangerSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('危险区', danger: true),
        OutlinedButton(
          onPressed: _deleting ? null : _handleDelete,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(44),
            side: const BorderSide(color: AppColors.danger),
            foregroundColor: AppColors.danger,
            backgroundColor: AppColors.dangerBg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
          ),
          child: _deleting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.danger,
                  ),
                )
              : const Text(
                  '删除项目',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
        ),
        const SizedBox(height: 8),
        const Center(
          child: Text(
            // 批次78 L2：与删除确认框（批次59）软删语义对齐，不再宣称「不可恢复」
            '删除后作品将不再显示，章节和诊断记录会保留',
            style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
          ),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.textTertiary),
      filled: true,
      fillColor: AppColors.surfaceWhite,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: const BorderSide(color: AppColors.primary),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );
  }
}

/// 分节标题（danger 时用危险色，对齐 RN dangerSectionTitle）
class _SectionTitle extends StatelessWidget {
  final String text;
  final bool danger;
  const _SectionTitle(this.text, {this.danger = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: danger ? AppColors.danger : AppColors.textSecondary,
        ),
      ),
    );
  }
}
