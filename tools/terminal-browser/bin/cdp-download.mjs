// cdp-download.mjs — generic PDF download for a running terminal-browser
// instance, for sites whose PDF "Download" opens an in-page viewer
// (Wiley, IEEE, Elsevier, arXiv, …) instead of transferring the file.
//
// Method: fetch the PDF in-page (carries the site's session/auth cookies),
// make a blob, click a synthetic <a download>.  CDP's
// Browser.setDownloadBehavior routes that download to a directory of
// ours; we verify on disk instead of trusting download events.
//
// No dependencies: Node >= 22 (global WebSocket + fetch).
//
// usage: node cdp-download.mjs <cdpPort> <target-url-substr> <pdf-url> <out-dir>
//        exit 0 + printed path on success
const port = process.argv[2], sub = process.argv[3], pdfUrl = process.argv[4], outDir = process.argv[5];
import fs from 'node:fs';
import path from 'node:path';

const base = `http://127.0.0.1:${port}`;
const j = async p => (await (await fetch(base + p)).json());
const ver = await j('/json/version');
const targets = await j('/json');
const page = targets.find(t => t.type === 'page' && t.url.includes(sub));
if (!page) { console.error('no CDP page target matching "' + sub + '"'); process.exit(2); }

const before = new Set(fs.readdirSync(outDir));
const ws = new WebSocket(ver.webSocketDebuggerUrl);
const pws = new WebSocket(page.webSocketDebuggerUrl);
let mid = 0;
const pending = new Map();
const dispatch = d => {
  if (d.id) {
    const p = pending.get(d.id);
    if (p) { d.error ? p.rej(new Error(d.error.message || 'cdp error')) : p.res(d.result); pending.delete(d.id); }
    return;
  }
};
ws.onmessage = e => dispatch(JSON.parse(e.data));
pws.onmessage = e => dispatch(JSON.parse(e.data));
await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });
await new Promise((res, rej) => { pws.onopen = res; pws.onerror = rej; });
const cmd = (m, p = {}) => new Promise((res, rej) => {
  const id = ++mid; pending.set(id, { res, rej }); ws.send(JSON.stringify({ id, method: m, params: p }));
});
const pcmd = (m, p = {}) => new Promise((res, rej) => {
  const id = ++mid; pending.set(id, { res, rej }); pws.send(JSON.stringify({ id, method: m, params: p }));
});

// Some flows leave the target on a raw PDF document (no JS context).  Put it
// back on the HTML page that serves the PDF and wait until it is usable.
await pcmd('Page.enable');
await pcmd('Page.navigate', { url: pdfUrl }).catch(() => {});
for (let i = 0; i < 30; i++) {
  await new Promise(r => setTimeout(r, 1000));
  const st = await pcmd('Runtime.evaluate', { expression: 'document.readyState', returnByValue: true }).catch(() => null);
  if (st?.result?.value === 'complete') break;
}
const probe = await pcmd('Runtime.evaluate', { expression: '"probe"', returnByValue: true }).catch(e => ({ err: String(e) }));
if (probe.err || probe?.result?.value !== 'probe') {
  console.error('target has no usable JS context (' + (probe.err || JSON.stringify(probe)) + '); is the tab on the HTML page that renders this PDF?');
  process.exit(5);
}

// route downloads into our dir for this browser instance
await cmd('Browser.setDownloadBehavior', { behavior: 'allow', downloadPath: outDir, eventsSuppressed: true });

// fetch in-page (session cookies ride along), blob, click a download anchor
// Some hosts serve the viewer wrapper at /pdf/ and the bytes at a variant
// URL (Wiley: /doi/pdf/ -> /doi/pdfdirect/). Try the URL and that variant.
const js = `(async()=>{
  const cands = [${JSON.stringify(pdfUrl)}, ${JSON.stringify(pdfUrl)} .replace('/pdf/', '/pdfdirect/')];
  let r, b;
  for (const u of cands) {
    const rr = await fetch(u, {credentials:'include'});
    const ct = rr.headers.get('content-type') || '';
    if (rr.ok && ct.includes('pdf')) { r = rr; b = await rr.blob(); break; }
  }
  if (!b) { const rr2 = await fetch(${JSON.stringify(pdfUrl)}, {credentials:'include'});
    return 'fetch failed: status=' + rr2.status + ' type=' + rr2.headers.get('content-type'); }
  const a = document.createElement('a');
  a.href = URL.createObjectURL(b);
  a.download = ${JSON.stringify(pdfUrl.split('/').pop() || 'download.pdf')};
  document.body.appendChild(a); a.click();
  return 'ok bytes=' + b.size;
})()`;
const out = await pcmd('Runtime.evaluate', { expression: js, awaitPromise: true, returnByValue: true });
// out IS the CDP result object: { result: RemoteObject, exceptionDetails? }
const jsMsg = out?.exceptionDetails
  ? 'js exception: ' + JSON.stringify(out.exceptionDetails.exception?.description || out.exceptionDetails.text)
  : out?.result?.value ?? 'no reply';
if (!String(jsMsg).startsWith('ok')) { console.error('in-page fetch: ' + jsMsg); process.exit(4); }
console.error('in-page fetch:', jsMsg);

// poll the dir until a new file appears and its size stabilizes
let name = null, lastSize = -1, stable = 0;
for (let i = 0; i < 120; i++) {
  await new Promise(r => setTimeout(r, 1000));
  const fresh = fs.readdirSync(outDir).filter(f => !before.has(f));
  if (fresh.length) {
    const p0 = path.join(outDir, fresh[0]);
    const size = fs.statSync(p0).size;
    if (size > 0 && size === lastSize) { if (++stable >= 2) { name = p0; break; } }
    lastSize = size;
  } else stable = 0;
}
// restore default download behavior
try { await cmd('Browser.setDownloadBehavior', { behavior: 'default' }); } catch {}
if (name) { console.log(name); process.exit(0); }
console.error('no completed download in ' + outDir); process.exit(3);
