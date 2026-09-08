// ─────────────────────────────────────────────────────────────
// ReferencePicker — 引用选择器（@ 按钮）
// 真源：yuesheng-android/src/components/reference/ReferencePicker.tsx
//
// 批次4b 范围（default 模式）：
//   - 作品 Tab：稿件列表 → 展开章节 → 选择章节 / 引用整本书
//   - 素材 Tab：按稿件分组的素材文件列表
//   - 选择后 onSelect(refType, refId, title) → 关闭弹层
//
// 说明：
//   - session_reference.ref_type 支持 manuscript/chapter/file（批次7 D2：v21 CHECK 已扩）；
//     素材文件（file）可作次引用，不可设主（setPrimaryReference 有 ArgumentError 防御）
//   - mention 模式（@作品标题/章节标题 插入输入框，批次71 文字格式）
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_theme.dart';
import '../data/database/database.dart';
import '../data/repositories/chapter_repository.dart';
import '../data/repositories/manuscript_repository.dart';
import '../data/repositories/reference_repository.dart';
import '../data/repositories/volume_repository.dart';
import '../providers/app_providers.dart';
import '../providers/capability_providers.dart';
import '../services/mention_parser.dart';

class ReferencePicker extends ConsumerStatefulWidget {
  /// 选择回调：refType ∈ {manuscript, chapter, file}（default 模式）
  final void Function(String refType, String refId, String title)? onSelect;

  /// mention 模式回调：选择后返回 @路径 + 标题（如 "@AAA/第一章"）
  final void Function(String mentionPath, String title)? onSelectMention;

  /// 模式：'default' 设引用；'mention' 插入 @路径 到输入框
  final String mode;

  const ReferencePicker({
    super.key,
    this.onSelect,
    this.onSelectMention,
    this.mode = 'default',
  });

  @override
  ConsumerState<ReferencePicker> createState() => _ReferencePickerState();
}

class _ReferencePickerState extends ConsumerState<ReferencePicker> {
  List<Manuscript> _manuscripts = [];
  Map<String, List<Chapter>> _chaptersMap = {};
  Map<String, List<AttachedFileRow>> _filesMap = {};

  /// 作品 → 卷列表（批次97 卷引用：分卷作品按卷分组）
  Map<String, List<Volume>> _volumesMap = {};
  String? _expandedMsId;

  /// 当前展开的卷（作品下二级展开）
  String? _expandedVolumeId;
  final Set<String> _filesExpanded = {};
  int _tab = 0; // 0=作品 1=素材

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(appDatabaseProvider);
    final msRepo = ManuscriptRepository(db);
    final refRepo = ref.read(referenceCapabilityProvider);

    final msList = await msRepo.listManuscripts();

    // 卷按稿件分组（批次97 卷引用）
    final volRepo = VolumeRepository(db);
    final volumesMap = <String, List<Volume>>{};
    for (final m in msList) {
      final vols = await volRepo.listVolumes(m.id);
      if (vols.isNotEmpty) volumesMap[m.id] = vols;
    }

    // 素材文件按稿件分组（RN loadFiles 语义）
    final filesMap = <String, List<AttachedFileRow>>{};
    for (final m in msList) {
      final files = await refRepo.listAttachedFiles(m.id);
      if (files.isNotEmpty) filesMap[m.id] = files;
    }

    if (!mounted) return;
    setState(() {
      _manuscripts = msList;
      _filesMap = filesMap;
      _volumesMap = volumesMap;
    });
  }

  Future<void> _toggleExpand(String manuscriptId) async {
    if (_expandedMsId == manuscriptId) {
      setState(() => _expandedMsId = null);
      return;
    }
    setState(() => _expandedMsId = manuscriptId);
    if (!_chaptersMap.containsKey(manuscriptId)) {
      final db = ref.read(appDatabaseProvider);
      final chapters = await ChapterRepository(db).listChapters(manuscriptId);
      if (!mounted) return;
      setState(() => _chaptersMap = {..._chaptersMap, manuscriptId: chapters});
    }
  }

  /// 展开/收起卷（作品展开后二级）
  void _toggleVolume(String volumeId) {
    setState(() {
      _expandedVolumeId = _expandedVolumeId == volumeId ? null : volumeId;
    });
  }

  void _handleSelect(
    String refType,
    String refId,
    String title,
    String mentionPath,
  ) {
    Navigator.of(context).pop();
    if (widget.mode == 'mention') {
      // 插入 @标题 路径（@AAA 或 @AAA/第一章，/ 表上下级；批次71 文字格式）。
      // 注：曾用稳定 ID 标记 @[refType:refId]（改名免疫），但用户侧展示为
      // 编号不易读；trade-off：改名后旧消息引用降级为普通文本（parser 兼容）。
      widget.onSelectMention?.call(mentionPath, title);
    } else {
      widget.onSelect?.call(refType, refId, title);
    }
  }

  /// mention 模式下的路径徽章
  Widget _mentionBadge(String path) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xsm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text(
        path,
        style: const TextStyle(fontSize: 11, color: AppColors.primary),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 顶部把手
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(
              top: AppSpacing.md,
              bottom: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: AppColors.borderSoft,
              borderRadius: BorderRadius.circular(AppRadius.xs),
            ),
            alignment: Alignment.center,
          ),
          const Text(
            '选择引用',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '选择要分析的作品或章节',
            textAlign: TextAlign.center,
            style: AppTextStyles.subCaption,
          ),
          const SizedBox(height: 12),

          // Tab 切换
          Container(
            margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            padding: const EdgeInsets.all(AppSpacing.xxs),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Row(
              children: [
                _TabButton(
                  label: '作品',
                  active: _tab == 0,
                  onTap: () => setState(() => _tab = 0),
                ),
                _TabButton(
                  label: '素材',
                  active: _tab == 1,
                  onTap: () => setState(() => _tab = 1),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // 列表区
          Flexible(
            child: SingleChildScrollView(
              child: _tab == 0 ? _buildWorksTab() : _buildFilesTab(),
            ),
          ),
          const SizedBox(height: 8),

          // 取消
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
                side: const BorderSide(color: AppColors.borderSoft),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
              ),
              child: const Text(
                '取消',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 作品 Tab ──
  Widget _buildWorksTab() {
    if (_manuscripts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl + AppSpacing.lg),
        child: Column(
          children: [
            Icon(
              Icons.library_books_outlined,
              size: 40,
              color: AppColors.disabledText,
            ),
            SizedBox(height: 8),
            Text('还没有作品', style: TextStyle(color: AppColors.textTertiary)),
            SizedBox(height: 4),
            Text(
              '去书架创建，或通过「+」导入小说',
              style: TextStyle(fontSize: 12, color: AppColors.disabledText),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [for (final m in _manuscripts) _buildManuscriptTile(m)],
    );
  }

  Widget _buildManuscriptTile(Manuscript m) {
    final expanded = _expandedMsId == m.id;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => _toggleExpand(m.id),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          m.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      if (widget.mode == 'mention') ...[
                        const SizedBox(width: 8),
                        _mentionBadge(buildMentionPath(m.title)),
                      ],
                    ],
                  ),
                ),
                // 引用整本书
                GestureDetector(
                  onTap: () => _handleSelect(
                    'manuscript',
                    m.id,
                    m.title,
                    buildMentionPath(m.title),
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xxs,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: const Text(
                      '引用整本书',
                      style: TextStyle(fontSize: 12, color: AppColors.primary),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  expanded
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_right,
                  size: 18,
                  color: AppColors.disabledText,
                ),
              ],
            ),
          ),
        ),
        if (expanded) ...[
          const Divider(height: 1, color: AppColors.borderSoft),
          _buildChapterList(m),
        ],
        const Divider(height: 1, color: AppColors.borderSoft),
      ],
    );
  }

  Widget _buildChapterList(Manuscript m) {
    final chapters = _chaptersMap[m.id] ?? const <Chapter>[];
    if (chapters.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Text(
          '暂无章节',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: AppColors.disabledText),
        ),
      );
    }

    // 批次97：分卷作品先按卷分组（卷 → 卷内章节），未分卷章节归「未分卷」组
    final volumes = _volumesMap[m.id] ?? const <Volume>[];
    if (volumes.isNotEmpty) {
      final ungrouped = chapters.where((c) => c.volumeId == null).toList();
      return Column(
        children: [
          for (final v in volumes) _buildVolumeTile(m, v),
          if (ungrouped.isNotEmpty) _buildUngroupedTitle(ungrouped.length),
          for (final c in ungrouped) _buildChapterRow(m, c),
        ],
      );
    }

    // 无卷：章节平铺（存量逻辑）
    return Column(children: [for (final c in chapters) _buildChapterRow(m, c)]);
  }

  /// 卷行：点击=选中卷（方案2b：@作品/卷 可引用），箭头=展开卷内章节
  Widget _buildVolumeTile(Manuscript m, Volume v) {
    final expanded = _expandedVolumeId == v.id;
    final inVol = (_chaptersMap[m.id] ?? const <Chapter>[])
        .where((c) => c.volumeId == v.id)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: _buildVolumeSelectArea(m, v)),
            _buildVolumeArrow(v, expanded),
          ],
        ),
        if (expanded)
          for (final c in inVol) _buildChapterRow(m, c, inVolume: v),
        const Divider(height: 1, color: AppColors.borderSoft),
      ],
    );
  }

  /// 卷行选中区（点击 → 引用整卷 @作品/卷）
  Widget _buildVolumeSelectArea(Manuscript m, Volume v) {
    return InkWell(
      onTap: () => _handleSelect(
        'volume',
        v.id,
        '${m.title} · ${v.title}',
        buildMentionPath(m.title, subTitle: v.title),
      ),
      child: Padding(
        padding: const EdgeInsets.only(
          left: AppSpacing.section + AppSpacing.sm,
          right: AppSpacing.xxs,
          top: AppSpacing.smx,
          bottom: AppSpacing.smx,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                v.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            if (widget.mode == 'mention') ...[
              const SizedBox(width: 8),
              _mentionBadge(buildMentionPath(m.title, subTitle: v.title)),
            ],
          ],
        ),
      ),
    );
  }

  /// 卷行展开箭头（点击 → 展开/收起卷内章节，不触发选中）
  Widget _buildVolumeArrow(Volume v, bool expanded) {
    return InkWell(
      onTap: () => _toggleVolume(v.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.smx,
        ),
        child: Icon(
          expanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
          size: 18,
          color: AppColors.disabledText,
        ),
      ),
    );
  }

  /// 未分卷章节组标题
  Widget _buildUngroupedTitle(int count) {
    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.section + AppSpacing.sm,
        right: AppSpacing.lg,
        top: AppSpacing.smx,
        bottom: AppSpacing.xxs,
      ),
      child: Text(
        '未分卷（$count）',
        style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
      ),
    );
  }

  /// 章节行（选中 → @作品/卷/章 或 @作品/章）
  Widget _buildChapterRow(Manuscript m, Chapter c, {Volume? inVolume}) {
    final path = buildMentionPath(
      m.title,
      volumeTitle: inVolume?.title,
      subTitle: c.title,
    );
    final displayTitle = inVolume == null
        ? '${m.title} · ${c.title}'
        : '${m.title} · ${inVolume.title} · ${c.title}';
    return InkWell(
      onTap: () => _handleSelect('chapter', c.id, displayTitle, path),
      child: _buildChapterRowBody(m, c, path),
    );
  }

  /// 章节行内容区（标题 + 路径徽章 + 字数）
  Widget _buildChapterRowBody(Manuscript m, Chapter c, String path) {
    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.section + AppSpacing.sm,
        right: AppSpacing.lg,
        top: AppSpacing.smx,
        bottom: AppSpacing.smx,
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    c.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                if (widget.mode == 'mention') ...[
                  const SizedBox(width: 8),
                  _mentionBadge(path),
                ],
              ],
            ),
          ),
          Text(
            '${c.wordCount} 字',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.disabledText,
            ),
          ),
        ],
      ),
    );
  }

  // ── 素材 Tab ──
  Widget _buildFilesTab() {
    final hasFiles = _filesMap.values.any((files) => files.isNotEmpty);
    if (!hasFiles) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl + AppSpacing.lg),
        child: Column(
          children: [
            Icon(Icons.attach_file, size: 40, color: AppColors.disabledText),
            SizedBox(height: 8),
            Text('还没有素材文件', style: TextStyle(color: AppColors.textTertiary)),
            SizedBox(height: 4),
            Text(
              // 批次77：文案指向真实路径（全应用无「素材页」，素材在作品详情的文件 Tab 添加）
              '在作品详情的「文件」中添加素材文件',
              style: TextStyle(fontSize: 12, color: AppColors.disabledText),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        for (final m in _manuscripts)
          if ((_filesMap[m.id] ?? const []).isNotEmpty) _buildFileGroup(m),
      ],
    );
  }

  Widget _buildFileGroup(Manuscript m) {
    final files = _filesMap[m.id]!;
    final expanded = _filesExpanded.contains(m.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() {
            expanded ? _filesExpanded.remove(m.id) : _filesExpanded.add(m.id);
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    m.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Icon(
                  expanded
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_right,
                  size: 18,
                  color: AppColors.disabledText,
                ),
              ],
            ),
          ),
        ),
        if (expanded)
          for (var fIndex = 0; fIndex < files.length; fIndex++)
            InkWell(
              onTap: () => _handleSelect(
                'file',
                files[fIndex].id,
                '【素材】${files[fIndex].fileName}',
                buildMentionPath(m.title, subTitle: files[fIndex].fileName),
              ),
              child: Padding(
                padding: const EdgeInsets.only(
                  left: AppSpacing.section + AppSpacing.sm,
                  right: AppSpacing.lg,
                  top: AppSpacing.smx,
                  bottom: AppSpacing.smx,
                ),
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        files[fIndex].fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    if (widget.mode == 'mention') ...[
                      const SizedBox(width: 8),
                      _mentionBadge(
                        buildMentionPath(
                          m.title,
                          subTitle: files[fIndex].fileName,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        const Divider(height: 1, color: AppColors.borderSoft),
      ],
    );
  }
}

class _TabButton extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _TabButton({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: active ? AppColors.surfaceWhite : null,
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: active ? FontWeight.w600 : FontWeight.w500,
              color: active ? AppColors.textPrimary : AppColors.textTertiary,
            ),
          ),
        ),
      ),
    );
  }
}
