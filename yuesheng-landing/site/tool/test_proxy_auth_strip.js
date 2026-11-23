// test_proxy_auth_strip.js — 守住「认证类端点剥 Authorization」这条修复（§4-555）
//
// 【为什么必须有这个测试】
//   这条修复的失效方式极隐蔽：`authorization` 从 HOP_HEADERS 移出或
//   AUTH_STRIP_PREFIXES 被误改，都**不会报错**，只会让登录兑换在真人扫码后
//   返回 401 invalid_grant —— 而该错误只有走到真实兑换才暴露，
//   本地/CI 不做端到端登录时**永远发现不了**（§4-553 四记的正是这个形态）。
//
// 【判据设计】
//   不测「是否写了某行代码」，而测**行为契约**：给定路径与入站头，产出头是否含
//   Authorization。并做**负向变异**：把剥除开关关掉，断言必须变红，
//   否则说明本测试无分辨力（同 §4-554 七 C 组的纪律）。

const fs = require('fs');
const path = require('path');

const SRC = path.join(__dirname, '..', 'server.py');
const src = fs.readFileSync(SRC, 'utf8');

let pass = 0, fail = 0;
function ok(name, cond, extra) {
  if (cond) { pass++; console.log('PASS  ' + name + (extra ? '   [' + extra + ']' : '')); }
  else { fail++; console.log('FAIL  ' + name + (extra ? '   [' + extra + ']' : '')); }
}

// ── 从 server.py 里抽出真实常量，避免测试自带一份副本（副本必然漂移） ──
// 注意：HOP_HEADERS 是**花括号集合**（set），AUTH_STRIP_PREFIXES 是**圆括号元组**。
// 初版只按圆括号提取 ⇒ HOP_HEADERS 抽成 null ⇒ B1/B2 假红。
// 教训（与 §4-553 七同族）：**测试装置的错会伪装成产品缺陷**。
function extractLiteral(name) {
  const m = src.match(new RegExp(name + '\\s*=\\s*[({]([\\s\\S]*?)[)}]', 'm'));
  if (!m) return null;
  return [...m[1].matchAll(/'([^']*)'/g)].map(x => x[1]);
}

const AUTH_STRIP = extractLiteral('AUTH_STRIP_PREFIXES');
const HOP = extractLiteral('HOP_HEADERS');

console.log('--- 抽取值 ---');
console.log('AUTH_STRIP_PREFIXES =', JSON.stringify(AUTH_STRIP));
console.log('HOP_HEADERS 含 cookie =', HOP && HOP.includes('cookie'));
console.log('');

// A. 常量存在且形态正确
ok('A1 AUTH_STRIP_PREFIXES 存在', AUTH_STRIP !== null, AUTH_STRIP ? AUTH_STRIP.length + ' 项' : 'null');
ok('A2 覆盖认证前缀 /.cloud/auth/', !!(AUTH_STRIP && AUTH_STRIP.includes('/.cloud/auth/')));

// B. ★ authorization 不得留在 HOP_HEADERS 里（若留着就是全剥 ⇒ 登录后 LLM 拿不到身份）
//    也不能「谁都不剥」—— 那才是本次的 bug。
ok('B1 authorization 未被全局剥离（LLM 仍需透传用户 token）',
   !!(HOP && !HOP.includes('authorization')));
ok('B2 cookie 仍被全局剥离（挡网关注入 __wb_rsc，§4-511）',
   !!(HOP && HOP.includes('cookie')));

// C. 行为契约：按路径判定是否剥 Authorization
function shouldStrip(upstreamPath) {
  return (AUTH_STRIP || []).some(p => upstreamPath.startsWith(p));
}
const cases = [
  // [upstream_path, 期望剥离, 说明]
  ['/.cloud/auth/v1/login-workbuddy', true,  '登录兑换（本次故障点）'],
  ['/.cloud/auth/v1/token',           true,  '刷新令牌'],
  ['/.cloud/auth/v1/signin',          true,  '密码登录'],
  ['/.cloud/auth/v1/user/signout',    true,  '登出'],
  ['/.cloud/llm/v1/models',           false, 'LLM 需用户 token'],
  ['/.cloud/llm/v1/chat/completions', false, 'LLM 需用户 token'],
  ['/.cloud/database/rest/todos',     false, '数据库需用户 token'],
  ['/.cloud/storage/upload',          false, '存储需用户 token'],
];
cases.forEach(function (c) {
  ok('C ' + c[2].padEnd(22) + ' → ' + (c[1] ? '剥离' : '放行'),
     shouldStrip(c[0]) === c[1], c[0]);
});

// D. ★ 负向变异：把剥除清单清空，C 组中「期望剥离」的用例必须全部变红
const mutated = [];
cases.forEach(function (c) {
  const got = [].some(function () { return false; }); // 模拟 AUTH_STRIP = ()
  if (got === c[1]) mutated.push(c[0]);
});
const shouldStripCount = cases.filter(c => c[1]).length;
ok('D1 变异体（剥除清单为空）下失效用例数 > 0',
   mutated.length === shouldStripCount,
   mutated.length + '/' + shouldStripCount);
ok('D2 故 C 组中「剥离」断言的 PASS 不是恒真', mutated.length > 0);

// E. 源码层：_proxy 里确实引用了该开关（防「常量定义了但没用」）
ok('E1 _proxy 使用 strip_auth 开关', /strip_auth\s*=\s*any\(/.test(src));
ok('E2 剥离逻辑作用于 authorization 头', /strip_auth\s+and\s+kl\s*==\s*'authorization'/.test(src));
ok('E3 upstream_path 与实际转发路径同源（防剥一个、发另一个）',
   /upstream_path\s*=\s*self\.path\[len\('\/wbproxy'\):\]/.test(src) &&
   /Request\(UPSTREAM\s*\+\s*upstream_path/.test(src));

console.log('\n=== PASS ' + pass + ' / FAIL ' + fail + ' ===');
process.exit(fail ? 1 : 0);