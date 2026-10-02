// ─────────────────────────────────────────────────────────────
// chat_page_host — 聊天页宿主能力接口
//
// 从 chat_page.dart 家族真分解而来（R-019：原 `part` + `extension
// _ChatX on _ChatPageState` 硬挂 State 的动作方法，改为独立控制器 +
// 显式接口注入）。
//
// 原 5 个 extension 隐式寄生在 `_ChatPageState` 上，直接读写 State 私有
// 字段 / setState / ref；提取后各控制器只依赖本接口暴露的最小能力集，
// 不再回指宿主文件（避免循环依赖，无需 part）。
//
// 由 `_ChatPageState implements ChatPageHost` 提供实现。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/diagnosis_repository.dart';
import '../../data/repositories/session_repository.dart';
import '../../services/attitude_advisor.dart';
import '../../types/teaching_types.dart';
import 'chat_input.dart';

/// 聊天页宿主对动作控制器暴露的能力（最小集）。
///
/// 说明：本页跨控制器共享的可变 UI 状态（态度/阶段/输入框/建议/会话列表等）
/// 仍物理保存在 [State] 中，经本接口以「getter 读 + 写方法内部 setState」
/// 暴露，保证重建时机与拆分前完全一致。
abstract class ChatPageHost {
  /// Riverpod 容器（读 provider / 调 notifier）
  WidgetRef get ref;

  /// 构建上下文（弹层 / 导航 / SnackBar）
  BuildContext get context;

  /// 是否仍挂载（异步间隙保护）
  bool get mounted;

  // ── 共享状态读取 ──

  /// 输入框当前文本
  String get inputText;

  /// 当前态度档位
  AttitudeLevel get attitude;

  /// C129（断点 B）：本会话是否已锁定自身态度（persistAttitude 写过
  /// teaching_state.attitudeLevel）。true = 设置页改全局教练不影响本会话，
  /// UI 在态度区显示「本会话已锁定」徽标。
  bool get isAttitudeLocked;

  /// 当前激活的教练人格名（用户自定义人格 → 显示名；系统预设 / 无 → null）。
  /// 供聊天菜单体现「当前教练」，消除「自定义了却显示豆包」的错觉。
  String? get activePersonaName;

  /// 当前教学方式（疑问式/直接说，正交于态度档位）
  TeachingMode get teachingMode;

  /// 当前教学阶段
  TeachingPhase get phase;

  /// 当前会话主引用书名（null = 未关联书籍）
  String? get primaryRefTitle;

  /// 当前展示的态度建议（null = 不展示）
  AttitudeSuggestion? get attitudeSuggestion;

  /// 上次建议时间（冷却期判定）
  int? get lastSuggestionTime;

  /// 当前会话活跃问题列表
  List<ActiveProblemView> get activeProblems;

  /// 会话列表（SessionDrawer 数据源）
  List<SessionWithPhase> get sessions;

  /// 输入框 GlobalKey（mention 插入 / 聚焦）
  GlobalKey<ChatInputState> get chatInputKey;

  // ── 共享状态写入（内部 setState） ──

  /// 更新输入框文本
  void setInputText(String value);

  /// 更新当前态度档位
  void setAttitude(AttitudeLevel value);

  /// 一次性更新态度 + 阶段 + 激活人格名（loadAttitudeState 返回后）。
  /// [isAttitudeLocked] = 该会话是否锁定自身态度（C129）。
  void applyAttitudeState(
    AttitudeLevel attitude,
    TeachingPhase phase, {
    String? activePersonaName,
    bool isAttitudeLocked = false,
  });

  /// C129：更新会话级态度锁定标志（persistAttitude 成功 = 锁定；失败回滚还原）。
  void setAttitudeLocked(bool value);

  /// 更新主引用书名
  void setPrimaryRefTitle(String? value);

  /// 更新态度建议（可同时刷新冷却期时间戳）
  void setAttitudeSuggestion(
    AttitudeSuggestion? suggestion, {
    int? lastSuggestionTime,
  });

  /// 更新活跃问题列表
  void setActiveProblems(List<ActiveProblemView> value);

  /// 更新会话列表
  void setSessions(List<SessionWithPhase> value);

  /// 切换/新建会话时清空输入框与态度建议横幅
  void clearComposerState();

  /// A4：取消当前进行中的流式生成（切/建/删会话入口先调用，避免旧会话流
  /// 的 chunk/完成/错误回调污染刚切到的新会话 UI）。无在途流时为空操作。
  void cancelActiveGeneration();

  /// 延迟检查态度建议（发送完成后调用，对齐 RN）
  void scheduleAttitudeCheck();
}
