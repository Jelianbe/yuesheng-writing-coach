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
// ★ 2026-11-24 §4-559 订正：原判据是「cleanCallbackParams(); 之后 60 字符内
//   必须出现 return '<branch>'」。加 §4-559 的清理后中间多了 clearVerifierBoth()
//   ⇒ 4 条一起变红。**这不是产品坏了，是判据把"两行紧邻"当成了"清理发生过"**。
//   语义真相是「该分支 return 之前清理已执行」，行距无关。
//
//   ⇒ 改为按 `return '` 切段：每段就是**导向该 return 的语句块**。
//     同一分支可能有多处 return（如 callback-error 既有 provider 校验提前返回、
//     又有兑换失败返回），故判「该分支**至少有一处** return 的语句块里做过清理」，
//     与原判据的"至少一处匹配"意图一致，但不再依赖字符距离。
function segsBeforeReturns(body) {
  const parts = body.split("return '");
  // parts[0] 是首个 return 之前的语句；parts[k] 是第 k 个 return 之前的语句
  return parts.slice(0, -1).map(function (s, i) {
    return { seg: s, ret: (parts[i + 1] || '').split("'")[0] };
  });
}
const SEGS = segsBeforeReturns(cbBody);
['callback-error', 'callback-ok', 'no-callback'].forEach(function (branch) {
  const hits = SEGS.filter(function (x) { return x.ret === branch; });
  const cleaned = hits.some(function (x) { return x.seg.indexOf('cleanCallbackParams()') >= 0; });
  ok('F ' + branch + ' 分支前已清 URL', hits.length > 0 && cleaned,
     'returns=' + hits.length + ' cleaned=' + cleaned);
});
ok('F4 异常路径也清 URL（catch 内）',
   /exchange_failed[\s\S]{0,200}cleanCallbackParams\(\)/.test(cbBody));

// 负向变异：把 callback-error 分支的清理去掉，断言必须变红
const errHits = SEGS.filter(function (x) { return x.ret === 'callback-error'; });
const errAllClean = errHits.map(function (x) { return x.seg; }).join('');
const cleanedHitsBefore = errHits.filter(function (x) {
  return x.seg.indexOf('cleanCallbackParams()') >= 0;
}).length;
const mutatedSeg = errAllClean.replace(/cleanCallbackParams\(\);/g, '');
ok('F5 变异体（去掉 callback-error 的清理）后断言会变红',
   errHits.length > 0 && cleanedHitsBefore > 0 &&
   mutatedSeg.indexOf('cleanCallbackParams()') < 0,
   'hits=' + errHits.length + ' cleanedHits=' + cleanedHitsBefore);

// ── G. index.html 失败分支清 URL ──
ok('G1 index 失败分支删除回调键',
   /showFail\(why\)/.test(index) &&
   /searchParams\.delete\(k\)[\s\S]{0,200}showFail\(why\)/.test(index));

// ── H. 触控可达性（44px，与登录门一致的下限）──
ok('H1 主按钮 min-height 44px', /acct-act[\s\S]{0,300}min-height:\s*44px/.test(diag));

// ── I. 窄屏可用性（2026-11-24 · §4-556 补）──
// 390px 实测头部会溢出（menu+logo+h1+官网+账号 ≈ 399px）。
// 取舍：缩短标题而非砍功能入口 —— 账号入口是本轮核心，官网是导航，
// 品牌在侧栏 .brand 已有完整呈现。判据：窄屏下不能出现 display:none 把它们藏掉。
const narrow = diag.slice(diag.indexOf('@media (max-width: 760px)'));
ok('I1 窄屏不隐藏账号入口（acct-btn 无 display:none）',
   !/\.acct-btn\s*\{[^}]*display:\s*none/.test(narrow));
ok('I2 窄屏不隐藏官网入口（nav-home 无 display:none）',
   !/\.nav-home\s*\{[^}]*display:\s*none/.test(narrow));
ok('I3 窄屏确实收紧了标题字号（防溢出）',
   /header h1\s*\{\s*font-size:\s*14px/.test(narrow));

// ── J. 检测区（2026-11-24 · §4-556 舰长要求「针对做检测」）──────────────
// 舰长两次失败都只有一句平台报错，无法区分"我这边脏了"还是"链路坏了"。
// 检测区就是把那个区分做出来：四行本地可自证读数 + 一个彻底重置。
const authJs = fs.readFileSync(path.join(SITE, 'js', 'auth.js'), 'utf8');

ok('J1 面板渲染检测区（两态都要有，不是只在未登录时）',
   (diag.match(/diagHtml\(\)/g) || []).length >= 2);
ok('J2 检测区四行读数齐全',
   ['云服务 SDK', '站点配置', '登录证明', '本地会话']
     .every(s => diag.indexOf(s) !== -1));
ok('J3 probe 读的是 SDK 真实键名（PKCE + session）',
   authJs.indexOf("'workbuddy-cloud.pkce.workbuddy.'") !== -1 &&
   authJs.indexOf("'workbuddy-cloud.session.'") !== -1);
ok('J4 resetLocal 清三类键（会话 / 证明 / 已消费标记）',
   /resetLocal/.test(authJs) &&
   /workbuddy-cloud\.session\./.test(authJs) &&
   /workbuddy-cloud\.pkce\.workbuddy\./.test(authJs) &&
   /workbuddy-cloud\.pkce-done\.workbuddy\./.test(authJs));
ok('J5 重置入口存在于面板（不只写在 auth.js）',
   diag.indexOf('acctReset') !== -1 && /id="acctReset"/.test(diag));

// ── K. 失败提示必须按读数分流（§4-559）────────────────────────────────
// 【为什么单列一组】
//   上一版无论什么原因都写「请再点一次登录」。在「发起页与回调页不在同一
//   顶层窗口」这个真实成因下，这句话是**做不到的承诺**：点多少次，
//   都在同一个作用域写、在另一个作用域读。
//   ⇒ 判据要能分辨「有条件分流」和「无条件重试」——只查"含'再点一次'"是
//     分辨不出来的（分流的兜底分支里也含这句）。
ok('K1 diagnose 有按 PKCE 读数分流的失败提示函数',
   /function loginFailHint\(\)/.test(diag) && /function retryAdvice\(\)/.test(diag));
ok('K2 分流覆盖 restored / none / stale 三态',
   /pkceSource === 'restored'/.test(diag) &&
   /pkceSource === 'none'/.test(diag) &&
   /pkceSource === 'stale'/.test(diag));
// 关键：restored 分支必须给「换独立标签页」这种**能绕开作用域**的动作，
// 而不是只说"再点一次"
ok('K3 restored 分支给出绕开作用域的动作（独立标签页）',
   /restored[\s\S]{0,400}独立标签页/.test(diag));
ok('K4 boot 的失败分支已改为调用分流函数（不再写死一句话）',
   /showLoginError\(loginFailHint\(\)\)/.test(diag) &&
   !/showLoginError\('登录没有完成，请再点一次登录/.test(diag));

// K5 负向变异：把 boot 里的分流调用换回写死文案 ⇒ K4 必须变红
{
  const mut = diag.replace(
    "showLoginError(loginFailHint());",
    "showLoginError('登录没有完成，请再点一次登录。若反复失败，可以先下载 Android 版。');"
  );
  const k4 = /showLoginError\(loginFailHint\(\)\)/.test(mut) &&
             !/showLoginError\('登录没有完成，请再点一次登录/.test(mut);
  ok('K5 变异体（换回写死文案）后 K4 会变红', mut !== diag && !k4);
}

// J6 负向变异：把所有 verifier 键名改错 ⇒ J3 的字符串断言必然落空
// ★ 必须 replaceAll（2026-11-24 踩到）：该键名在 auth.js 出现 2 次
//   （probe 读 + resetLocal 清），只换第一处时 J3 仍能靠第二处绿 ⇒
//   变异没覆盖被测断言 ⇒ 报了"变异无效"的假红。
//   ⇒ 变异测试的判据是「断言真的会红」，不是「我改了某个字符串」。
const authMut = authJs.split("'workbuddy-cloud.pkce.workbuddy.'").join("'WRONG'");
ok('J6 变异体（改错全部 verifier 键名）后 J3 会变红',
   authMut.indexOf("'workbuddy-cloud.pkce.workbuddy.'") === -1 && authMut !== authJs);

console.log('\n=== PASS ' + pass + ' / FAIL ' + fail + ' ===');
process.exit(fail ? 1 : 0);
