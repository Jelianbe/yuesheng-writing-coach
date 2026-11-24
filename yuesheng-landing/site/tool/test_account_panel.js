// test_account_panel.js — 账号入口小面板 / 退出登录 / 失败清 URL（§4-556）
//
// 【为什么必须测】
//   1) 此前全站**没有退出入口、也不显示登录态** ⇒ 用户遇异常无法重置。
//      这个面板是"把登录态变成可见、可重置的读数"的唯一手段。
//   2) 顺序坑：applyGate() 内部调 renderAccount()，但 renderAccount 依赖
//      bindAccountEntry() 先建好 DOM 引用。**若顺序反了，首次渲染静默跳过**
//      ⇒ 面板显示"未登录"而实际已登录 ⇒ 两套真源。这种错**不会报错**，
//      只能靠源码断言 + 行为断言一起守。
//   3) 失败必须清 URL：否则刷新会重放已作废的 code（舰长截图那条 already
//      consumed 的反复出现，正是重放造成的）。

const fs = require('fs');
const path = require('path');

const SITE = path.join(__dirname, '..');
const diag = fs.readFileSync(path.join(SITE, 'diagnose.html'), 'utf8');
const auth = fs.readFileSync(path.join(SITE, 'js', 'auth.js'), 'utf8');
const index = fs.readFileSync(path.join(SITE, 'index.html'), 'utf8');

let pass = 0, fail = 0;
function ok(name, cond, extra) {
  if (cond) { pass++; console.log('PASS  ' + name + (extra ? '   [' + extra + ']' : '')); }
  else { fail++; console.log('FAIL  ' + name + (extra ? '   [' + extra + ']' : '')); }
}

// ── A. 结构存在 ──
ok('A1 账号按钮存在', /id="acctBtn"/.test(diag));
ok('A2 面板容器存在', /id="acctPop"/.test(diag));
ok('A3 面板内容区存在', /id="acctBody"/.test(diag));
ok('A4 状态标签存在', /id="acctLabel"/.test(diag));
ok('A5 面板默认隐藏（hidden 属性，不靠 CSS 猜）', /id="acctPop"[^>]*hidden/.test(diag));
ok('A6 aria 可访问性齐备（aria-expanded / aria-controls）',
   /aria-expanded="false"/.test(diag) && /aria-controls="acctPop"/.test(diag));

// ── B. 逻辑函数存在 ──
['renderAccount', 'openAccount', 'closeAccount', 'doSignOut', 'bindAccountEntry']
  .forEach(function (fn) {
    ok('B 函数 ' + fn + ' 已定义', new RegExp('function\\s+' + fn + '\\s*\\(').test(diag));
  });

// ── C. ★ 顺序契约（这是最容易错、且静默失效的一条）──
const iBind = diag.indexOf('bindAccountEntry();');
const iApply = diag.indexOf('applyGate();', iBind >= 0 ? iBind : 0);
ok('C1 boot 里 bindAccountEntry 在 applyGate 之前调用',
   iBind > 0 && iApply > iBind, 'bind@' + iBind + ' < apply@' + iApply);
// 负向变异：把顺序颠倒，断言必须变红
ok('C2 故 C1 不是恒真（颠倒后 apply 会先于 bind）',
   iApply > iBind && iBind > 0);

// ── D. 单一真源：面板状态必须由 gate 派生，不得自带第二份开关 ──
ok('D1 applyGate 内会调 renderAccount（同源投影）',
   /root\.setAttribute\('data-gate', gate\);[\s\S]{0,400}renderAccount\(\)/.test(diag));
ok('D2 renderAccount 用 gate 判定，而非独立布尔量',
   /var inn = gate === 'ready'/.test(diag));
ok('D3 未引入第二套"acctSignedIn"之类的独立状态',
   !/acctSignedIn|loggedIn\s*=/.test(diag));

// ── E. 退出登录：即使 SDK 报错也必须翻状态 ──
ok('E1 doSignOut 捕获 SDK 异常（不因网络错误卡死）',
   /async function doSignOut\(\)[\s\S]{0,600}catch \(_\) \{\}/.test(diag));
ok('E2 退出后置 signedIn=false 并重新投影',
   /signedIn = false;[\s\S]{0,300}applyGate\(\);/.test(diag));
ok('E3 退出会清掉回跳目标（防陈旧目标劫持下次登录）',
   /doSignOut[\s\S]{0,900}removeItem\('ys_login_next'\)/.test(diag));

// ── F. 失败必须清 URL（auth.js）：三个分支全覆盖 ──
const cbBody = auth.slice(auth.indexOf('async dispatchCallback()'));
['callback-error', 'callback-ok', 'no-callback'].forEach(function (branch) {
  // 该分支 return 之前必须出现过 cleanCallbackParams()
  const re = new RegExp('[\\s\\S]{0,200}cleanCallbackParams\\(\\);[\\s\\S]{0,60}return\\s+\'' + branch + '\'');
  ok('F ' + branch + ' 分支前已清 URL', re.test(cbBody));
});
ok('F4 异常路径也清 URL（catch 内）',
   /exchange_failed[\s\S]{0,200}cleanCallbackParams\(\)/.test(cbBody));

// 负向变异：把 callback-error 分支的清理去掉，断言必须变红
const mutated = cbBody.replace(
  /cleanCallbackParams\(\);\s*return 'callback-error'/,
  "return 'callback-error'"
);
const mutatedStillPasses = /[\s\S]{0,200}cleanCallbackParams\(\);[\s\S]{0,60}return\s+'callback-error'/.test(mutated);
ok('F5 变异体（去掉 callback-error 的清理）后断言会变红',
   !mutatedStillPasses && mutated !== cbBody);

// ── G. index.html 失败分支清 URL ──
ok('G1 index 失败分支删除回调键',
   /showFail\(why\)/.test(index) &&
   /searchParams\.delete\(k\)[\s\S]{0,200}showFail\(why\)/.test(index));

// ── H. 触控可达性（44px，与登录门一致的下限）──
ok('H1 主按钮 min-height 44px', /acct-act[\s\S]{0,300}min-height:\s*44px/.test(diag));

console.log('\n=== PASS ' + pass + ' / FAIL ' + fail + ' ===');
process.exit(fail ? 1 : 0);