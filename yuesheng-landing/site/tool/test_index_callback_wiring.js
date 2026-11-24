// index.html 回调接线验证（负向变异版）
//
// 目的：证明「根页面会加载 SDK 并兑换回调」这件事**真的写在 index.html 里**，
//   而不是只写在 auth.js 里。
// 上一版失败的根因正是：auth.js 完全正确，但 index.html 根本不加载它 ⇒
//   回调落在根页面无人处理。所以只测 auth.js 的单元逻辑**不足以**防住这个回归。
//
// 手法：直接分析 index.html 源码 + 在最小 DOM 桩里执行它的那段内联脚本，
//   断言「带 code 时会依次注入 config → SDK → auth」。
// 负向变异：把注入列表清空，本测试必须变红（证明断言有牙齿）。

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const html = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8');
const inline = [...html.matchAll(/<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/g)].map(m => m[1]);
// ★ 锚点不能写死 `files = ['config.js'`（2026-11-24 · §4-557 踩到）：
//   给 config.js 加了缓存版本号后变成 `files = ['config.js?v=557j1iRP'`，
//   锚点失配 ⇒ boot 抽成空串 ⇒ A 组全红，看起来像"产品坏了"，其实是**测试装置
//   跟改动脱节**。⇒ 锚点改为匹配"赋值给 files 的那个数组"，与数组内容解耦。
const boot = inline.find(s => /files\s*=\s*\[[^\]]*config\.js/.test(s)) || '';

let pass = 0, fail = 0;
const rows = [];
function rec(n, ok, d) {
  if (ok) pass++; else fail++;
  rows.push(`${ok ? 'PASS' : 'FAIL'}  ${n}${d !== undefined ? '   [' + String(d).slice(0, 90) + ']' : ''}`);
}

// ── A. 源码级断言：这段逻辑必须存在且形状正确 ──
rec('A1 index.html 含回调处理脚本块', boot.length > 0, boot.length + ' chars');
rec('A2 按 code/error 判定回调', /sp\.has\('code'\)[\s\S]{0,60}sp\.has\('error'\)/.test(boot));
rec('A3 注入列表含 config.js', /files\s*=\s*\[[^\]]*config\.js/.test(boot));
rec('A4 注入列表含 SDK', /files\s*=\s*\[[^\]]*wbcs-sdk\.global\.js[^\]]*\]/.test(boot));
rec('A5 注入列表含 auth.js', /files\s*=\s*\[[^\]]*auth\.js/.test(boot));
// ★ 新增 A5b：config.js 必须带缓存版本号（§4-557）。
//   不带的话浏览器可能继续用**缓存里的旧 config.js** —— 那里面还是另一个应用
//   的 key，于是"改了没生效"，表现与没改完全相同。这类问题极易被误判成"改错了"。
rec('A5b config.js 带缓存版本号（防读到旧 key）',
  /config\.js\?v=/.test(boot), (boot.match(/config\.js\?v=[\w.]+/) || ['无'])[0]);
rec('A6 顺序：config 在 SDK 之前',
  boot.indexOf('config.js') < boot.indexOf('wbcs-sdk.global.js'));
rec('A7 顺序：SDK 在 auth 之前',
  // ★ 不能用裸 indexOf('auth.js')（§4-557）：config.js 带版本号后，
  //   `auth.js` 可能先出现在别的地方；且 config 段含 `?v=` 会干扰定位。
  //   改为在"注入数组"那一段里比位置。
  (function () {
    const arr = boot.match(/files\s*=\s*\[([^\]]*)\]/);
    if (!arr) return false;
    const s = arr[1];
    return s.indexOf('wbcs-sdk.global.js') !== -1 &&
           s.indexOf('auth.js') !== -1 &&
           s.indexOf('wbcs-sdk.global.js') < s.indexOf('auth.js');
  })());
rec('A8 成功后 location.replace 回跳', /r === 'callback-ok'/.test(boot) && /location\.replace/.test(boot));
rec('A9 失败时显示原因（不静默）', /showFail/.test(boot));

// ── B. 用最小 DOM 桩真实执行这段脚本，验证注入序列 ──
function runBoot(scriptSrc, searchStr, mut) {
  const injected = [];
  let curUrl = new URL('https://app.test/' + searchStr);
  const sandbox = {
    console, URL, URLSearchParams, Promise, setTimeout,
    __injected: injected,
    __readyState: 'complete',
  };
  sandbox.window = sandbox;
  sandbox.location = {
    get href() { return curUrl.toString(); },
    get search() { return curUrl.search; },
    get pathname() { return curUrl.pathname; },
    get hash() { return curUrl.hash; },
    replace(u) { sandbox.__replaced = u; },
    assign(u) { sandbox.__replaced = u; },
  };
  sandbox.history = { replaceState(_a, _b, u) { curUrl = new URL(u, curUrl); } };
  sandbox.document = {
    readyState: 'complete',
    head: {
      appendChild(el) {
        injected.push(el.src);
        // 立刻模拟加载回调（本轮只关心"注入了哪些、什么顺序"）
        if (el.onload) setTimeout(() => el.onload(), 0);
      },
    },
    body: { appendChild(el) { (sandbox.__alerts = sandbox.__alerts || []).push(el.textContent); } },
    createElement() { return { style: {}, setAttribute() {}, textContent: '' }; },
    addEventListener(ev, fn) { if (ev === 'DOMContentLoaded') fn(); },
  };
  // 供 exchange() 使用
  sandbox.YueshengAuth = {
    async dispatchCallback() { return mut && mut.cbResult ? mut.cbResult : 'callback-ok'; },
    nextLocation() { return 'diagnose.html?sharecode=SC'; },
    lastError() { return 'stub_error'; },
  };

  vm.createContext(sandbox);
  vm.runInContext(scriptSrc, sandbox);
  return sandbox;
}

(async () => {
  // B1 无回调参数 ⇒ 不得注入任何脚本
  {
    const s = runBoot(boot, '?sharecode=SC');
    await new Promise(r => setTimeout(r, 30));
    rec('B1 无回调 → 零注入（官网访客零开销）', s.__injected.length === 0, JSON.stringify(s.__injected));
  }
  // B2 有 code ⇒ 依次注入三件，且顺序正确
  {
    const s = runBoot(boot, '?code=c&state=s&provider=workbuddy&sharecode=SC');
    await new Promise(r => setTimeout(r, 120));
    // ★ 先剥查询串再取文件名（§4-557）：config.js 带了 `?v=` 缓存版本号，
    //   直接 split('/') 会得到 `config.js?v=557j1iRP` ⇒ 精确比较必然失败。
    //   ⇒ 判据比较的是"哪个脚本"，不应被缓存参数影响；版本号另有 A5b 单独守。
    const names = s.__injected.map(x => x.split('/').pop().split('?')[0]);
    rec('B2 有回调 → 注入 3 个脚本', s.__injected.length === 3, names.join(' → '));
    rec('B3 注入顺序 config → sdk → auth',
      names[0] === 'config.js' && names[1] === 'wbcs-sdk.global.js' && names[2] === 'auth.js',
      names.join(' → '));
    rec('B4 兑换成功后回跳', String(s.__replaced || '').indexOf('diagnose.html') !== -1, s.__replaced);
  }
  // B5 只有 error ⇒ 不注入脚本，只提示
  {
    const s = runBoot(boot, '?error=access_denied&error_description=nope');
    await new Promise(r => setTimeout(r, 60));
    rec('B5 只有 error → 不注入脚本', s.__injected.length === 0, JSON.stringify(s.__injected));
    const alerts = s.__alerts || [];
    rec('B6 只有 error → 显示提示文案', alerts.length > 0 && /登录未完成/.test(alerts[0] || ''), (alerts[0] || '').slice(0, 50));
  }
  // B7 兑换失败 ⇒ 显示失败原因，且不静默
  {
    const s = runBoot(boot, '?code=c&state=s&provider=workbuddy', { cbResult: 'callback-failed' });
    await new Promise(r => setTimeout(r, 120));
    const alerts = s.__alerts || [];
    rec('B7 兑换失败 → 显示原因', alerts.length > 0 && /登录没有完成/.test(alerts[0] || ''), (alerts[0] || '').slice(0, 60));
  }
  // B8 ★ 带 code 却换不出会话（SDK 返回空 ⇒ dispatchCallback 报 no-callback）
  //    必须提示，不能静默。这是 2026-11-24 线上实测假 code 时踩到的形态：
  //    地址栏挂着 code、页面毫无反应、用户完全不知道发生了什么。
  {
    const s = runBoot(boot, '?code=c&state=s&provider=workbuddy', { cbResult: 'no-callback' });
    await new Promise(r => setTimeout(r, 120));
    const alerts = s.__alerts || [];
    rec('B8 带 code 但无会话 → 必须提示（不静默）',
        alerts.length > 0, (alerts[0] || '(无提示)').slice(0, 60));
    rec('B8b 提示文案说清是授权码问题',
        /授权码/.test(alerts[0] || ''), (alerts[0] || '').slice(0, 60));
  }

  // ── C. 负向变异：证明上面的断言有牙齿 ──
  // 把注入列表改成空数组 —— 等价于"上一版"（根页面不加载 SDK）。
  // 若 B2 类断言仍绿，说明它根本没在检查东西。
  {
    const mutated = boot.replace(/files\s*=\s*\[[^\]]*\]/, 'files = []');
    rec('C1 变异体确实改动了源码', mutated !== boot);
    const s = runBoot(mutated, '?code=c&state=s&provider=workbuddy');
    await new Promise(r => setTimeout(r, 120));
    const injectedCount = s.__injected.length;
    rec('C2 变异体（不加载 SDK）下注入数为 0 ⇒ 原断言能变红', injectedCount === 0, injectedCount);
    rec('C3 故 B2 的 PASS 不是恒真', injectedCount !== 3);
  }

  console.log(rows.join('\n'));
  console.log(`\n=== PASS ${pass} / FAIL ${fail} ===`);
  process.exit(fail === 0 ? 0 : 1);
})().catch(e => { console.error('EXC', e && e.stack || e); process.exit(2); });