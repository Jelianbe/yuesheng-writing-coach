// ─────────────────────────────────────────────────────────────
// last_session_storage — 上次会话 ID 持久化
// 复刻 yuesheng-android/src/store/chat-store.ts 的 LAST_SESSION_KEY
//   - key：'yuesheng_last_session_id'（对齐 RN chat-store.ts L22）
//   - getLastSessionId()：对齐 RN L284-286（SecureStore.getItemAsync）
//   - setLastSessionId(id)：对齐 RN initSession L79（SecureStore.setItemAsync）
//
// 用途：SessionBootstrapNotifier.build() 启动时恢复上次会话，
// 使应用重启后落在「上次使用的会话」而非「updated_at 最新会话」。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const String _kKeyLastSession = 'yuesheng_last_session_id';

/// 上次会话 ID 存储抽象（测试可注入内存 fake，避免触碰平台通道）
abstract class LastSessionStorage {
  /// 读取上次会话 ID；无记录返回 null
  Future<String?> getLastSessionId();

  /// 持久化当前会话 ID（对齐 RN initSession 每次写入）
  Future<void> setLastSessionId(String sessionId);
}

/// flutter_secure_storage 实现（对应 RN expo-secure-store，
/// 键名与 RN LAST_SESSION_KEY 保持一致）
class SecureLastSessionStorage implements LastSessionStorage {
  final FlutterSecureStorage _storage;

  SecureLastSessionStorage([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<String?> getLastSessionId() => _storage.read(key: _kKeyLastSession);

  @override
  Future<void> setLastSessionId(String sessionId) =>
      _storage.write(key: _kKeyLastSession, value: sessionId);
}
