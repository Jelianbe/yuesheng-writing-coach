// ─────────────────────────────────────────────────────────────
// WritingCoachPanelHost — 写作教练控制器访问宿主 State 能力的注入接口
//
// R-019 真分解：把宿主能力接口独立成文件，避免「控制器 ↔ 链路执行器」之间
// 因互相 import 而形成循环依赖（门禁 3 全量卡口）。各控制器只依赖本接口。
// ─────────────────────────────────────────────────────────────

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../types/teaching_types.dart';

/// 教学控制器访问宿主（State）能力的注入接口。
///
/// 宿主只需实现本接口即可把能力交给控制器，控制器不直接触碰 State 私有成员。
abstract class WritingCoachPanelHost {
  /// Riverpod WidgetRef（由 ConsumerState 提供）
  WidgetRef get ref;

  /// 宿主 BuildContext（SnackBar / 弹窗定位）
  BuildContext get context;

  /// 当前章节 id
  String get chapterId;

  /// 当前作品 id
  String get manuscriptId;

  /// 章节标题（缺省诊断标题回退值）
  String get chapterTitle;

  /// 输入栏控制器
  TextEditingController get inputController;

  /// 当前会话 id（可能为 null）
  String? get sessionId;

  /// 写入会话 id
  set sessionId(String? value);

  /// 是否已挂载
  bool get isMounted;

  /// 读取态度档位
  AttitudeLevel get attitude;

  /// 写入流式阶段标签（null = 复位）
  set streamStageLabel(String? value);

  /// 写入诊断中标志
  set isDiagnosing(bool value);

  /// 会话创建/绑定后恢复态度档位
  Future<void> loadAttitude(String sessionId);

  /// 当前流式取消令牌（可能为 null）
  CancelToken? get cancelToken;

  /// 写入当前流式取消令牌（null = 清空）
  set cancelToken(CancelToken? value);

  /// 等待初始化 Future 完成（删除消息前确保会话绑定）
  Future<void> awaitInit();

  /// 聚焦输入栏（三卡回调）
  void focusInput();
}
