// ─────────────────────────────────────────────────────────────
// WritingCoachPanel 专用 ChatStore Provider（独立文件，避免循环依赖）
//
// 从 writing_coach_panel.dart 抽出：各控制器 / 链路执行器都需要它，
// 若继续放在宿主文件中会与宿主相互 import 形成循环（门禁 3 全量卡口）。
// 宿主与各协作类统一从本文件 import。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/chat_store.dart';

/// WritingCoachPanel 专用 ChatStore（与 Tab2 chatStoreProvider 隔离）
///
/// 按 chapterId 隔离：每个章节拥有独立的 ChatStore 实例，
/// 避免多个 WritingCoachPanel 实例共享同一个 store 导致会话污染。
final writingCoachStoreProvider =
    StateNotifierProvider.family<ChatStore, ChatState, String>((
      ref,
      chapterId,
    ) {
      return ChatStore();
    });
