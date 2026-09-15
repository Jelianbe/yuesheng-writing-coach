// ─────────────────────────────────────────────────────────────
// L2 路由迟滞（粘性路由）— U2 批 · 2026-09-15
//
// 背景（U1 批实测）：L2 组每切换一次，整段 prompt 前缀即失效，切换点
// 全部按 miss 计价。实测「训练组 → 诊断组」一次切换 = 22,135 miss
//（U1 共享前置后降至 20,087）。而这条切换**不是用户动作驱动的**：
// 训练轮结束时 diagnosis_flow_handler 自动 `updateSubphase(null)`
//（diagnosis_flow_handler.dart:1144），下一轮 resolveL2Mode 把 null 与
// diagnosis 同归诊断组（skill_layers.dart:195）⇒ 立刻回切一次。
//
// 本类只做一件事：给「训练组 → 诊断组」这一条边加 N 轮迟滞，消掉练习
// 结束后那次自动回切，再按正常节奏回落。
//
// ★ 设计约束（勿破）：
//   1. **只覆盖 L2Mode**，绝不触碰 TeachingSubphase —— 后者是功能开关
//      （diagnosis_flow_handler.dart:1129：非 feedback 即整段 return，
//      不出评价报告/达标卡）。改它 = 教学事故。
//   2. **显式解锁必须穿透**：用户经 UI 显式改子阶段（handleSkipPractice
//      → ChatService.setSubphase）时须调 [reset]，否则「用户说不练了」
//      会被迟滞多留一轮训练语境。
//   3. 状态按会话隔离；[maxSessions] 兜住无界增长。
//   4. **纯内存、不落库**：丢失只退化为「不抑制」（首轮 raw 本就正确），
//      不会产生错误路由 ⇒ 不需要持久化，也不该进 DB。
//
// 归因：docs/audits/U1批-共享前置落地与缓存偏移实证-2026-09-15.md §5
// ─────────────────────────────────────────────────────────────

import 'package:writingcoach/contracts/teaching_capability.dart';

/// 单个会话的路由状态。
class _RouteState {
  _RouteState(this.lastApplied);

  /// 上一次**实际生效**的 L2 组（非 raw 决议）。
  L2Mode lastApplied;

  /// 已连续抑制的轮数（未抑制时归零）。
  int heldRounds = 0;
}

/// L2 路由迟滞器（有状态）——与纯函数 `resolveL2Mode` 互补。
///
/// 调用方（ChatService）先取纯函数决议 `raw`，再问 [overrideFor]：
/// 返回 `null` ⇒ 不干预，走默认路径（零漂移）；返回非 `null` ⇒ 本轮抑制，
/// 把它作为 `modeOverride` 传入 `buildSystemPrompt`。
class L2RouteHysteresis {
  L2RouteHysteresis({this.holdRounds = 1, this.maxSessions = 64})
    : assert(holdRounds >= 0, 'holdRounds 不可为负'),
      assert(maxSessions >= 1, 'maxSessions 至少为 1');

  /// 抑制窗口：「训练组 → 诊断组」的自动回切最多被推迟几轮。
  ///
  /// 默认 1 —— 收益（消掉那次切换）已全额拿到，教学代价最小
  ///（只多一轮训练语境，下一轮自动回落）。0 = 关闭迟滞。
  final int holdRounds;

  /// 会话状态上限（防无界增长）；超出时清最陈旧的会话。
  final int maxSessions;

  /// Dart `Map` 保插入序 ⇒ 天然 FIFO，无需额外 LRU 结构。
  final Map<String, _RouteState> _routes = {};

  /// 决议本轮是否需**强制覆盖** L2 组（见类注释）。
  ///
  /// 返回 `null` 表示不干预 —— 调用方应**不传** `modeOverride`，
  /// 使默认路径与改造前逐字节等价（两处锚点零漂移的依据）。
  L2Mode? overrideFor(String sessionId, L2Mode raw) {
    final st = _routes[sessionId];
    if (st == null) {
      _remember(sessionId, _RouteState(raw));
      return null; // 首轮无历史 ⇒ 不干预
    }

    // 未想切换（或抑制期内 raw 已回到当前组）：计数归零。
    if (raw == st.lastApplied) {
      st.heldRounds = 0;
      return null;
    }

    // 只对「训练组 → 诊断组」这一条边迟滞 —— 它对应训练轮结束后的
    // 自动回切，是本类存在的唯一理由。其余切换（阶段推进 / 大纲 /
    // 零基础 / 用户显式动作）一律立即生效。
    if (st.lastApplied == L2Mode.training &&
        raw == L2Mode.diagnosis &&
        st.heldRounds < holdRounds) {
      st.heldRounds++;
      return st.lastApplied; // 抑制：维持训练组
    }

    st.lastApplied = raw;
    st.heldRounds = 0;
    return null;
  }

  /// 清空某会话的迟滞状态 —— **显式解锁穿透**。
  ///
  /// 调用时机：用户经 UI 显式改教学子阶段时（`ChatService.setSubphase`，
  /// 如 handleSkipPractice）。不调则「跳过练习」会被迟滞吞掉一轮。
  void reset(String sessionId) {
    _routes.remove(sessionId);
  }

  /// 当前跟踪的会话数（测试 / 诊断用）。
  int get trackedSessions => _routes.length;

  void _remember(String sessionId, _RouteState st) {
    if (_routes.length >= maxSessions) {
      _routes.remove(_routes.keys.first); // 清最陈旧者（插入序 = FIFO）
    }
    _routes[sessionId] = st;
  }
}
