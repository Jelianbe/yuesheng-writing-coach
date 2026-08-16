// ─────────────────────────────────────────────────────────────
// 批次54：会话级 teaching state 缓存
//
// 动机：DiagnosisCard._loadTeachingStates 在每个 State 创建（含 ListView
// 滚动回收重建）都执行 getAllDiagnoses(sessionId) + computeSyndromeProfile，
// 长会话多卡片时滚动抖动/重复查库。
//
// 方案：按 sessionId 缓存一次聚合结果（症候 → TeachingState），
// 新诊断落库（diagnosis_results INSERT，唯一写入入口 DiagnosisRepository
// .commitDiagnosis）后由 repository 显式失效，保证画像新鲜。
// ─────────────────────────────────────────────────────────────

import '../types/teaching_types.dart';

/// sessionId → (syndromeId → TeachingState)
final Map<String, Map<String, TeachingState>> _teachingStateCache = {};

/// 读取缓存（未命中返回 null）
Map<String, TeachingState>? readCachedTeachingStates(String sessionId) =>
    _teachingStateCache[sessionId];

/// 写入缓存
void writeCachedTeachingStates(
  String sessionId,
  Map<String, TeachingState> states,
) {
  _teachingStateCache[sessionId] = states;
}

/// 失效（新诊断落库后调用，保证画像数据新鲜）
void invalidateTeachingStates(String sessionId) {
  _teachingStateCache.remove(sessionId);
}
