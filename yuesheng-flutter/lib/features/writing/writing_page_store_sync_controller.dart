// ─────────────────────────────────────────────────────────────
// WritingPageStoreSyncController — store 状态同步控制器（C92-6b）
//
// 来源：宿主 `writing_page.dart` 外迁（`ref.listen` 挂载与各状态同步：
// 正文/标题/行段聚焦开关同步、保存失败提示、草稿恢复触发、跨章搜索定位、
// 网络状态订阅、dispose 强制保存）。
// 依赖：宿主 + 文档控制器（正文同步）+ 状态控制器（草稿恢复弹窗）。
// ─────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

import '../../providers/writing_providers.dart';
import 'writing_page_host.dart';
import 'writing_page_document_controller.dart';
import 'writing_page_status_controller.dart';

class WritingPageStoreSyncController {
  WritingPageStoreSyncController(this._host, this._document, this._status);

  final WritingPageHost _host;
  final WritingPageDocumentController _document;
  final WritingPageStatusController _status;

  // 网络状态订阅（离线 → 保存走本地草稿 + 横幅提示 + 恢复网络自动同步）
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  /// 对齐 RN useNetInfo：监听网络状态变化 → 写入 store（离线草稿/恢复同步）。
  /// 测试环境无 connectivity 平台插件 → onError 容错静默降级（不影响编辑）。
  void bindConnectivity() {
    _connectivitySub = Connectivity().onConnectivityChanged.listen(
      (results) => _setOffline(results.contains(ConnectivityResult.none)),
      onError: (Object e) {
        debugPrint('[WritingPage] 网络状态监听不可用: $e');
      },
    );
    // 初始状态查询（流只在变化时触发，需主动取一次初值）
    Connectivity()
        .checkConnectivity()
        .then((results) {
          if (!_host.mounted) return;
          _setOffline(results.contains(ConnectivityResult.none));
        })
        .catchError((Object e) {
          debugPrint('[WritingPage] 初始网络检查不可用: $e');
        });
  }

  void _setOffline(bool offline) {
    _host.ref
        .read(writingStoreProvider(_host.chapterId).notifier)
        .setOffline(offline);
  }

  void disposeConnectivity() {
    _connectivitySub?.cancel();
  }

  /// `ref.listen` 挂载（监听状态变化以同步 controller / 提示保存失败 / 定位光标）
  void bindStoreListener() {
    _host.ref.listen<WritingState>(writingStoreProvider(_host.chapterId), (
      previous,
      next,
    ) {
      syncEditorFromState(next);
      handleSaveErrorTransition(previous, next);
      syncTitleFromState(next);
      syncFocusMode(previous, next);
      maybeLocateSearchCursor();
      maybeShowDraftRestore(next);
    });
  }

  /// 章节内容就绪 → 同步 controller（仅当 controller 尚空）
  void syncEditorFromState(WritingState next) {
    if (_host.editorController.text.isEmpty && next.localContent.isNotEmpty) {
      _document.syncEditorText(next.localContent);
    }
  }

  /// 批次60/91-1：保存失败 → SnackBar 温和提示（防刷屏标志，成功自动复位）
  void handleSaveErrorTransition(WritingState? previous, WritingState next) {
    if (previous?.saveError == null && next.saveError != null) {
      if (!_host.saveErrorShown) {
        _host.saveErrorShown = true;
        ScaffoldMessenger.of(
          _host.context,
        ).showSnackBar(const SnackBar(content: Text('刚才的内容没能保存成功，请稍后重试')));
      }
    } else if (next.saveError == null) {
      _host.saveErrorShown = false;
    }
  }

  /// 批次 36：章节标题同步到标题输入框（仅非用户输入时；用户输入时
  /// state.chapter.title 同步为输入值 == controller.text，天然跳过）
  void syncTitleFromState(WritingState next) {
    final nextTitle = next.chapter?.title;
    if (nextTitle != null && _host.titleController.text != nextTitle) {
      _host.titleController.text = nextTitle;
    }
  }

  /// 批次96-9：行段聚焦开关状态同步到控制器（排版设置里切换 → 淡化渲染即时生效）
  void syncFocusMode(WritingState? previous, WritingState next) {
    if (previous?.focusMode != next.focusMode) {
      _host.editorController.focusMode = next.focusMode;
    }
  }

  /// 批次96-11：跨章全文搜索定位——内容就绪后定位到命中处
  /// （initialCursorOffset 来自路由 extra，搜索 sheet 点击跨章结果时携带）
  /// FIX-5：定位失败（offset 越界/文本不匹配）**不置位** [searchCursorLocated]，
  /// 内容后续变化时再次尝试（草稿恢复/未保存编辑致 DB 与编辑器坐标系错位时，
  /// 原 offset 可能失效，等待新文本就绪后重试）。
  void maybeLocateSearchCursor() {
    final offset = _host.initialCursorOffset;
    if (offset == null || _host.searchCursorLocated) return;
    final text = _host.editorController.text;
    if (text.isEmpty) return; // 内容未就绪 → 等待下次同步
    if (_host.locateCursor(offset)) {
      _host.searchCursorLocated = true;
    }
  }

  /// 草稿恢复弹窗（仅一次）：打开章节检测到较新草稿 → 询问是否恢复
  /// 对齐 RN chapter-editor.tsx#L128-L133 Alert
  void maybeShowDraftRestore(WritingState next) {
    if (!_host.draftDialogShown &&
        next.hasDraft &&
        !next.isLoading &&
        next.chapter != null) {
      _host.draftDialogShown = true;
      _status.showDraftRestoreDialog(next);
    }
  }

  /// 批次91-1：有未保存改动或未决合并保存 → 离开页面时强制保存
  /// （fire-and-forget；`_dirty` 在 scheduleSave 路径下不再自动清除，
  /// 加上 hasPendingSave 双保险，保证 300ms 窗口内返回页面时未落库内容不丢失）
  void forceSaveOnDispose() {
    final store = _host.store;
    if ((_host.dirty || store?.hasPendingSave == true) && store != null) {
      // 立即取消未决的保存/历史定时器（防 dispose 后回调访问已销毁状态，
      // 以及测试 binding 报 pending timer）；保存走下一帧强制 saveNow
      store.cancelPendingTimers();
      // 延迟到下一帧执行：此时 widget 已完全卸载，ref.watch 依赖已清理，
      // state 变化不会触发已销毁 element 的 rebuild。
      debugPrint('[WritingPage] dispose 触发强制保存: chapterId=${_host.chapterId}');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // ★ 2026-10-07 补生命周期守卫：本回调可能落在 store 已 dispose 之后
        //   （页面 dispose → 下一帧才跑，而 ProviderContainer 卸载会先 dispose
        //   WritingStore）。此时 `saveNow` 首行即 `state = ...`，
        //   WritingStore 未对 saveNow 加 mounted 守卫（writing_providers.dart:457-464）
        //   ⇒ 直接抛 `Bad state: Tried to use WritingStore after dispose was called`。
        //   实证：批次91-1 用例在测试拆树期的 warm-up 帧上抛该 StateError。
        //   守卫放在**调用点**而非 saveNow 内：saveNow 的其余调用
        //   （applyParagraphFormat 等）都在页面 mounted 期执行，
        //   给它加闸等于用全局改动掩盖单点时序问题。
        if (!store.mounted) {
          debugPrint(
            '[WritingPage] dispose 强制保存跳过（store 已 dispose）: '
            'chapterId=${_host.chapterId}',
          );
          return;
        }
        // saveNow 内部 catch 所有异常并 debugPrint（含 chapterId + error）；
        // widget 已销毁无人监听 state.error，此处仅留 dispose 上下文标记，
        // 与 [WritingStore] saveNow 失败 日志通过 chapterId 关联排查。
        store.saveNow();
      });
    }
  }

  /// A1 修复：App 切后台 / 锁屏 / inactive / hidden 时立即 flush 未保存输入。
  ///
  /// 自动保存只靠 300ms `Timer`，但后台挂起后 timer 不保证触发、
  /// `addPostFrameCallback` 也无新帧可跑；最后一次击键后 300ms 内切后台，
  /// 这一段文字既不落 chapters 表、离线分支也没走。这里取消未决定时器后
  /// 直接 `saveNow()`（fire-and-forget），复用现有落库通道——在线写库、
  /// 离线写草稿，两条路都覆盖。
  void flushOnLifecycle() {
    final store = _host.store;
    if (store == null) return;
    // 与 dispose 强制保存同判据：有未保存改动或未决保存定时器才 flush，
    // 无改动时 saveNow 是冗余写库。
    if (!_host.dirty && !store.hasPendingSave) return;
    store.cancelPendingTimers();
    debugPrint('[WritingPage] 生命周期切后台触发 flush: chapterId=${_host.chapterId}');
    store.saveNow();
  }
}
