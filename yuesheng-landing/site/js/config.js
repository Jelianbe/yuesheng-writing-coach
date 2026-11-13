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
};
