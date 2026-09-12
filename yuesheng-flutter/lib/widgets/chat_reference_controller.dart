// ─────────────────────────────────────────────────────────────
// chat_reference_controller — 聊天页引用/上传/保存动作控制器
//
// 从 chat_reference.dart（原 part/extension）真分解而来：
//   handleUploadFile / handleUploadComplete / refreshAfterUpload
//   / handleSkipPractice / handleSaveToFile / handleMention
//   / handleMentionSelect / handleOpenReferences
//   / openPickerFromReferencesSheet / handleReferencesChanged
//   / loadPrimaryRefTitle
//
// 依赖经 [ChatPageHost] 显式注入；消息刷新委托 [ChatSessionController]。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_theme.dart';
import '../data/database/database.dart';
import '../data/repositories/session_repository.dart';
import '../providers/app_providers.dart';
import '../providers/capability_providers.dart';
import '../providers/chat_store.dart';
import '../providers/practice_providers.dart';
import '../providers/session_providers.dart';
import '../providers/ui_overlay_provider.dart';
import '../services/message_card_service.dart';
import '../services/work_import_service.dart';
import '../types/teaching_types.dart';
import 'abandon_practice_modal.dart';
import 'chat_page_host.dart';
import 'chat_session_controller.dart';
import 'import_success_sheet.dart';
import 'reference_bar.dart';
import 'reference_picker.dart';
import 'save_to_file_sheet.dart';
import 'work_import_sheet.dart';
import 'yue_sheet.dart';

/// 聊天页引用与文件相关动作
class ChatReferenceController {
  final ChatPageHost host;
  final ChatSessionController session;

  ChatReferenceController(this.host, this.session);

  /// + 按钮：打开作品导入弹层（对齐 RN chat.tsx onUploadFile → showUploadModal）
  Future<void> handleUploadFile() async {
    final bootstrap = host.ref.read(sessionBootstrapProvider).valueOrNull;
    if (bootstrap == null || !host.mounted) return;
    showYueModalBottomSheet<void>(
      context: host.context,
      isScrollControlled: true,
      builder: (_) => WorkImportSheet(
        sessionId: bootstrap.sessionId,
        onUploadComplete: handleUploadComplete,
      ),
    );
  }

  /// 导入完成：显示成功引导弹层（对齐 RN ImportSuccessSheet），
  /// 并刷新消息/引用（主引用已建，下轮对话注入引用上下文）
  void handleUploadComplete(WorkImportResult result) {
    if (!host.mounted) return;
    showYueModalBottomSheet<void>(
      context: host.context,
      isScrollControlled: true,
      builder: (_) => ImportSuccessSheet(
        manuscriptTitle: result.title,
        chapterCount: result.chapterCount,
        manuscriptId: result.manuscriptId,
        chapterId: result.firstChapterId,
        onClose: refreshAfterUpload,
        onDiagnose: () {
          // 立即诊断：记录待诊断章节 → 自动诊断（对齐 RN startDiagnosis=true&chapterId=X）
          if (result.firstChapterId.isNotEmpty) {
            host.ref.read(pendingDiagnosisChapterProvider.notifier).state =
                result.firstChapterId;
          }
          refreshAfterUpload();
        },
      ),
    );
  }

  /// 导入后刷新：重载消息（批次 33：ReferenceBar 已移除，仅保留消息刷新）
  void refreshAfterUpload() {
    if (!host.mounted) return;
    session.reloadMessages();
  }

  /// 跳过练习：阻断式确认弹窗（对齐 RN AbandonPracticeModal + chat.tsx L486）
  /// 确认跳过 → 清空练习状态（resetPracticeState）→ 子阶段回 DIAGNOSIS
  Future<void> handleSkipPractice() async {
    final bootstrap = host.ref.read(sessionBootstrapProvider).valueOrNull;
    if (bootstrap == null || !host.mounted) return;
    await AbandonPracticeDialog.show(
      host.context,
      onContinue: () {
        // 继续练习：仅关闭弹窗，任务保留（对齐 RN cancelAbandonPractice）
      },
      onConfirmSkip: () async {
        // 确认跳过：清空练习状态 + 子阶段回 DIAGNOSIS（对齐 RN L486）
        host.ref.read(practiceStoreProvider.notifier).resetPractice();
        try {
          await host.ref
              .read(chatServiceProvider)
              .setSubphase(bootstrap.sessionId, TeachingSubphase.diagnosis);
        } catch (_) {
          // 持久化失败保持内存状态（对齐 RN 不阻塞跳过流程）
        }
      },
    );
  }

  /// 「保存到文件」：读取主引用 → 打开 SaveToFileSheet（对齐 RN onSaveToFile）
  ///
  /// 批次 39（引用死数据修复）：无主引用时回退到第一条引用（章节/作品），
  /// 避免 @ 引用场景下保存到文件永远提示「请先关联一本书籍」（死数据）。
  Future<void> handleSaveToFile(Message message) async {
    final bootstrap = host.ref.read(sessionBootstrapProvider).valueOrNull;
    if (bootstrap == null || !host.mounted) return;
    final refRepo = host.ref.read(referenceCapabilityProvider);
    final refs = await refRepo.listReferences(bootstrap.sessionId);
    // 主引用优先；无主引用（@ 附加引用场景）回退到第一条章节/作品引用
    final primary =
        refs.where((r) => r.isPrimary == 1).firstOrNull ??
        refs.where((r) => r.refType != 'file').firstOrNull;
    if (primary == null) {
      if (host.mounted) {
        // 真机反馈：底部 SnackBar 完全遮挡输入框，改用全局 toast
        host.ref.read(uiOverlayProvider.notifier).showToast('请先关联一本书籍');
      }
      return;
    }
    if (!host.context.mounted) return;
    // bookId：chapter 主引用用其所属作品，manuscript 主引用用自身
    final bookId = primary.manuscriptId ?? primary.refId;
    await showYueModalBottomSheet<void>(
      context: host.context,
      isScrollControlled: true,
      builder: (_) => SaveToFileSheet(
        content: message.content,
        bookId: bookId,
        bookTitle: primary.title,
      ),
    );
  }

  /// @ 按钮：打开引用选择器（mention 模式，对齐 RN onMention）
  void handleMention() {
    final bootstrap = host.ref.read(sessionBootstrapProvider).valueOrNull;
    if (bootstrap == null || !host.mounted) return;
    showYueModalBottomSheet<void>(
      context: host.context,
      isScrollControlled: true,
      builder: (_) => ReferencePicker(
        mode: 'mention',
        onSelectMention: handleMentionSelect,
      ),
    );
  }

  /// mention 选择：通过 ChatInputState.insertMention 把 @路径 插到光标位置
  void handleMentionSelect(String mentionPath, String title) {
    if (!host.mounted) return;
    host.chatInputKey.currentState?.insertMention(mentionPath);
  }

  /// 引用管理：底部弹层内嵌 ReferenceBar（撤销/设主/批量删除/添加）。
  void handleOpenReferences() {
    final bootstrap = host.ref.read(sessionBootstrapProvider).valueOrNull;
    if (bootstrap == null || !host.mounted) return;
    showYueModalBottomSheet<void>(
      context: host.context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(
            top: AppSpacing.sm,
            bottom: AppSpacing.sm,
          ),
          child: ReferenceBar(
            sessionId: bootstrap.sessionId,
            onPressPicker: () =>
                openPickerFromReferencesSheet(bootstrap.sessionId),
            onReferencesChanged: handleReferencesChanged,
          ),
        ),
      ),
    );
  }

  /// ReferenceBar「+ 添加引用」：关闭管理弹层 → 引用选择器 → 添加引用
  void openPickerFromReferencesSheet(String sessionId) {
    if (!host.mounted) return;
    Navigator.of(host.context).pop(); // 关闭引用管理弹层
    final refRepo = host.ref.read(referenceCapabilityProvider);
    showYueModalBottomSheet<void>(
      context: host.context,
      isScrollControlled: true,
      builder: (sheetCtx) => ReferencePicker(
        mode: 'default',
        onSelect: (refType, refId, title) async {
          try {
            // 从管理入口添加的引用保持附加身份（主引用可在弹层内切换）
            await refRepo.addReference(sessionId, refType, refId);
            handleReferencesChanged('add', refType, title);
            if (host.context.mounted) {
              ScaffoldMessenger.of(
                host.context,
              ).showSnackBar(SnackBar(content: Text('已添加引用：$title')));
            }
          } catch (_) {
            if (host.context.mounted) {
              ScaffoldMessenger.of(
                host.context,
              ).showSnackBar(const SnackBar(content: Text('添加引用失败，请稍后再试')));
            }
          }
        },
      ),
    );
  }

  /// 引用变更（设主/移除/添加）→ 插入 reference_change 卡片 + 刷新消息列表。
  Future<void> handleReferencesChanged(
    String action,
    String refType,
    String refTitle,
  ) async {
    final bootstrap = host.ref.read(sessionBootstrapProvider).valueOrNull;
    if (bootstrap == null) return;
    try {
      await insertReferenceChangeCard(
        SessionRepository(host.ref.read(appDatabaseProvider)),
        bootstrap.sessionId,
        ReferenceChangeCardPayload(
          action: action,
          refType: refType,
          refTitle: refTitle,
        ),
      );
      final messages = await SessionRepository(
        host.ref.read(appDatabaseProvider),
      ).listMessages(bootstrap.sessionId);
      host.ref.read(chatStoreProvider.notifier).setMessages(messages);
    } catch (_) {
      // 卡片写入失败不阻断主操作（引用变更本身已生效）
    }
    // 设主/添加/移除后主引用可能变了，刷新头部小字
    loadPrimaryRefTitle();
  }

  /// 加载当前会话主引用书名（头部小字展示）。
  /// 主引用 = references 里 isPrimary==1；无主引用时回退第一条章节/作品引用
  /// （与 handleSaveToFile 口径一致），都没有则 null -> 显示「未关联书籍」。
  Future<void> loadPrimaryRefTitle() async {
    final bootstrap = host.ref.read(sessionBootstrapProvider).valueOrNull;
    if (bootstrap == null || !host.mounted) return;
    try {
      final refs = await host.ref
          .read(referenceCapabilityProvider)
          .listReferences(bootstrap.sessionId);
      final primary =
          refs.where((r) => r.isPrimary == 1).firstOrNull ??
          refs.where((r) => r.refType != 'file').firstOrNull;
      if (!host.mounted) return;
      host.setPrimaryRefTitle(primary?.title);
    } catch (_) {
      // 读取失败保持现状（头部小字降级为未关联文案）
    }
  }
}
