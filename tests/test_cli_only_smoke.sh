#!/usr/bin/env bash
# Smoke test for the fork's shipped CLI-only binary (milestone 01, E3–E6).
# - Non-CLI argv shapes (bare, unknown, daemon, MCP, worker, hook) are inert:
#   exit 2, never answer JSON-RPC, never block on an open stdin.
# - Every one of the 17 tools returns one JSON document via `cli --json`.
# - Two concurrent index runs serialize and leave a DB passing integrity_check.
# - No sockets or daemon/cohort artifacts appear.
# All scratch state lives under build/c/ (never /tmp). Needs python3 (stdlib).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="${CBM_TEST_BINARY:-${ROOT}/build/c/codebase-memory-cli}"
[[ -x "$BIN" ]] || { echo "missing binary: $BIN" >&2; exit 2; }
command -v python3 >/dev/null || { echo "python3 required" >&2; exit 2; }

mkdir -p "${ROOT}/build/c"
WORK="$(mktemp -d "${ROOT}/build/c/cli-only-smoke.XXXXXX")" || { echo "mktemp failed" >&2; exit 2; }
cleanup() {
  local pids; pids="$(jobs -p)"
  [[ -n $pids ]] && kill -9 $pids 2>/dev/null
  chmod -R u+w "$WORK" 2>/dev/null; rm -rf "$WORK"
}
trap cleanup EXIT
export HOME="$WORK/home" TMPDIR="$WORK/tmp" CBM_CACHE_DIR="$WORK/cache"
export XDG_CONFIG_HOME="$HOME/.config" XDG_CACHE_HOME="$HOME/.cache" LC_ALL=C
mkdir -p "$HOME" "$TMPDIR" "$CBM_CACHE_DIR"
# Open-stdin mode: a FIFO whose write end this script holds for its lifetime,
# so a child that reads stdin blocks instead of seeing EOF.
FIFO="$WORK/stdin.fifo"; mkfifo "$FIFO"; exec 3<>"$FIFO"

FAILS=0
ok()   { echo "ok   $*"; }
fail() { echo "FAIL $*"; FAILS=$((FAILS + 1)); }

# Sockets owned by us in the shared temp dir (the product's own lock dir,
# /tmp/cbm-daemon-<uid>, holds only plain lock files and is allowed).
tmp_sockets() { find /tmp/ -maxdepth 2 -user "$(id -u)" \( -type s -o -name '*.sock' \) 2>/dev/null | sort; }
TMP_BEFORE="$(tmp_sockets)"

# run_bounded SECS OUT ERR STDIN_MODE ARGS... -> sets RC (124 on timeout).
run_bounded() {
  local secs=$1 out=$2 err=$3 mode=$4; shift 4
  if [[ $mode == pipe ]]; then
    echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' >&3
    "$BIN" "$@" <"$FIFO" >"$out" 2>"$err" &
  else
    "$BIN" "$@" </dev/null >"$out" 2>"$err" &
  fi
  bounded_wait "$!" "$secs"
}

# bounded_wait PID SECS -> sets RC (124 and SIGKILL on timeout).
bounded_wait() {
  local pid=$1 secs=$2 waited=0
  while kill -0 "$pid" 2>/dev/null && ((waited < secs * 10)); do sleep 0.1; waited=$((waited + 1)); done
  if kill -0 "$pid" 2>/dev/null; then
    kill -9 "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; RC=124
  else
    wait "$pid"; RC=$?
  fi
}

is_json() { python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$1" 2>/dev/null; }

# ── E3/E4: inert dispatch ────────────────────────────────────────────────
FP=0000000000000000000000000000000000000000000000000000000000000000
inert_cases=(
  "2|"  "2|frobnicate"  "0|--help"  "0|-h"
  "2|--cbm-daemon-internal"  "2|daemon status"  "2|daemon stop"  "2|daemon start"
  "2|--stdio"  "2|mcp"  "2|serve"  "2|--ui=true"
  "2|cli --index-worker --index-worker-build $FP index_repository {} --response-out r.json"
)
for entry in "${inert_cases[@]}"; do
  want=${entry%%|*}; argv=${entry#*|}
  for mode in null pipe; do
    # shellcheck disable=SC2086  # argv is a deliberate word list
    run_bounded 5 "$WORK/o" "$WORK/e" "$mode" $argv
    label="'${argv}' stdin=$mode"
    if ((RC == 124)); then fail "$label: timed out (read stdin?)"
    elif ((RC != want)); then fail "$label: rc=$RC want $want"
    elif grep -q '"jsonrpc"' "$WORK/o" "$WORK/e"; then fail "$label: answered JSON-RPC"
    elif ! grep -q cli "$WORK/o" "$WORK/e"; then fail "$label: no help text"
    else ok "$label (rc=$RC)"; fi
  done
done
# Hooks are contractually fail-open (any rc, may read stdin); only assert
# that they finish and never answer JSON-RPC.
for argv in "hook-augment" "hook-augment --event PreToolUse"; do
  for mode in null pipe; do
    # shellcheck disable=SC2086
    run_bounded 5 "$WORK/o" "$WORK/e" "$mode" $argv
    if ((RC == 124)) || grep -q '"jsonrpc"' "$WORK/o"; then fail "'$argv' stdin=$mode: rc=$RC"
    else ok "'$argv' stdin=$mode fail-open (rc=$RC)"; fi
  done
done

# ── E5: 17 tools return JSON ─────────────────────────────────────────────
REPO="$WORK/repo"; mkdir -p "$REPO"
printf 'static int helper(int x) { return x + 1; }\nint main(void) { return helper(1); }\n' >"$REPO/main.c"
git -C "$REPO" init -q && git -C "$REPO" add . &&
  git -C "$REPO" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false commit -qm fixture \
  || { echo "fixture: git failed" >&2; exit 2; }

tool() { run_bounded 120 "$WORK/o" "$WORK/e" null cli --json "$1" "$2"; }
tool index_repository "{\"repo_path\":\"$REPO\"}"
DB="$(ls "$CBM_CACHE_DIR"/*.db 2>/dev/null | head -1)"
P="$(basename "${DB:-x.db}" .db)"
if ((RC != 0)) || [[ -z $DB ]] || ! is_json "$WORK/o"; then
  fail "index_repository: rc=$RC, no DB or bad JSON"; cat "$WORK/e" >&2
else ok "index_repository (project $P)"; fi

tools=(
  "search_graph|{\"project\":\"$P\",\"query\":\"helper\"}"
  "query_graph|{\"project\":\"$P\",\"query\":\"MATCH (n) RETURN n.name LIMIT 3\"}"
  "trace_path|{\"project\":\"$P\",\"function_name\":\"main\"}"
  "get_code_snippet|{\"project\":\"$P\",\"qualified_name\":\"helper\"}"
  "get_file_outline|{\"project\":\"$P\",\"file_path\":\"main.c\"}"
  "get_graph_schema|{\"project\":\"$P\"}"
  "compare_graphs|{\"base_project\":\"$P\",\"target_project\":\"$P\"}"
  "get_architecture|{\"project\":\"$P\"}"
  "search_code|{\"project\":\"$P\",\"pattern\":\"helper\"}"
  "list_projects|{}"
  "index_status|{\"project\":\"$P\"}"
  "check_index_coverage|{\"project\":\"$P\",\"paths\":[\"main.c\"]}"
  "detect_changes|{\"project\":\"$P\"}"
  "manage_adr|{\"project\":\"$P\",\"mode\":\"get\"}"
  "ingest_traces|{\"project\":\"$P\",\"traces\":[]}"
  "delete_project|{\"project\":\"cli-only-no-such-project\"}"
)
((${#tools[@]} + 1 == 17)) || fail "tool table has $((${#tools[@]} + 1)) entries, want 17"
for entry in "${tools[@]}"; do
  name=${entry%%|*}; tool "$name" "${entry#*|}"
  # rc 1 is a tool-level error; the envelope must still be valid JSON.
  if ((RC > 1)); then fail "$name: rc=$RC"
  elif ! is_json "$WORK/o"; then fail "$name: stdout is not one JSON document"
  elif grep -qi 'unknown tool' "$WORK/o"; then fail "$name: unknown tool"
  else ok "$name (rc=$RC)"; fi
done
tool nosuchtool '{}'
if ((RC != 0)) && is_json "$WORK/o"; then ok "nosuchtool -> JSON error (rc=$RC)"
else fail "nosuchtool: rc=$RC"; fi

# ── E6: concurrent index runs serialize ──────────────────────────────────
integrity() {
  python3 - "$DB" <<'PY'
import sqlite3, sys
c = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
sys.exit(0 if all(c.execute(q).fetchone()[0] == "ok"
                  for q in ("PRAGMA integrity_check", "PRAGMA quick_check")) else 1)
PY
}
for i in 1 2 3; do
  "$BIN" cli --json index_repository "{\"repo_path\":\"$REPO\"}" </dev/null >"$WORK/a" 2>/dev/null & a=$!
  "$BIN" cli --json index_repository "{\"repo_path\":\"$REPO\"}" </dev/null >"$WORK/b" 2>/dev/null & b=$!
  bounded_wait "$a" 120; ra=$RC; bounded_wait "$b" 120; rb=$RC
  if ((ra == 0 && rb == 0)) && is_json "$WORK/a" && is_json "$WORK/b" && integrity; then
    ok "concurrent index #$i: both rc 0, DB integrity ok"
  else fail "concurrent index #$i: rc=$ra/$rb or integrity failed"; fi
done

# ── M7 / TEST-6: help and install/uninstall output never advise MCP setup ─
MCP_SETUP_RE='mcp server|mcpServers|\.mcp\.json|claude mcp add'
for argv in "--help" "-h" "cli --help" "install --help" "uninstall --help" \
            "update --help" "config --help" "install" "uninstall --dry-run -y"; do
  # shellcheck disable=SC2086  # argv is a deliberate word list
  run_bounded 10 "$WORK/o" "$WORK/e" null $argv
  # Removal reports name the file they edited; they are not setup advice.
  hits="$(cat "$WORK/o" "$WORK/e" | grep -viE '(^|[[:space:]])removed[[:space:]]' | grep -iE "$MCP_SETUP_RE")"
  if ((RC == 124)); then fail "'$argv': timed out"
  elif [[ -n $hits ]]; then fail "'$argv' mentions MCP setup: $(echo "$hits" | head -2)"
  else ok "'$argv' output MCP-setup free (rc=$RC)"; fi
done

# ── Artifacts ────────────────────────────────────────────────────────────
bad="$(find "$WORK" \( -type s -o -name '*.sock' -o -name '*cohort*' -o -name '*daemon*' -o -name '*startup_lock*' \) 2>/dev/null)"
[[ -z $bad ]] && ok "no socket/daemon artifacts under temp root" || fail "artifacts: $bad"
new_tmp="$(comm -13 <(echo "$TMP_BEFORE") <(tmp_sockets))"
[[ -z $new_tmp ]] && ok "no new sockets in /tmp" || fail "new sockets in /tmp: $new_tmp"

echo "cli-only smoke: $FAILS failure(s)"
((FAILS == 0))
