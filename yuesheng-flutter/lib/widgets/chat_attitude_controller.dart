// ─────────────────────────────────────────────────────────────
// chat_attitude_controller — 聊天页态度档位/建议动作控制器
//
// 从 chat_attitude.dart（原 part/extension）真分解而来：
//   handleAttitudeChange / checkAttitudeSuggestion
//   / handleAcceptAttitudeSuggestion / handleDismissAttitudeSuggestion
//   / scheduleAttitudeCheck / loadAttitude
//
// 依赖经 [ChatPageHost] 显式注入；P2 阶段活跃问题加载委托
// [ChatDiagnosisController]。
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database/database.dart';
import '../data/repositories/session_repository.dart';
import '../providers/app_providers.dart';
import '../providers/session_providers.dart';
import '../services/attitude_advisor.dart';
import '../types/teaching_types.dart';
import 'chat_diagnosis_controller.dart';
import 'chat_page_host.dart';

/// 聊天页态度档位与建议动作
class ChatAttitudeController {
  final ChatPageHost host;
  final ChatDiagnosisController diagnosis;

  ChatAttitudeController(this.host, this.diagnosis);

  /// 切换态度：乐观更新 → persistAttitude 双写 → 失败回滚（对齐 RN setAttitude）
  Future<void> handleAttitudeChange(AttitudeLevel attitude) async {
    if (attitude == host.attitude) return;
    final bootstrap = host.ref.read(sessionBootstrapProvider).valueOrNull;
    if (bootstrap == null) return;

    final prev = host.attitude;
    host.setAttitude(attitude);
    try {
      await host.ref
          .read(chatServiceProvider)
          .persistAttitude(bootstrap.sessionId, attitude);
    } catch (e) {
      host.setAttitude(prev);
      if (host.context.mounted) {
        ScaffoldMessenger.of(
          host.context,
        ).showSnackBar(const SnackBar(content: Text('态度切换失败，请稍后再试')));
      }
    }
  }

  /// 批次 12 态度建议：检查是否需要建议切换档位（对齐 RN checkAttitudeSuggestion）。
  ///
  /// 从消息中提取最新 diagnosis_result 的症候严重度列表作为诊断输入，
  /// 命中阈值且未在冷却期内则展示建议并记录建议时间。
  Future<void> checkAttitudeSuggestion() async {
    if (host.attitudeSuggestion != null) return; // 已有建议则跳过（对齐 RN）
    final bootstrap = host.ref.read(sessionBootstrapProvider).valueOrNull;
    if (bootstrap == null) return;

    final sessionRepo = SessionRepository(host.ref.read(appDatabaseProvider));
    final messages = await sessionRepo.listMessages(bootstrap.sessionId);
    final syndromes = _extractSeverities(messages);

    // B4：接入连续负反馈 / 安全词降档信号（否则降档逻辑为死代码）
    final consecutiveNegative = computeAttitudeDowngradeSignal(
      messages.map((m) => (role: m.role, content: m.content)).toList(),
    );

    final suggestion = suggestAttitudeAdjustment(
      currentAttitude: host.attitude,
      currentPhase: host.phase,
      syndromes: syndromes,
      messageCount: messages.length,
      consecutiveNegativeFeedback: consecutiveNegative,
      lastSuggestionTime: host.lastSuggestionTime,
    );
    if (suggestion != null && host.mounted) {
      host.setAttitudeSuggestion(
        suggestion,
        lastSuggestionTime: DateTime.now().millisecondsSinceEpoch,
      );
    }
  }

  /// 最新诊断消息 → 症候严重度列表（无诊断 = 空列表）。
  List<Severity> _extractSeverities(List<Message> messages) {
    final lastDiagnosis = messages
        .where((m) => m.messageType == 'diagnosis_result')
        .lastOrNull;
    final syndromes = <Severity>[];
    if (lastDiagnosis == null) return syndromes;
    try {
      final payload = jsonDecode(lastDiagnosis.content) as Map<String, dynamic>;
      final rawList = (payload['syndromes'] as List?) ?? const [];
      for (final raw in rawList) {
        final sev = Severity.fromString((raw as Map)['severity'] as String?);
        if (sev != null) syndromes.add(sev);
      }
    } catch (_) {
      // 解析失败按无诊断处理，静默
    }
    return syndromes;
  }

  /// 批次 12 态度建议：接受 → 切换到目标档位 + 关闭横幅。
  Future<void> handleAcceptAttitudeSuggestion() async {
    final suggestion = host.attitudeSuggestion;
    if (suggestion == null) return;
    host.setAttitudeSuggestion(null);
    await handleAttitudeChange(suggestion.targetLevel);
  }

  /// 批次 12 态度建议：暂不 → 关闭横幅（对齐 RN dismissAttitudeSuggestion）
  void handleDismissAttitudeSuggestion() {
    if (!host.mounted) return;
    host.setAttitudeSuggestion(null);
  }

  /// 批次 12 态度建议：延迟检查（对齐 RN setTimeout(CHAT_DELAYS.ATTITUDE_CHECK_MS)）
  void scheduleAttitudeCheck() {
    Future.delayed(const Duration(milliseconds: 500), checkAttitudeSuggestion);
  }

  /// 加载已持久化的态度 + 阶段（bootstrap 完成后调用）。
  Future<void> loadAttitude(String sessionId) async {
    try {
      final state = await host.ref
          .read(chatServiceProvider)
          .loadAttitudeState(sessionId);
      if (!host.mounted) return;
      host.applyAttitudeState(state.attitude, state.phase);
      // 批次 18：P2 阶段进入时加载活跃问题（对齐 RN useEffect currentPhase 依赖）
      if (state.phase == TeachingPhase.p2PracticeLoop) {
        diagnosis.loadActiveProblems(sessionId);
      }
    } catch (_) {
      // 加载失败保持默认档位，静默（release 不暴露技术细节）
    }
  }
}
