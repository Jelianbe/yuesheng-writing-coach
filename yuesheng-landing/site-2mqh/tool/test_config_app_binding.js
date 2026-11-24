// test_config_app_binding.js — 守住「config.js 的 key 必须属于站点所在应用」（§4-557）
//
// 【为什么必须有这个测试】
//   登录连续失败多轮，根因不是代码 bug，是**配置指向了另一个应用**：
//   站点部署域 `yuesheng-apk-test` 属于应用 j1iRP，而 config.js 写的是应用
//   2mqh 的 key，还把请求代理到 2mqh 的数据面（yuesheng-coach）。
//   ⇒ Relay 按本站域签发 state（记在 j1iRP 名下），兑换却被送到 2mqh 的数据面，
//     2mqh 从没见过这个 state ⇒ 只能答 `state parameter is invalid`。
//
// 【这个错误最难查的地方】
//   报错文本**没有分辨力**：用假 code + 假 state 打同一端点，返回一字不差。
//   所以「报错说什么」帮不上忙，真正的信息在**结构事实**里：
//   key 里的 applicationId == 站点域所属的 applicationId。
//   ⇒ 判据只能钉结构，不能钉报错文本。这就是本测试的存在理由。
//
// 【判据设计】
//   A 组：key 内嵌的 app id 必须与部署域所属应用一致（可从 genie 文件名独立得出）
//   B 组：endpoint 必须是站点自身域，**不得**再套跨应用的 /wbproxy
//   C 组：负向变异 —— 把 key 改回 2mqh，A1 必须变红（证明断言不是恒真）

const fs = require('fs');
const path = require('path');

const SITE = path.join(__dirname, '..');
let pass = 0, fail = 0;
function ok(name, cond, extra) {
  if (cond) { pass++; console.log('PASS  ' + name + (extra ? '   [' + extra + ']' : '')); }
  else { fail++; console.log('FAIL  ' + name + (extra ? '   [' + extra + ']' : '')); }
}

const cfg = fs.readFileSync(path.join(SITE, 'js', 'config.js'), 'utf8');
const srv = fs.readFileSync(path.join(SITE, 'server.py'), 'utf8');

// ── 取 config.js 的实值 ──
function pick(name) {
  const m = cfg.match(new RegExp(name + "\\s*:\\s*'([^']+)'"));
  return m ? m[1] : null;
}
const endpoint = pick('endpoint');
const key = pick('publishableKey');

ok('A0 能读出 endpoint 与 publishableKey', !!endpoint && !!key,
   'endpoint=' + endpoint + ' key=' + (key ? key.slice(0, 18) + '…' : 'null'));

// ── A. key 内嵌的 applicationId ──
// 平台 key 形如 wbpk_<applicationId>_<secret>（实测两个应用都是此形态）。
function appIdOf(k) {
  if (!k) return null;
  const m = k.match(/^wbpk_([A-Za-z0-9]+)_/);
  return m ? m[1] : null;
}
const keyApp = appIdOf(key);
ok('A1 key 内嵌应用 id 可解析', !!keyApp, 'app=' + keyApp);

// ── A2. 站点域所属应用：从部署产物 genie 文件名得出 ──
// ⚠️ 这里踩过一次：初版假设"仓库根只有一个 .wbapp_*.genie"，实测**有两个**
//   （两个应用各一个：2mqh 与 j1iRP）⇒ 取唯一文件的做法返回 null。
//   ⇒ 判据改为「按 endpoint 里的域名反查」，因为 genie 文件名只含 appId、
//     不含域名，无法直接映射。故用「候选集合 + 域名线索」两步：
//     ① 收集所有 .wbapp_*.genie 的 appId；
//     ② 站点域名 `yuesheng-apk-test` 对应的应用，必须在这批候选里
//        —— 且它必须**就是 config 里 key 的那个**（A3 的核心）。
//   另注：域名↔appId 的权威映射只能由平台查询（workbuddy_cloud_service
//   inspect / sites deploy 返回值）给出，测试无法自行推导 ⇒ 本测试把它作为
//   **已知事实**记录，并在漂移时报错（提醒人重新核对，而不是假装通过）。
const root = path.join(SITE, '..', '..');
let genieApps = [];
try {
  genieApps = fs.readdirSync(root)
    .filter(f => /^\.wbapp_.+\.genie$/.test(f))
    .map(f => f.replace(/^\.wbapp_/, '').replace(/\.genie$/, ''));
} catch (_) {}
ok('A2 能枚举到部署产物中的应用 id', genieApps.length > 0,
   'genieApps=' + JSON.stringify(genieApps));

// ★ 2026-11-24 §4-561 判据升级：原来把 SITE_APP 写死成 j1iRP，
//   站点副本迁到 2mqh 后 A3/B1 立刻误报——**判据把"本站是哪个应用"写死成了字面量**。
//   ⇒ 改为从**平台部署产物**动态推导：genie 标记里 localDir 指向本 SITE 的那个 appId。
//   仍是外部事实（平台写的标记），不是从 config.js 自证，避免循环论证。
//   localDir 的比较要归一化：genie 里是 Windows 反斜杠，__dirname 是 posix 风格。
function normDir(x) {
  return String(x || '')
    .split(String.fromCharCode(92)).join('/')   // 反斜杠 → 正斜杠（避开字面量转义）
    .replace(/\/+$/, '').toLowerCase();
}
const hereNorm = normDir(SITE);
let ownMarker = null, ownCount = 0;
try {
  genieApps.forEach(function (appId) {
    const mp = path.join(root, '.wbapp_' + appId + '.genie');
    const txt = fs.readFileSync(mp, 'utf8');
    const m = txt.match(/^localDir:\s*(.+)$/m);
    if (m && normDir(m[1]) === hereNorm) { ownMarker = appId; ownCount++; }
  });
} catch (_) {}
ok('A2c 本站有且仅有一个平台部署标记（防两个站点共用目录导致误判）',
   ownCount === 1, 'ownMarker=' + ownMarker + ' count=' + ownCount);
const SITE_APP = ownMarker;
// 域名 ↔ appId 映射：**平台查得的两个已知事实**（inspect/deploy 返回值），
// 不是从 config.js 自证。写全两条是为了让副本也能用，而不是放宽判据。
const HOST_OF = {
  'j1iRP0QdPV8ezelACqoC7y': 'yuesheng-apk-test.app.workbuddy.host',
  '2mqhpPIkw6lCf4kthBTrB0': 'yuesheng-coach.app.workbuddy.host'
};
const SITE_HOST = HOST_OF[SITE_APP] || '';
ok('A2b 站点域所属应用出现在部署产物中（防记录过期）',
   genieApps.indexOf(SITE_APP) !== -1,
   'want=' + SITE_APP + ' have=' + JSON.stringify(genieApps));

// ★ 核心断言：配置 key 的应用 == 站点域所属应用
ok('A3 配置 key 所属应用 == 站点域所属应用（错配即登录必失败）',
   !!keyApp && keyApp === SITE_APP,
   'key=' + keyApp + ' site=' + SITE_APP);

// ── B. endpoint 必须与站点域一致，且不套跨应用代理 ──
ok('B1 endpoint 指向站点自身域', !!endpoint && endpoint.indexOf(SITE_HOST) !== -1,
   endpoint);
ok('B2 endpoint 不再套 /wbproxy（那是跨应用代理，与本站 state 无关）',
   !!endpoint && endpoint.indexOf('/wbproxy') === -1, endpoint);

// B3 server.py 的代理目标若仍是另一个应用，必须显式标注为「已不再被前端使用」
//    —— 防止有人误以为它还在链路上，又去改它。
if (/UPSTREAM\s*=\s*'https:\/\/yuesheng-coach/.test(srv)) {
  ok('B3 遗留代理目标已标注"前端不再使用"',
     /不再被前端使用|前端不再使用|not used by the front end/.test(srv));
} else {
  ok('B3 代理目标已不是另一个应用（或已移除）', true);
}

// ── C. 负向变异：把 key 换成「另一个应用」⇒ A3 必须变红 ──
// ★ §4-561 订正：原写死 OLD_KEY=2mqh。站点副本迁到 2mqh 后，
//   "变异体"恰好等于本站 ⇒ C1/C2 误报 FAIL。**这是判据写死字面量的病，
//   不是产品坏**。改为从 HOST_OF 的动态键集里选一个 ≠ SITE_APP 的应用。
//   这才是 C 组真正要证明的：A3 钉的是"归属关系"，不是"某个特定字符串"。
const otherApp = Object.keys(HOST_OF).find(function (a) { return a !== SITE_APP; });
const MUT_KEY = otherApp
  ? 'wbpk_' + otherApp + '_MUTATION_PROBE'
  : null;
const mutApp = appIdOf(MUT_KEY);
ok('C1 变异体（key 换成另一个应用）下 A3 的判据会变红',
   !!mutApp && mutApp !== SITE_APP,
   'mutApp=' + mutApp + ' site=' + SITE_APP);
ok('C2 故 A3 的 PASS 不是恒真', !!mutApp && mutApp !== SITE_APP);

// ── D. 代价必须记录：切到本站应用后 AI 能力未开会 403 ──
// 这不是代码缺陷，是平台侧开关；但没有提示就会变成静默失败。
const diag = fs.readFileSync(path.join(SITE, 'diagnose.html'), 'utf8');
ok('D1 friendlyError 覆盖 capability_disabled（否则用户只看到错误码）',
   /capability_disabled/.test(diag) && /friendlyError/.test(diag));

// ★★ 2026-11-24 二次订正（§4-558）：判据反转。
//   原 D2 要求提示里出现「云服务」+「开启」——那等于**把一条未核实的点击路径
//   钉成了验收条件**，于是文案越错、测试越绿。
//   实测：官方《云服务》文档列出的能力只有 数据库/身份认证/文件存储/数据统计，
//   **AI 不在其中** ⇒「去云服务页开启 AI」这条路我并没有证据。
//   ⇒ 新判据：① 必须出现"开通"（说明这是能力开关问题，不是代码问题）；
//             ② **不得**再把用户指向那个未核实的路径（出现"数据管理"+“云服务”
//                的组合即判红）。**测试要能拦住我写第二次同样的错。**
const dBlock = diag.slice(diag.indexOf("r.code === 'capability_disabled'"),
                          diag.indexOf("r.code === 'login_required'"));
ok('D2 提示指明这是「能力未开通」而非代码/额度问题',
   /开通/.test(dBlock) && !/额度用完）|额度用完就会/.test(dBlock.replace(/不是额度用完/g, '')));
ok('D2b 不再把用户指向未核实的开启路径（§4-558 订正点）',
   !/设置\s*→\s*数据管理|设置\s*>\s*数据管理/.test(dBlock),
   'capability_disabled 文案块长度=' + dBlock.length);

// ── D3：★ 不能只说"改不了"，必须给出**能走通的那一句**（§4-560）──────────
// 【为什么单列】§4-558 的二次订正撤掉了错误指路，但只留下"页面这边改不了"。
//   我的教训原文是「走不通的路吃掉时间」；它的**对偶**同样成立：
//   告诉人"这里过不去"却不给出口，等于把问题原样退回给他。
//   实测证明出口只有一条：幂等 activate(reuse) 后 403 一点没变，
//   管理面 llm/models 全 enabled:true 而数据面仍 403
//   ⇒ "申请"是唯一真路（官方文档原文：在需求中说明"接入大模型"即可）。
ok('D3 capability_disabled 给出可执行的申请方式（不是只留"改不了"）',
   /接入大模型/.test(dBlock), '含"接入大模型"=' + /接入大模型/.test(dBlock));
ok('D3b 申请话术可整句复制（含应用指代，用户不必自己想措辞）',
   /给这个应用接入大模型/.test(dBlock));
ok('D3c 仍保留 Android 兜底路径（不能因为有了申请方式就撤掉即时可用选项）',
   /Android/.test(dBlock));
// D3d 负向变异：把文案退回"只说改不了" ⇒ D3/D3b 必须变红
{
  const mut = dBlock.replace(/接入大模型[\s\S]*?写作诊断/, '这是应用侧的配置。');
  ok('D3d 变异体（撤掉申请方式）后 D3 会变红',
     !/接入大模型/.test(mut) && mut !== dBlock);
}

console.log('\n=== PASS ' + pass + ' / FAIL ' + fail + ' ===');
process.exit(fail ? 1 : 0);