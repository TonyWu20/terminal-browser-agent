#!/bin/sh
# selftest: prove the tool package works, in ~5 s, no browser needed
# for everything but the last (optional) live check.
set -u
cd "$(dirname "$0")/.."
TB=tools/terminal-browser/bin/tb
fail=0

# 1) wrapper parses and self-documents
sh -n "$TB" || { echo "FAIL: tb syntax"; exit 1; }
"$TB" help >/dev/null 2>&1 || { echo "FAIL: tb help"; fail=1; }

# 2) manifest is valid TOML with the fields route needs
python3 - <<'PY' || { echo "FAIL: tool.toml"; exit 1; }
import tomllib
m = tomllib.load(open("tools/terminal-browser/tool.toml","rb"))
t = m["tool"]
assert t["command"] == "tb"
assert "Drive the terminal-browser" in t["description"]
assert t["schema"]["required"] == ["op"]
print("tool.toml ok")
PY

# 3) route-ABI JSON in -> JSON out, and the JSON parses
out=$(printf '{"op":"ls"}' | "$TB" 2>/dev/null)
printf '%s' "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert "output" in d or "error" in d' \
  || { echo "FAIL: ABI JSON"; fail=1; }
[ "$fail" -eq 0 ] && echo "ABI ok: $(printf '%s' "$out" | head -c 80)…"

# 4) optional live check: drive a real browser through the tool
if command -v terminal-browser >/dev/null 2>&1; then
  "$TB" ls >/dev/null 2>&1 && echo "live ok: terminal-browser reachable"
fi
exit $fail
