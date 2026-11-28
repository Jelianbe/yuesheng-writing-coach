// auth.js 纯逻辑单元测试（node 环境，最小 DOM 桩）
// 为什么在 node 里测：待验的是**分支逻辑**（三分支分发、redirectTo 构造、开放重定向防护），
// 这些不依赖真实浏览器渲染。而平台兑换本身官方明说 localhost 不可验，故不在此范围。

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const src = fs.readFileSync(path.join(__dirname, '..', 'js', 'auth.js'), 'utf8');

let pass = 0, fail = 0;
const rows = [];
// 与下面默认 WB_CONFIG 的 publishableKey 一致。SDK 的 verifier 键名由它派生，
// 桩与断言必须共用同一个常量，各写一份字面量迟早漂移。
const WBKEY = 'wbpk_x';
const VK = 'workbuddy-cloud.pkce.workbuddy.' + WBKEY;   // SDK 的 verifier 键名
const MK = VK + '.ysmirror';                            // §4-559 镜像键名
function rec(name, ok, detail) {
  if (ok) pass++; else fail++;
  rows.push(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail !== undefined ? '   [' + String(detail).slice(0, 90) + ']' : ''}`);
}

function makeEnv(opts) {
  opts = opts || {};
  const search = opts.search || '';
  let curUrl = new URL('https://app.test/' + (opts.page || '') + search);
  const store = Object.assign({}, opts.session || {});
  // ★ §4-559：必须**独立**的 localStorage 桩。
  //   原来的 harness 只有 sessionStorage，所以「verifier 跨上下文丢失」这个
  //   缺陷在测试里**结构上不可能被发现** —— 缺哪个上下文，就测不到哪个上下文。
  //   localStore 与 store 刻意分开：验证"回填"必须是真的跨存储搬运，
  //   若两者共用同一对象，回填断言会恒真（假绿）。
  const localStore = Object.assign({}, opts.local || {});

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
              // ★ §4-559：复现真机症状 —— SDK 只在 sessionStorage 找 verifier，
              //   找不到就**一个请求都不发**直接报错。桩必须照这个语义写，
              //   否则「回填缺失」在测试里永远看不见（桩比产品宽容 = 假绿）。
              const vk = 'workbuddy-cloud.pkce.workbuddy.' + (WBKEY);
              if (!sandbox.sessionStorage.getItem(vk)) {
                return { data: null, error: { message:
                  'workbuddy callback has no local PKCE verifier; sign in again in this tab' } };
              }
              // 消费掉（真实 SDK 读后立刻 clearVerifier）
              sandbox.sessionStorage.removeItem(vk);
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
  sandbox.localStorage = {
    getItem(k) { return Object.prototype.hasOwnProperty.call(localStore, k) ? localStore[k] : null; },
    setItem(k, v) { localStore[k] = String(v); },
    removeItem(k) { delete localStore[k]; },
  };
  sandbox.__store = store;
  sandbox.__localStore = localStore;
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
    const e = makeEnv({ page: 'index.html', search: '?code=c1&state=s1&provider=workbuddy&sharecode=SC', cbMode: 'ok', session: { [VK]: 'vf' } });
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
    const e = makeEnv({ page: 'index.html', search: '?code=c2&state=s2&provider=workbuddy', cbMode: 'err', session: { [VK]: 'vf' } });
    const r = await e.YueshengAuth.dispatchCallback();
    rec('D2 code+平台报错 → callback-error', r === 'callback-error', r);
    rec('D2b lastError 带平台原因', /授权被拒绝/.test(e.YueshengAuth.lastError()), e.YueshengAuth.lastError());
  }
  {
    // D3 空结果（已消费 code）
    const e = makeEnv({ page: 'index.html', search: '?code=c3&state=s3&provider=workbuddy', cbMode: 'null', session: { [VK]: 'vf' } });
    const r = await e.YueshengAuth.dispatchCallback();
    rec('D3 code+空结果 → no-callback（重复回调安全）', r === 'no-callback', r);
  }
  {
    // D4 兑换抛错
    const e = makeEnv({ page: 'index.html', search: '?code=c4&state=s4&provider=workbuddy', cbMode: 'throw', session: { [VK]: 'vf' } });
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

  // ══════════════════════════════════════════════════════════════════════
  // P 组：PKCE verifier 跨上下文镜像（§4-559）
  // ══════════════════════════════════════════════════════════════════════
  // 【这一组要证明什么】
  //   真机报 no local PKCE verifier。SDK 只认 sessionStorage，而它是
  //   「顶层标签页 + 源」隔离的 ⇒ 发起与回跳不在同一顶层上下文时必然读不到。
  //   修复 = 发起时向 localStorage 抄一份，回调前缺则回填。
  //   下面 P1/P2 分别验「写入」和「回填」；P4 是**负向变异**：
  //   去掉回填后 P2 必须变红 —— 否则这条判据只是措辞，没有牙。
  {
    const VVAL = 'verifier_abc123';

    // P0：SDK 桩确实在模拟"只认 sessionStorage"——若这条不成立，后面全是假绿
    {
      // ★ 这里**故意两边都不给** verifier。目的不是测产品，而是测**桩本身**：
      //   若桩在"没有 verifier"时仍返回成功，那么后面所有 P 组断言都是假绿。
      //   （我第一版写错了：给了副本 ⇒ 修复生效 ⇒ 桩返回成功 ⇒ 这条判据失败。
      //     判据失败不等于产品坏，是我把"测桩"写成了"测产品"。）
      const e = makeEnv({ search: '?code=C&state=S&provider=workbuddy' });
      const r = await e.YueshengAuth.dispatchCallback();
      const err = e.YueshengAuth.lastError() || '';
      rec('P0 桩的语义 = 只认 sessionStorage（无回填时会报 no local PKCE verifier）',
          r !== 'callback-ok' && /no local PKCE verifier/.test(err),
          'r=' + r + ' err=' + err.slice(0, 48));
    }

    // P1：signIn 必须把 verifier 镜像到 localStorage
    {
      const e = makeEnv({ page: 'diagnose.html' });
      // 模拟 SDK 已经在 sessionStorage 写了 verifier
      e.__store[VK] = VVAL;
      await e.YueshengAuth.signIn();
      const raw = e.__localStore[MK];
      let parsed = null;
      try { parsed = JSON.parse(raw || 'null'); } catch (_) {}
      rec('P1 signIn 把 verifier 镜像写入 localStorage', !!parsed && parsed.v === VVAL,
          raw ? String(raw).slice(0, 40) : 'null');
      rec('P1b 镜像带时间戳（供 TTL 判断）', !!parsed && typeof parsed.t === 'number', parsed && parsed.t);
      rec('P1c signIn 仍然同标签页跳转（未改成 window.open）', e.__navCalls.length === 1, e.__navCalls.join(','));
    }

    // P2：★ 核心 —— 回跳时 sessionStorage 为空、localStorage 有副本 ⇒ 必须救回来
    {
      const e = makeEnv({
        search: '?code=C&state=S&provider=workbuddy',
        local: { [MK]: JSON.stringify({ v: VVAL, t: Date.now() }) },
      });
      const r = await e.YueshengAuth.dispatchCallback();
      const p = e.YueshengAuth.probe();
      rec('P2 跨上下文回跳：靠镜像副本兑换成功', r === 'callback-ok', 'r=' + r);
      rec('P2b probe 报出 pkceSource=restored（坐实跨上下文）', p.pkceSource === 'restored', p.pkceSource);
    }

    // P3：副本过期（超 TTL）不得被使用
    {
      const e = makeEnv({
        search: '?code=C&state=S&provider=workbuddy',
        local: { [MK]: JSON.stringify({ v: VVAL, t: Date.now() - 11 * 60 * 1000 }) },
      });
      const r = await e.YueshengAuth.dispatchCallback();
      const p = e.YueshengAuth.probe();
      rec('P3 过期副本不回填（不复活旧 proof）', r !== 'callback-ok' && p.pkceSource === 'stale',
          'r=' + r + ' src=' + p.pkceSource);
    }

    // P4：同标签页正常路径不受影响（sessionStorage 有值时不走镜像）
    {
      const e = makeEnv({
        search: '?code=C&state=S&provider=workbuddy',
        session: { [VK]: VVAL },
      });
      const r = await e.YueshengAuth.dispatchCallback();
      const p = e.YueshengAuth.probe();
      rec('P4 同标签页正常路径仍然成功', r === 'callback-ok', 'r=' + r);
      rec('P4b 且 pkceSource=session（未误报为 restored）', p.pkceSource === 'session', p.pkceSource);
    }

    // P5：兑换成功后两边都清，不留长尾
    {
      const e = makeEnv({
        search: '?code=C&state=S&provider=workbuddy',
        local: { [MK]: JSON.stringify({ v: VVAL, t: Date.now() }) },
      });
      await e.YueshengAuth.dispatchCallback();
      rec('P5 成功后清掉镜像', e.__localStore[MK] === undefined, e.__localStore[MK]);
      rec('P5b 成功后清掉 sessionStorage 里的 verifier', e.__store[VK] === undefined, e.__store[VK]);
    }

    // P7：★ 上下文对照 —— 写入侧 iframe vs 读取侧 iframe
    //   这是「跨上下文」从假设变证据的那条判据：
    //   镜像里记了写入时的 inIframe，probe 拿它与当前值对比。
    {
      // 模拟：写入时在 iframe 里（inIframe:true），现在读的时候也在 iframe（同）
      const e = makeEnv({
        search: '?code=C&state=S&provider=workbuddy',
        local: { [MK]: JSON.stringify({ v: VVAL, t: Date.now(), inIframe: false }) },
      });
      // ★ 注意：probe() **只读**，它不会触发回填。所以必须先跑 dispatchCallback，
      //   再读 probe —— 这一点本身值得钉住：若哪天有人让 probe 产生副作用，
      //   "检测"就会改变被检测的状态（观测污染）。
      const before = e.YueshengAuth.probe();
      rec('P7 probe 是纯只读（未回填时 mirror 为空）',
          !before.mirror, before.mirror && 'has-mirror');

      await e.YueshengAuth.dispatchCallback();
      const after = e.YueshengAuth.probe();
      rec('P7b 回填后可读到写入侧上下文（mirror.inIframe）',
          !!after.mirror && after.mirror.inIframe === false,
          after.mirror && String(after.mirror.inIframe));
      // 沙箱里 window.top === window.self ⇒ 读取侧 inIframe=false；
      // 写入侧也是 false ⇒ 未发生上下文切换
      rec('P7c contextSwitched 比对真实（两侧一致时为 false，不是恒 null）',
          after.contextSwitched === false, String(after.contextSwitched));
    }

    // P7d：★ 真正跨上下文时 contextSwitched 必须为 true
    //   做法：镜像里写 inIframe:true（假装当初在 iframe 里登录），
    //   而当前沙箱 window.top===window.self（读取侧 false）⇒ 必须报 true。
    //   这条是 P7c 的对照：若 contextSwitched 恒为 false/null，它就变成空话。
    {
      const e = makeEnv({
        search: '?code=C&state=S&provider=workbuddy',
        local: { [MK]: JSON.stringify({ v: VVAL, t: Date.now(), inIframe: true }) },
      });
      await e.YueshengAuth.dispatchCallback();
      const p = e.YueshengAuth.probe();
      rec('P7d 跨上下文时 contextSwitched=true（判据不是恒 false）',
          p.contextSwitched === true, String(p.contextSwitched));
    }

    // P6：resetLocal 必须也清镜像（否则"重置"后仍留旧 proof）
    {
      const e = makeEnv({
        local: { [MK]: JSON.stringify({ v: VVAL, t: Date.now() }) },
        session: { [VK]: VVAL },
      });
      e.YueshengAuth.resetLocal();
      rec('P6 resetLocal 清掉镜像', e.__localStore[MK] === undefined, e.__localStore[MK]);
      rec('P6b resetLocal 清掉 sessionStorage verifier', e.__store[VK] === undefined, e.__store[VK]);
    }
  }

  console.log(rows.join('\n'));
  console.log(`\n=== PASS ${pass} / FAIL ${fail} ===`);
  process.exit(fail === 0 ? 0 : 1);
})().catch(e => { console.error('EXC', e); process.exit(2); });