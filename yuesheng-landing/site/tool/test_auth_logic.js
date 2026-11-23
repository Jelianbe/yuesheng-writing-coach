// auth.js 纯逻辑单元测试（node 环境，最小 DOM 桩）
// 为什么在 node 里测：待验的是**分支逻辑**（三分支分发、redirectTo 构造、开放重定向防护），
// 这些不依赖真实浏览器渲染。而平台兑换本身官方明说 localhost 不可验，故不在此范围。

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const src = fs.readFileSync(path.join(__dirname, '..', 'js', 'auth.js'), 'utf8');

let pass = 0, fail = 0;
const rows = [];
function rec(name, ok, detail) {
  if (ok) pass++; else fail++;
  rows.push(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail !== undefined ? '   [' + String(detail).slice(0, 90) + ']' : ''}`);
}

function makeEnv(opts) {
  opts = opts || {};
  const search = opts.search || '';
  let curUrl = new URL('https://app.test/' + (opts.page || '') + search);
  const store = Object.assign({}, opts.session || {});

  const sandbox = {
    console,
    URL,
    URLSearchParams,
    setTimeout,
    Promise,
    // 页面配置
    WB_CONFIG: opts.config === undefined ? {
      endpoint: 'https://app.test/wbproxy',
      publishableKey: 'wbpk_x',
      oauthRelayBaseUrl: 'https://relay.test/oauth',
    } : opts.config,
    // SDK 桩
    WorkBuddyCloud: opts.noSDK ? undefined : {
      createWorkBuddyCloud() {
        return {
          auth: {
            async getSession() { return opts.sessionResult || { data: null, error: null }; },
            async signInWithOAuth(o) {
              sandbox.__signInArg = o;
              return { data: { url: 'https://platform.test/auth?x=1' }, error: null };
            },
            async handleWorkBuddyCallback() {
              const m = opts.cbMode || 'ok';
              if (m === 'ok') return { data: { accessToken: 'tok', refreshToken: 'r', expiresAt: 9e15, user: { id: 'u' } }, error: null };
              if (m === 'err') return { data: null, error: { message: '授权被拒绝' } };
              if (m === 'null') return { data: null, error: null };
              throw new Error('网络爆炸');
            },
            async signOut() { return { data: null, error: null }; },
          },
        };
      },
    },
    __navCalls: [],
  };

  sandbox.window = sandbox;
  sandbox.location = {
    get href() { return curUrl.toString(); },
    get search() { return curUrl.search; },
    get pathname() { return curUrl.pathname; },
    get hash() { return curUrl.hash; },
    assign(u) { sandbox.__navCalls.push(u); },
    replace(u) { sandbox.__navCalls.push(u); },
  };
  sandbox.history = {
    replaceState(_s, _t, u) {
      const nu = new URL(u, curUrl);
      curUrl = nu;
    },
  };
  sandbox.sessionStorage = {
    getItem(k) { return Object.prototype.hasOwnProperty.call(store, k) ? store[k] : null; },
    setItem(k, v) { store[k] = String(v); },
    removeItem(k) { delete store[k]; },
  };
  sandbox.__store = store;
  sandbox.__getUrl = () => curUrl.toString();

  vm.createContext(sandbox);
  vm.runInContext(src, sandbox);
  return sandbox;
}

(async () => {
  // ── L: signIn 的关键约束 ──
  {
    const env = makeEnv({ page: 'diagnose.html', search: '?sharecode=SC&from=ut' });
    const A = env.YueshengAuth;
    rec('L0 auth.js 加载并暴露 YueshengAuth', !!A);

    const rd = A._debug.buildRedirectTo();
    const u = new URL(rd);
    rec('L1 redirectTo 是站点根（pathname=/）', u.pathname === '/', u.pathname);
    rec('L2 redirectTo 保留 sharecode', u.searchParams.get('sharecode') === 'SC', u.search);
    rec('L3 redirectTo 保留 from', u.searchParams.get('from') === 'ut');

    // 带回调参数时，redirectTo 必须剥掉 code/state/provider（防旧 code 撞车）
    const env2 = makeEnv({ page: 'diagnose.html', search: '?code=old&state=old&provider=workbuddy&sharecode=SC' });
    const u2 = new URL(env2.YueshengAuth._debug.buildRedirectTo());
    rec('L4 redirectTo 剥掉 code', u2.searchParams.get('code') === null);
    rec('L5 redirectTo 剥掉 state', u2.searchParams.get('state') === null);
    rec('L6 redirectTo 剥掉 provider', u2.searchParams.get('provider') === null);
    rec('L7 redirectTo 仍保留 sharecode', u2.searchParams.get('sharecode') === 'SC');

    // signIn 实际入参
    await A.signIn();
    rec('L8 signIn 传 provider=workbuddy', env.__signInArg.provider === 'workbuddy', env.__signInArg.provider);
    rec('L9 signIn 传入 redirectTo', !!env.__signInArg.redirectTo);
    rec('L10 signIn 用同标签页 assign（非 window.open）',
        env.__navCalls.length === 1 && env.__navCalls[0].indexOf('platform.test') !== -1, env.__navCalls[0]);
    rec('L11 signIn 记下了回跳目标', env.__store.ys_login_next === 'diagnose.html?sharecode=SC&from=ut',
        env.__store.ys_login_next);
  }

  // ── D: 三分支分发 ──
  {
    // D0 无回调
    const e0 = makeEnv({ page: 'index.html', search: '?sharecode=SC' });
    const r0 = await e0.YueshengAuth.dispatchCallback();
    rec('D0 无 code/error → no-callback', r0 === 'no-callback', r0);
  }
  {
    // D1 成功
    const e = makeEnv({ page: 'index.html', search: '?code=c1&state=s1&provider=workbuddy&sharecode=SC', cbMode: 'ok' });
    const r = await e.YueshengAuth.dispatchCallback();
    rec('D1 code+成功 → callback-ok', r === 'callback-ok', r);
    // ★ 断言口径修正：不能用 indexOf('code=') —— `sharecode=SC` 里同样含 "code="
    //   子串（第 2 次踩这个坑：上一批 grep -c 数行 vs 数处也是同族）。
    //   必须用 URLSearchParams 取**参数名**，而不是在字符串里找子串。
    const su1 = new URL(e.__getUrl()).searchParams;
    rec('D1b 成功态清掉 code 参数', su1.get('code') === null && !su1.has('code'), su1.toString());
    rec('D1b2 成功态清掉 state 参数', !su1.has('state'));
    rec('D1b3 成功态清掉 provider 参数', !su1.has('provider'));
    rec('D1c 成功态保留 sharecode', su1.get('sharecode') === 'SC', su1.toString());
  }
  {
    // D2 错误
    const e = makeEnv({ page: 'index.html', search: '?code=c2&state=s2&provider=workbuddy', cbMode: 'err' });
    const r = await e.YueshengAuth.dispatchCallback();
    rec('D2 code+平台报错 → callback-error', r === 'callback-error', r);
    rec('D2b lastError 带平台原因', /授权被拒绝/.test(e.YueshengAuth.lastError()), e.YueshengAuth.lastError());
  }
  {
    // D3 空结果（已消费 code）
    const e = makeEnv({ page: 'index.html', search: '?code=c3&state=s3&provider=workbuddy', cbMode: 'null' });
    const r = await e.YueshengAuth.dispatchCallback();
    rec('D3 code+空结果 → no-callback（重复回调安全）', r === 'no-callback', r);
  }
  {
    // D4 兑换抛错
    const e = makeEnv({ page: 'index.html', search: '?code=c4&state=s4&provider=workbuddy', cbMode: 'throw' });
    const r = await e.YueshengAuth.dispatchCallback();
    rec('D4 兑换异常 → callback-failed', r === 'callback-failed', r);
    rec('D4b lastError 记录异常', /网络爆炸/.test(e.YueshengAuth.lastError()), e.YueshengAuth.lastError());
  }
  {
    // D5 只有 error 无 code
    const e = makeEnv({ page: 'index.html', search: '?error=access_denied&error_description=nope' });
    const r = await e.YueshengAuth.dispatchCallback();
    rec('D5 只有 error → 不当普通访问', r !== 'no-callback', r);
  }
  {
    // D6 非 workbuddy provider
    const e = makeEnv({ page: 'index.html', search: '?code=c6&state=s6&provider=wechat' });
    const r = await e.YueshengAuth.dispatchCallback();
    rec('D6 其他 provider → callback-error', r === 'callback-error', r);
  }
  {
    // D7 SDK 缺失：不能静默当作"没有回调"
    const e = makeEnv({ page: 'index.html', search: '?code=c7&state=s7&provider=workbuddy', noSDK: true });
    const r = await e.YueshengAuth.dispatchCallback();
    rec('D7 SDK 缺失 → callback-failed（非静默）', r === 'callback-failed', r);
  }
  {
    // D8 config 缺失
    const e = makeEnv({ page: 'index.html', search: '?code=c8&state=s8&provider=workbuddy', config: null });
    const r = await e.YueshengAuth.dispatchCallback();
    rec('D8 config 缺失 → callback-failed（非静默）', r === 'callback-failed', r);
    rec('D8b 且 lastError=config_missing', e.YueshengAuth.lastError() === 'config_missing', e.YueshengAuth.lastError());
  }

  // ── S: getSession 口径 ──
  {
    const e = makeEnv({});
    const s = await e.YueshengAuth.getSession();
    rec('S1 无会话 → null（不是假绿）', s === null, s);
  }
  {
    const e = makeEnv({ sessionResult: { data: { accessToken: 'tok' }, error: null } });
    const s = await e.YueshengAuth.getSession();
    rec('S2 有 accessToken → 返回会话', !!(s && s.accessToken), s && s.accessToken);
  }
  {
    // 关键负例：data 是空对象但没有 accessToken —— 上一版会假绿的形态
    const e = makeEnv({ sessionResult: { data: {}, error: null } });
    const s = await e.YueshengAuth.getSession();
    rec('S3 data={} 无 accessToken → null（防假绿）', s === null, JSON.stringify(s));
  }
  {
    const e = makeEnv({ sessionResult: { data: null, error: { message: 'x' } } });
    const s = await e.YueshengAuth.getSession();
    rec('S4 error 且无 data → null', s === null, JSON.stringify(s));
  }

  // ── N: 回跳目标的白名单（防开放重定向）──
  {
    const cases = [
      ['https://evil.com/x', false, '外部 URL'],
      ['//evil.com/x', false, '协议相对'],
      ['../../etc/passwd', false, '路径穿越'],
      ['javascript:alert(1)', false, 'js 伪协议'],
      ['diagnose.html', true, '合法相对页'],
      ['diagnose.html?sharecode=SC', true, '带参数合法页'],
      ['dashboard.html', true, '另一合法页'],
    ];
    for (const [val, shouldAccept, label] of cases) {
      const e = makeEnv({ session: { ys_login_next: val } });
      const got = e.YueshengAuth.nextLocation();
      const accepted = got === val;
      rec(`N ${label} ${shouldAccept ? '应接受' : '应拒绝'}`, accepted === shouldAccept, got);
    }
    // 也验证：取用后即清除（防重复跳）
    const e2 = makeEnv({ session: { ys_login_next: 'diagnose.html' } });
    e2.YueshengAuth.nextLocation();
    rec('N8 nextLocation 取用后清除', e2.__store.ys_login_next === undefined, e2.__store.ys_login_next);
    // 默认值
    const e3 = makeEnv({});
    rec('N9 无记录 → 默认 diagnose.html', e3.YueshengAuth.nextLocation() === 'diagnose.html', e3.YueshengAuth.nextLocation());
  }

  console.log(rows.join('\n'));
  console.log(`\n=== PASS ${pass} / FAIL ${fail} ===`);
  process.exit(fail === 0 ? 0 : 1);
})().catch(e => { console.error('EXC', e); process.exit(2); });