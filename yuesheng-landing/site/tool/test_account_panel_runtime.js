// test_account_panel_runtime.js — 账号面板的**运行期行为**验证（§4-556）
//
// 【为什么不能只做源码断言】
//   源码里写了 `renderAccount()` 不等于它跑得通。这个项目已经栽过多次：
//   「代码看着对、页面不报错、就是不工作」（§4-553 三 const 静默失效）。
//   本测试用最小 DOM 桩把 diagnose.html 里那段真实代码**跑起来**，
//   断言点击/状态切换的**可观测结果**，而不是断言"字符串出现过"。
//
// 【与 test_account_panel.js 的分工】
//   - test_account_panel.js：静态契约（结构、顺序、单源、分支覆盖）
//   - 本文件：运行期行为（点开→有内容、已登录→出现退出、点外部→关闭）

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const SITE = path.join(__dirname, '..');
const diagHtml = fs.readFileSync(path.join(SITE, 'diagnose.html'), 'utf8');

let pass = 0, fail = 0;
function ok(name, cond, extra) {
  if (cond) { pass++; console.log('PASS  ' + name + (extra ? '   [' + extra + ']' : '')); }
  else { fail++; console.log('FAIL  ' + name + (extra ? '   [' + extra + ']' : '')); }
}

// ── 最小 DOM 桩：只实现本段代码真正用到的 API ──
function makeEl(tag, id) {
  const el = {
    tagName: (tag || 'div').toUpperCase(),
    id: id || '',
    _attrs: {}, _cls: new Set(), _kids: [], _listeners: {},
    _text: '', innerHTML: '', hidden: false, disabled: false, style: {}, dataset: {},
    setAttribute(k, v) { this._attrs[k] = String(v); },
    getAttribute(k) { return this._attrs[k]; },
    removeAttribute(k) { delete this._attrs[k]; },
    set textContent(v) { this._text = String(v); },
    get textContent() { return this._text; },
    classList: null,
    appendChild(c) { this._kids.push(c); return c; },
    addEventListener(t, fn) { (this._listeners[t] = this._listeners[t] || []).push(fn); },
    removeEventListener(t, fn) {
      const a = this._listeners[t] || [];
      const i = a.indexOf(fn); if (i >= 0) a.splice(i, 1);
    },
    contains(n) { return n === this || this._kids.indexOf(n) >= 0; },
    click() { (this._listeners['click'] || []).slice().forEach(fn => fn({ target: this, stopPropagation() {} })); },
    focus() {},
    querySelector() { return null; },
    querySelectorAll() { return []; },
  };
  el.classList = {
    add: c => el._cls.add(c), remove: c => el._cls.delete(c),
    contains: c => el._cls.has(c), toggle: c => el._cls.has(c) ? el._cls.delete(c) : el._cls.add(c),
  };
  return el;
}

const els = {};
['acctBtn', 'acctPop', 'acctBody', 'acctLabel', 'lgSignIn', 'lgErr', 'input', 'send', 'hint']
  .forEach(id => { els[id] = makeEl('div', id); });
els.acctPop.hidden = true;

const docListeners = {};
const document = {
  documentElement: makeEl('html'),
  body: makeEl('body'),
  readyState: 'complete',
  getElementById: id => els[id] || null,
  querySelector: () => null,
  querySelectorAll: () => [],
  createElement: t => makeEl(t),
  addEventListener(t, fn) { (docListeners[t] = docListeners[t] || []).push(fn); },
  removeEventListener(t, fn) {
    const a = docListeners[t] || []; const i = a.indexOf(fn); if (i >= 0) a.splice(i, 1);
  },
};

const sandbox = {
  document, console,
  setTimeout: (fn) => { try { fn(); } catch (_) {} },
  clearTimeout: () => {},
  localStorage: {
    _d: {},
    getItem(k) { return k in this._d ? this._d[k] : null; },
    setItem(k, v) { this._d[k] = String(v); },
    removeItem(k) { delete this._d[k]; },
    clear() { this._d = {}; },
  },
  sessionStorage: {
    _d: {},
    getItem(k) { return k in this._d ? this._d[k] : null; },
    setItem(k, v) { this._d[k] = String(v); },
    removeItem(k) { delete this._d[k]; },
  },
  location: { search: '', href: 'https://x/diagnose.html', pathname: '/diagnose.html', origin: 'https://x' },
  history: { replaceState() {} },
  URLSearchParams, URL, JSON, Math, Date, String, Object, Array, RegExp, Promise,
  navigator: { userAgent: 'node' },
};
sandbox.window = sandbox;
sandbox.globalThis = sandbox;
sandbox.WB_CONFIG = { publishableKey: 'wbpk_test', endpoint: 'https://x' };

// ── 抽出与账号面板相关的函数定义（renderAccount/escHtml/open/close/doSignOut/bind）──
function sliceFn(src, name) {
  const i = src.indexOf('function ' + name + '(');
  if (i < 0) return '';
  // 用花括号配对取完整函数体
  let depth = 0, started = false;
  for (let j = i; j < src.length; j++) {
    const c = src[j];
    if (c === '{') { depth++; started = true; }
    else if (c === '}') { depth--; if (started && depth === 0) return src.slice(i, j + 1); }
  }
  return '';
}

const FN = ['escHtml', 'renderAccount', 'openAccount', 'closeAccount', 'onDocClickForAcct', 'bindAccountEntry', 'acctEmail'];
let code = 'var gate = "needlogin"; var signedIn = false; var acctBtn=null,acctPop=null,acctBody=null,acctLabel=null;\n' +
           // ★ 必须忠实复刻真实 applyGate 的两件事：① 由 signedIn 重算 gate
           //   ② 再调 renderAccount。初版桩只写了 ②，漏了 ① ⇒ doSignOut 里
           //   applyGate 无法把 gate 翻回 needlogin ⇒ E1 假红。
           //   这与 §4-553 七「测试装置的错会伪装成产品缺陷」是同族错误。
           'function computeGate(){ return signedIn ? "ready" : "needlogin"; }\n' +
           'function applyGate(){ gate = computeGate(); if (typeof renderAccount === "function") renderAccount(); }\n' +
           'function showLoginError(){} \n';
FN.forEach(n => { const s = sliceFn(diagHtml, n); if (s) code += s + '\n'; });
// doSignOut 是 async
const dso = sliceFn(diagHtml, 'doSignOut');
code += (dso ? 'var doSignOut = async ' + dso.replace(/^async function doSignOut/, 'function doSignOut') + ';\n' : '');

const ctx = vm.createContext(sandbox);
try {
  vm.runInContext(code, ctx);
} catch (e) {
  console.log('!! 装载失败: ' + e.message);
  console.log('=== PASS 0 / FAIL 1 ===');
  process.exit(1);
}

// ── A. 未登录态 ──
vm.runInContext('gate="needlogin"; bindAccountEntry();', ctx);
ok('A1 未登录 → 按钮 data-state=out', els.acctBtn.getAttribute('data-state') === 'out',
   els.acctBtn.getAttribute('data-state'));
ok('A2 未登录 → 标签显示「未登录」', els.acctLabel.textContent === '未登录', els.acctLabel.textContent);
ok('A3 面板初始隐藏', els.acctPop.hidden === true);

// 点开
els.acctBtn.click();
ok('A4 点击后面板展开', els.acctPop.hidden === false);
ok('A5 展开后 aria-expanded=true', els.acctBtn.getAttribute('aria-expanded') === 'true');
ok('A6 未登录面板含「登录」动作', els.acctBody.innerHTML.indexOf('acctSignIn') !== -1);
ok('A7 未登录面板**不含**退出动作', els.acctBody.innerHTML.indexOf('acctSignOut') === -1);

// ── B. 已登录态 ──
vm.runInContext('gate="ready"; signedIn=true; renderAccount();', ctx);
ok('B1 已登录 → 按钮 data-state=in', els.acctBtn.getAttribute('data-state') === 'in',
   els.acctBtn.getAttribute('data-state'));
ok('B2 已登录 → 标签显示「已登录」', els.acctLabel.textContent === '已登录', els.acctLabel.textContent);
ok('B3 已登录面板含退出按钮', els.acctBody.innerHTML.indexOf('acctSignOut') !== -1);
ok('B4 已登录面板**不含**登录按钮', els.acctBody.innerHTML.indexOf('acctSignIn') === -1);
ok('B5 面板文案说明「记录仍在本机」（防误解退出会删数据）',
   els.acctBody.innerHTML.indexOf('不会因退出而删除') !== -1);

// ── C. 点外部关闭 ──
els.acctBtn.click(); // 再点一次 → 收起
ok('C1 再次点击按钮 → 面板收起', els.acctPop.hidden === true);

// ── D. Esc 关闭 ──
els.acctBtn.click();
ok('D1 展开后可被 Esc 关闭',
   (docListeners['keydown'] || []).length > 0);
(docListeners['keydown'] || []).forEach(fn => fn({ key: 'Escape' }));
ok('D2 Esc 后确实关闭', els.acctPop.hidden === true);

// ── E. ★ 退出登录：SDK 抛错也必须翻状态 ──
vm.runInContext('gate="ready"; signedIn=true; renderAccount();', ctx);
sandbox.YueshengAuth = {
  signOut: async function () { throw new Error('network down'); },
};
vm.runInContext('globalThis.__p = doSignOut();', ctx);
Promise.resolve(vm.runInContext('globalThis.__p', ctx)).then(function () {
  ok('E1 SDK 抛错时仍完成退出（不卡在「正在退出…」）', els.acctLabel.textContent === '未登录',
     els.acctLabel.textContent);
  const popHidden = els.acctPop.hidden;
  ok('E2 退出后面板关闭', popHidden === true);

  // 负向变异：把 catch 去掉，SDK 抛错就会中断 ⇒ E1 应变红
  const mutated = code.replace(/catch \(_\) \{\}/, 'catch (_) { throw _; }');
  const sandbox2 = Object.assign({}, sandbox);
  sandbox2.YueshengAuth = { signOut: async function () { throw new Error('x'); } };
  const ctx2 = vm.createContext(sandbox2);
  let mutatedThrew = false;
  try {
    vm.runInContext(mutated, ctx2);
    vm.runInContext('globalThis.__q = doSignOut();', ctx2);
    Promise.resolve(vm.runInContext('globalThis.__q', ctx2)).catch(() => { mutatedThrew = true; });
  } catch (_) { mutatedThrew = true; }
  setTimeout(function () {
    ok('E3 变异体（去掉 catch）确实会失败 ⇒ E1 不是恒真', mutatedThrew === true, 'threw=' + mutatedThrew);
    console.log('\n=== PASS ' + pass + ' / FAIL ' + fail + ' ===');
    process.exit(fail ? 1 : 0);
  }, 30);
});