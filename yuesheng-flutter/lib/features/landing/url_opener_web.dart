// url_opener_web.dart — web 平台实现：新标签页打开外链（条件导入的 web 支）
//
// 为什么不用 `url_launcher`：引入新依赖须单独报批（本批边界 = 零新依赖）。
// 为什么不用 `dart:html`：本仓 web 构建是 **`--wasm`**（`§4-457`），
//   `dart:html` 在 wasm 下不可用；`dart:js_interop` 是 wasm 兼容入口。
//
// `@JS('open')` 解析到全局 `open`（即 `window.open`）。用 `_blank` 打开，
// 不把用户从当前页带走 —— 用户可能正想留在门面再点一次「立即试用」。

import 'dart:js_interop';

@JS('open')
external JSAny? _openJs(JSString url, JSString target);

/// 在外部浏览器打开 [url]（新标签页）。
void openExternalUrl(String url) {
  _openJs(url.toJS, '_blank'.toJS);
}
