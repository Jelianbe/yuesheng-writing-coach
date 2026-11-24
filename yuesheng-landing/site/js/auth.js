// auth.js — WorkBuddy 账号登录（2026-11-24 重写 · §4-554）
//
// ═══════════════════════════════════════════════════════════════════════
// 【为什么重写：上一版有一个必然失败的架构错误】
// ═══════════════════════════════════════════════════════════════════════
// 上一版把「发起登录」和「兑换回调」都放在 diagnose.html，但官方文档明确规定
// redirectTo **必须是站点根**（references/auth/code-generation.md）：
//   - `:259` "The redirect target must be the site root"
//   - `:968` "`redirectTo` is the site root, not a sub-path. A sub-path 404s
//            before any JavaScript runs."
//   - `:989` "`redirectTo` is the **root path** ... not a sub-path."
// 而站点根解析到的是 **index.html**（官网首页），不是 diagnose.html。
// ⇒ 授权回跳落在 index.html，那个页面**没有加载本模块、也没有兑换代码**
// ⇒ code 白白过期（single-use），会话从未建立 ⇒ 永远显示「登录后使用」。
//
// 这不是"概率性失败"，是**每次登录都必然失败**。我上一轮把它当作
// 「未做真人端到端验证」的风险挂在那里，实际上它是确定性的缺陷。
//
// 【为什么本地测不出来】同一份文档 `:270` 明写：
//   "`localhost` and WorkBuddy preview are rejected by the Relay, so this flow
//    cannot be verified before publishing — that is a platform boundary"
// 我在 localhost:8801 上做的所有"验证"都不可能覆盖回调兑换这一段。
//
// 【本版修法】把回调兑换搬到**根页面**（index.html），并保持 diagnose.html 也能兑换
// （双落点都安全：handleWorkBuddyCallback 对已消费的 code 返回空而非报错）。
//
// ═══════════════════════════════════════════════════════════════════════
// 【第二处修正：不再依赖 bridge 暴露的 client】
// ═══════════════════════════════════════════════════════════════════════
// 上一版靠 `window.WbcsBridgeGetClient()` 拿 client。但 index.html 不加载 bridge
// （7.6K 只为登录不值得），且 bridge 在 SDK 未就绪时返回 null ⇒ 登录静默不可用。
// 本版改为**自建 client**：SDK 的会话存在 localStorage
// （`workbuddy-cloud.session.<publishableKey>`，源码 resolveStorage 走
//  globalThis.localStorage）⇒ 两个 client 实例读写同一份会话，不会割裂。
// 初始化必须是幂等的：本模块在 index 与 diagnose 都会加载。

(function () {
  'use strict';

  var CALLBACK_KEYS = ['code', 'state', 'provider', 'error', 'error_description'];
  var NEXT_KEY = 'ys_login_next';           // 登录前记住"用户本来在哪一页"
  var DEFAULT_NEXT = 'diagnose.html';

  var _client = null;
  var _lastError = null;                    // 供页面读取并显示（不静默吞掉）

  function cfg() {
    // config.js 同时挂了 window.WB_CONFIG 与顶层 const，两种取法都兜住
    var c = (typeof window !== 'undefined' && window.WB_CONFIG) ||
            (typeof WB_CONFIG !== 'undefined' ? WB_CONFIG : null);
    return c && c.endpoint && c.publishableKey ? c : null;
  }

  // 惰性建 client。为什么不用 bridge：见文件头「第二处修正」。
  function getCloud() {
    if (_client) return _client;
    var c = cfg();
    if (!c) { _lastError = 'config_missing'; return null; }
    if (!window.WorkBuddyCloud || typeof window.WorkBuddyCloud.createWorkBuddyCloud !== 'function') {
      _lastError = 'sdk_missing';
      return null;
    }
    var opts = { endpoint: c.endpoint, publishableKey: c.publishableKey };
    // oauthRelayBaseUrl 在 SDK 里**没有默认值**，缺省会抛
    // signInWithOAuth requires oauthRelayBaseUrl（empirically verified）
    if (c.oauthRelayBaseUrl) opts.oauthRelayBaseUrl = c.oauthRelayBaseUrl;
    _client = window.WorkBuddyCloud.createWorkBuddyCloud(opts);
    return _client;
  }

  function q(name) {
    return new URLSearchParams(window.location.search).get(name);
  }

  function hasCallbackParams() {
    var sp = new URLSearchParams(window.location.search);
    return sp.has('code') || sp.has('error');
  }

  // 回调后清理 URL：**只**删回调相关键，业务参数（?sharecode= 等）原样保留。
  // 官方专警告（:341）："a blanket `location.pathname` throws away parameters the
  // app depends on (`?sharecode=…`, `?from=…`) and the user lands on the wrong
  // content after logging in."
  function cleanCallbackParams() {
    var url = new URL(window.location.href);
    var touched = false;
    for (var i = 0; i < CALLBACK_KEYS.length; i++) {
      if (url.searchParams.has(CALLBACK_KEYS[i])) {
        url.searchParams.delete(CALLBACK_KEYS[i]);
        touched = true;
      }
    }
    if (touched) history.replaceState(null, '', url.pathname + url.search + url.hash);
  }

  // 构造 redirectTo：**站点根** + 保留应用自有参数 + 去掉回调三键（防旧 code 撞车）。
  function buildRedirectTo() {
    var back = new URL(window.location.href);
    back.pathname = '/';
    for (var i = 0; i < 3; i++) back.searchParams.delete(['code', 'state', 'provider'][i]);
    return back.toString();
  }

  // 记住"从哪来"，登录成功后回哪去。存 sessionStorage：同标签页跨站往返仍保留。
  function rememberNext() {
    try {
      var here = window.location.pathname.replace(/^\/+/, '');
      // 只记本应用内的 HTML 页，避免把回调地址自己记进去
      if (/\.html?$/i.test(here)) {
        sessionStorage.setItem(NEXT_KEY, here + window.location.search);
      }
    } catch (_) {}
  }

  function popNext() {
    try {
      var v = sessionStorage.getItem(NEXT_KEY);
      sessionStorage.removeItem(NEXT_KEY);
      // 白名单式校验：只允许本应用内的相对 html 路径，防开放重定向
      if (v && /^[A-Za-z0-9_.\-\/]+\.html(\?|$)/.test(v)) return v;
    } catch (_) {}
    return DEFAULT_NEXT;
  }

  var Auth = {
    // 登录态读取。**只认 accessToken 真值**：SDK 无会话时返回 {data:null}，
    // 用 !!data 判会在某些路径上假绿。
    async getSession() {
      var cloud = getCloud();
      if (!cloud || !cloud.auth) { _lastError = _lastError || 'no_auth_api'; return null; }
      try {
        var r = await cloud.auth.getSession();
        var s = (r && r.data) || null;
        if (s && s.accessToken) { _lastError = null; return s; }
        return null;
      } catch (e) {
        _lastError = 'get_session_failed:' + (e && e.message ? e.message : String(e));
        return null;
      }
    },

    // 供页面显示诊断信息（不静默失败）
    lastError: function () { return _lastError; },

    // ★ 回调分发，按官方 "One callback dispatcher per page" 的三分支实现：
    //   ① 有 error 无 code → 停在登录视图并报错
    //   ② 有 code → 按 provider 选 handler 兑换；成功则清 URL 并进应用
    //   ③ 都没有 → 正常启动（恢复既有会话）
    //   返回 'no-callback' | 'callback-ok' | 'callback-failed' | 'callback-error'
    async dispatchCallback() {
      if (!hasCallbackParams()) return 'no-callback';

      var cloud = getCloud();
      if (!cloud || !cloud.auth) {
        _lastError = _lastError || 'sdk_missing';
        return 'callback-failed';
      }

      // 只支持 workbuddy 一家；provider 缺失时也尝试（Relay 正常会带，缺了不该直接锁死）
      var provider = q('provider');
      if (provider && provider !== 'workbuddy') {
        _lastError = 'unsupported_provider:' + provider;
        return 'callback-error';
      }
      var handler = cloud.auth.handleWorkBuddyCallback;
      if (typeof handler !== 'function') {
        // 官方明令："Never treat a missing SDK method as an empty callback"
        _lastError = 'handler_missing';
        return 'callback-failed';
      }

      try {
        var r = await handler.call(cloud.auth);
        // 官方分支：error → 停在登录视图；session → 进应用；空 → 当作普通访问
        if (r && r.error) {
          _lastError = (r.error.message || 'callback_error');
          // ★ 兑换失败也必须清 URL（2026-11-24 · §4-556）。
          //   原实现只在成功/空结果时清理 ⇒ 失败时地址栏挂着已作废的 code，
          //   用户一刷新就重放同一个必然失败的兑换，症状是"怎么试都不行"。
          //   舰长真机截图那条 `state ... already consumed` 正是这个形态：
          //   报错本身是真话（那个 state 确实已被消费），但"反复出现"是重放造成的。
          cleanCallbackParams();
          return 'callback-error';
        }
        if (r && r.data && r.data.accessToken) {
          cleanCallbackParams();
          return 'callback-ok';
        }
        // 空结果：可能是已消费的 code（重复回调）或非本 provider。清参数，按普通访问。
        cleanCallbackParams();
        return 'no-callback';
      } catch (e) {
        _lastError = 'exchange_failed:' + (e && e.message ? e.message : String(e));
        cleanCallbackParams();   // 同上：异常路径也不得留下可重放的 code
        return 'callback-failed';
      }
    },

    // 发起登录。signInWithOAuth **不跳转**，只返回 URL；必须同标签页 assign，
    // 否则跨标签拿不到本地 PKCE proof（官方："window.open / target=_blank loses
    // the local proof"）。
    async signIn() {
      var cloud = getCloud();
      if (!cloud) throw new Error(_lastError === 'sdk_missing'
        ? '云服务 SDK 未就绪，请刷新页面重试' : '云服务未配置（config.js 缺少 endpoint / publishableKey）');
      rememberNext();
      var r = await cloud.auth.signInWithOAuth({
        provider: 'workbuddy',
        redirectTo: buildRedirectTo(),
      });
      if (r && r.error) throw new Error(r.error.message || '发起登录失败');
      var url = r && r.data && r.data.url;
      if (!url) throw new Error('平台未返回登录地址');
      window.location.assign(url);           // 同标签页
      return url;
    },

    async signOut() {
      var cloud = getCloud();
      if (!cloud || !cloud.auth) return;
      try { await cloud.auth.signOut(); } catch (_) {}
    },

    // 登录成功后该去哪：优先回用户发起登录的那一页
    nextLocation: function () { return popNext(); },

    _debug: { getCloud: getCloud, buildRedirectTo: buildRedirectTo, cfg: cfg },
  };

  window.YueshengAuth = Auth;
})();