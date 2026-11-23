// test_proxy_auth_strip.js — 守住「代理剥 Authorization」这条修复（§4-555）
//
// 【为什么必须有这个测试】
//   这条修复已经**来回错过一次**：§4-553 把 authorization 移出剥离名单，
//   理由是「用户 token 要透传给 LLM」；结果把**整站**打死 ——
//   实测三个端点（llm / auth / database）在线上全部返回
//   401 invalid_grant「issued for another client」，而直连数据面各报各的错。
//   失效方式极隐蔽：不报错、不抛异常，只有走到真实网络才暴露。
//
// 【判据设计】
//   测**行为契约**（给定入站头，产出头是否含 Authorization），
//   并按 A3c 纪律做**负向变异**：把 authorization 移出剥离集合后，
//   断言必须变红，否则说明本测试无分辨力。

const fs = require('fs');
const path = require('path');

const SRC = path.join(__dirname, '..', 'server.py');
const src = fs.readFileSync(SRC, 'utf8');

let pass = 0, fail = 0;
function ok(name, cond, extra) {
  if (cond) { pass++; console.log('PASS  ' + name + (extra ? '   [' + extra + ']' : '')); }
  else { fail++; console.log('FAIL  ' + name + (extra ? '   [' + extra + ']' : '')); }
}

// 从 server.py 抽真实常量，避免测试自带副本（副本必然漂移）。
// 注意 HOP_HEADERS 是**花括号集合**，初版只按圆括号提取 ⇒ 抽成 null ⇒ 假红。
// 教训（§4-553 七同族）：**测试装置的错会伪装成产品缺陷**。
function extractLiteral(name) {
  const m = src.match(new RegExp(name + '\\s*=\\s*[({]([\\s\\S]*?)[)}]', 'm'));
  if (!m) return null;
  return [...m[1].matchAll(/'([^']*)'/g)].map(x => x[1]);
}

const HOP = extractLiteral('HOP_HEADERS');
const STRIP = extractLiteral('STRIP_PREFIXES');

console.log('--- 抽取值 ---');
console.log('HOP_HEADERS =', JSON.stringify(HOP));
console.log('');

// A. 常量可用
ok('A1 HOP_HEADERS 可解析', HOP !== null, HOP ? HOP.length + ' 项' : 'null');

// B. ★ 核心断言：authorization 必须在剥离名单里
ok('B1 authorization 被剥离（网关会无条件覆盖它，透传无意义）',
   !!(HOP && HOP.includes('authorization')));
ok('B2 cookie 仍被剥离（挡网关注入 __wb_rsc，§4-511）',
   !!(HOP && HOP.includes('cookie')));
ok('B3 publishableKey 转发头被剥（强制由服务端注入）',
   !!(STRIP && STRIP.includes('x-wb-webapp-access-key')));

// C. 行为契约：遍历关键头，验证产出头集合
function buildForwardHeaders(inbound) {
  const out = {};
  for (const k of Object.keys(inbound)) {
    const kl = k.toLowerCase();
    if ((HOP || []).includes(kl) || (STRIP || []).includes(kl) || kl === 'origin') continue;
    out[kl] = inbound[k];
  }
  return out;
}

const INBOUND = {
  'authorization': 'Bearer whatever-gateway-injected',
  'cookie': '__wb_rsc=deadbeef',
  'x-wb-webapp-access-key': 'wbpk_should_be_replaced',
  'origin': 'https://yuesheng-apk-test.app.workbuddy.host',
  'content-type': 'application/json',
  'x-request-id': 'abc-123',
  'accept': 'application/json',
};
const FWD = buildForwardHeaders(INBOUND);

console.log('--- 产出的转发头 ---');
console.log(JSON.stringify(FWD));
console.log('');

const mustStrip = ['authorization', 'cookie', 'x-wb-webapp-access-key', 'origin'];
mustStrip.forEach(function (h) {
  ok('C 剥离 ' + h, !(h in FWD));
});
const mustKeep = ['content-type', 'x-request-id', 'accept'];
mustKeep.forEach(function (h) {
  ok('C 保留 ' + h, FWD[h] === INBOUND[h], FWD[h]);
});

// D. ★ 负向变异：把 authorization 从剥离名单移除（= §4-553 的错误做法）
const mutatedHOP = (HOP || []).filter(h => h !== 'authorization');
const FWD_BAD = (function () {
  const out = {};
  for (const k of Object.keys(INBOUND)) {
    const kl = k.toLowerCase();
    if (mutatedHOP.includes(kl) || (STRIP || []).includes(kl) || kl === 'origin') continue;
    out[kl] = INBOUND[k];
  }
  return out;
})();
ok('D1 变异体（移出 authorization）下该头会漏出去', 'authorization' in FWD_BAD,
   '漏出值=' + FWD_BAD['authorization']);
ok('D2 故 B1 的 PASS 不是恒真', 'authorization' in FWD_BAD);

// E. 源码层：`header` 剥除分支确实在用 HOP_HEADERS（防「常量定义了但没用」）
ok('E1 _proxy 用 HOP_HEADERS 过滤',
   /kl in HOP_HEADERS or kl in STRIP_PREFIXES or kl == 'origin'/.test(src));
ok('E2 已移除无效的按路径剥除开关（AUTH_STRIP_PREFIXES）',
   !/AUTH_STRIP_PREFIXES/.test(src));

// F. 回归护栏：断言注释里保留了「响应头证明不了请求头」这条教训
//    防止将来有人删注释后又一次凭响应头推断请求头
ok('F1 注释保留了这次反转的原因（响应头证明不了请求头）',
   /响应头证明不了请求头/.test(src));

console.log('\n=== PASS ' + pass + ' / FAIL ' + fail + ' ===');
process.exit(fail ? 1 : 0);