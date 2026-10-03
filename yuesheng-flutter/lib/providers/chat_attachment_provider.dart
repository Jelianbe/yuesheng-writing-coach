// ─────────────────────────────────────────────────────────────
// chat_attachment_provider — 待发图片附件暂存（C147）
//
// 解耦「选图入口」与「发送链路」：
//   - 选图（WorkImportSheet → ChatReferenceController.attachPickedImage）写入；
//   - 发送（ChatTeachingController.handleSend）取走并清空，注入 SendMessageOptions。
//
// 用 provider 而非控制器直挂，避免 teaching↔reference 跨控制器耦合。
// R-009/R-027：仅承载图片 content block，不夹带任何看图评判指令文本。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/llm_client.dart';

/// 待随下一条用户消息发出的多模态附件（图片 content block）。
class PendingAttachmentsNotifier extends StateNotifier<List<ChatContentBlock>> {
  PendingAttachmentsNotifier() : super(const []);

  void add(ChatContentBlock block) => state = [...state, block];

  /// 取走全部附件并清空（发送一次性消费）。
  List<ChatContentBlock> drain() {
    final out = List<ChatContentBlock>.from(state);
    state = const [];
    return out;
  }
}

final pendingAttachmentsProvider =
    StateNotifierProvider<PendingAttachmentsNotifier, List<ChatContentBlock>>(
      (ref) => PendingAttachmentsNotifier(),
    );
