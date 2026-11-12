// platform_quota_bridge.dart — 平台资源点通道的条件导入入口
//
// 同一调用点两端可编：Android 解析到 `_stub`（返回 null ⇒ 老路不变），
// web 解析到 `_web`（调官方 SDK）。范式与 `url_opener.dart`
// （`lib/features/landing/`）一致 —— 仓库既有做法，不新造轮子。

export 'platform_quota_bridge_stub.dart'
    if (dart.library.js_interop) 'platform_quota_bridge_web.dart';
