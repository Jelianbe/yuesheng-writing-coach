// bridge.js — 平台资源点通道的 JS 桥（web 端「无 key 体验装」唯一出口）
//
// 【为什么需要这一层】官方 SDK 的流式接口返回的是 JS async iterator。
//   在 Dart(wasm) 里手搓 `Symbol.asyncIterator` 既易碎又难测（spike 实测踩过）。
//   因此把 `for await` 整个留在 JS，Dart 只收两种东西：
//     ① 增量文本回调（逐字推给 UI）
//     ② 一个 JSON 字符串（结束态：成功载荷 或 结构化错误）
//
// 【为什么错误也走返回值而不是 reject】Dart 侧拿到的是 JSPromise，
//   跨 wasm 边界抛 JS 异常会被压成 `JSObject`，`error.code` 全部丢失 ——
//   那正好是「quota_exhausted 与 quota_rate_limited 必须区分」所依赖的字段。
//   故此处**捕获后序列化返回**，让 Dart 拿到可判定的结构而不是一个黑盒。
//
// 【错误字段来源】官方 `references/llm/code-generation.md` §Error Handling：
//   `CloudOpenAIError` 公开形状 = { error: { message, code }, status, requestId, retryAfterMs }
//   —— 只用公开字段，不读 SDK 私有字段。
//
// 【调用约定】
//   WbcsBridge.chat(paramsJson, onDelta)  → Promise<string>  恒为 JSON，永不 reject
//     paramsJson = JSON.stringify({ endpoint, publishableKey, model, messages, maxTokens })
//   成功：{ ok:true, text, finishReason, credit }
//   失败：{ ok:false, code, errorName, retryAfterMs, status, requestId, message }
//
// 【为什么参数打成一个 JSON 而不是并列展开】
//   Dart 侧 `JSFunction.callAsFunction` 最多接受 5 个位置参数（thisArg 之外），
//   并列展开会在编译期就报 `Too many positional arguments`。打包成单串既
//   绕开该上限，也让「加字段」不需要两端同时改签名。

(function () {
  'use strict';

  var BRIDGE_VERSION = '1.0.0';

  // client 复用：endpoint + key 相同则复用（避免每次对话新建）。
  // 注意 key 只存在本闭包里，不写 window，不进日志。
  var _client = null;
  var _clientSig = null;

  function getClient(endpoint, publishableKey) {
    var sig = endpoint + '\u0000' + publishableKey;
    if (_client && _clientSig === sig) return _client;
    _client = window.WorkBuddyCloud.createWorkBuddyCloud({
      endpoint: endpoint,
      publishableKey: publishableKey,
    });
    _clientSig = sig;
    return _client;
  }

  function toErrorPayload(e) {
    var inner = (e && e.error) || {};
    var code = typeof inner.code === 'string' ? inner.code : null;
    return {
      ok: false,
      code: code,
      errorName: (e && e.name) || null,
      retryAfterMs:
        typeof (e && e.retryAfterMs) === 'number' ? e.retryAfterMs : null,
      status: typeof (e && e.status) === 'number' ? e.status : null,
      requestId: (e && e.requestId) || null,
      message: String(inner.message || (e && e.message) || ''),
    };
  }

  async function chat(paramsJson, onDelta) {
    try {
      var p = JSON.parse(paramsJson);
      var endpoint = p.endpoint;
      var publishableKey = p.publishableKey;
      var model = p.model;
      var maxTokens = p.maxTokens;

      if (typeof window.WorkBuddyCloud === 'undefined') {
        return JSON.stringify({
          ok: false,
          code: 'bridge_sdk_missing',
          errorName: 'BridgeError',
          retryAfterMs: null,
          status: null,
          requestId: null,
          message: 'sdk not loaded',
        });
      }

      var cloud = getClient(endpoint, publishableKey);
      if (!cloud || !cloud.llm || !cloud.llm.chat) {
        return JSON.stringify({
          ok: false,
          code: 'bridge_llm_missing',
          errorName: 'BridgeError',
          retryAfterMs: null,
          status: null,
          requestId: null,
          message: 'llm namespace not mounted',
        });
      }

      var body = {
        model: model,
        messages: p.messages,
        stream: true,
      };
      if (typeof maxTokens === 'number' && maxTokens > 0) {
        body.max_tokens = maxTokens;
      }

      var text = '';
      var finishReason = null;
      var usage = null;

      for await (var chunk of cloud.llm.chat.completions.create(body)) {
        var ch = chunk && chunk.choices && chunk.choices[0];
        if (ch) {
          var d = ch.delta;
          if (d && typeof d.content === 'string' && d.content.length) {
            text += d.content;
            // 回调异常不得污染流：UI 侧已销毁时仍要把流读完并正常返回。
            try {
              onDelta(d.content);
            } catch (_e) {
              /* 忽略：回调属于消费方，不影响本轮结果 */
            }
          }
          if (ch.finish_reason) finishReason = ch.finish_reason;
        }
        if (chunk && chunk.usage) usage = chunk.usage;
      }

      return JSON.stringify({
        ok: true,
        text: text,
        finishReason: finishReason,
        credit:
          usage && typeof usage.credit === 'number' ? usage.credit : null,
      });
    } catch (e) {
      return JSON.stringify(toErrorPayload(e));
    }
  }

  // 埋点写入：匿名统计事件插云库（复用同一 client；RLS 仅放行 INSERT）。
  // 与 chat 同约定：paramsJson = JSON.stringify({ endpoint, publishableKey, table, row })
  // 返回恒为 JSON 永不 reject：成功 { ok:true }；失败 { ok:false, code, message }。
  // 调用方负责「埋点失败不阻断」。
  async function insertEvent(paramsJson) {
    try {
      var p = JSON.parse(paramsJson);
      if (typeof window.WorkBuddyCloud === 'undefined') {
        return JSON.stringify({ ok: false, code: 'bridge_sdk_missing', message: 'sdk not loaded' });
      }
      var cloud = getClient(p.endpoint, p.publishableKey);
      if (!cloud || !cloud.database || !cloud.database.from) {
        return JSON.stringify({ ok: false, code: 'bridge_database_missing', message: 'database namespace not mounted' });
      }
      var r = await cloud.database.from(p.table).insert(p.row);
      if (r && r.error) {
        return JSON.stringify({
          ok: false,
          code: (r.error.code && typeof r.error.code === 'string') ? r.error.code : 'db_error',
          message: String(r.error.message || ''),
        });
      }
      return JSON.stringify({ ok: true });
    } catch (e) {
      var payload = toErrorPayload(e);
      payload.ok = false;
      return JSON.stringify(payload);
    }
  }

  window.WbcsBridge = {
    version: BRIDGE_VERSION,
    chat: chat,
    insertEvent: insertEvent,
  };
})();
