// auth.js — WorkBuddy 账号登录（2026-11-23 · §4-553）
//
// 【为什么需要这个文件】
//   平台对 LLM 能力返回 401 `login_required`（E1 实测，§4-552 三）⇒ 未登录无法诊断。
//   接入账号登录后，SDK 的 `llm` 请求会自动带 `Authorization: Bearer <token>`
//   （SDK 源码实证：`this.llm = new M(e, s)` 其中 `s` 每次取 `auth.getAccessToken()`），
//   从而解锁模型调用。
//
// 【严格照官方 `references/auth/code-generation.md` 范式实现，三处易错点都处理了】
//   ① **必须保留业务查询参数**。官方原文警告：删 `code/state/provider` 时
//      「a blanket `location.pathname` throws away parameters the app depends on
//      (`?sharecode=…`, `?from=…`)」。本站**全靠 `?sharecode=WHHKITHUJH` 才能访问**，
//      一旦被冲掉，用户登录完就落到 403「链接不完整」页。⇒ 只逐键删这三个。
//   ② **回调分发必须先于任何路由守卫**，且重复调用安全（SDK 会合并并发同 state）。
//   ③ **同一标签页跳转**。`window.open` / `target="_blank"` 会丢本地 PKCE proof。
//
// 【失败关闭】任何一步拿不到 client / 出错，都显式报错，不静默降级。

(function () {
  'use strict';

  var CODES = ['code', 'state', 'provider'];

  function getCloud() {
    if (typeof window.WbcsBridgeGetClient === 'function') {
      var c = window.WbcsBridgeGetClient();
      if (c && c.auth) return c;
    }
    return null;
  }

  // 构造回到本站的地址：**保留**应用的查询参数（尤其 sharecode），只去掉回调三键。
  function buildRedirectTo() {
    var back = new URL(window.location.href);
    // 官方要求回到站点根；子路径（如 /auth/callback）不被接受。
    back.pathname = back.pathname.replace(/[^/]*$/, '') || '/';
    for (var i = 0; i < CODES.length; i++) back.searchParams.delete(CODES[i]);
    back.hash = '';
    return back.toString();
  }

  // 登录成功回调后清理 URL：**只**删 code/state/provider，其余参数原样保留。
  function cleanCallbackParams() {
    var url = new URL(window.location.href);
    var touched = false;
    for (var i = 0; i < CODES.length; i++) {
      if (url.searchParams.has(CODES[i])) { url.searchParams.delete(CODES[i]); touched = true; }
    }
    if (touched) {
      history.replaceState(null, '', url.pathname + url.search + url.hash);
    }
  }

  function hasCallbackParams() {
    var q = new URLSearchParams(window.location.search);
    return q.has('code') && q.has('state');
  }

  var Auth = {
    // 当前会话（无则 null）。**只读**，不改状态。
    async getSession() {
      var cloud = getCloud();
      if (!cloud) return null;
      try {
        var r = await cloud.auth.getSession();
        return (r && r.data) || null;
      } catch (e) {
        return null;
      }
    },

    // 回调分发：页面启动时**最先**调用（早于任何 UI 判断）。
    // 返回 'callback-ok' | 'no-callback' | 'callback-failed'
    async dispatchCallback() {
      if (!hasCallbackParams()) return 'no-callback';
      var cloud = getCloud();
      if (!cloud) return 'callback-failed';
      try {
        await cloud.auth.handleWorkBuddyCallback();
        cleanCallbackParams();
        return 'callback-ok';
      } catch (e) {
        // 保留参数不清，便于用户重试/排查；但不阻断页面渲染。
        return 'callback-failed';
      }
    },

    // 点「使用 WorkBuddy 登录」。注意：signInWithOAuth **不跳转**，只返回 URL，
    // 必须由我们 location.assign —— 这样才是同标签页，PKCE proof 才不丢。
    async signIn() {
      var cloud = getCloud();
      if (!cloud) {
        throw new Error('云服务未初始化：请刷新页面重试');
      }
      var r = await cloud.auth.signInWithOAuth({
        provider: 'workbuddy',
        redirectTo: buildRedirectTo(),
      });
      if (r && r.error) {
        throw new Error(r.error.message || '发起登录失败');
      }
      var url = r && r.data && r.data.url;
      if (!url) {
        throw new Error('平台未返回登录地址');
      }
      window.location.assign(url);
      return url;
    },

    async signOut() {
      var cloud = getCloud();
      if (!cloud) return;
      try { await cloud.auth.signOut(); } catch (e) { /* 登出失败不阻断 UI */ }
    },
  };

  window.YueshengAuth = Auth;
})();