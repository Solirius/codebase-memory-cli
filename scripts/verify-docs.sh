#!/usr/bin/env bash
# verify-docs.sh — fork milestone 05 doc gates.
#
#   Q1  Every fenced ```sh block in docs/CLI_QUICKSTART.md runs, in order, from
#       the root of a clean copy of the repository and exits 0.
#   Q3  The fork docs contain no MCP server registration (mcp.json,
#       mcpServers) and no 0.0.0.0, except lines marked as the explicit caveat
#       ("caveat" on the same line).
#
# The clean copy holds the tracked + untracked-but-not-ignored files of the
# working tree (so uncommitted doc edits are verified too), under build/c/.
# HOME and CBM_CACHE_DIR point into it, so the real home is never touched.
#
# Usage: scripts/verify-docs.sh [--skip-run] [--keep]
#   --skip-run  only run the Q3 text check (no build)
#   --keep      keep the scratch copy for inspection
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QUICKSTART="docs/CLI_QUICKSTART.md"
FORK_DOCS=(docs/CLI_QUICKSTART.md docs/CLI_BUILD_RUN_GUIDE.md docs/COPILOT_CLI_INTEGRATION.md
           docs/copilot-examples scripts/cbm)
SKIP_RUN=0
KEEP=0
for a in "$@"; do
  case "$a" in
    --skip-run) SKIP_RUN=1 ;;
    --keep) KEEP=1 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

FAILS=0
ok()   { echo "ok   $*"; }
fail() { echo "FAIL $*"; FAILS=$((FAILS + 1)); }

# ── Q3: forbidden text in fork docs ─────────────────────────────────────────
cd "$ROOT" || exit 2
readme_fork="$(awk '/^## .*About this fork/{on=1} on&&/^---$/{exit} on' README.md)"
hits="$( { grep -rniE 'mcp\.json|mcpServers|0\.0\.0\.0' "${FORK_DOCS[@]}" 2>/dev/null
          printf '%s\n' "$readme_fork" | grep -niE 'mcp\.json|mcpServers|0\.0\.0\.0' | sed 's/^/README.md(fork):/'
        } | grep -vi 'caveat')"
if [[ -z $hits ]]; then ok "Q3 fork docs: no mcp.json / mcpServers / 0.0.0.0 outside the caveat"
else fail "Q3 forbidden text:"; echo "$hits" | head -20; fi

if ((SKIP_RUN)); then
  ((FAILS == 0)) && { echo "verify-docs: PASS (Q3 only)"; exit 0; }
  echo "verify-docs: $FAILS failure(s)"; exit 1
fi

# ── Q1: run the quickstart on a clean copy ─────────────────────────────────
mkdir -p "$ROOT/build/c"
WORK="$(mktemp -d "$ROOT/build/c/verify-docs.XXXXXX")" || { echo "mktemp failed" >&2; exit 2; }
cleanup() { ((KEEP)) || { chmod -R u+w "$WORK" 2>/dev/null; rm -rf "$WORK"; }; }
trap cleanup EXIT
COPY="$WORK/repo"
mkdir -p "$COPY" "$WORK/home" "$WORK/cache"
(cd "$ROOT" && git ls-files -z --cached --others --exclude-standard |
  while IFS= read -r -d '' f; do [[ -e $f || -L $f ]] && printf '%s\0' "$f"; done |
  tar --null -T - -cf -) | (cd "$COPY" && tar -xf -) ||
  { fail "could not copy the working tree"; exit 1; }
git -C "$COPY" init -q && git -C "$COPY" add -A >/dev/null 2>&1

SCRIPT="$WORK/quickstart.sh"
{
  echo 'set -eux'
  awk '/^```sh[[:space:]]*$/{on=1; next} on&&/^```/{on=0; next} on' "$ROOT/$QUICKSTART"
} >"$SCRIPT"
blocks="$(grep -c '^```sh[[:space:]]*$' "$ROOT/$QUICKSTART")"
((blocks > 0)) || fail "no sh blocks found in $QUICKSTART"

echo "running $blocks sh block(s) from $QUICKSTART in $COPY (log: $WORK/quickstart.log)"
(cd "$COPY" && HOME="$WORK/home" CBM_CACHE_DIR="$WORK/cache" TMPDIR="$WORK" \
   XDG_CONFIG_HOME="$WORK/home/.config" XDG_CACHE_HOME="$WORK/home/.cache" \
   sh "$SCRIPT") >"$WORK/quickstart.log" 2>&1
rc=$?
if ((rc == 0)); then ok "Q1 quickstart sh blocks exit 0 on a clean copy"
else fail "Q1 quickstart failed (rc=$rc); last lines:"; tail -25 "$WORK/quickstart.log"; KEEP=1; fi

# ── Q2: JSON examples in the guide match live output (keys and types) ──────
BIN="$COPY/build/c/codebase-memory-cli"
if [[ -x $BIN ]] && command -v python3 >/dev/null; then
  DEMO="$WORK/demo"; mkdir -p "$DEMO"
  cat >"$DEMO/main.c" <<'C'
#include <stdio.h>

static int add(int a, int b) { return a + b; }

int compute(int x) { return add(x, 1); }

int main(void) {
    printf("%d\n", compute(41));
    return 0;
}
C
  git -C "$DEMO" init -q -b main && git -C "$DEMO" add -A &&
    git -C "$DEMO" -c user.email=docs@localhost -c user.name=docs commit -qm demo
  if (cd "$COPY" && HOME="$WORK/home2" CBM_CACHE_DIR="$WORK/cache2" CBM_BIN="$BIN" DEMO="$DEMO" \
        python3 - "docs/CLI_BUILD_RUN_GUIDE.md" <<'PY'
import json, re, subprocess, sys
text = open(sys.argv[1]).read()
pairs = re.findall(r"<!-- json-example: (.*?) -->\s*```json\n(.*?)\n```", text, re.S)
if not pairs:
    print("no json-example blocks found"); sys.exit(1)
def shape(v):
    if isinstance(v, dict):
        return {k: shape(x) for k, x in sorted(v.items())}
    if isinstance(v, list):
        return [shape(v[0])] if v else []
    if isinstance(v, bool):
        return "bool"
    if isinstance(v, (int, float)):
        return "number"
    return type(v).__name__
bad = 0
for args, doc in pairs:
    proc = subprocess.run("scripts/cbm " + args, shell=True, capture_output=True, text=True, stdin=subprocess.DEVNULL)
    out = proc.stdout if proc.returncode == 0 else proc.stderr
    try:
        live = json.loads(out)
    except ValueError:
        print(f"  FAIL {args}: not JSON (rc={proc.returncode}): {out[:200]} {proc.stderr[:300]}"); bad += 1; continue
    if shape(json.loads(doc)) != shape(live):
        print(f"  FAIL {args}:\n    doc  {shape(json.loads(doc))}\n    live {shape(live)}"); bad += 1
    else:
        print(f"  ok   {args}")
sys.exit(1 if bad else 0)
PY
  ); then ok "Q2 JSON examples match live output (keys and types)"
  else fail "Q2 JSON examples drifted from live output"; fi

  # The example files must be exactly what `install` writes.
  EX="$WORK/example-proj"; mkdir -p "$EX"
  "$BIN" install --project "$EX" >/dev/null
  if cmp -s "$EX/.vscode/tasks.json" "$ROOT/docs/copilot-examples/vscode/tasks.json" &&
     cmp -s "$EX/.github/copilot-instructions.md" "$ROOT/docs/copilot-examples/copilot-instructions.section.md" &&
     diff -r "$EX/.github/prompts" "$ROOT/docs/copilot-examples/prompts" >/dev/null
  then ok "docs/copilot-examples match install output"
  else fail "docs/copilot-examples differ from install output"; fi
else
  fail "Q2 skipped: no built binary in the clean copy or no python3"
fi

if ((FAILS)); then echo "verify-docs: $FAILS failure(s)"; exit 1; fi
echo "verify-docs: PASS"
