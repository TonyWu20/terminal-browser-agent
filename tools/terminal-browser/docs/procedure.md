# terminal-browser: agent procedure (on-demand)

Read this file when a task needs the web. `tb` is the tool entry
point (ops: `open`, `ls`, `goto`, `shot`, `get`, `click`, `pdf`,
`shutdown`); the raw CLI is `terminal-browser` underneath it.

## Research loop

1. **Check state**: `tb ls` — is a browser already running? (key + tabs)
2. **Open**: `tb open <url>` creates a pane (new browser if none);
   `tb goto <url>` navigates the active tab instead.
3. **Read the page**: `tb shot` gives an accessibility tree with stable
   element refs (`@e1`, `@e2`, …) — the primary way to find clickable
   elements and links.
4. **Extract data**: `tb get '<js>'` evaluates JS in the active tab
   (title, `document.body.innerText`, selectors, `window.location.href`).
5. **Interact**: `tb click <@ref|selector>`, then re-`shot` — the DOM
   changed, so old refs are dead.
6. **Download**: `tb pdf <url> [out]` — see below.
7. **Clean up**: `tb shutdown` stops the daemon when the task is done.

## PDF downloads (the case that breaks naive agents)

Journal sites (arXiv, IEEE, Elsevier, …) serve the PDF **inline**:
clicking "Download PDF" opens the in-page PDF *viewer* instead of
transferring the file. A download-event-based tool then times out
waiting for an event that never fires.

The working recipe (what `tb pdf` automates):

1. Navigate **straight to the PDF URL** (`tb goto https://…/pdf/<id>`
   or `tb open`). The site's viewer loads in an iframe.
2. **Poll** `tb shot` until the viewer's toolbar renders — a progress
   bar shows while the PDF streams; the "Download" button ref exists
   only after load. (arXiv: 3–15 s typical.)
3. **Click the viewer's own Download button** — `terminal-browser
   action -- download @<ref> <path>` captures the download event and
   saves to disk. The result line is `✓ Download saved to <path>`.

Verified on: arxiv.org PDF viewer (buttons inside an iframe),
example.com (link navigation), google.com searches.

## Pitfalls learned the hard way

- **Refs go stale on every DOM change** — navigation, iframe load,
  page update. Re-snapshot immediately before using a ref; do
  snapshot + act in the same command block when scripting.
- **CSS selectors do not cross iframe boundaries.** The PDF viewer
  toolbar lives in an iframe: `button:has-text("Download")` fails
  ("Element not found"), while the snapshot ref `@e12` reaches it.
  Use refs for in-iframe UI, selectors for the top document.
- **Elements under a sticky header** are "covered" — clicks fail
  with a clear error. Navigate directly to the target URL instead of
  clicking a covered link.
- **`eval` reuses variable scope across calls** in the same tab —
  a second `const t = …` throws `Identifier already declared`.
  Wrap multi-statement JS in an IIFE: `(() => { const t=…; return t })()`.
- **Page load blocks**: `shot`/`get` right after `goto` may block on
  load; budget generous timeouts (the harness bash cap is 300 s).
- **Search engines**: DuckDuckGo HTML (`https://html.duckduckgo.com/html/?q=…`)
  is the agent-friendly choice (no consent wall, parseable result
  links). Google works too but is region-routed and JS-heavy; its
  Scholar links still carry the arXiv IDs.
- **Verify downloads**: check `%PDF` header + `%%EOF` marker; the
  `file(1)` page count is unreliable for compressed PDFs.

## Notes

- The browser instance persists across `tb` calls (daemon + CDP).
  `tb ls` shows keys; `--browser <key>` / `--tab <id>` selectors on
  `terminal-browser action` target specific instances/tabs.
- In a rushi session this tool arrives as the `terminal-browser`
  tool (JSON args on stdin, one JSON result object on stdout).
  Standalone it is the `tb` CLI: `tb <op> [a] [b]`.
