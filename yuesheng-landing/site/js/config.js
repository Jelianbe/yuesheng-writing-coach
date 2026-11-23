// config.js — 平台云服务公开配置（publishableKey 设计上随客户端公开，非私密凭据）
// 提取自构建产物 main.dart.wasm（与 Android/web 端同一编译值）。勿提交私密密钥。
// endpoint = 本站自身域 + /wbproxy（§4-511 同源代理批）：SDK 拼接 baseUrl =
// endpoint + '/.cloud/llm' ⇒ 请求落 /wbproxy/.cloud/...，由 server.py 剥前缀
// 同源代理到数据面（yuesheng-coach.app.workbuddy.host）并重写 Origin——数据面按
// Origin 白名单拒跨域（实测 403 access_denied），且 /.cloud/ 前缀在站点域被平台
// 路由层接管（实测 401 invalid_client），代理前缀必须用 /wbproxy。
'use strict';
const WB_CONFIG = {
  endpoint: 'https://yuesheng-apk-test.app.workbuddy.host/wbproxy',
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
