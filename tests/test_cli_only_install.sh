#!/usr/bin/env bash
# Milestone 02 (spec CLI-2, CLI-3, FAIL-9, FAIL-10, TEST-5): in the CLI-only
# binary `install` refuses before touching the filesystem, and `uninstall`
# only REMOVES existing codebase-memory-mcp entries.
# All state lives in a mktemp HOME removed by trap; the real $HOME is never
# touched. Needs python3 (stdlib).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="${CBM_TEST_BINARY:-${ROOT}/build/c/codebase-memory-cli}"
# The default (upstream) build seeds genuine codebase-memory-mcp entries with
# its own writer, so uninstall is checked against the exact canonical shape.
UPSTREAM_BIN="${CBM_UPSTREAM_BINARY:-${ROOT}/build/c/codebase-memory-mcp}"
[[ -x "$BIN" ]] || { echo "missing binary: $BIN" >&2; exit 2; }
[[ -x "$UPSTREAM_BIN" ]] || { echo "missing upstream binary: $UPSTREAM_BIN (make -f Makefile.cbm cbm)" >&2; exit 2; }
command -v python3 >/dev/null || { echo "python3 required" >&2; exit 2; }

REAL_HOME="${HOME:-}"
# System temp (not build/c): agent hook commands embed $HOME paths, and the
# repository path may contain spaces that are unrelated to this contract.
WORK="$(mktemp -d "${TMPDIR:-/tmp}/cbm-cli-only-install.XXXXXX")" || { echo "mktemp failed" >&2; exit 2; }
trap '[[ -n "${KEEP:-}" ]] || { chmod -R u+w "$WORK" 2>/dev/null; rm -rf "$WORK"; }' EXIT
export HOME="$WORK/home" TMPDIR="$WORK/tmp" CBM_CACHE_DIR="$WORK/cache"
export XDG_CONFIG_HOME="$HOME/.config" XDG_CACHE_HOME="$HOME/.cache" LC_ALL=C
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"
[[ "$HOME" != "$REAL_HOME" ]] || { echo "refusing: HOME is the real home" >&2; exit 2; }
mkdir -p "$HOME" "$TMPDIR" "$CBM_CACHE_DIR"

FAILS=0
ok()   { echo "ok   $*"; }
fail() { echo "FAIL $*"; FAILS=$((FAILS + 1)); }

EXPECTED_ERR='{"error":"install is not available in the CLI-only build; see docs (milestone 05)"}'
PATTERN='mcpServers|"mcp"|\.mcp\.json|codebase-memory-mcp'

# ── Fixture: client detection dirs + configs for every client surface ──────
CLIENT_DIRS=(
  .claude .codex .cursor .gemini .gemini/config .gemini/antigravity-cli .augment .cline
  .codeium/windsurf .config/Code/User .config/Code/User/globalStorage/kilocode.kilo-code
  .config/crush .config/goose .config/kilo .config/opencode .config/warp-terminal .config/zed
  .copilot .factory .grok .junie/mcp .kimi-code .omp/agent .openhands .pi/agent .pochi .qoder
  .rovodev .vibe .warp .bob .codebuddy .kiro/settings .qwen .hermes .openclaw .continue
  .aws/amazonq .tabnine .trae .roo .amp .devin .config/amp .local/bin
)
for d in "${CLIENT_DIRS[@]}"; do mkdir -p "$HOME/$d"; done

# Every JSON config carries an unrelated server and key that must survive
# uninstall; canonical codebase-memory-mcp entries are added later by the
# upstream writer.
JSON_CONFIGS=(
  .claude.json .mcp.json .cursor/mcp.json .gemini/settings.json .gemini/config/mcp_config.json
  .gemini/antigravity-cli/settings.json .augment/settings.json .codeium/windsurf/mcp_config.json
  .factory/mcp.json .junie/mcp/mcp.json .openhands/mcp.json .kiro/settings/mcp.json
  .qwen/settings.json .config/crush/crush.json .config/Code/User/mcp.json
)
for f in "${JSON_CONFIGS[@]}"; do
  cat >"$HOME/$f" <<'JSON'
{
  "mcpServers": {
    "other-server": { "command": "/usr/bin/other", "args": ["--keep"] }
  },
  "unrelated": true
}
JSON
done
cat >"$HOME/.config/opencode/opencode.json" <<'JSON'
{ "mcp": { "other-server": { "type": "local", "command": ["/usr/bin/other"] } } }
JSON
cat >"$HOME/.config/zed/settings.json" <<'JSON'
{ "context_servers": { "other-server": { "command": "/usr/bin/other" } } }
JSON
cat >"$HOME/.codex/config.toml" <<'TOML'
[mcp_servers.other-server]
command = "/usr/bin/other"
TOML
echo '# user profile' >"$HOME/.zshrc"

# snapshot OUT: path, size, mtime_ns, sha256 for every entry under $HOME.
snapshot() {
  python3 - "$HOME" "$1" <<'PY'
import hashlib, os, sys
root, out = sys.argv[1], sys.argv[2]
rows = []
for d, dirs, files in os.walk(root):
    for name in sorted(dirs + files):
        p = os.path.join(d, name)
        st = os.lstat(p)
        digest = "-"
        if os.path.isfile(p) and not os.path.islink(p):
            digest = hashlib.sha256(open(p, "rb").read()).hexdigest()
        rows.append(f"{os.path.relpath(p, root)}\t{st.st_size}\t{st.st_mtime_ns}\t{digest}")
open(out, "w").write("\n".join(sorted(rows)) + "\n")
PY
}
# matches OUT: every "file:line" under $HOME matching PATTERN.
matches() { (cd "$HOME" && grep -rnE "$PATTERN" . 2>/dev/null | sed 's/^\([^:]*\):[0-9]*:/\1:/' | sort -u) >"$1"; }

# ── install refuses and writes nothing (CLI-2, FAIL-9) ─────────────────────
snapshot "$WORK/before"
matches "$WORK/m-baseline"
for argv in "install" "install -y" "install --dry-run" "install --force -y"; do
  # shellcheck disable=SC2086
  "$BIN" $argv </dev/null >"$WORK/out" 2>"$WORK/err"; rc=$?
  snapshot "$WORK/after"
  if ((rc == 0)); then fail "'$argv' exited 0"; else ok "'$argv' exit=$rc"; fi
  if [[ "$(cat "$WORK/out")" == "$EXPECTED_ERR" ]]; then ok "'$argv' prints CLI-2 JSON error"
  else fail "'$argv' stdout: $(head -c 300 "$WORK/out")"; fi
  if diff -q "$WORK/before" "$WORK/after" >/dev/null; then ok "'$argv' left \$HOME byte- and mtime-identical"
  else fail "'$argv' modified \$HOME:"; diff "$WORK/before" "$WORK/after" | head -10; fi
done

# ── uninstall with no upstream entry writes nothing (FAIL-10) ──────────────
CLEAN="$WORK/clean-home"
mkdir -p "$CLEAN/.cursor"
echo '{"mcpServers":{"other-server":{"command":"/usr/bin/other"}}}' >"$CLEAN/.cursor/mcp.json"
(HOME="$CLEAN"; export HOME XDG_CONFIG_HOME="$CLEAN/.config"
 snapshot "$WORK/clean-before"
 "$BIN" uninstall -y </dev/null >"$WORK/uout" 2>"$WORK/uerr"; echo $? >"$WORK/urc"
 snapshot "$WORK/clean-after")
if [[ "$(cat "$WORK/urc")" == 0 ]]; then ok "uninstall (no entry) exit=0"
else fail "uninstall (no entry) exit=$(cat "$WORK/urc"): $(head -c 300 "$WORK/uerr")"; fi
if diff -q "$WORK/clean-before" "$WORK/clean-after" >/dev/null; then ok "uninstall (no entry) wrote nothing"
else fail "uninstall (no entry) changed files:"; diff "$WORK/clean-before" "$WORK/clean-after" | head -10; fi

# ── uninstall only removes upstream entries (CLI-3) ────────────────────────
"$UPSTREAM_BIN" install -y </dev/null >"$WORK/seed-out" 2>"$WORK/seed-err"; rc=$?
if ((rc == 0)) && grep -rqF codebase-memory-mcp "$HOME/.cursor/mcp.json" 2>/dev/null; then
  ok "seeded upstream entries with $(basename "$UPSTREAM_BIN") install -y"
else fail "upstream seed install rc=$rc: $(tail -c 300 "$WORK/seed-err")"; fi
matches "$WORK/m-before"
"$BIN" uninstall -y </dev/null >"$WORK/uout" 2>"$WORK/uerr"; rc=$?
matches "$WORK/m-after"
if ((rc == 0)); then ok "uninstall exit=0"; else fail "uninstall exit=$rc: $(head -c 300 "$WORK/uerr")"; fi
sort -u "$WORK/m-baseline" "$WORK/m-before" >"$WORK/m-known"
new_matches="$(comm -13 "$WORK/m-known" "$WORK/m-after")"
if [[ -z "$new_matches" ]]; then ok "uninstall added/changed no MCP-pattern lines"
else fail "uninstall added/changed MCP-pattern lines:"; echo "$new_matches" | head -10; fi
python3 - "$HOME" "${JSON_CONFIGS[@]}" .config/opencode/opencode.json .config/zed/settings.json <<'PY' >"$WORK/json-check"
import json, os, sys
root, files = sys.argv[1], sys.argv[2:]
bad = []
for f in files:
    p = os.path.join(root, f)
    if not os.path.exists(p):
        bad.append(f"{f}: file removed"); continue
    text = open(p).read()
    if "other-server" not in text: bad.append(f"{f}: unrelated server lost")
    if '"unrelated": true' not in text and f not in (".config/opencode/opencode.json", ".config/zed/settings.json"):
        bad.append(f"{f}: unrelated key lost")
print("\n".join(bad))
PY
if [[ -z "$(tr -d '\n' <"$WORK/json-check")" ]]; then ok "uninstall kept every unrelated server and key"
else fail "uninstall unrelated-content check:"; head -20 "$WORK/json-check"; fi
left="$(cd "$HOME" && grep -rlF '"codebase-memory-mcp"' . 2>/dev/null | head -5)"
if [[ -z "$left" ]]; then ok "uninstall removed every seeded codebase-memory-mcp entry"
else fail "entries still present after uninstall:"; echo "$left"; fi
# Removal reports name the file they edited (e.g. ".../.mcp.json"); only
# lines that are not removal reports are checked for MCP-setup guidance.
setup_hits="$(cat "$WORK/uout" "$WORK/uerr" | grep -viE '(^|[[:space:]])removed[[:space:]]' | grep -iE 'mcp server|mcpServers|\.mcp\.json|claude mcp add')"
if [[ -n "$setup_hits" ]]; then
  fail "uninstall output mentions MCP setup:"; echo "$setup_hits" | head -3
else ok "uninstall output MCP-setup free"; fi

[[ "${HOME}" != "${REAL_HOME}" ]] || fail "HOME leaked to the real home"
echo
if ((FAILS)); then echo "test_cli_only_install: $FAILS failure(s)"; exit 1; fi
echo "test_cli_only_install: PASS"
