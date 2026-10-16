// ─────────────────────────────────────────────────────────────
// diagnosis_temperature_provider — 诊断温度档位的 UI 共享真源
//
// 与 reasoning_tier_provider 同构：设置页是唯一改动入口；请求路径不受
// 本 provider 影响——诊断 runner 每次直读 app_state（getDiagnosisTemperature
// → mergeTemperatureFor），保证「UI 状态」与「实际下发」同键同值。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/diagnosis_temperature.dart';
import '../data/repositories/app_state_repository.dart';
import 'app_providers.dart';

/// 诊断温度档位状态（值 = 档位 key，见 [diagnosisTemperaturePresets]）。
class DiagnosisTemperatureNotifier extends Notifier<String> {
  /// 水合只做一次（设置页首帧调用）。
  bool _hydrated = false;

  @override
  String build() => diagnosisTempFlexible;

  /// 从 app_state 水合档位（幂等）。
  Future<void> hydrate() async {
    if (_hydrated) return;
    _hydrated = true;
    try {
      final repo = AppStateRepository(ref.read(appDatabaseProvider));
      final stored = await repo.getDiagnosisTemperature();
      state = diagnosisTemperatureOf(stored).key;
    } catch (_) {
      // 读失败保持灵活档：= 现网行为，最保守
    }
  }

  /// 显式选档：乐观更新 → 落库 → 失败回滚并返回 false。
  Future<bool> setTier(String tierKey) async {
    final key = diagnosisTemperatureOf(tierKey).key;
    final prev = state;
    state = key;
    try {
      final repo = AppStateRepository(ref.read(appDatabaseProvider));
      await repo.setDiagnosisTemperature(key);
      return true;
    } catch (_) {
      state = prev;
      return false;
    }
  }
}

/// 当前诊断温度档位（默认灵活档；首帧后由 hydrate 校正）。
final diagnosisTemperatureProvider =
    NotifierProvider<DiagnosisTemperatureNotifier, String>(
      DiagnosisTemperatureNotifier.new,
    );
