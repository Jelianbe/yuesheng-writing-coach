// config.js — 平台云服务公开配置（publishableKey 设计上随客户端公开，非私密凭据）
//
// ★★★ 2026-11-24（§4-557）**key 与 endpoint 全部换成站点所属应用 j1iRP**。
//   这次改的是**根因**，不是又一轮试错。错配长这样：
//
//   【错在哪】本站部署域 `yuesheng-apk-test` 属于应用 **j1iRP**
//     （部署返回的 genie 文件名 `.wbapp_j1iRP0QdPV8ezelACqoC7y` 就是铁证），
//     而本文件此前写的是**另一个应用 2mqh** 的 key，并且 endpoint 还套了
//     `/wbproxy` 把请求代理到 2mqh 的数据面（yuesheng-coach）。
//     ⇒ 一条链上出现了**两个应用**。
//
//   【为什么登录必然失败】WorkBuddy 登录是 Relay 的 OAuth：
//     ① Relay 按 `callback_url`（= 本站域）签发 state，这个 state 记在 **j1iRP** 名下；
//     ② 回跳后 SDK 拿 code + state + verifier 去换会话；
//     ③ 但这个请求被代理送到了 **2mqh** 的数据面 —— **2mqh 从没见过这个 state**；
//     ④ 于是数据面只能答 `the state parameter is invalid, expired or already consumed`。
//     ★ 注意 ③ 的报错是**真话**（对 2mqh 而言这个 state 确实无效），
//       所以它不是"含糊的报错"，而是**指向了正确的方向：应用对不上**。
//
//   【为什么之前查不出来】报错文本本身没有分辨力 —— 用**假 code + 假 state**
//     打同一个端点，返回的是**一模一样**的这句话。我一度把它当成"重复兑换"
//     去修（清 URL、加单飞），那些修复都对、但**修的不是这里**。
//     ⇒ 教训：**当一个报错对不同输入都返回同一句话时，它的文本不携带信息，
//       真正的信息在"这个请求被送到了哪个应用"这种**结构事实**里。**
//
//   【怎么确认的（E1 实测，可重跑）】
//     · j1iRP 的 key → 本站域 `/ .cloud /auth/v1/verification` → **200，正常**
//     · 2mqh 的 key → 本站域 → `403 access_denied`（origin 不符，预期）
//     · 2mqh 的 key → 它自己的数据面 → `401 login_required`（它确实支持登录，
//       但它服务的是另一个域，跟本站域的 state 无关）
//
// ⚠️ **代价（必须说清，不得掩盖）**：j1iRP 的 **AI 能力未开通**
//    （实测 `403 capability_disabled`）⇒ 切到本站 key 后**登录能通，诊断会 403**。
//    这不是代码问题，是平台侧的应用能力开关，需在应用「月笙写作教练下载测试」
//    的「云服务」入口开启 AI 能力后恢复。diagnose.html 的 friendlyError 已为该
//    错误码补了人话提示，**不会静默失败**。
// ★ 2026-11-24 §4-561 迁移副本：本文件指向 **2mqh**（AI 能力已开），
//   原 j1iRP 站点保留在 ../site/ 不动。详见 .ai/DECISIONS.md §4-561。
'use strict';
const WB_CONFIG = {
  // ★ 与站点域一致（j1iRP）。**不再套 /wbproxy**：endpoint 就是本站自身域，
  //   SDK 拼 baseUrl = endpoint + '/.cloud/...' ⇒ 直接落本站数据面，同源无需代理。
  //   /wbproxy 代理代码保留在 server.py（不删），但前端不再使用它。
  endpoint: 'https://yuesheng-coach.app.workbuddy.host',
  publishableKey: 'wbpk_2mqhpPIkw6lCf4kthBTrB0_JtS0d38zjLYP0YK1ubroX9wf0s5tinaH',
  model: 'deepseek-v4.1-flash',
  // ★ 2026-11-23 登录接入（§4-553）：由平台 `publicConfig` 现取，非猜测值。
  //   【为什么必须有】SDK 源码里此参数**没有默认值**（实测：
  //   `oauthRelayBaseUrl:r.oauthRelayBaseUrl?...:""`，缺省为空串 ⇒ 点登录时
  //   抛 `signInWithOAuth requires oauthRelayBaseUrl`）。它**不能从 endpoint 推导**
  //   ——endpoint 是每应用独立域，Relay 是平台中心地址。
  //   【来源】`workbuddy_cloud_service action=activate applicationMode=reuse`
  //   返回的 publicConfig.oauthRelayBaseUrl（reusedExisting=true，幂等无重复扣费）。
  oauthRelayBaseUrl: 'https://www.workbuddy.cn/v2/as/genie-baas/oauth',
};
// ★ 2026-11-24 必须同时挂到 window（实测踩到的真 bug，不是防御性写法）。
//   【问题】顶层 `const` 只创建**全局词法绑定**，**不会**成为 window 的属性。
//     故同一份配置有两种引用方式、结果不同：
//       · `WB_CONFIG.endpoint`        → 能用（引擎侧一直这么写，所以从未暴露）
//       · `window.WB_CONFIG.endpoint` → **undefined**（登录侧新代码这么写）
//   【后果】登录模块 `getSharedClient()` 首行 `if (!window.WB_CONFIG) return null`
//     ⇒ 永远返回 null ⇒ 点「登录」拿不到 client ⇒ 登录**静默不可用**。
//     页面不报错、控制台无红字、按钮点了只是没反应 —— 最难查的那一类。
//   【怎么发现的】实测探针读数 `hasCfg:false / client:NULL`，而 `config.js` HTTP 200
//     且内容正确 ⇒ 排除加载失败，才定位到「绑定可见性 ≠ window 属性」。
//   ⇒ 此后两种写法都成立；但**新增代码统一用 `window.WB_CONFIG`**（显式、可静态检索）。
window.WB_CONFIG = WB_CONFIG;
