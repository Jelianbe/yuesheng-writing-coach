// ─────────────────────────────────────────────────────────────
// PhaseUpgradeCard — 阶段升级卡片（缺口清单 B 类：消息卡片渲染扩展）
// 真源：yuesheng-android/src/components/chat/message-cards/PhaseUpgradeCard.tsx
// + config/phase-constants.ts
//
// 展示型卡片：庆祝图标 + 「进入新阶段！」+ 完整阶段名 + 解锁描述 + 鼓励文案
// （RN 的「开始新阶段/查看学员画像」按钮依赖 subphase 推进与画像跳转上下文，
// Flutter 渲染层暂不绑定交互，展示为主）
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../services/message_card_service.dart';

/// 阶段升级完整阶段名（对齐 RN PHASE_UPGRADE_LABELS）
const Map<String, String> _phaseUpgradeLabels = {
  'P0_ENGAGE': '启程阶段',
  'P1_WORLD': '世界观阶段',
  'P2_PRACTICE_LOOP': '练习循环阶段',
  'P3_TRAINING': '训练阶段',
  'P4_REVIEW': '复盘阶段',
};

/// 阶段升级解锁功能描述（对齐 RN PHASE_UNLOCK_DESCRIPTIONS）
const Map<String, String> _phaseUnlock = {
  'P1_WORLD': '解锁：世界观构建与场景描写训练',
  'P2_PRACTICE_LOOP': '解锁：系统化写作练习循环',
  'P3_TRAINING': '解锁：针对性强化训练模块',
  'P4_REVIEW': '解锁：写作能力复盘与总结',
};

/// 阶段升级鼓励语（对齐 RN PHASE_ENCOURAGE_TEXTS）
const Map<String, String> _phaseEncourage = {
  'P1_WORLD': '你的写作之旅迈出了第一步！',
  'P2_PRACTICE_LOOP': '持续练习是进步的阶梯！',
  'P3_TRAINING': '专注训练，突破瓶颈！',
  'P4_REVIEW': '复盘总结，巩固成果！',
};

class PhaseUpgradeCard extends StatelessWidget {
  final String from; // TeachingPhase.value
  final String to; // TeachingPhase.value
  final String? reason;

  const PhaseUpgradeCard({
    super.key,
    required this.from,
    required this.to,
    this.reason,
  });

  /// 便利构造：从 Message.content 的 JSON 解析 payload 渲染
  /// 由 MessageList message_type='phase_upgrade' 分支直接调用
  static PhaseUpgradeCard fromMessageContent(String content, {Key? key}) {
    try {
      final payload = PhaseUpgradeCardPayload.fromJson(
        jsonDecode(content) as Map<String, dynamic>,
      );
      return PhaseUpgradeCard(
        key: key,
        from: payload.from,
        to: payload.to,
        reason: payload.reason,
      );
    } catch (_) {
      return const PhaseUpgradeCard(from: 'P0_ENGAGE', to: 'P1_WORLD');
    }
  }

  String get _phaseLabel => _phaseUpgradeLabels[to] ?? '新阶段';

  String get _unlockText => _phaseUnlock[to] ?? '解锁：更多学习功能';

  String get _encourageText => _phaseEncourage[to] ?? '继续加油！';

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.surfaceWhite,
            border: Border.fromBorderSide(BorderSide(color: AppColors.border)),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // 庆祝图标（对齐 RN resultBg.partial 圆底）
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  color: AppColors.primarySoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.celebration_outlined,
                  size: 28,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '进入新阶段！',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              // 阶段名（对齐 RN phaseContainer）
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                child: Text(
                  _phaseLabel,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _unlockText,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _encourageText,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textTertiary,
                  fontStyle: FontStyle.italic,
                ),
              ),
              if (reason != null && reason!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  reason!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.disabledText,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
