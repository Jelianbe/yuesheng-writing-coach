// url_opener_stub.dart — 非 web 平台的空实现（条件导入的兜底支）
//
// 为什么需要它：`dart:js_interop` 只在 web 编译目标下存在，非 web 平台
// 编译到那一支会直接失败。条件导入 `if (dart.library.js_interop)` 让
// Android 走本文件、web 走 `url_opener_web.dart` ⇒ 同一调用点两端都能编。
//
// 为什么非 web 什么都不做：本仓 Android 侧不需要「在浏览器打开外链」这个能力
// （下载入口只出现在 web 门面上）。留空实现 = 若将来误在 Android 调用，
// 静默无副作用，不会崩。**但调用点只在 web 门面页 ⇒ 实际不可达。**

/// 在外部浏览器打开 [url]。非 web 平台：无操作。
void openExternalUrl(String url) {}
