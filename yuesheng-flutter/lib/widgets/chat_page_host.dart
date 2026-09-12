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

import '../data/repositories/diagnosis_repository.dart';
import '../data/repositories/session_repository.dart';
import '../services/attitude_advisor.dart';
import '../types/teaching_types.dart';
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

  /// 一次性更新态度 + 阶段（loadAttitudeState 返回后）
  void applyAttitudeState(AttitudeLevel attitude, TeachingPhase phase);

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

  /// 延迟检查态度建议（发送完成后调用，对齐 RN）
  void scheduleAttitudeCheck();
}
