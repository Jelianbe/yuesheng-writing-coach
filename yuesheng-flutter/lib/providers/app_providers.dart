// ─────────────────────────────────────────────────────────────
// app_providers — 全局 Riverpod providers
//
// 生产环境 AppDatabase 单例；测试时 override。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database/database.dart';
import '../data/repositories/error_log_repository.dart';
import '../services/error_handler.dart';

/// 全局 AppDatabase provider（单例）
/// 生产环境自动创建；测试时可 override 传入内存 DB
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  // 批次2（2.1）：DB ready 后挂载 error_logs 仓库，flush 启动期错误队列
  ErrorHandler.instance.attachRepository(ErrorLogRepository(db));
  ref.onDispose(db.close);
  return db;
});

/// 批次64（B62g）：编辑器活动时间戳（秒）——写作页每次输入时更新。
/// 心流判定叠加"最近 120s 内有编辑输入"时，Teacher 建议延迟触发。
final editorActivityProvider = StateProvider<int?>((ref) => null);
