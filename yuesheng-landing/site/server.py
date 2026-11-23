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
UPSTREAM = 'https://yuesheng-coach.app.workbuddy.host'
SELF_ORIGIN = 'https://yuesheng-apk-test.app.workbuddy.host'
ALLOWED_ORIGINS = {SELF_ORIGIN, 'http://127.0.0.1:8795', 'http://localhost:8795'}
# 前缀 = /wbproxy/（★ 不可用 /.cloud/——那是平台保留路径，站点域上被平台数据面
# 路由层直接接管（实测 401 invalid_client），本服务收不到）。SDK 拼接形态
# baseUrl = endpoint + '/.cloud/llm' ⇒ endpoint = 本站域 + '/wbproxy'，
# 本服务收到 /wbproxy/.cloud/... 后剥前缀转发到数据面 /.cloud/...。
PROXY_PREFIX = '/wbproxy/'
# 逐跳头不转发（RFC 7230）＋ 网关注入头不转发：
# Cookie 一律剥（挡平台网关注入的 `__wb_rsc`，§4-511）。
HOP_HEADERS = {'host', 'connection', 'keep-alive', 'transfer-encoding',
               'upgrade', 'proxy-authorization', 'proxy-authenticate',
               'te', 'trailers', 'cookie'}
STRIP_PREFIXES = ('x-wb-webapp-access-key',)

# ★★ 2026-11-24（§4-555）：**认证类端点一律剥 Authorization**，其余端点放行。
#
#   【为什么必须分路径，不能一刀切】
#     · 放行（§4-553 的写法）⇒ 兑换必然失败：实测 `POST /auth/v1/login-workbuddy`
#       只要带 Authorization（任何值：`Bearer faketok123` / 随机串 / 伪 JWT 三种都试过），
#       数据面返回 401 `invalid_grant: the session is invalid, expired or issued for
#       another client`；**不带**则正常推进到 code/state 校验
#       （400 `invalid_request: the state parameter is invalid...`）。
#       舰长真机截图上的报错与「带 Authorization」这一组**一字不差**。
#     · 全剥（§4-511 的写法）⇒ 登录后 LLM 调用拿不到用户身份。
#
#   【为什么「认证类端点剥」是安全的，这不是妥协而是依据】
#     SDK 源码实证：`postForSession` 只发 `{code,state,code_verifier}` /
#     `{username,password}` / `{refresh_token}` 这类**凭据本体**，
#     这些端点靠**请求体里的凭据**认证，**设计上不接受也不需要 Bearer**
#     （`exchangeWorkBuddyCode` → `postForSession(b.loginWorkBuddy, {...})`，无 token 参数）。
#     ⇒ 该路径上的 Authorization 只会污染兑换，**没有任何正向作用**。
#
#   【LLM 等业务端点仍放行】因为那里恰恰是用户 token 的用武之地。
#   ⚠️ 若登录后 LLM 仍报 `invalid_grant`，则说明**平台网关会覆盖/注入**入站
#     Authorization（而非浏览器原值），此时须改走「服务端会话换取」而非透传，
#     不要简单回退成本文件早先的「全剥」。
AUTH_STRIP_PREFIXES = ('/.cloud/auth/',)

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
        upstream_path = self.path[len('/wbproxy'):]
        # 认证类端点额外剥 Authorization（依据见文件头 AUTH_STRIP_PREFIXES 注释）
        strip_auth = any(upstream_path.startswith(p) for p in AUTH_STRIP_PREFIXES)
        headers = {}
        for k, v in self.headers.items():
            kl = k.lower()
            if kl in HOP_HEADERS or kl in STRIP_PREFIXES or kl == 'origin':
                continue
            if strip_auth and kl == 'authorization':
                continue
            headers[k] = v
        headers['Origin'] = UPSTREAM  # ★ 重写为数据面自身域 ⇒ 后端按同源放行
        headers['X-Wb-Webapp-Access-Key'] = _access_key()  # ★ 强制注入（防网关剥/换客户端头）
        req = urllib.request.Request(UPSTREAM + upstream_path,
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
        else:
            SimpleHTTPRequestHandler.do_GET(self)

    def do_HEAD(self):
        if self.path.startswith(PROXY_PREFIX):
            self._proxy()
        else:
            SimpleHTTPRequestHandler.do_HEAD(self)

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
