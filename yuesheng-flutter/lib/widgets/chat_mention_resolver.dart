// ─────────────────────────────────────────────────────────────
// chat_mention_resolver — 聊天页 @ 引用解析器
//
// 从 chat_teaching.dart 的 `_handleSend` 引用解析分支真分解而来（R-019：
// 原超限方法拆出独立关注点）：解析 @ 提及 → 落库为会话附加引用
// （无主引用时首条自动设主）→ 生成引用快照 JSON → 用户反馈。
//
// 依赖经 [ChatPageHost] 显式注入。
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:flutter/material.dart';

import '../contracts/mention_capability.dart';
import '../contracts/reference_capability.dart';
import '../providers/capability_providers.dart';
import 'chat_page_host.dart';

/// @ 引用解析结果（发送前收集，供反馈与落库使用）。
typedef MentionOutcome = ({
  String text,
  String? referencesJson,
  List<String> titles,
  String? autoPrimaryTitle,
});

/// 聊天页 @ 引用解析
class ChatMentionResolver {
  final ChatPageHost host;

  ChatMentionResolver(this.host);

  /// 解析 @ 引用（对齐 RN handleSend）：引用对象添加为会话附加引用，
  /// 发送清理后的文本；无主引用时首条 @ 引用自动设为主引用（file 除外）。
  /// 解析失败时原样返回输入文本（不阻断发送）。
  Future<MentionOutcome> resolve(String text, String sessionId) async {
    try {
      final result = await host.ref
          .read(mentionParserProvider)
          .parseMentions(text);
      final refRepo = host.ref.read(referenceCapabilityProvider);
      final existing = await refRepo.listReferences(sessionId);
      final hasPrimary = existing.any((r) => r.isPrimary == 1);
      final added = await _appendMentions(
        result.mentions,
        refRepo,
        sessionId,
        hasPrimary,
      );
      // 批次71：@ 引用快照（JSON 数组字符串），随消息落库供气泡徽章展示 + 跳转
      final referencesJson = result.mentions.isEmpty
          ? null
          : _encodeReferences(result.mentions);
      return (
        text: result.cleanedText.isNotEmpty ? result.cleanedText : text,
        referencesJson: referencesJson,
        titles: added.titles,
        autoPrimaryTitle: added.autoPrimaryTitle,
      );
    } catch (_) {
      return (
        text: text,
        referencesJson: null,
        titles: const <String>[],
        autoPrimaryTitle: null,
      );
    }
  }

  /// 逐条落库 @ 引用；无主引用时首条（非 file）自动设主（幂等）。
  Future<({List<String> titles, String? autoPrimaryTitle})> _appendMentions(
    List<ParsedMention> mentions,
    ReferenceCapability refRepo,
    String sessionId,
    bool hasPrimary,
  ) async {
    final titles = <String>[];
    String? autoPrimaryTitle;
    var autoPrimaryAssigned = false;
    for (final mention in mentions) {
      // 批次7（D2）：file 允许作次引用（v21 CHECK 已扩），但不可设主
      if (mention.refType == 'file') {
        await refRepo.addReference(sessionId, mention.refType, mention.refId);
        titles.add(mention.title);
        continue;
      }
      final autoPrimary = !hasPrimary && !autoPrimaryAssigned;
      if (autoPrimary) {
        autoPrimaryTitle = mention.title;
        autoPrimaryAssigned = true;
      }
      await refRepo.addReference(
        sessionId,
        mention.refType,
        mention.refId,
        isPrimary: autoPrimary,
      );
      titles.add(mention.title);
    }
    return (titles: titles, autoPrimaryTitle: autoPrimaryTitle);
  }

  /// @ 引用快照序列化（气泡徽章展示 + 点击跳转用）。
  String _encodeReferences(List<ParsedMention> mentions) => jsonEncode([
    for (final m in mentions)
      {
        'refType': m.refType,
        'refId': m.refId,
        'manuscriptId': m.manuscriptId,
        'title': m.title,
      },
  ]);

  /// @ 引用反馈：让用户感知引用已生效；自动设主时显式提示归属。
  void showFeedback(MentionOutcome outcome) {
    if (outcome.titles.isEmpty || !host.context.mounted) return;
    final autoPrimary = outcome.autoPrimaryTitle;
    final feedback = autoPrimary != null
        ? '已引用：${outcome.titles.join('、')}（$autoPrimary 已自动设为主引用）'
        : '已引用：${outcome.titles.join('、')}';
    ScaffoldMessenger.of(
      host.context,
    ).showSnackBar(SnackBar(content: Text(feedback)));
  }
}
