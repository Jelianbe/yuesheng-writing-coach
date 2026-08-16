// ─────────────────────────────────────────────────────────────
// ReferenceChangeCard — 引用变更卡片（缺口清单 B 类：消息卡片渲染扩展）
// 真源：message-card-service.ts ReferenceChangeCardPayload + RN 引用变更提示语义
//
// 展示型卡片（无交互）：图标 + 标题（按 action）+ 引用标题
//   - set_primary → 主引用已切换
//   - add        → 已添加引用
//   - remove     → 已移除引用
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../services/message_card_service.dart';

class ReferenceChangeCard extends StatelessWidget {
  final String action; // 'set_primary' | 'add' | 'remove'
  final String refType; // 'manuscript' | 'chapter'
  final String refTitle;

  const ReferenceChangeCard({
    super.key,
    required this.action,
    required this.refType,
    required this.refTitle,
  });

  /// 便利构造：从 Message.content 的 JSON 解析 payload 渲染
  /// 由 MessageList message_type='reference_change' 分支直接调用
  static ReferenceChangeCard fromMessageContent(String content, {Key? key}) {
    try {
      final payload = ReferenceChangeCardPayload.fromJson(
        jsonDecode(content) as Map<String, dynamic>,
      );
      return ReferenceChangeCard(
        key: key,
        action: payload.action,
        refType: payload.refType,
        refTitle: payload.refTitle,
      );
    } catch (_) {
      return const ReferenceChangeCard(
        action: 'add',
        refType: 'manuscript',
        refTitle: '',
      );
    }
  }

  String get _typeLabel => refType == 'chapter' ? '章节' : '作品';

  (IconData, String, String) get _content => switch (action) {
    'set_primary' => (
      Icons.star_outline,
      '主引用已切换',
      refTitle.isEmpty ? '已切换到新的主引用' : '已切换到「$refTitle」',
    ),
    'remove' => (
      Icons.link_off,
      '已移除引用',
      refTitle.isEmpty ? '已从对话中移除引用' : '已移除「$refTitle」',
    ),
    _ => (
      Icons.add_link,
      '已添加引用',
      refTitle.isEmpty ? '已将内容添加到对话' : '已添加「$refTitle」',
    ),
  };

  @override
  Widget build(BuildContext context) {
    final (icon, title, subtitle) = _content;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border.fromBorderSide(
              BorderSide(color: AppColors.borderSoft),
            ),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 左竹青色条
                Container(width: 4, color: AppColors.primary),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: const BoxDecoration(
                            color: AppColors.primarySoft,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(icon, size: 18, color: AppColors.primary),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    title,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.borderSoft,
                                      borderRadius: BorderRadius.circular(AppRadius.xs),
                                    ),
                                    child: Text(
                                      _typeLabel,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textTertiary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
