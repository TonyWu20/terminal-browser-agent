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

## Nix flake (Mode B)

The repo ships a `flake.nix` following the rushi
`ext-flake-authoring` pattern. It exposes one tool package per
system. There is no cargo build. The package is a plain copy of
`tools/terminal-browser/` into the tool `$out` contract:

    $out/terminal-browser/tool.toml
    $out/terminal-browser/bin/tb
    $out/terminal-browser/bin/cdp-download.mjs
    $out/terminal-browser/docs/procedure.md

Build and gate it:

    nix build .#terminal-browser          # or .#default
    nix build .#checks.x86_64-linux.tool-layout   # P1 layout check

The package declares `meta.rushi.entry = "terminal-browser"`. When
a consumer passes the package to `rushi.external_tools`, the kernel
`lib.mkRushi` fills `[paths] extension_tool_paths` with
`"tools/terminal-browser"` at eval time (issue #13). It needs no
second hand-typed copy.

Consumer wiring (see `rust-unix-harness/examples/rushi-config`):

    # consumer flake
    inputs = {
      tbAgent.url = "github:<user>/terminal-browser-agent";
      # plus the kernel flake input that provides lib.mkRushi
    };

    rushi.external_tools = [
      tbAgent.packages.x86_64-linux."terminal-browser"
    ];

The `terminal-browser` binary and `python3` are runtime PATH
dependencies of the tool. They are not build inputs. Provide them in
the agent environment.

## Standalone use

    tools/terminal-browser/bin/tb help
    tools/terminal-browser/bin/tb open https://example.com
    tools/terminal-browser/bin/tb get "document.title"
    tools/terminal-browser/bin/tb pdf https://arxiv.org/pdf/2010.08895 out.pdf

