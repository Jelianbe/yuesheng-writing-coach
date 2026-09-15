// ─────────────────────────────────────────────────────────────
// reasoning_tier_provider — 推理档位的 UI 共享真源（跨页面同步）
//
// 为什么需要它：档位有**两个改动入口**（设置页「模型行为」/ 聊天页
// 「更多」菜单的「思考档位」）与**一个显示入口**（输入框上方思考开关）。
// 若各页各自读一次 app_state，则 A 页改档后 B 页仍显示旧值（同一 true
// 状态两份副本）。本 provider 是 UI 侧唯一可读源，写操作一律经
// [ReasoningTierNotifier] 落 app_state。
//
// 请求路径不受影响：`llm_config_resolver` 仍直读 DB（每次请求现取），
// 保证「UI 状态」与「实际下发」同键同值，且不引入 provider 生命周期耦合。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/reasoning_tier.dart';
import '../data/repositories/app_state_repository.dart';
import 'app_providers.dart';

/// 推理档位状态（值 = 档位 key，见 [reasoningTierPresets]）。
class ReasoningTierNotifier extends Notifier<String> {
  /// 水合只做一次（设置页 / 聊天页都可能在首帧调用）。
  bool _hydrated = false;

  /// 开关「关」之前的最后开启态档位（内存镜像；落库见 [kReasoningTierLastOnKey]）。
  String _lastOn = reasoningTierStandard;

  @override
  String build() => reasoningTierStandard;

  /// 从 app_state 水合档位与「上次开启态档位」（幂等）。
  Future<void> hydrate() async {
    if (_hydrated) return;
    _hydrated = true;
    try {
      final repo = AppStateRepository(ref.read(appDatabaseProvider));
      final stored = await repo.getReasoningTier();
      final lastOn = await repo.getValue(kReasoningTierLastOnKey);
      final tier = reasoningTierOf(stored).key;
      state = tier;
      // 当前档位即最强依据；仅当处于 off 时才回退查「上次开启态」
      _lastOn = tier == reasoningTierOff ? restoredOnTier(lastOn) : tier;
    } catch (_) {
      // 读失败保持标准档：不干预请求体，行为最保守
    }
  }

  /// 显式选档：乐观更新 → 落库 → 失败回滚并返回 false。
  Future<bool> setTier(String tierKey) async {
    final key = reasoningTierOf(tierKey).key;
    final prevTier = state;
    final prevLastOn = _lastOn;
    state = key;
    if (key != reasoningTierOff) _lastOn = key;
    try {
      final repo = AppStateRepository(ref.read(appDatabaseProvider));
      await repo.setReasoningTier(key);
      if (key != reasoningTierOff) {
        await repo.setValue(kReasoningTierLastOnKey, key);
      }
      return true;
    } catch (_) {
      state = prevTier;
      _lastOn = prevLastOn;
      return false;
    }
  }

  /// 输入框上方开关：开 → 恢复上次开启态档位；关 → 关闭思考档。
  Future<bool> setThinkingEnabled(bool on) =>
      setTier(on ? _lastOn : reasoningTierOff);
}

/// 当前推理档位（默认 [reasoningTierStandard]；首帧后由 [ReasoningTierNotifier.hydrate] 校正）。
final reasoningTierProvider = NotifierProvider<ReasoningTierNotifier, String>(
  ReasoningTierNotifier.new,
);
