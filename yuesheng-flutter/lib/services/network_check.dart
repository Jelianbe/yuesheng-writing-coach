// ─────────────────────────────────────────────────────────────
// 网络预检 — 复刻 llm-client.ts 的 checkNetwork
// 使用 connectivity_plus（对应 RN 的 @react-native-community/netinfo）
// ─────────────────────────────────────────────────────────────

import 'package:connectivity_plus/connectivity_plus.dart';

/// 网络预检：返回设备是否联网
Future<bool> checkNetwork() async {
  final result = await Connectivity().checkConnectivity();
  // none 表示无连接；其他值（wifi/mobile/ethernet/bluetooth/vpn）均视为有连接
  return result.any((c) => c != ConnectivityResult.none);
}
