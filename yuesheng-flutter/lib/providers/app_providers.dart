// ─────────────────────────────────────────────────────────────
// app_providers — 全局 Riverpod providers
//
// 生产环境 AppDatabase 单例；测试时 override。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database/database.dart';
import '../data/repositories/character_fact_repository.dart';
import '../data/repositories/error_log_repository.dart';
import '../data/repositories/pilot_metrics_repository.dart';
import '../data/repositories/world_fact_repository.dart';
import '../services/error_handler.dart';
import '../services/setting_library_service.dart';

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

/// 设定资料库第一批：用户裁决服务（character + world 双表）。
/// 确认卡 UI 经此裁决 pending 断言；测试可 override。
final settingLibraryServiceProvider = Provider<SettingLibraryService>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return SettingLibraryService(
    characterRepo: CharacterFactRepository(db),
    worldRepo: WorldFactRepository(db),
  );
});

/// 小白冷启动试点埋点仓库（ADR-C121，v41）。
/// 追加式事件日志；测试可 override 内存库。
final pilotMetricsRepositoryProvider = Provider<PilotMetricsRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return PilotMetricsRepository(db);
});

/// C129（断点 A）：全局教练人格变更 revision 信号。
///
/// 设置页改选/删除当前激活教练（setActiveCoachPersona 成功）后递增。
/// ChatPage 经 StatefulShellRoute.indexedStack 常驻存活，ref.listen 到变化后
/// 对当前会话重新 resolve 态度：**未锁定**会话随之反映新全局教练；**锁定**
/// 会话（teaching_state 已持久 attitudeLevel）由 loadAttitudeState 仍返回其
/// 锁定值——本信号只触发重载，不改加载优先级（R：会话级锁定 > 全局）。
/// 与会话切换重载（bootstrap 变更 → _onBootstrapReady）语义同构。
final coachPersonaRevisionProvider = StateProvider<int>((ref) => 0);
