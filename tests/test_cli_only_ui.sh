#!/usr/bin/env bash
# Live test for the fork's `ui` subcommand (milestone 03, U2–U6).
# Needs a binary built by `make -f Makefile.cbm cbm-cli-with-ui`.
# - `ui --port 0 --format json` prints {"status":"listening","url":...}
# - GET / → 200; SIGINT/SIGTERM → rc 0 within 2 s                        (U2)
# - the only listener is 127.0.0.1                                       (U3)
# - a foreign Host header is rejected with 403                           (U4)
# - 10 start/stop cycles all exit 0; FDs do not grow over 50 requests    (U5)
# - POST /rpc answers no JSON-RPC                                        (U6)
# - a busy port → {"error":{"code":"port_in_use"}} and non-zero exit
# - POST /api/index indexes in-process; /api/projects then lists it
# All scratch state lives under build/c/ (never /tmp). Needs curl and lsof.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="${CBM_TEST_BINARY:-${ROOT}/build/c/codebase-memory-cli}"
[[ -x "$BIN" ]] || { echo "missing binary: $BIN" >&2; exit 2; }
for tool in curl lsof; do command -v "$tool" >/dev/null || { echo "$tool required" >&2; exit 2; }; done

mkdir -p "${ROOT}/build/c"
WORK="$(mktemp -d "${ROOT}/build/c/cli-only-ui.XXXXXX")" || { echo "mktemp failed" >&2; exit 2; }
cleanup() {
  local pids; pids="$(jobs -p)"
  [[ -n $pids ]] && kill -9 $pids 2>/dev/null
  rm -rf "$WORK"
}
trap cleanup EXIT
export HOME="$WORK/home" TMPDIR="$WORK/tmp" CBM_CACHE_DIR="$WORK/cache"
export XDG_CONFIG_HOME="$HOME/.config" XDG_CACHE_HOME="$HOME/.cache" LC_ALL=C
mkdir -p "$HOME" "$TMPDIR" "$CBM_CACHE_DIR"

FAILS=0
ok()   { echo "ok   $*"; }
fail() { echo "FAIL $*"; FAILS=$((FAILS + 1)); }

UI_PID=""
UI_URL=""
# start_ui OUT ERR ARGS... -> sets UI_PID and UI_URL (empty on failure).
start_ui() {
  local out=$1 err=$2; shift 2
  "$BIN" ui "$@" </dev/null >"$out" 2>"$err" &
  UI_PID=$!
  UI_URL=""
  local i
  for ((i = 0; i < 100; i++)); do
    UI_URL="$(sed -n 's/.*"url":"\(http:[^"]*\)".*/\1/p' "$out" 2>/dev/null)"
    [[ -n $UI_URL ]] && return 0
    kill -0 "$UI_PID" 2>/dev/null || return 1
    sleep 0.05
  done
  return 1
}

# stop_ui SIGNAL -> sets RC and ELAPSED_MS (RC 124 if still alive after 2 s).
stop_ui() {
  local sig=$1 waited=0 start end
  start=$(python3 -c 'import time; print(int(time.time()*1000))' 2>/dev/null || echo 0)
  kill "-$sig" "$UI_PID" 2>/dev/null
  while kill -0 "$UI_PID" 2>/dev/null && ((waited < 20)); do sleep 0.1; waited=$((waited + 1)); done
  if kill -0 "$UI_PID" 2>/dev/null; then
    kill -9 "$UI_PID" 2>/dev/null; wait "$UI_PID" 2>/dev/null; RC=124
  else
    wait "$UI_PID"; RC=$?
  fi
  end=$(python3 -c 'import time; print(int(time.time()*1000))' 2>/dev/null || echo 0)
  ELAPSED_MS=$((end - start))
}

fd_count() { lsof -n -p "$1" 2>/dev/null | awk 'NR > 1' | wc -l | tr -d ' '; }

# ── U2/U3/U4/U6 on one running server ────────────────────────────────────────
if start_ui "$WORK/ui.out" "$WORK/ui.err" --port 0 --format json; then
  line="$(head -n 1 "$WORK/ui.out")"
  if [[ $line =~ ^\{\"status\":\"listening\",\"url\":\"http://127\.0\.0\.1:[0-9]+\"\}$ ]]; then
    ok "json banner: $line"
  else
    fail "json banner shape: $line"
  fi
  PORT="${UI_URL##*:}"

  code="$(curl -s -o "$WORK/index.html" -w '%{http_code}' "$UI_URL/")"
  if [[ $code == 200 ]] && grep -qi '<html' "$WORK/index.html"; then ok "U2 GET / -> 200 (embedded UI)"
  else fail "U2 GET / -> $code"; fi

  code="$(curl -s -o "$WORK/projects.json" -w '%{http_code}' "$UI_URL/api/projects")"
  [[ $code == 200 ]] && ok "GET /api/projects -> 200" || fail "GET /api/projects -> $code"

  listeners="$(lsof -nP -a -p "$UI_PID" -iTCP -sTCP:LISTEN 2>/dev/null | awk 'NR > 1 {print $9}')"
  if [[ $listeners == "127.0.0.1:$PORT" ]]; then ok "U3 only listener: $listeners"
  else fail "U3 listeners: ${listeners:-<none>}"; fi

  code="$(curl -s -o /dev/null -w '%{http_code}' -H 'Host: evil.example' "$UI_URL/api/projects")"
  [[ $code == 403 ]] && ok "U4 foreign Host -> 403" || fail "U4 foreign Host -> $code"
  code="$(curl -s -o /dev/null -w '%{http_code}' -H 'Origin: http://evil.example' "$UI_URL/api/projects")"
  [[ $code == 403 ]] && ok "U4 foreign Origin -> 403" || fail "U4 foreign Origin -> $code"

  body="$(curl -s -X POST -H 'Content-Type: application/json' \
    -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' "$UI_URL/rpc")"
  if grep -q '"jsonrpc"' <<<"$body"; then fail "U6 /rpc answered JSON-RPC: ${body:0:120}"
  else ok "U6 /rpc answers no JSON-RPC"; fi

  # Busy port: same port while the first server holds it.
  "$BIN" ui --port "$PORT" --format json </dev/null >"$WORK/busy.out" 2>"$WORK/busy.err"; rc=$?
  if [[ $rc -ne 0 ]] && grep -q '"code":"port_in_use"' "$WORK/busy.out"; then ok "busy port -> port_in_use (rc=$rc)"
  else fail "busy port rc=$rc out=$(cat "$WORK/busy.out")"; fi

  # In-process indexing through the UI, serialized by project_lock.
  mkdir -p "$WORK/repo"; printf 'def f():\n    return 1\n' >"$WORK/repo/a.py"
  code="$(curl -s -o "$WORK/index.json" -w '%{http_code}' -X POST -H 'Content-Type: application/json' \
    -d "{\"root_path\":\"$WORK/repo\"}" "$UI_URL/api/index")"
  if [[ $code == 202 || $code == 200 ]]; then
    for ((i = 0; i < 100; i++)); do
      curl -s "$UI_URL/api/index-status" >"$WORK/status.json"
      grep -q '"status":"\(done\|error\)"' "$WORK/status.json" && break
      sleep 0.2
    done
    if grep -q '"status":"done"' "$WORK/status.json" && curl -s "$UI_URL/api/projects" | grep -q 'repo'; then
      ok "POST /api/index indexed in-process"
    else
      fail "POST /api/index status: $(cat "$WORK/status.json")"
    fi
  else
    fail "POST /api/index -> $code $(cat "$WORK/index.json")"
  fi

  # U5 (FD hygiene): 50 requests must not grow the process's descriptor count.
  before="$(fd_count "$UI_PID")"
  for ((i = 0; i < 50; i++)); do curl -s -o /dev/null "$UI_URL/api/projects"; done
  after="$(fd_count "$UI_PID")"
  if [[ -n $before && $after -le $before ]]; then ok "U5 FDs stable over 50 requests ($before -> $after)"
  else fail "U5 FD growth $before -> $after"; fi

  stop_ui INT
  if [[ $RC -eq 0 && $ELAPSED_MS -le 2000 ]]; then ok "U2 SIGINT -> rc 0 in ${ELAPSED_MS} ms"
  else fail "U2 SIGINT rc=$RC after ${ELAPSED_MS} ms"; fi
  code="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/" 2>/dev/null)"
  [[ $code == 000 ]] && ok "listener gone after stop" || fail "port $PORT still answers ($code)"
else
  fail "ui did not start: $(cat "$WORK/ui.out" "$WORK/ui.err")"
fi

# ── U5: 10 start/stop cycles (SIGTERM and SIGINT alternate) ──────────────────
cycles_ok=0
for ((n = 0; n < 10; n++)); do
  sig=INT; ((n % 2)) && sig=TERM
  if start_ui "$WORK/c.out" "$WORK/c.err" --port 0 --format json &&
     [[ "$(curl -s -o /dev/null -w '%{http_code}' "$UI_URL/")" == 200 ]]; then
    stop_ui "$sig"
    if [[ $RC -eq 0 ]] && ! grep -q 'ERROR: \(Address\|Leak\)Sanitizer' "$WORK/c.err"; then
      cycles_ok=$((cycles_ok + 1))
    else
      echo "     cycle $n: rc=$RC $(head -c 300 "$WORK/c.err")"
    fi
  else
    [[ -n $UI_PID ]] && kill -9 "$UI_PID" 2>/dev/null
    echo "     cycle $n: start failed"
  fi
done
[[ $cycles_ok -eq 10 ]] && ok "U5 10/10 start/stop cycles clean" || fail "U5 $cycles_ok/10 cycles clean"

# ── text mode and argument errors ────────────────────────────────────────────
if start_ui "$WORK/t.out" "$WORK/t.err" --port=0 --format json; then stop_ui TERM; fi
"$BIN" ui --port 70000 --format json </dev/null >"$WORK/bad.out" 2>&1; rc=$?
if [[ $rc -eq 2 ]] && grep -q '"code":"invalid_argument"' "$WORK/bad.out"; then ok "bad --port -> invalid_argument rc=2"
else fail "bad --port rc=$rc $(cat "$WORK/bad.out")"; fi
"$BIN" ui --bind 0.0.0.0 </dev/null >"$WORK/bind.out" 2>&1; rc=$?
[[ $rc -eq 2 ]] && ok "no interface option (--bind rejected, rc=2)" || fail "--bind rc=$rc"

echo
if [[ $FAILS -eq 0 ]]; then echo "test_cli_only_ui: PASS"; exit 0; fi
echo "test_cli_only_ui: $FAILS failure(s)"; exit 1
