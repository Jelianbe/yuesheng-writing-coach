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
import '../services/pilot_metrics_summary.dart';
import '../services/p0_verify/anchor_probe.dart' show kAnchorPayloadVersion;
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

/// 「引文锚定」卡聚合读数（T-20261018-06 · D 议题 · 设计批 2026-10-22 已批）。
///
/// 只读 anchor_probe 事件（停写两类与 app_opened 不读——DECISIONS §4-232
/// 裁定④「停写类不呈」+ 文案待裁 A「删」启动次数行）；payload 明细经纯函数
/// 现算 AER（`buildPilotMetricsSummary`，services/pilot_metrics_summary.dart）。
///
/// R-028 容错（设计批 §五）：DB 读失败 ⇒ ErrorHandler 留痕后返回 null
/// ⇒ 卡不渲染、growth 页不崩；loading/error 态消费方一律不出卡。
/// R-029（口径③）：数据零外发——本 provider 不接入任何 prompt 构造路径
/// （守卫 P3 机器判据，scripts/check_pilot_surface.py）。
final pilotMetricsSummaryProvider = FutureProvider<PilotMetricsSummary?>((
  ref,
) async {
  final repo = ref.watch(pilotMetricsRepositoryProvider);
  try {
    final events = await repo.listByType(PilotEventTypes.anchorProbe);
    return buildPilotMetricsSummary(
      events.map((e) => e.payload).toList(),
      version: kAnchorPayloadVersion,
    );
  } catch (e, st) {
    ErrorHandler.instance.captureError(
      level: 'warn',
      category: 'database',
      message: 'anchor_probe 读取失败，「引文锚定」卡不渲染',
      context: {'error': '$e'},
      stack: '$st',
    );
    return null;
  }
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
