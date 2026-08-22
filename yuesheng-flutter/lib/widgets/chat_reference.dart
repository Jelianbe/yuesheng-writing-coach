// ignore_for_file: invalid_use_of_protected_member
part of 'chat_page.dart';

extension _ChatReference on _ChatPageState {
  /// + 按钮：打开作品导入弹层（对齐 RN chat.tsx onUploadFile → showUploadModal）
  Future<void> _handleUploadFile() async {
    final bootstrap = ref.read(sessionBootstrapProvider).valueOrNull;
    if (bootstrap == null || !mounted) return;
    showYueModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => WorkImportSheet(
        sessionId: bootstrap.sessionId,
        onUploadComplete: _handleUploadComplete,
      ),
    );
  }

  /// 导入完成：显示成功引导弹层（对齐 RN ImportSuccessSheet），
  /// 并刷新消息/引用（主引用已建，下轮对话注入引用上下文）
  void _handleUploadComplete(WorkImportResult result) {
    if (!mounted) return;
    showYueModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ImportSuccessSheet(
        manuscriptTitle: result.title,
        chapterCount: result.chapterCount,
        manuscriptId: result.manuscriptId,
        chapterId: result.firstChapterId,
        onClose: _refreshAfterUpload,
        onDiagnose: () {
          // 立即诊断：记录待诊断章节 → 自动诊断（对齐 RN startDiagnosis=true&chapterId=X）
          if (result.firstChapterId.isNotEmpty) {
            ref.read(pendingDiagnosisChapterProvider.notifier).state =
                result.firstChapterId;
          }
          _refreshAfterUpload();
        },
      ),
    );
  }

  /// 导入后刷新：重载消息（批次 33：ReferenceBar 已移除，仅保留消息刷新）
  void _refreshAfterUpload() {
    if (!mounted) return;
    _reloadMessages();
  }

  /// 跳过练习：阻断式确认弹窗（对齐 RN AbandonPracticeModal + chat.tsx L486）
  /// 确认跳过 → 清空练习状态（resetPracticeState）→ 子阶段回 DIAGNOSIS
  Future<void> _handleSkipPractice() async {
    final bootstrap = ref.read(sessionBootstrapProvider).valueOrNull;
    if (bootstrap == null || !mounted) return;
    await AbandonPracticeDialog.show(
      context,
      onContinue: () {
        // 继续练习：仅关闭弹窗，任务保留（对齐 RN cancelAbandonPractice）
      },
      onConfirmSkip: () async {
        // 确认跳过：清空练习状态 + 子阶段回 DIAGNOSIS（对齐 RN L486）
        ref.read(practiceStoreProvider.notifier).resetPractice();
        setState(() => _subphase = TeachingSubphase.diagnosis);
        try {
          await ref
              .read(chatServiceProvider)
              .setSubphase(bootstrap.sessionId, TeachingSubphase.diagnosis);
        } catch (_) {
          // 持久化失败保持内存状态（对齐 RN 不阻塞跳过流程）
        }
      },
    );
  }

  /// 「保存到文件」：读取主引用 → 打开 SaveToFileSheet（对齐 RN onSaveToFile chat.tsx L450）
  ///
  /// 批次 39（引用死数据修复）：无主引用时回退到第一条引用（章节/作品），
  /// 避免 @ 引用场景下保存到文件永远提示「请先关联一本书籍」（死数据）。
  Future<void> _handleSaveToFile(Message message) async {
    final bootstrap = ref.read(sessionBootstrapProvider).valueOrNull;
    if (bootstrap == null || !mounted) return;
    final refRepo = ref.read(referenceCapabilityProvider);
    final refs = await refRepo.listReferences(bootstrap.sessionId);
    // 主引用优先；无主引用（@ 附加引用场景）回退到第一条章节/作品引用
    final primary =
        refs.where((r) => r.isPrimary == 1).firstOrNull ??
        refs.where((r) => r.refType != 'file').firstOrNull;
    if (primary == null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('请先关联一本书籍')));
      }
      return;
    }
    if (!mounted) return;
    // bookId：chapter 主引用用其所属作品（manuscriptId 已回填），manuscript 主引用用自身
    final bookId = primary.manuscriptId ?? primary.refId;
    await showYueModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SaveToFileSheet(
        content: message.content,
        bookId: bookId,
        bookTitle: primary.title,
      ),
    );
  }

  /// @ 按钮：打开引用选择器（mention 模式，对齐 RN chat.tsx onMention → showReferencePicker）
  void _handleMention() {
    final bootstrap = ref.read(sessionBootstrapProvider).valueOrNull;
    if (bootstrap == null || !mounted) return;
    showYueModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ReferencePicker(
        mode: 'mention',
        onSelectMention: _handleMentionSelect,
      ),
    );
  }

  /// mention 选择：通过 ChatInputState.insertMention 把 @路径 插到光标位置
  /// （批次70：替代原简单末尾拼接；mentionPath 已由 buildMentionPath 带 @ 前缀）
  void _handleMentionSelect(String mentionPath, String title) {
    if (!mounted) return;
    _chatInputKey.currentState?.insertMention(mentionPath);
  }

  /// 引用管理：底部弹层内嵌 ReferenceBar（撤销/设主/批量删除/添加）。
  /// 修复「@ 只能添加、不能撤销/管理」的断裂链路（批次 33 移除顶部条后无入口）。
  void _handleOpenReferences() {
    final bootstrap = ref.read(sessionBootstrapProvider).valueOrNull;
    if (bootstrap == null || !mounted) return;
    showYueModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: ReferenceBar(
            sessionId: bootstrap.sessionId,
            onPressPicker: () =>
                _openPickerFromReferencesSheet(bootstrap.sessionId),
            onReferencesChanged: _handleReferencesChanged,
          ),
        ),
      ),
    );
  }

  /// ReferenceBar「+ 添加引用」：关闭管理弹层 → 引用选择器（default 模式）→ 添加引用
  void _openPickerFromReferencesSheet(String sessionId) {
    if (!mounted) return;
    Navigator.of(context).pop(); // 关闭引用管理弹层
    final refRepo = ref.read(referenceCapabilityProvider);
    showYueModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => ReferencePicker(
        mode: 'default',
        onSelect: (refType, refId, title) async {
          Navigator.pop(sheetCtx);
          try {
            // 从管理入口添加的引用保持附加身份（主引用可在弹层内切换）
            await refRepo.addReference(sessionId, refType, refId);
            _handleReferencesChanged('add', refType, title);
            if (mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('已添加引用：$title')));
            }
          } catch (_) {
            if (mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('添加引用失败，请稍后再试')));
            }
          }
        },
      ),
    );
  }

  /// 引用变更（设主/移除/添加）→ 插入 reference_change 卡片 + 刷新消息列表。
  /// 修复 message_card_service.insertReferenceChangeCard 写入端无人调用的死链路。
  Future<void> _handleReferencesChanged(
    String action,
    String refType,
    String refTitle,
  ) async {
    final bootstrap = ref.read(sessionBootstrapProvider).valueOrNull;
    if (bootstrap == null) return;
    try {
      await insertReferenceChangeCard(
        SessionRepository(ref.read(appDatabaseProvider)),
        bootstrap.sessionId,
        ReferenceChangeCardPayload(
          action: action,
          refType: refType,
          refTitle: refTitle,
        ),
      );
      final messages = await SessionRepository(
        ref.read(appDatabaseProvider),
      ).listMessages(bootstrap.sessionId);
      ref.read(chatStoreProvider.notifier).setMessages(messages);
    } catch (_) {
      // 卡片写入失败不阻断主操作（引用变更本身已生效）
    }
  }
}
