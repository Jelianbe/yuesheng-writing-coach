// ─────────────────────────────────────────────────────────────
// mock_last_session_storage — 测试共享内存 LastSessionStorage
//
// 批次 50 引入 lastSessionStorageProvider 后，所有触发
// SessionBootstrapNotifier.build() 的测试都必须 override 该 provider：
// testWidgets（fakeAsync）环境下未 mock 的 flutter_secure_storage
// 平台通道调用会永久挂起（.timeout 计时器也不推进），导致
// bootstrap future 永不完成、ChatPage 渲染不出内容。
// ─────────────────────────────────────────────────────────────

import 'package:writingcoach/services/last_session_storage.dart';

/// 内存版 LastSessionStorage（测试隔离平台通道）
class MemoryLastSessionStorage implements LastSessionStorage {
  String? _id;

  @override
  Future<String?> getLastSessionId() async => _id;

  @override
  Future<void> setLastSessionId(String sessionId) async {
    _id = sessionId;
  }
}
