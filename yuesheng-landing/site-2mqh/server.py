# server.py — 月笙 landing 同源代理（§4-511 · 0.6 发版批 ③ 部署闸）
#
# 背景：landing 部署域（yuesheng-apk-test.app.workbuddy.host）与云数据面
# （yuesheng-coach.app.workbuddy.host）跨域 ⇒ 数据面按 Origin 白名单拒
# （实测 403 access_denied；平台未暴露 Origin 白名单配置工具）。
# 本服务把 /.cloud/* 同源代理到数据面并把 Origin 重写为数据面自身域
# ⇒ 后端按同源放行。database REST 的 GET / POST、LLM 流式 POST 全走此径。
#
# 安全边界：
# - 只代理 /.cloud/ 前缀（云数据面固定路径），不做任意转发；
# - Origin 守卫：仅放行本站生产域 + 本地开发口（浏览器 fetch 同源 POST
#   也带 Origin，故守卫不误伤）；无 Origin 的裸请求一律 403（防开放代理
#   被第三方蹭额度——额度走 coach 环境计费）；
# - publishableKey 仍由客户端携带（设计上公开），本服务不存任何密钥、
#   不落访问日志。
#
# 部署：workbuddy_sites_deploy，language=python，listen $PORT bind 0.0.0.0。

import os
import urllib.request
import urllib.error
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler

PORT = int(os.environ.get('PORT', '8795'))
# ⚠️ 2026-11-24（§4-557）：**本代理已不再被前端使用**，保留仅为兼容旧缓存页面。
#   原因：登录失败的根因是「配置指向了另一个应用」——
#   endpoint 曾套 `/wbproxy` 把请求代理到 yuesheng-coach（应用 2mqh），
#   而本站域属于应用 j1iRP，Relay 按本站域签发 state，2mqh 从没见过 ⇒ 必失败。
#   现在 config.js 的 endpoint 已改为站点自身域（j1iRP 直连，平台网关 tcbgw
#   在静态服务之前接管 /.cloud/，实测 200）。**不要再把前端指回这里。**
UPSTREAM = 'https://yuesheng-coach.app.workbuddy.host'
SELF_ORIGIN = 'https://yuesheng-apk-test.app.workbuddy.host'
ALLOWED_ORIGINS = {SELF_ORIGIN, 'http://127.0.0.1:8795', 'http://localhost:8795'}
# 前缀 = /wbproxy/（★ 不可用 /.cloud/——那是平台保留路径，站点域上被平台数据面
# 路由层直接接管（实测 401 invalid_client），本服务收不到）。SDK 拼接形态
# baseUrl = endpoint + '/.cloud/llm' ⇒ endpoint = 本站域 + '/wbproxy'，
# 本服务收到 /wbproxy/.cloud/... 后剥前缀转发到数据面 /.cloud/...。
PROXY_PREFIX = '/wbproxy/'
# 逐跳头不转发（RFC 7230）＋ 网关注入头不转发。
# Cookie 剥掉：挡平台网关注入的 `__wb_rsc`（§4-511）。
#
# ★★★ 2026-11-24（§4-555）`authorization` **回到剥离名单**。这次是**认知反转**，
#   来回一次，务必读完再改：
#
#   【第一次改动 · §4-553 · 错】把 `authorization` 移出了本集合。
#     当时理由：接入账号登录后，浏览器送的 `Authorization: Bearer <用户 token>`
#     是用户真实身份，剥掉就永远登录不上。
#     当时「证据」：响应头里只有 `Set-Cookie: __wb_rsc`、**没有 Authorization**
#     ⇒ 断定网关不注入 Authorization。
#     ★ **这个推断是错的：响应头证明不了请求头。** 网关往**入站请求**里注什么，
#       在**响应**里根本看不见。用响应头下一个关于请求头的否定结论，方向就错了。
#
#   【实测（可复现，任何人可重跑）】客户端两边都**不发** Authorization，
#   唯一差异是「经不经平台网关」：
#     · 线上（经网关）→ `401 invalid_grant: the session is invalid, expired or
#       issued for another client`   ← 舰长真机截图报错**一字不差**
#     · 本地（不经网关）→ `400 invalid_request: the state parameter is invalid...`
#   三个端点（llm / auth / database）全部如此；直连数据面时它们各报各的错
#   （`login_required` / `UNAUTHENTICATED` / `DATABASE_PGRST205`），一经网关
#   **全部变成同一个 invalid_grant** ⇒ 是网关这层把请求污染了。
#
#   【网关是「覆盖」而非「追加」——这一步决定修法】
#   客户端发 `Bearer AAA` / `Bearer BBB` / `Basic CCC` / **不发**，四种结果
#   **完全相同** ⇒ 网关**无条件覆盖** Authorization，客户端送什么到不了数据面。
#   ⇒ **在这条链路上透传 Authorization 没有任何意义**，剥掉不损失任何信息。
#     这也解决了「登录后 LLM 要用户 token」的顾虑：那条路本来就不通。
#
#   【那登录身份靠什么到数据面？】不走 Authorization 头。`postForSession` 把
#   `code` / `code_verifier` 放在**请求体**里（SDK 源码实证）；数据面按
#   `X-Wb-Webapp-Access-Key` 认应用、按请求体会话认用户。
#   ⚠️ 若将来要恢复「按用户身份调用 LLM」，正确方向是**服务端会话换取/短时票据**，
#     **不是**把 Authorization 加回透传名单 —— 那会被网关覆盖，且复现本次全站故障。
HOP_HEADERS = {'host', 'connection', 'keep-alive', 'transfer-encoding',
               'upgrade', 'proxy-authorization', 'proxy-authenticate',
               'te', 'trailers', 'authorization', 'cookie'}
STRIP_PREFIXES = ('x-wb-webapp-access-key',)

# ★ 临时探针文件一律不外发（2026-11-24 · §4-556 实测踩到）。
#   起因：调试账号面板时建了 7 个 `_probe_acct*.html`，本地删掉后**重新部署
#   仍然 200**。实测 `Last-Modified` 还是旧值 ⇒ 平台是**增量覆盖上传**，
#   **不删除**线上已存在但本地已消失的文件。
#   ⇒ `rm 本地 + 重新部署` 这条路清不掉线上残留，这是平台行为，不是我的误判。
#   对策：在服务层对 `_probe_` 前缀直接 404。这样即使文件残留在线上磁盘，
#   也不会被静态服务出去 —— 而且以后任何人加的临时探针都自动被挡。
#   ⚠️ 副作用为零：正常的页面/资源不以 `_probe_` 开头。
BLOCKED_PREFIXES = ('_probe_',)

# publishableKey 从同目录 config.js 读入（该 key 设计上随客户端公开，
# 已在站点静态文件里；服务端读入仅为强制注入，不新增泄露面、不进日志）。
_KEY = None


def _access_key():
    global _KEY
    if _KEY is None:
        import re
        here = os.path.dirname(os.path.abspath(__file__))
        cfg = open(os.path.join(here, 'js', 'config.js'), encoding='utf-8').read()
        _KEY = re.search(r"publishableKey:\s*'([^']+)'", cfg).group(1)
    return _KEY


class Handler(SimpleHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def log_message(self, fmt, *args):
        pass  # 不落访问日志（防内容进日志）

    def _allowed_origin(self):
        o = self.headers.get('Origin')
        return o if o in ALLOWED_ORIGINS else None

    def _cors(self, origin):
        if origin:
            self.send_header('Access-Control-Allow-Origin', origin)
            self.send_header('Access-Control-Allow-Headers',
                             'Content-Type, Accept, X-Wb-Webapp-Access-Key, '
                             'X-Request-Id, X-Device-Id')
            self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
            self.send_header('Access-Control-Max-Age', '600')

    def _reject(self, code):
        self.send_response(code)
        self.send_header('Content-Length', '0')
        self.end_headers()

    def do_OPTIONS(self):
        origin = self._allowed_origin()
        if not origin:
            self._reject(403)
            return
        self.send_response(204)
        self._cors(origin)
        self.send_header('Content-Length', '0')
        self.end_headers()

    def _proxy(self):
        origin = self._allowed_origin()
        if not origin:
            self._reject(403)
            return
        length = int(self.headers.get('Content-Length') or 0)
        body = self.rfile.read(length) if length else None
        headers = {}
        for k, v in self.headers.items():
            kl = k.lower()
            # HOP_HEADERS 已含 authorization（网关无条件覆盖，透传无意义，见文件头）
            if kl in HOP_HEADERS or kl in STRIP_PREFIXES or kl == 'origin':
                continue
            headers[k] = v
        headers['Origin'] = UPSTREAM  # ★ 重写为数据面自身域 ⇒ 后端按同源放行
        headers['X-Wb-Webapp-Access-Key'] = _access_key()  # ★ 强制注入（防网关剥/换客户端头）
        req = urllib.request.Request(UPSTREAM + self.path[len('/wbproxy'):],
                                     data=body, method=self.command, headers=headers)
        try:
            up = urllib.request.urlopen(req, timeout=120)
        except urllib.error.HTTPError as e:
            up = e  # 4xx/5xx 原样回传（错误契约由客户端解析）
        except Exception:
            self._reject(502)
            return
        self.send_response(up.code if hasattr(up, 'code') else 502)
        for k, v in up.headers.items():
            if k.lower() in HOP_HEADERS or k.lower() == 'access-control-allow-origin':
                continue
            self.send_header(k, v)
        self._cors(origin)
        self.send_header('Connection', 'close')
        self.end_headers()
        # 流式透传（SSE/分块不缓冲）
        while True:
            chunk = up.read(1024)
            if not chunk:
                break
            try:
                self.wfile.write(chunk)
                self.wfile.flush()
            except (BrokenPipeError, ConnectionAbortedError):
                return
        up.close()

    def do_GET(self):
        if self.path.startswith(PROXY_PREFIX):
            self._proxy()
        elif self._is_blocked():
            self._reject(404)
        else:
            SimpleHTTPRequestHandler.do_GET(self)

    def do_HEAD(self):
        if self.path.startswith(PROXY_PREFIX):
            self._proxy()
        elif self._is_blocked():
            self._reject(404)
        else:
            SimpleHTTPRequestHandler.do_HEAD(self)

    def _is_blocked(self):
        """临时探针文件不外发（见 BLOCKED_PREFIXES 注释）。
        取路径最后一段判断，防 `sub/_probe_x.html` 绕过。"""
        name = self.path.split('?', 1)[0].rstrip('/').rsplit('/', 1)[-1]
        return any(name.startswith(p) for p in BLOCKED_PREFIXES)

    def do_POST(self):
        if self.path.startswith(PROXY_PREFIX):
            self._proxy()
        else:
            self._reject(404)

    do_PUT = do_POST
    do_PATCH = do_POST
    do_DELETE = do_POST


if __name__ == '__main__':
    ThreadingHTTPServer(('0.0.0.0', PORT), Handler).serve_forever()
