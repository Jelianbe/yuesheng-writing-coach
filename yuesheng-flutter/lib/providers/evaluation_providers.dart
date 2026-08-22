// ─────────────────────────────────────────────────────────────
// evaluation_providers — 评估报告状态管理
// 真源：yuesheng-android/src/store/modal-store.ts（evaluationReports 部分）
//
// 状态：
//   - reports：Map<messageId, EvaluationData>（训练反馈后挂到对应消息）
//   - currentRound：评估轮次（每次构建 +1）
//
// 生命周期：
//   buildEvaluationReport(sessionId, messageId) → 计算评估 → reports[messageId]
//   dismissEvaluationReport(messageId) → 关闭报告
//   resetReports() → 清空（会话切换）
//
// 批次4-M3：报告 + 轮次持久化到 app_state KV 表，应用重启后恢复
// ─────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/app_state_repository.dart';
import '../data/repositories/diagnosis_repository.dart';
import '../data/repositories/student_model_repository.dart';
import '../providers/app_providers.dart';
import '../services/evaluation_service.dart';
import '../types/display_types.dart';

/// 评估报告状态
class EvaluationReportsState {
  /// messageId → EvaluationData
  final Map<String, EvaluationData> reports;

  /// 当前评估轮次
  final int currentRound;

  const EvaluationReportsState({
    this.reports = const {},
    this.currentRound = 0,
  });
}

/// 评估报告状态管理
class EvaluationReportsStore extends StateNotifier<EvaluationReportsState> {
  final EvaluationService _service;
  final AppStateRepository _appStateRepo;

  /// 当前会话 id（用于持久化 key 隔离）
  String? _currentSessionId;

  EvaluationReportsStore(this._service, this._appStateRepo)
    : super(const EvaluationReportsState());

  /// 批次4-M3：会话启动时从 DB 恢复 reports + currentRound
  /// 在 ChatPage 会话 bootstrap 后调用
  Future<void> restoreForSession(String sessionId) async {
    _currentSessionId = sessionId;
    try {
      final round = await _appStateRepo.getEvaluationRound(sessionId);
      final reports = await _appStateRepo.listEvaluationReports(sessionId);
      state = EvaluationReportsState(reports: reports, currentRound: round);
    } catch (e) {
      debugPrint('[EvalStore] restoreForSession 失败: $e');
    }
  }

  /// 构建评估报告并挂到对应消息（无诊断历史时静默跳过）
  Future<void> buildEvaluationReport(String sessionId, String messageId) async {
    try {
      final round = state.currentRound;
      final evaluation = await _service.computeRoundEvaluation(
        sessionId,
        round,
      );
      if (evaluation == null) return;

      state = EvaluationReportsState(
        reports: {...state.reports, messageId: evaluation},
        currentRound: state.currentRound + 1,
      );

      // 批次4-M3：落库（报告 + 轮次）
      _currentSessionId = sessionId;
      await _appStateRepo.saveEvaluationReport(
        sessionId,
        messageId,
        evaluation,
      );
      await _appStateRepo.setEvaluationRound(sessionId, state.currentRound);
    } catch (e) {
      debugPrint('[EvalStore] buildEvaluationReport 失败: $e');
    }
  }

  /// 关闭某条消息的评估报告
  Future<void> dismissEvaluationReport(String messageId) async {
    final reports = {...state.reports};
    reports.remove(messageId);
    state = EvaluationReportsState(
      reports: reports,
      currentRound: state.currentRound,
    );
    // 批次4-M3：同步删除 DB 记录
    if (_currentSessionId != null) {
      try {
        await _appStateRepo.deleteEvaluationReport(
          _currentSessionId!,
          messageId,
        );
      } catch (e) {
        debugPrint('[EvalStore] dismissEvaluationReport 删除失败: $e');
      }
    }
  }

  /// 清空全部评估报告（会话切换）
  Future<void> resetReports() async {
    state = const EvaluationReportsState();
    // 批次4-M3：清空当前会话的 DB 记录
    if (_currentSessionId != null) {
      try {
        await _appStateRepo.clearEvaluationReports(_currentSessionId!);
      } catch (e) {
        debugPrint('[EvalStore] resetReports 清空失败: $e');
      }
      _currentSessionId = null;
    }
  }
}

/// 评估服务单例
final evaluationServiceProvider = Provider<EvaluationService>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return EvaluationService(DiagnosisRepository(db), StudentModelRepository(db));
});

/// 全局评估报告 store
final evaluationReportsProvider =
    StateNotifierProvider<EvaluationReportsStore, EvaluationReportsState>((
      ref,
    ) {
      final db = ref.watch(appDatabaseProvider);
      return EvaluationReportsStore(
        ref.watch(evaluationServiceProvider),
        AppStateRepository(db),
      );
    });
