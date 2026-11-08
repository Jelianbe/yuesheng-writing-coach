// ─────────────────────────────────────────────────────────────
// VerificationGate — 验证层第二模型接入（ADR-0014 · R-027 施工稿）
// 定位：主判产出之后的旁路（不写主判 / 不改返回对象 / 不直报 / 不触发训练）。
// 四态（V-4）：notConfigured / timeout / error / parseFail —— 不外抛、不重试、不排队。
// 读数恒 E2、永不进必过门（V-6）；独立熔断 + 独立并发闸（V-2 / V-3）。
// 硬超时复用 `LlmConfig.testTimeoutMs`（C3 定值，不新增常量）。
// ─────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/shared_constants.dart';
import 'llm_circuit_breaker.dart';
import 'llm_client.dart';
import 'llm_concurrency_gate.dart';
import 'llm_config_storage.dart';

/// 验证层独立三键的存储键（与主链三键**不同键** ⇒ 互不干扰）。
const String kVerificationKeyBaseUrl = 'yuesheng_verify_api_base_url';
const String kVerificationKeyApiKey = 'yuesheng_verify_api_key';
const String kVerificationKeyModel = 'yuesheng_verify_api_model';

/// 验证层单次读数的证据等级（恒 E2；不得升 E1、不得折算）。
const String kVerificationEvidenceGrade = 'E2';

/// 验证层独立三键。任一为空 ⇒ [isComplete] = false ⇒ 不出站（V-2）。
class VerificationKeys {
  final String baseUrl;
  final String apiKey;
  final String model;

  const VerificationKeys({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
  });

  /// 三键齐 = 出站的**必要**条件；空串与缺键同义（不区分「未设置」与「设成空」）。
  bool get isComplete =>
      baseUrl.isNotEmpty && apiKey.isNotEmpty && model.isNotEmpty;
}

/// 三键读取点（V-2）。缺键即空串，**不抛异常**（读配置失败不得中断主链）。
class VerificationKeysStorage {
  final FlutterSecureStorage _storage;

  VerificationKeysStorage([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  Future<VerificationKeys> load() async {
    final baseUrl = await _storage.read(key: kVerificationKeyBaseUrl) ?? '';
    final apiKey = await _storage.read(key: kVerificationKeyApiKey) ?? '';
    final model = await _storage.read(key: kVerificationKeyModel) ?? '';
    return VerificationKeys(baseUrl: baseUrl, apiKey: apiKey, model: model);
  }

  /// 保存独立三键（写入前 trim；范式同 llm_config_storage.dart:57-63 的
  /// `Future.wait` 三 write）。trim 后空串等价未配置，与
  /// [VerificationKeys.isComplete] 同语义，不引入第四态。
  /// 异常上抛，由调用方（UI 边界层）非空 catch + SnackBar 反馈。
  Future<void> save(VerificationKeys keys) async {
    await Future.wait([
      _storage.write(key: kVerificationKeyBaseUrl, value: keys.baseUrl.trim()),
      _storage.write(key: kVerificationKeyApiKey, value: keys.apiKey.trim()),
      _storage.write(key: kVerificationKeyModel, value: keys.model.trim()),
    ]);
  }

  /// 清除独立三键（**只删这三个**）。验证层没有 fallback 键，
  /// 不照抄 llm_config_storage.dart 的 `_kKeyApiFallbacks`、不引入第四键。
  /// 判据：clear() 后 `load().isComplete == false`（空串与缺键同义）。
  Future<void> clear() async {
    await Future.wait([
      _storage.delete(key: kVerificationKeyBaseUrl),
      _storage.delete(key: kVerificationKeyApiKey),
      _storage.delete(key: kVerificationKeyModel),
    ]);
  }
}

/// 验证结论三态（S-6）。**没有第四态**：非法值一律 parseFail 并降级（V-5）。
enum VerificationVerdict { rejected, confirmed, needsFullText }

/// 三态与线上字面量的唯一映射表。新增字面量必须同时改本表**与**
/// `verification_gate_test.dart` 的非法值负向用例，否则「恰 3 值」会退化成「表里几个算几个」。
const Map<String, VerificationVerdict> kVerdictWire = {
  'rejected': VerificationVerdict.rejected,
  'confirmed': VerificationVerdict.confirmed,
  'needs_full_text': VerificationVerdict.needsFullText,
};

/// 四态降级枚举（V-4）。[ok] 是唯一「验证层真的执行了判定」的态。
enum VerificationOutcome { notConfigured, timeout, error, parseFail, ok }

/// 一条待核对假设：**只含候选编号、症候编号、原文证据**。
///
/// ★ 刻意不含发现层的 `description` / `severity` / `excluded`：验证上下文
/// 不得含发现层结论（S-7）。结构上不提供入口，比事后断言更难破。
class VerificationHypothesis {
  final String id;
  final String syndromeId;
  final List<String> evidence;

  const VerificationHypothesis({
    required this.id,
    required this.syndromeId,
    required this.evidence,
  });
}

/// 一条验证读数（旁路产物，V-8：全枚举 / 布尔，无折算、无百分比、无「全绿」）。
class VerificationRecord {
  final VerificationOutcome outcome;
  final int hypothesisCount;
  final Map<String, VerificationVerdict> verdicts;
  final String at;

  const VerificationRecord({
    required this.outcome,
    required this.hypothesisCount,
    required this.verdicts,
    required this.at,
  });

  Map<String, dynamic> toJson() => {
    'at': at,
    'evidence': kVerificationEvidenceGrade,
    'outcome': outcome.name,
    'hypothesisCount': hypothesisCount,
    'verdicts': verdicts.map((key, value) => MapEntry(key, value.name)),
  };
}

/// 读数出口（V-8）。缺省只打一行结构化日志；测试注入内存 sink 断言。
typedef VerificationSink = void Function(VerificationRecord record);

void _defaultSink(VerificationRecord record) {
  debugPrint('[verification_gate] ${jsonEncode(record.toJson())}');
}

/// 验证层系统提示词（**新增注入面**，逐字授权见 R-027 施工稿 §3.1）。
///
/// 约束来源：R-009（不替用户改写、不替用户做剧情决定）、S-6（恰三态）、
/// S-7（只给证据、不给发现层结论）。**不含**任何厂商名 / 模型名（V-3）。
const String kVerificationSystemPrompt =
    '你是独立的文本核对者。下面给出若干「候选症候」及各自在原文中的证据片段。\n'
    '\n'
    '对每一条，只回答一个问题：仅凭给出的证据，这条候选是否成立？\n'
    '\n'
    '规则：\n'
    '1. 只依据给出的证据判断，不得补充证据之外的信息。\n'
    '2. 证据不足以判断时回答 needs_full_text，不得猜测。\n'
    '3. 不改写原文，不提出修改建议，不给出教学解释。\n'
    '4. 只输出 JSON 数组，每项一个对象：'
    '{"id": "<候选编号>", "verdict": "confirmed" | "rejected" | "needs_full_text"}。\n'
    '5. 数组项数必须与候选条数相等，id 必须与给定编号一致。';

/// 验证层入口。**旁路 / 后置**：不写主判、不改主链返回对象。
class VerificationGate {
  final Future<VerificationKeys> Function() keysLoader;
  final LlmClient Function(VerificationKeys keys) clientFactory;
  final VerificationSink sink;

  /// 仅测试可传：把 15 s 硬上限压到毫秒级，避免真等 15 s。
  /// 生产恒为 null ⇒ 用 [hardTimeout]（该字段不影响硬值判据，见 §8 T-3）。
  final Duration? debugTimeoutOverride;

  const VerificationGate({
    required this.keysLoader,
    required this.clientFactory,
    this.sink = _defaultSink,
    this.debugTimeoutOverride,
  });

  /// 硬超时上限（C3 定值 = 复用 `LlmConfig.testTimeoutMs`，**不新增常量**）。
  ///
  /// 代价：与「测试连通性」共用同一数值。若将来要独立调档 ⇒ 属判据口径变更，
  /// 须另走 R-027，不得就地改数。
  static const Duration hardTimeout = Duration(
    milliseconds: LlmConfig.testTimeoutMs,
  );

  Duration get _timeout => debugTimeoutOverride ?? hardTimeout;

  /// 执行一次验证。返回 null 的两种情形：调用方已取消 / 无候选（不是降级）。
  Future<VerificationRecord?> run({
    required List<VerificationHypothesis> hypotheses,
    bool cancelled = false,
  }) async {
    // 用户已点「停止生成」⇒ 不发起出站（省成本，也不与主链的取消语义打架）。
    if (cancelled) return null;
    // 无候选 ⇒ 无验证对象；这不是四态之一，不留读数（V-2 的 8 子集分母不含它）。
    if (hypotheses.isEmpty) return null;

    final keys = await keysLoader();
    if (!keys.isComplete) {
      return _emit(VerificationOutcome.notConfigured, hypotheses, const {});
    }

    final client = clientFactory(keys);
    final messages = <ChatMessage>[
      const ChatMessage(role: 'system', content: kVerificationSystemPrompt),
      ChatMessage(role: 'user', content: _buildUserContent(hypotheses)),
    ];

    String raw;
    try {
      raw = await client.chatCompletion(messages).timeout(_timeout);
    } on TimeoutException {
      return _emit(VerificationOutcome.timeout, hypotheses, const {});
    } catch (_) {
      // 非空 catch：留痕由 _emit 的 sink 承担（V-4③「禁空 catch」）。
      return _emit(VerificationOutcome.error, hypotheses, const {});
    }

    final verdicts = _parseVerdicts(raw, hypotheses);
    if (verdicts == null) {
      return _emit(VerificationOutcome.parseFail, hypotheses, const {});
    }
    return _emit(VerificationOutcome.ok, hypotheses, verdicts);
  }

  /// 只拼「候选编号 + 症候编号 + 原文证据」——不带任何解读性字段（S-7）。
  String _buildUserContent(List<VerificationHypothesis> hypotheses) {
    final buffer = StringBuffer();
    for (var i = 0; i < hypotheses.length; i++) {
      final hypothesis = hypotheses[i];
      buffer.writeln(
        '候选 ${i + 1}（编号 ${hypothesis.id}，症候 ${hypothesis.syndromeId}）：',
      );
      for (final quote in hypothesis.evidence) {
        buffer.writeln('- 「$quote」');
      }
      buffer.writeln();
    }
    return buffer.toString();
  }

  /// 三态解析器（V-5）。任一不合规 ⇒ null（整批 parseFail，不产生第四态、不部分采信）。
  Map<String, VerificationVerdict>? _parseVerdicts(
    String raw,
    List<VerificationHypothesis> hypotheses,
  ) {
    final jsonText = _extractJsonArray(raw);
    if (jsonText == null) return null;

    Object? decoded;
    try {
      decoded = jsonDecode(jsonText);
    } catch (_) {
      return null;
    }
    if (decoded is! List) return null;
    // 项数必须逐条对齐：少一项 = 有候选没被核对，多一项 = 自造候选。
    if (decoded.length != hypotheses.length) return null;

    final expectedIds = hypotheses.map((hypothesis) => hypothesis.id).toSet();
    final parsed = <String, VerificationVerdict>{};
    for (final item in decoded) {
      if (item is! Map) return null;
      final id = item['id'];
      final wire = item['verdict'];
      if (id is! String || wire is! String) return null;
      if (!expectedIds.contains(id) || parsed.containsKey(id)) return null;
      final verdict = kVerdictWire[wire];
      if (verdict == null) return null; // 非法值 ⇒ 整批 parseFail
      parsed[id] = verdict;
    }
    if (parsed.length != expectedIds.length) return null;
    return parsed;
  }

  /// 取首个 `[` 到末个 `]`（模型常包代码围栏或加一句前言）。
  /// 抽不出 ⇒ null ⇒ parseFail；**不做「猜哪段像 JSON」的启发式**。
  String? _extractJsonArray(String text) {
    final start = text.indexOf('[');
    final end = text.lastIndexOf(']');
    if (start < 0 || end <= start) return null;
    return text.substring(start, end + 1);
  }

  VerificationRecord _emit(
    VerificationOutcome outcome,
    List<VerificationHypothesis> hypotheses,
    Map<String, VerificationVerdict> verdicts,
  ) {
    final record = VerificationRecord(
      outcome: outcome,
      hypothesisCount: hypotheses.length,
      verdicts: verdicts,
      at: DateTime.now().toUtc().toIso8601String(),
    );
    try {
      sink(record);
    } catch (error) {
      // sink 是外部注入点；它抛异常绝不能冒泡到主链（V-4(b) 主链不被阻塞）。
      debugPrint('[verification_gate] sink 异常已吞: $error');
    }
    return record;
  }
}

/// 生产 client 工厂：独立熔断 + 独立并发闸 ⇒ 不占主链的锁、不排主链的队。
LlmClient _buildVerificationClient(VerificationKeys keys) => LlmClient(
  null,
  null,
  () async => LlmConfigValues(
    apiKey: keys.apiKey,
    baseUrl: keys.baseUrl,
    model: keys.model,
  ),
  LlmCircuitBreaker(),
  LlmConcurrencyGate(),
);

/// ADR-0014 V-1 **唯一装配点**：两条链都经此，调用方不得另建入口（V-2「全集 ⇒ 出站恰 = 1」依赖单点）。
VerificationGate productionVerificationGate() => VerificationGate(
  keysLoader: VerificationKeysStorage().load,
  clientFactory: _buildVerificationClient,
);
