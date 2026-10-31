// ─────────────────────────────────────────────────────────────
// ChunkMessages — 分块链单块消息装配（T-20261025-06 件2 职责级分解）
//
// 从 `progressive_diagnosis.dart` **整段搬迁**而来（逐字，不重写）。与
// `chunk_prompt.dart` 同一职责面（分块注入），因 R-019 文件级 300 行上限而分开：
// prompt 文本构造留在 `chunk_prompt.dart`，messages 形状在此。
// ─────────────────────────────────────────────────────────────

import '../types/teaching_types.dart';
import 'chunk_prompt.dart';
import 'llm_client.dart';

/// 分块链「窗口元信息」消息正文（`T-20261027-01` **H9** 文案 + **H8** 形状）。
///
/// **只声明系统确实知道的两件事**：这条片段取自哪条来源记录、它是第几块。
/// 旧标签「`章节标题：<title>`」把**记录标题**当成**片段内容的章节归属** ——
/// 系统并不知道后者：`Chapters` 只有 `title`（自由文本，可为空）与 `sortOrder`
/// （记录在书中的位置），没有章号；用户把多章抄进一条记录时，那两者都只代表
/// **记录**，不代表块内正文（`tables.dart:41`）。离线采样器同一模板同理：
/// 语料只有作品名，没有章节标题（`tool/build_chunk_sim_tasks.py:96`）。
///
/// ⇒ 改为中性声明 + 「可能含多章」，把「本窗正文是什么」交回片段正文自己。
/// 标题为空时整行省略（`chapters.title` 默认空串，不是异常态）。
///
/// **H8（2026-10-29 · 批八）**：本串**不再与正文拼在同一条 user 消息里**。
/// 它是「关于这条输入的说明」，不是「这条输入的内容」——混在正文前时，
/// 「可能含多章」这句窗口断言直接压在 P003「谁在看」的判定域上（§1.2 机理）。
/// ⇒ 单独成一条 system 消息，正文那条逐字节 == 片段本体。
/// **文案一字未改**：H8 只改形状，改字须另走 R-027。
///
/// 形状先例：短链首轮判据块同为「主 system + 独立 system 消息」（`w17` ⑧），
/// 生产链已有三条 system 相邻（`message_sequence_anchor.json` = `SSSUS`）。
String buildChunkWindowMeta({
  required String recordTitle,
  required int chunkIndex,
  required int chunkCount,
}) {
  final head = recordTitle.isEmpty ? '' : '来源记录：$recordTitle（本片段可能含多章）\n\n';
  return '$head文本片段 ${chunkIndex + 1}/$chunkCount：';
}

/// 单块分析的 messages（尝试 1 与兜底重试共用同一组消息）。
///
/// **H8**：三条 —— 主 system（字节不变）· 窗口元信息（独立成条）· 纯正文。
/// 公开：注入形状需要机器执行点（角色序列 + 逐条内容），只靠「总条数」
/// 守不住「放对了哪条角色」；件2 起被 `progressive_diagnosis.dart` 调用，
/// 故不再标 `@visibleForTesting`（跨文件生产调用会触发 lint）。
List<ChatMessage> buildChunkMessages(
  String title,
  String chunk,
  int chunkIndex,
  int chunkCount, {
  Set<String> disabledSyndromeIds = const {},
  TeachingMode teachingMode = TeachingMode.socratic,
  String? positionBand,
}) {
  final useDefaultPrompt =
      disabledSyndromeIds.isEmpty &&
      teachingMode == TeachingMode.socratic &&
      positionBand == null;
  return [
    // ADR-C69：kChunkSystemPrompt 改由注册表派生（非 const），此处 const 去掉。
    // 诊断编辑器：按用户启用集运行时构造 prompt（空集 + 无位次 = 全启用默认）。
    ChatMessage(
      role: 'system',
      content: useDefaultPrompt
          ? kChunkSystemPrompt
          : buildChunkSystemPrompt(
              disabledSyndromeIds,
              teachingMode,
              positionBand,
            ),
    ),
    ChatMessage(
      role: 'system',
      content: buildChunkWindowMeta(
        recordTitle: title,
        chunkIndex: chunkIndex,
        chunkCount: chunkCount,
      ),
    ),
    // H8：正文那条**只装正文** —— 标签不再前置污染「这段是谁在看」的观察对象。
    ChatMessage(role: 'user', content: chunk),
  ];
}
