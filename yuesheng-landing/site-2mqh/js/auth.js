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

  var _client = null;                       // 惰性创建的 SDK client（见 getCloud）
  var _lastError = null;                    // 供页面读取并显示（不静默吞掉）
  var _pkceSource = null;                   // 最近一次回调时 verifier 的来源（§4-559）
  var _mirrorMeta = null;                   // 副本写入时的上下文（inIframe / href / 年龄）

  // ═══════════════════════════════════════════════════════════════════════
  // ★★ PKCE verifier 的「跨上下文」镜像（2026-11-24 · §4-559）
  // ═══════════════════════════════════════════════════════════════════════
  // 【症状】真机报：workbuddy callback has no local PKCE verifier; sign in again in this tab
  //
  // 【这句报错的准确位置（读 SDK 源码定的，不是猜）】
  //   handleWorkBuddyCallback:
  //     let d = this.workBuddyPkce.readVerifier();
  //     if (!d) return 错误("no local PKCE verifier");
  //     this.workBuddyPkce.clearVerifier();
  //     exchangeWorkBuddyCode(code, state, d)
  //   ⇒ 失败发生在 readVerifier() 之后、**任何网络请求之前**，
  //     即"本地没读到"，不是"服务端拒了"。
  //   ⇒ 报错从上轮的 `state parameter is invalid` 换成这句，**是进步**：
  //     服务端那一关已经过了（key/endpoint 同属 j1iRP），现在卡在本地存储。
  //
  // 【为什么会读不到：存储粒度不对】
  //   SDK：storage() { return globalThis.sessionStorage ?? null }
  //        verifierKey = "workbuddy-cloud.pkce.workbuddy." + publishableKey
  //   sessionStorage 的隔离粒度是 **顶层标签页 + 源**：
  //     · 同标签页跨站往返 → 保留（SDK 的本意）
  //     · 换了顶层上下文（预览面板 iframe / 新开标签 / 授权页跳顶层）→ **读不到**
  //   localStorage 的隔离粒度是 **只有源**，与"哪个标签页/是不是 iframe"无关。
  //
  // 【本版修法：镜像双写，读时兜底】
  //   写入侧：发起登录后，把 verifier 额外向 localStorage 存一份（同键名 + 后缀）。
  //   读取侧：回调前若 sessionStorage 为空，就用 localStorage 的副本回填，
  //           让 SDK 照原样读到，**不改 SDK、不改它的语义**。
  //   清理侧：兑换走通/明确失败后两边一起清，不留长尾。
  //
  // 【代价与边界（必须写清，不得掩盖）】
  //   · 这不能修「授权回调被投到完全不同的浏览器配置文件」——那种情况下两边都读不到。
  //   · localStorage 比 sessionStorage 活得久，故加 TTL，且在兑换后立即清理。
  //   · **不声称这一定能修好**：verifier 到底是在哪个上下文被写/被读，
  //     仍需真机一次登录的读数来确认（见 probe 的 verifierMirror 字段）。
  var PKCE_PREFIX = 'workbuddy-cloud.pkce.workbuddy.';
  var MIRROR_SUFFIX = '.ysmirror';
  var MIRROR_TTL_MS = 10 * 60 * 1000;        // 10 分钟，够一次人工登录

  function verifierKeyFor() {
    var c = cfg();
    return c && c.publishableKey ? (PKCE_PREFIX + c.publishableKey) : null;
  }

  function mirrorKeyFor() {
    var k = verifierKeyFor();
    return k ? (k + MIRROR_SUFFIX) : null;
  }

  // 把当前 sessionStorage 里的 verifier 抄一份到 localStorage（带时间戳）
  // ★ 同时记下**写入时所在的上下文**（inIframe）。这是本次排查缺的那块证据：
  //   只报"读不到"没用，必须能说清"写的地方和读的地方是不是同一个窗口"。
  function stashVerifierMirror() {
    var vk = verifierKeyFor(), mk = mirrorKeyFor();
    if (!vk || !mk) return;
    try {
      var v = sessionStorage.getItem(vk);
      if (!v) return;                        // 没写进去就没什么可抄
      var inFrame = false;
      try { inFrame = (window.top !== window.self); } catch (_) { inFrame = true; }
      localStorage.setItem(mk, JSON.stringify({
        v: v,
        t: Date.now(),
        inIframe: inFrame,                   // 写入侧上下文
        href: String(location.href).slice(0, 300),
      }));
    } catch (_) {}
  }

  // 回调侧调用：sessionStorage 空而 localStorage 有未过期的副本 → 回填
  // 返回 'session' | 'restored' | 'stale' | 'none'
  function restoreVerifierIfMissing() {
    var vk = verifierKeyFor(), mk = mirrorKeyFor();
    if (!vk || !mk) return 'none';
    try {
      if (sessionStorage.getItem(vk)) return 'session';   // 本来就在，无需干预
    } catch (_) { return 'none'; }
    try {
      var raw = localStorage.getItem(mk);
      if (!raw) return 'none';
      var o = JSON.parse(raw);
      if (!o || !o.v) return 'none';
      if (!o.t || (Date.now() - o.t) > MIRROR_TTL_MS) return 'stale';
      // 记下写入侧上下文，供 probe 对照（不改变行为，只留证据）
      _mirrorMeta = { inIframe: !!o.inIframe, href: o.href || null, ageMs: Date.now() - o.t };
      sessionStorage.setItem(vk, o.v);      // 回填给 SDK 读
      return 'restored';
    } catch (_) { return 'none'; }
  }

  function clearVerifierBoth() {
    var vk = verifierKeyFor(), mk = mirrorKeyFor();
    try { if (vk) sessionStorage.removeItem(vk); } catch (_) {}
    try { if (mk) localStorage.removeItem(mk); } catch (_) {}
  }

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

      // ★ §4-559：SDK 只在 sessionStorage 找 verifier，而 sessionStorage
      //   是「顶层标签页 + 源」隔离的。若发起与回跳不在同一顶层上下文，
      //   SDK 会直接报 no local PKCE verifier（一个请求都不发）。
      //   这里在**调用 handler 之前**尝试从 localStorage 副本回填。
      var pkceSrc = restoreVerifierIfMissing();
      _pkceSource = pkceSrc;                 // 供 probe / 报错文案使用

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
          // §4-559：**不清镜像**，理由要说清 ——
          //   失败时把 verifier 的来源（session / restored / none）留给 probe 读，
          //   这是本次排查唯一能自证的读数；TTL 10 分钟后自动失效，不会长留。
          //   下一次登录会重新生成 verifier 并覆盖镜像，不存在"复活旧 proof"。
          return 'callback-error';
        }
        if (r && r.data && r.data.accessToken) {
          cleanCallbackParams();
          clearVerifierBoth();      // §4-559：成功后两边都清，不留长尾
          return 'callback-ok';
        }
        // 空结果：可能是已消费的 code（重复回调）或非本 provider。清参数，按普通访问。
        cleanCallbackParams();
        clearVerifierBoth();        // §4-559：code 已不可用，verifier 留着也没意义
        return 'no-callback';
      } catch (e) {
        _lastError = 'exchange_failed:' + (e && e.message ? e.message : String(e));
        cleanCallbackParams();   // 同上：异常路径也不得留下可重放的 code
        clearVerifierBoth();     // §4-559
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
      // ★ §4-559：SDK 刚把 verifier 写进 sessionStorage，立刻抄一份到
      //   localStorage。若回跳落在另一个顶层上下文（预览 iframe / 新标签），
      //   sessionStorage 读不到，但同源的 localStorage 副本还在。
      stashVerifierMirror();
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

    // ★ 检测探针（2026-11-24 · §4-556）。面板要「针对做检测」，这是它读的数。
    //
    // 为什么查 PKCE verifier：SDK 的 handleWorkBuddyCallback 顺序是
    //   ① 读 state（由 Relay 签发，服务端校验）
    //   ② readVerifier() —— 本地 sessionStorage，没有就 fail "no local PKCE verifier"
    //   ③ 拿 code + state + verifier 去换会话
    // ⇒ 服务端报 `state invalid` 时，本地唯一能自证的是「verifier 还在不在」。
    //   若 verifier 已丢，说明回调不是在本标签页发起的（换标签 / 清了存储），
    //   重试即可；若 verifier 还在而仍报 state 错，则问题在 Relay 侧 state 生命周期，
    //   本地无从修复 —— 这个区分正是舰长要的「检测」。
    probe: function () {
      var out = { sdk: false, cfg: false, verifier: false, session: false, error: _lastError };
      var c = cfg();
      out.cfg = !!c;
      out.sdk = !!(window.WorkBuddyCloud &&
                   typeof window.WorkBuddyCloud.createWorkBuddyCloud === 'function');
      // verifier 键名与 SDK 一致：workbuddy-cloud.pkce.workbuddy.<publishableKey>
      try {
        if (c && c.publishableKey) {
          out.verifier = !!sessionStorage.getItem(
            'workbuddy-cloud.pkce.workbuddy.' + c.publishableKey);
        }
      } catch (_) {}
      try {
        if (c && c.publishableKey) {
          out.session = !!localStorage.getItem(
            'workbuddy-cloud.session.' + c.publishableKey);
        }
      } catch (_) {}
      // ★ §4-559：把「这次回调的 verifier 到底从哪来」变成可读读数。
      //   pkceSource 取值：
      //     'session'  → sessionStorage 本来就有（同标签页往返，正常路径）
      //     'restored' → sessionStorage 空了，靠 localStorage 副本救回来的
      //                  ⇒ **坐实了「发起与回跳不在同一顶层上下文」**
      //     'stale'    → 副本过了 10 分钟 TTL，没回填
      //     'none'     → 两边都没有（发起侧就没写进去，或已被清）
      //     null       → 本次没有回调，无从判断
      out.pkceSource = _pkceSource;
      // 镜像是否还在（诊断"下次能不能救回来"）
      out.verifierMirror = false;
      try {
        var mk = mirrorKeyFor();
        out.verifierMirror = !!(mk && localStorage.getItem(mk));
      } catch (_) {}
      // 当前是否被嵌在 iframe 里 —— 这是「跨上下文」最可能的发生条件。
      // 注意：**只读事实，不据此改行为**（改行为要单独评估，见 §4-559 未验项）
      try { out.inIframe = (window.top !== window.self); } catch (_) { out.inIframe = true; }
      // ★ 关键对照：写入侧 inIframe vs 读取侧 inIframe
      //   restored 且两侧不一致 ⇒ **跨上下文已被坐实**，不是推测。
      //   （镜像里存了写入时的 inIframe，这里和当前值对比）
      out.mirror = _mirrorMeta;
      if (_mirrorMeta && typeof out.inIframe === 'boolean') {
        out.contextSwitched = (_mirrorMeta.inIframe !== out.inIframe);
      } else {
        out.contextSwitched = null;          // 无从判断
      }
      return out;
    },

    // 彻底重来：清掉会话 + verifier + 已消费标记，让下一次登录从零开始。
    // 用途：舰长遇到"怎么试都不行"时，先分清是「状态脏了」还是「链路坏了」。
    resetLocal: function () {
      var c = cfg();
      var keys = ['ys_login_next'];
      if (c && c.publishableKey) {
        var k = c.publishableKey;
        keys.push('workbuddy-cloud.session.' + k);
        keys.push('workbuddy-cloud.pkce.workbuddy.' + k);
        keys.push('workbuddy-cloud.pkce.workbuddy.' + k + MIRROR_SUFFIX);  // §4-559
        keys.push('workbuddy-cloud.pkce-done.workbuddy.' + k);
      }
      var i;
      for (i = 0; i < keys.length; i++) {
        try { localStorage.removeItem(keys[i]); } catch (_) {}
        try { sessionStorage.removeItem(keys[i]); } catch (_) {}
      }
      _lastError = null;
    },

    _debug: { getCloud: getCloud, buildRedirectTo: buildRedirectTo, cfg: cfg },
  };

  window.YueshengAuth = Auth;
})();