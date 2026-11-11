// U2 (A) 主证探针：真宿主（server.js 同一份）+ 真浏览器（Edge CDP）
// 目标：① 五头从 HTTP 层真实下发（含值）② Report-Only 收窄名单是否漏域
// 关键：必须有负对照 —— 非白名单域若不产生违规，说明采集通道本身失效，「零违规」就是废读数。
const CDP_PORT = Number(process.argv[2] || 9334);
const TARGET = process.argv[3] || 'http://127.0.0.1:3030/';

const COLLECTOR = `
window.__csp_v = [];
document.addEventListener('securitypolicyviolation', function (e) {
  window.__csp_v.push({
    directive: e.effectiveDirective || e.violatedDirective || '',
    blocked: e.blockedURI || '',
    disposition: e.disposition || '',
    sample: (e.sample || '').slice(0, 50),
    src: (e.sourceFile || '').slice(-70),
    line: e.lineNumber,
    col: e.columnNumber,
  });
});
`;

const WHITELIST = [
  'https://api.deepseek.com/',
  'https://api.moonshot.cn/',
  'https://api.openai.com/',
  'https://ark.cn-beijing.volces.com/',
  'https://dashscope.aliyuncs.com/',
  'https://open.bigmodel.cn/',
  'https://www.bigmodel.cn/',
  'https://www.gstatic.com/generate_204',
  'https://fonts.gstatic.com/s/roboto/v30/KFOmCnqEu92Fr1Me5WZLCzYlKw.woff2',
];
const NEGATIVE = ['https://example.com/', 'https://cspsmoke.invalid/'];

const http = await import('node:http');

function httpJson(path) {
  return new Promise((res, rej) => {
    http
      .get({ host: '127.0.0.1', port: CDP_PORT, path }, (r) => {
        let b = '';
        r.on('data', (d) => (b += d));
        r.on('end', () => {
          try {
            res(JSON.parse(b));
          } catch (e) {
            rej(new Error('bad json: ' + b.slice(0, 200)));
          }
        });
      })
      .on('error', rej);
  });
}

const vlist = await httpJson('/json/list');
const page = vlist.find((t) => t.type === 'page');
if (!page) {
  console.log(JSON.stringify({ error: 'no page target', targets: vlist.map((t) => t.type) }));
  process.exit(1);
}

const ws = new WebSocket(page.webSocketDebuggerUrl);
let _id = 0;
const pending = new Map();
const events = [];
ws.addEventListener('message', (m) => {
  const msg = JSON.parse(m.data);
  if (msg.id && pending.has(msg.id)) {
    pending.get(msg.id)(msg);
    pending.delete(msg.id);
  } else if (msg.method) {
    events.push(msg);
  }
});
await new Promise((r) => ws.addEventListener('open', r, { once: true }));

function send(method, params = {}) {
  const id = ++_id;
  return new Promise((resolve, reject) => {
    pending.set(id, (msg) => (msg.error ? reject(new Error(method + ': ' + msg.error.message)) : resolve(msg.result)));
    ws.send(JSON.stringify({ id, method, params }));
  });
}

async function evalJs(expression, awaitPromise = true) {
  const r = await send('Runtime.evaluate', { expression, awaitPromise, returnByValue: true });
  if (r.exceptionDetails) throw new Error('JS: ' + JSON.stringify(r.exceptionDetails).slice(0, 300));
  return r.result.value;
}

await send('Network.enable');
await send('Page.enable');
await send('Runtime.enable');
// 必须在导航前注入：文档创建时执行，才能抓到加载期的违规（如 style-src 收窄）
await send('Page.addScriptToEvaluateOnNewDocument', { source: COLLECTOR });

await send('Page.navigate', { url: TARGET });
await new Promise((r) => setTimeout(r, 15000)); // Flutter web 启动 + CanvasKit 拉取

// ---- ① HTTP 层真实下发的头 ----
const docReq = events.filter((e) => e.method === 'Network.responseReceived' && e.params.type === 'Document');
const headers = docReq.length ? docReq[0].params.response.headers : {};
const lower = {};
for (const k of Object.keys(headers)) lower[k.toLowerCase()] = headers[k];
const HDR = [
  'cross-origin-opener-policy',
  'cross-origin-embedder-policy',
  'permissions-policy',
  'content-security-policy',
  'content-security-policy-report-only',
];
const hdrOut = {};
for (const h of HDR) hdrOut[h] = lower[h] ? lower[h] : null;

// ---- ② 加载期违规（含负对照前提：采集器是否活着）----
const loaded = await evalJs('JSON.stringify({live: Array.isArray(window.__csp_v), n: (window.__csp_v||[]).length, v: (window.__csp_v||[]).slice(0,50)})');
const loadViolations = JSON.parse(loaded);

// ---- ③ 白名单逐一探活 + 负对照 ----
const probeScript = (urls) => `(async () => {
  const out = [];
  for (const u of ${JSON.stringify(urls)}) {
    const before = window.__csp_v.length;
    let netErr = null;
    try {
      await fetch(u, { mode: 'no-cors', cache: 'no-store' });
    } catch (e) { netErr = String(e).slice(0, 60); }
    await new Promise(r => setTimeout(r, 400));
    const nv = window.__csp_v.slice(before);
    out.push({ url: u, newViolations: nv.length, directives: nv.map(x => x.directive + ' <- ' + x.blocked), netErr });
  }
  return JSON.stringify(out);
})()`;

const wl = JSON.parse(await evalJs(probeScript(WHITELIST)));
const ng = JSON.parse(await evalJs(probeScript(NEGATIVE)));

// ---- ④ 汇总 ----
const allViolations = await evalJs('JSON.stringify(window.__csp_v)');
const all = JSON.parse(allViolations);
const byDirective = {};
for (const v of all) byDirective[v.directive] = (byDirective[v.directive] || 0) + 1;

const out = {
  target: TARGET,
  headers: hdrOut,
  headerCount: Object.values(hdrOut).filter(Boolean).length,
  collectorAlive: loadViolations.live,
  loadPhaseViolationCount: loadViolations.n,
  finalViolationCount: all.length,
  violationsByDirective: byDirective,
  violationsSample: all.slice(0, 12),
  whitelist: wl,
  negative: ng,
  negativeCaught: ng.filter((x) => x.newViolations > 0).length,
  negativeTotal: ng.length,
  whitelistClean: wl.filter((x) => x.newViolations === 0).length,
  whitelistTotal: wl.length,
};
console.log(JSON.stringify(out, null, 1));
ws.close();
process.exit(0);
