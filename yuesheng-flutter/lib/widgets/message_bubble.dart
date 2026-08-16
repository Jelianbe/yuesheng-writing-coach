// ─────────────────────────────────────────────────────────────
// MessageBubble — 单条消息气泡（T9 视觉对齐版本）
// 对齐 yuesheng-android/src/components/chat/MessageBubble.tsx
//
// 视觉规范（月色竹青主题）：
//   - user 气泡：右对齐 + 竹青底 (#2D5A52) + 白字 + 右下尖角(4px)
//   - assistant 气泡：左对齐 + 灰白底 (#F2F4F2) + 深灰字 + 左下尖角(4px)
//   - assistant 头像：圆形品牌色 (#2D5A52) + "月"字
//   - assistant 时间戳：气泡外部下方独立一行
//   - user 时间戳：气泡内部底部
//   - streaming 气泡：半透明 (opacity 0.6)
//   - 最大宽度：80% 屏幕宽
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/app_theme.dart';
import '../data/database/database.dart';

class MessageBubble extends StatelessWidget {
  final Message message;
  final bool isStreaming;
  final bool isFailed;
  final void Function(String messageId)? onRetry;
  final void Function(Message message)? onLongPress;

  /// 「保存到文件」：assistant 气泡操作区按钮（对齐 RN MessageBubble.tsx onSaveToFile）
  final void Function(Message message)? onSaveToFile;

  /// 批次71：点击引用徽章跳转（manuscript→作品详情 / chapter→章节写作 / file→所属作品详情）
  final void Function(String refType, String refId, String? manuscriptId)?
      onMentionTap;

  const MessageBubble({
    super.key,
    required this.message,
    this.isStreaming = false,
    this.isFailed = false,
    this.onRetry,
    this.onLongPress,
    this.onSaveToFile,
    this.onMentionTap,
  });

  bool get _isUser => message.role == 'user';

  @override
  Widget build(BuildContext context) {
    // E4：读屏语义 — 标注消息角色（用户/AI），避免读屏用户无法区分
    final roleLabel = _isUser ? '我' : '教练';
    return Semantics(
      label: '$roleLabel：${message.content}',
      child: _isUser
          ? _buildUserBubble(context)
          : _buildAssistantBubble(context),
    );
  }

  /// 用户消息气泡：右对齐 + 竹青底 + 右下尖角 + 失败状态
  Widget _buildUserBubble(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Opacity(
        opacity: isStreaming ? 0.6 : 1.0,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            GestureDetector(
              onLongPress: onLongPress != null
                  ? () {
                      // E3：长按触发触觉反馈，让"长按可删"交互可感知
                      HapticFeedback.mediumImpact();
                      onLongPress!(message);
                    }
                  : null,
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.80,
                ),
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: isFailed ? AppColors.dangerBg : AppColors.primary,
                  border: isFailed
                      ? Border.all(color: AppColors.dangerBorder)
                      : null,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                    bottomLeft: Radius.circular(12),
                    bottomRight: Radius.circular(4),
                  ),
                ),
                child: Text(
                  message.content,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.4,
                    color: isFailed ? AppColors.danger : AppColors.onPrimary,
                  ),
                ),
              ),
            ),
            // 批次71：@ 引用徽章（气泡底部，点击跳转）
            _ReferencesBadges(
              references: _parseReferences(message),
              onMentionTap: onMentionTap,
            ),
            // 失败时显示重试按钮
            if (isFailed && onRetry != null) ...[
              GestureDetector(
                onTap: () => onRetry!(message.id),
                child: const Padding(
                  padding: EdgeInsets.only(top: 2, bottom: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.warning, size: 14, color: AppColors.danger),
                      SizedBox(width: 4),
                      Text(
                        '发送失败，点击重试',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.danger,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            // 非 streaming 且非 failed 时显示时间戳
            if (!isStreaming && !isFailed) ...[
              const SizedBox(height: 4),
              Text(
                _formatTime(message.timestamp),
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.onPrimary.withValues(alpha: 0.6),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// AI 消息气泡：左对齐 + 头像 + 灰白底 + 左下尖角 + 外部时间戳
  Widget _buildAssistantBubble(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头像
          Container(
            width: 32,
            height: 32,
            margin: const EdgeInsets.only(right: 8, top: 4),
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Text(
              '月',
              style: TextStyle(
                color: AppColors.onPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          // 气泡 + 时间戳
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onLongPress: onLongPress != null
                      ? () {
                          // E3：长按触发触觉反馈，让"长按可删"交互可感知
                          HapticFeedback.mediumImpact();
                          onLongPress!(message);
                        }
                      : null,
                  child: Opacity(
                    opacity: isStreaming ? 0.6 : 1.0,
                    child: Container(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.80,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        border: Border.all(color: AppColors.borderSoft),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(12),
                          topRight: Radius.circular(12),
                          bottomLeft: Radius.circular(4),
                          bottomRight: Radius.circular(12),
                        ),
                      ),
                      child: Text(
                        message.content,
                        style: const TextStyle(
                          fontSize: 15,
                          height: 1.4,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
                if (!isStreaming) ...[
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatTime(message.timestamp),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      // 操作区：保存到文件（对齐 RN messageMetaRow.actionBtnGroup）
                      if (onSaveToFile != null) ...[
                        const SizedBox(width: 12),
                        InkWell(
                          onTap: () => onSaveToFile!(message),
                          borderRadius: BorderRadius.circular(AppRadius.xs),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.save_alt,
                                size: 12,
                                color: AppColors.primary,
                              ),
                              SizedBox(width: 2),
                              Text(
                                '保存到文件',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 格式化时间戳为 HH:mm
  ///
  /// Message.timestamp 存储为秒级 unixepoch（见 tables.dart Messages 表），
  /// DateTime.fromMillisecondsSinceEpoch 需要毫秒，所以 * 1000。
  String _formatTime(int timestamp) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  /// 批次71：解析消息携带的 @ 引用快照（JSON 数组，解析失败降级为空）
  List<Map<String, dynamic>> _parseReferences(Message message) {
    final raw = message.referencesJson;
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded.whereType<Map<String, dynamic>>().toList();
    } catch (_) {
      return const [];
    }
  }
}

/// 批次71：@ 引用徽章组（作品/章节/素材 小胶囊，点击跳转对应页面）
class _ReferencesBadges extends StatelessWidget {
  final List<Map<String, dynamic>> references;
  final void Function(String refType, String refId, String? manuscriptId)?
      onMentionTap;

  const _ReferencesBadges({required this.references, this.onMentionTap});

  @override
  Widget build(BuildContext context) {
    if (references.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        alignment: WrapAlignment.end,
        children: [
          for (final ref in references) _ReferenceBadge(ref: ref, onMentionTap: onMentionTap),
        ],
      ),
    );
  }
}

/// 单个引用徽章：竹青淡底 + 深青文字 + 类型图标
class _ReferenceBadge extends StatelessWidget {
  final Map<String, dynamic> ref;
  final void Function(String refType, String refId, String? manuscriptId)?
      onMentionTap;

  const _ReferenceBadge({required this.ref, this.onMentionTap});

  @override
  Widget build(BuildContext context) {
    final refType = (ref['refType'] as String?) ?? '';
    final title = (ref['title'] as String?) ?? '';
    final refId = (ref['refId'] as String?) ?? '';
    final manuscriptId = ref['manuscriptId'] as String?;

    final IconData icon;
    if (refType == 'chapter') {
      icon = Icons.description_outlined;
    } else if (refType == 'file') {
      icon = Icons.attach_file;
    } else {
      icon = Icons.menu_book_outlined;
    }

    final canTap = onMentionTap != null && refId.isNotEmpty;
    return GestureDetector(
      onTap: canTap ? () => onMentionTap!(refType, refId, manuscriptId) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.primarySoft,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: AppColors.primaryDeep),
            const SizedBox(width: 3),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.primaryDeep,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
