// ─────────────────────────────────────────────────────────────
// LLM 配置存储 — 复刻 llm-client.ts 的 SecureStore 部分
// 使用 flutter_secure_storage（对应 RN 的 expo-secure-store）
// 键名保持一致：yuesheng_api_key / yuesheng_api_base_url / yuesheng_api_model
// ─────────────────────────────────────────────────────────────

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const String _kKeyApiKey = 'yuesheng_api_key';
const String _kKeyApiBaseUrl = 'yuesheng_api_base_url';
const String _kKeyApiModel = 'yuesheng_api_model';

/// B1-1 备选端点链（JSON 数组，可选配置；未配置 = 无 fallback）
const String _kKeyApiFallbacks = 'yuesheng_api_fallbacks';

/// LLM 配置（API Key / Base URL / Model）
class LlmConfigValues {
  final String apiKey;
  final String baseUrl;
  final String model;

  const LlmConfigValues({
    required this.apiKey,
    required this.baseUrl,
    required this.model,
  });
}

/// LLM 配置存储（flutter_secure_storage 封装）
class LlmConfigStorage {
  final FlutterSecureStorage _storage;
  LlmConfigStorage([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  /// 读取配置；任一字段缺失返回 null
  Future<LlmConfigValues?> getLlmConfig() async {
    final apiKey = await _storage.read(key: _kKeyApiKey);
    final baseUrl = await _storage.read(key: _kKeyApiBaseUrl);
    final model = await _storage.read(key: _kKeyApiModel);
    if (apiKey == null ||
        apiKey.isEmpty ||
        baseUrl == null ||
        baseUrl.isEmpty ||
        model == null ||
        model.isEmpty) {
      return null;
    }
    return LlmConfigValues(apiKey: apiKey, baseUrl: baseUrl, model: model);
  }

  /// 保存配置（三字段并行写入）
  Future<void> saveLlmConfig(LlmConfigValues config) async {
    await Future.wait([
      _storage.write(key: _kKeyApiKey, value: config.apiKey),
      _storage.write(key: _kKeyApiBaseUrl, value: config.baseUrl),
      _storage.write(key: _kKeyApiModel, value: config.model),
    ]);
  }

  /// 清除配置
  Future<void> clearLlmConfig() async {
    await Future.wait([
      _storage.delete(key: _kKeyApiKey),
      _storage.delete(key: _kKeyApiBaseUrl),
      _storage.delete(key: _kKeyApiModel),
    ]);
  }

  /// 读取备选端点链原始 JSON（B1-1）；键不存在返回 null。
  /// 解析容错见 parseFallbacks（llm_fallback.dart）。
  Future<String?> getLlmFallbacksRaw() async {
    return _storage.read(key: _kKeyApiFallbacks);
  }

  /// 保存备选端点链（JSON 数组字符串，由调用方序列化）
  Future<void> saveLlmFallbacksRaw(String rawJson) async {
    await _storage.write(key: _kKeyApiFallbacks, value: rawJson);
  }
}
