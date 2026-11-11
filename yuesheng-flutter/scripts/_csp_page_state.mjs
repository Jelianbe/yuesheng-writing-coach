// 正对照探针：证明「0 违规」是页面真的加载成功后的 0，而不是白屏/未加载
const CDP_PORT = Number(process.argv[2] || 9342);
const TARGET = process.argv[3] || 'http://127.0.0.1:3030/';
const OUT = process.argv[4] || 'outputs/u3_csp_after.png';

const r = await fetch(`http://127.0.0.1:${CDP_PORT}/json/new?${encodeURIComponent(TARGET)}`, { method: 'PUT' });
const tab = await r.json();
const ws = new WebSocket(tab.webSocketDebuggerUrl);
let id = 0;
const pending = new Map();
ws.addEventListener('message', (ev) => {
  const m = JSON.parse(ev.data);
  if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); }
});
await new Promise((res) => ws.addEventListener('open', res));
const send = (method, params = {}) => new Promise((res) => {
  const myId = ++id;
  pending.set(myId, res);
  ws.send(JSON.stringify({ id: myId, method, params }));
});

await send('Page.enable');
await send('Runtime.enable');
await send('Page.navigate', { url: TARGET });
await new Promise((r) => setTimeout(r, 4500));

const evalJs = async (expr) => {
  const m = await send('Runtime.evaluate', { expression: expr, returnByValue: true });
  return m.result?.result?.value;
};

const state = await evalJs(`(() => ({
  title: document.title,
  readyState: document.readyState,
  fltNodes: document.querySelectorAll('flt-glass-pane, flt-scene-host, flt-semantics-host, canvas').length,
  bodyLen: (document.body ? document.body.innerText : '').length,
  bodyHead: (document.body ? document.body.innerText : '').slice(0, 60).replace(/\\s+/g,' '),
  glassPanePresent: !!document.querySelector('flt-glass-pane'),
  viewport: [innerWidth, innerHeight],
  dpr: devicePixelRatio
}))()`);

const shot = await send('Page.captureScreenshot', { format: 'png' });
const { writeFileSync } = await import('node:fs');
writeFileSync(OUT, Buffer.from(shot.result.data, 'base64'));

console.log(JSON.stringify({ ...state, screenshot: OUT }, null, 1));
ws.close();
