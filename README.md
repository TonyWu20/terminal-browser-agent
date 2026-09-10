# terminal-browser-agent

`terminal-browser` knowledge, packaged in the rushi
"OS + applications" style (docs/skill-remapped-to-os-apps.md):
a tool registers **by sitting on the agent-visible path**,
self-documents via `--help`, and its multi-step procedure
(downloading a PDF through a site's in-page viewer) is a
short-lived executable, not a SKILL.md.

## Layout

    tools/terminal-browser/
    ├── tool.toml            # the manifest route/assemble discover
    ├── bin/tb               # POSIX sh wrapper (self-documenting, no build)
    └── docs/procedure.md    # on-demand agent procedure (cache-safe read)

## What it gives the agent

One tool, seven ops (JSON args on stdin via route, CLI standalone):

    op            purpose
    open <url>    start a browser pane (new browser if none)
    ls            list running browsers / tabs
    goto <url>    navigate the active tab
    shot          accessibility snapshot with element refs (@eNN)
    get <js>      evaluate JS in the active tab
    click <ref|selector>  click an element
    pdf <url> [out]       download a PDF, handling in-page viewers
    shutdown      stop the daemon

The `pdf` op encodes the case that breaks naive agents: journal
sites open the PDF in an in-page viewer instead of transferring the
file. The working recipe (verified on arXiv): navigate straight to
the PDF URL → poll the viewer for its Download button → click it via
`terminal-browser action -- download @ref <path>`.

## Install into a rushi project

Requirements: `terminal-browser` on the agent-visible PATH, `python3`
on PATH (route-ABI JSON parsing; the sed fallback degrades), and the
wrapper executable.

Option A — register the tool root (recommended, matches the
`extra_tools_roots` extension pattern):

    # in the project's config, [paths]:
    extra_tools_roots = ["/home/tony/programming/terminal-browser-agent/tools/"]

`route` then discovers `tools/terminal-browser/` and resolves the
binary at `tools/terminal-browser/bin/tb` relative to that root.

Option B — copy/symlink into the project's `tools/` dir:

    ln -s /home/tony/programming/terminal-browser-agent/tools/terminal-browser \
        <project>/tools/terminal-browser

Either way `assemble` adds one line to the prompt prefix:
`terminal-browser: Drive the terminal-browser web browser…`
(a one-time prefix rebuild, per the cache rule).

## Standalone use

    tools/terminal-browser/bin/tb help
    tools/terminal-browser/bin/tb open https://example.com
    tools/terminal-browser/bin/tb get "document.title"
    tools/terminal-browser/bin/tb pdf https://arxiv.org/pdf/2010.08895 out.pdf

