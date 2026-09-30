#!/usr/bin/env bash
# fork-acceptance.sh — fork milestone 06: the release acceptance gate.
#
# Runs every fork gate and milestone eval in order and stops at the first
# failure: G1–G6, E3–E6, M1–M7, U1–U6, N (04's no-network checks), Q1–Q4, Q6,
# A3 and A5–A7. U7 and Q5 are manual; they are listed as MANUAL and never block.
#
# Output: a summary table on stdout, per-step logs under build/c/fork-acceptance/,
# and build/c/fork-acceptance.json (machine-readable). Exit 0 = every automated
# step passed (or was skipped for a missing optional prerequisite, see below).
#
# Invoked by `make -f Makefile.cbm fork-acceptance`, which exports MAKE and the
# forbidden symbol/string lists from cli-only.mk. It can also be run directly.
#
# Optional prerequisites. The build never fetches anything, so a clean clone
# lacks some of them. Steps that need them are SKIPped, not failed:
#   graph-ui/node_modules  (cd graph-ui && npm ci)  -> M3 npm test, U2–U6, A6 UI half
#   shellcheck                                      -> Q4
# FORK_ACCEPTANCE_STRICT=1 turns every SKIP into a failure (use it for a release).
#
# Environment:
#   FORK_ACCEPTANCE_STRICT=1        SKIP counts as failure
#   FORK_ACCEPTANCE_UPSTREAM_BASE   upstream commit for A3 (default: merge-base
#                                   with upstream/main if that ref exists, else
#                                   the pinned fork point below)
#   FORK_ACCEPTANCE_ONLY="ID ..."   iteration only: run just these step IDs
#                                   (result is then PARTIAL, never PASS)
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 2
MAKE_CMD="${MAKE:-make}"
MK=("$MAKE_CMD" -f Makefile.cbm --no-print-directory)
STRICT="${FORK_ACCEPTANCE_STRICT:-0}"
OUT_DIR="$ROOT/build/c/fork-acceptance"
LOG_DIR="$OUT_DIR/logs"
JSON="$ROOT/build/c/fork-acceptance.json"
BIN="$ROOT/build/c/codebase-memory-cli"
UI_BIN="$ROOT/build/c/codebase-memory-cli-ui"
UI_ASAN_BIN="$ROOT/build/c/codebase-memory-cli-ui-asan"
# Upstream commit the fork branched from (DeusData/codebase-memory-mcp,
# "Merge pull request #2138 from DeusData/fix/decision-bd").
PINNED_UPSTREAM_BASE=055fbb7d
SHARED_CORE=(src/foundation src/store src/cypher src/pipeline internal/cbm)

: "${CLI_ONLY_FORBIDDEN_PREFIXES:=cbm_daemon_runtime_ cbm_daemon_frontend_ cbm_daemon_host_ cbm_daemon_application_ cbm_daemon_service_ cbm_version_cohort_ cbm_daemon_maintenance_monitor_ cbm_daemon_ipc_listen cbm_daemon_ipc_accept cbm_daemon_ipc_connect cbm_daemon_ipc_startup_lock_ cbm_daemon_ipc_local_transition_ cbm_daemon_ipc_lifetime_reservation_ cbm_mcp_server_run cbm_mcp_server_handle cbm_jsonrpc_}"
: "${CLI_ONLY_FORBIDDEN_STRINGS:=jsonrpc tools/list protocolVersion notifications/initialized}"

mkdir -p "$LOG_DIR"
rm -f "$LOG_DIR"/*.log
WORK="$(mktemp -d "$OUT_DIR/work.XXXXXX")" || { echo "mktemp failed" >&2; exit 2; }
cleanup() {
  local pids; pids="$(jobs -p)"
  [[ -n $pids ]] && kill -9 $pids 2>/dev/null
  chmod -R u+w "$WORK" 2>/dev/null; rm -rf "$WORK"
}
trap cleanup EXIT

HAVE_NODE_MODULES=0; [[ -d graph-ui/node_modules ]] && HAVE_NODE_MODULES=1
HAVE_SHELLCHECK=0; command -v shellcheck >/dev/null && HAVE_SHELLCHECK=1

# ── result bookkeeping ───────────────────────────────────────────────────────
IDS=(); EVALS=(); DESCS=(); STATUSES=(); SECS=(); NOTES=()
record() { IDS+=("$1"); EVALS+=("$2"); DESCS+=("$3"); STATUSES+=("$4"); SECS+=("$5"); NOTES+=("$6"); }

json_str() { python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1"; }

write_report() {
  local overall=$1 sha dirty i n=${#IDS[@]}
  sha="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
  dirty=false; [[ -n "$(git status --porcelain --untracked-files=no 2>/dev/null)" ]] && dirty=true
  {
    printf '{\n  "gate": "fork-acceptance",\n  "result": "%s",\n  "commit": "%s",\n  "dirty": %s,\n' \
      "$overall" "$sha" "$dirty"
    printf '  "host": %s,\n  "timestamp": "%s",\n  "strict": %s,\n  "steps": [\n' \
      "$(json_str "$(uname -sm)")" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$([[ $STRICT == 1 ]] && echo true || echo false)"
    for ((i = 0; i < n; i++)); do
      printf '    {"id": %s, "evals": %s, "check": %s, "status": "%s", "seconds": %s, "note": %s, "log": %s}%s\n' \
        "$(json_str "${IDS[$i]}")" "$(json_str "${EVALS[$i]}")" "$(json_str "${DESCS[$i]}")" \
        "${STATUSES[$i]}" "${SECS[$i]}" "$(json_str "${NOTES[$i]}")" \
        "$(json_str "build/c/fork-acceptance/logs/${IDS[$i]}.log")" "$([[ $i -lt $((n - 1)) ]] && echo ,)"
    done
    printf '  ]\n}\n'
  } >"$JSON"

  echo
  echo "=== fork-acceptance summary ($(git rev-parse --short HEAD 2>/dev/null)) ==="
  printf '%-8s %-7s %6s  %-26s %s\n' STATUS STEP SECS EVALS CHECK
  for ((i = 0; i < n; i++)); do
    printf '%-8s %-7s %6s  %-26s %s%s\n' "${STATUSES[$i]}" "${IDS[$i]}" "${SECS[$i]}" "${EVALS[$i]}" \
      "${DESCS[$i]}" "${NOTES[$i]:+ — ${NOTES[$i]}}"
  done
  echo "result: $overall   (json: build/c/fork-acceptance.json, logs: build/c/fork-acceptance/logs/)"
}

finish_fail() {
  local id=$1
  echo "---- last 40 lines of build/c/fork-acceptance/logs/$id.log ----"
  tail -n 40 "$LOG_DIR/$id.log"
  write_report FAIL
  exit 1
}

# step ID EVALS DESC CMD... : runs CMD (a shell function or command), logs it,
# stops the gate on failure.
step() {
  local id=$1 evals=$2 desc=$3; shift 3
  local log="$LOG_DIR/$id.log" start rc
  if ! selected "$id"; then return 0; fi
  echo "==> [$id] $evals: $desc"
  start=$(date +%s)
  ("$@") >"$log" 2>&1; rc=$?  # subshell: step env (HOME, TMPDIR) never leaks
  if ((rc == 0)); then
    record "$id" "$evals" "$desc" PASS $(($(date +%s) - start)) ""
  else
    record "$id" "$evals" "$desc" FAIL $(($(date +%s) - start)) "rc=$rc"
    echo "    FAIL (rc=$rc)"
    finish_fail "$id"
  fi
}

selected() { [[ -z ${FORK_ACCEPTANCE_ONLY:-} || " $FORK_ACCEPTANCE_ONLY " == *" $1 "* ]]; }

skip() {
  local id=$1 evals=$2 desc=$3 why=$4
  if ! selected "$id"; then return 0; fi
  echo "==> [$id] $evals: $desc — SKIP ($why)"
  echo "SKIP: $why" >"$LOG_DIR/$id.log"
  if [[ $STRICT == 1 ]]; then
    record "$id" "$evals" "$desc" FAIL 0 "skipped under FORK_ACCEPTANCE_STRICT=1: $why"
    finish_fail "$id"
  fi
  record "$id" "$evals" "$desc" SKIP 0 "$why"
}

manual() { record "$1" "$2" "$3" MANUAL 0 "$4"; echo "LOG: manual — $4" >"$LOG_DIR/$1.log"; }

# ── helpers used by steps ────────────────────────────────────────────────────
# bounded PID SECS -> RC (124 and SIGKILL on timeout)
bounded() {
  local pid=$1 secs=$2 waited=0
  while kill -0 "$pid" 2>/dev/null && ((waited < secs * 10)); do sleep 0.1; waited=$((waited + 1)); done
  if kill -0 "$pid" 2>/dev/null; then kill -9 "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; RC=124
  else wait "$pid"; RC=$?; fi
}

sandbox_env() {
  export HOME="$WORK/home" TMPDIR="$WORK/tmp" CBM_CACHE_DIR="$WORK/cache"
  export XDG_CONFIG_HOME="$WORK/home/.config" XDG_CACHE_HOME="$WORK/home/.cache" LC_ALL=C
  mkdir -p "$HOME" "$TMPDIR" "$CBM_CACHE_DIR"
}

JSONRPC_MSGS='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"a6","version":"0"}}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"list_projects","arguments":{}}}'

# Static half of M1/A6 on any binary: forbidden router symbols and protocol strings.
check_no_router() {
  local bin=$1 fail=0 p t syms strs
  syms="$WORK/syms.txt"; strs="$WORK/strs.txt"
  nm "$bin" | awk '$2 ~ /^[TtDdBbSs]$/ {sub(/^_/, "", $3); print $3}' >"$syms"
  strings -a "$bin" >"$strs"
  for p in $CLI_ONLY_FORBIDDEN_PREFIXES; do
    if grep -qE "^$p" "$syms"; then echo "FAIL: $bin links $p*"; fail=1; else echo "ok absent symbol: $p*"; fi
  done
  for t in $CLI_ONLY_FORBIDDEN_STRINGS; do
    if grep -qF -- "$t" "$strs"; then echo "FAIL: $bin contains string '$t'"; fail=1; else echo "ok absent string: $t"; fi
  done
  grep -qx cbm_mcp_handle_tool "$syms" && echo "ok engine present: cbm_mcp_handle_tool" \
    || { echo "FAIL: engine cbm_mcp_handle_tool missing"; fail=1; }
  return $fail
}

# ── step bodies ──────────────────────────────────────────────────────────────
g1_build() {
  "${MK[@]}" cbm-cli && "${MK[@]}" cbm || return 1
  echo "ok: cbm-cli and default cbm built"
}

m5_suppressions() {
  # D-3: -Wno-unused-* may appear only in the main.c flag set (and its ASan twin).
  local bad
  bad="$(grep -n -- '-Wno-' cli-only.mk | grep -v '^\s*#' | grep -v 'CLI_ONLY_MAIN_CFLAGS' | grep -v '^[0-9]*:#')"
  if [[ -n $bad ]]; then echo "FAIL: unexpected warning suppression outside CLI_ONLY_MAIN_CFLAGS:"; echo "$bad"; return 1; fi
  echo "ok: only CLI_ONLY_MAIN_CFLAGS relaxes warnings (justified in 02 plan.md, D-3)"
}

n_no_network() {
  sandbox_env
  local out rc
  out="$("$BIN" update 2>&1 </dev/null)"; rc=$?
  if ((rc == 0)) || ! grep -q 'not available in the CLI-only build' <<<"$out"; then
    echo "FAIL: 'update' rc=$rc out=$out"; return 1
  fi
  echo "ok: update refused (rc=$rc)"
  if "$BIN" --help | grep -qE '^\s*codebase-memory-[a-z]+ update'; then echo "FAIL: help advertises update"; return 1; fi
  echo "ok: help does not advertise update"
}

m3_grep_rpc() {
  if grep -rn '/rpc' graph-ui/src; then echo "FAIL: graph-ui/src still references /rpc"; return 1; fi
  echo "ok: no /rpc in graph-ui/src"
}

m3_npm_test() { (cd graph-ui && npm test --silent); }

q4_shellcheck() { shellcheck -s sh scripts/cbm; }

u_live() { "${MK[@]}" test-cli-only-ui-live; }

build_ui_release() { "${MK[@]}" cbm-cli-with-ui CLI_ONLY_UI_BIN=build/c/codebase-memory-cli-ui; }  # relative: make recipes are unquoted

a6_stdin() {
  sandbox_env
  local shapes=("" "frobnicate" "--stdio" "mcp" "serve" "--cbm-daemon-internal" "daemon start"
    "daemon status" "--ui=true" "cli" "cli --json" "cli list_projects" "cli --json list_projects"
    "ui" "ui --format json" "config list" "uninstall --copilot --dry-run" "hook-augment" "--version")
  local argv fail=0 out
  for argv in "${shapes[@]}"; do
    out="$WORK/a6.out"
    # shellcheck disable=SC2086  # argv is a deliberate word list
    (cd "$WORK" && printf '%s\n' "$JSONRPC_MSGS" | "$BIN" $argv >"$out" 2>&1) &
    bounded "$!" 10
    if ((RC == 124)); then echo "FAIL: '$argv' blocked on stdin"; fail=1
    elif grep -q '"jsonrpc"' "$out" || grep -q '"protocolVersion"' "$out"; then
      echo "FAIL: '$argv' answered JSON-RPC:"; head -c 400 "$out"; echo; fail=1
    else echo "ok: '$argv' rc=$RC, no JSON-RPC reply"; fi
  done
  check_no_router "$BIN" || fail=1
  return $fail
}

a6_ui() {
  sandbox_env
  local fail=0 port="" i route method out code body
  check_no_router "$UI_BIN" || fail=1
  "$UI_BIN" ui --port 0 --format json >"$WORK/ui.out" 2>"$WORK/ui.err" </dev/null &
  local pid=$!
  for ((i = 0; i < 100; i++)); do
    port="$(sed -n 's/.*"url":"http:\/\/127\.0\.0\.1:\([0-9]*\)".*/\1/p' "$WORK/ui.out" | head -n1)"
    [[ -n $port ]] && break; sleep 0.1
  done
  if [[ -z $port ]]; then echo "FAIL: UI did not start"; cat "$WORK/ui.err"; kill -9 "$pid" 2>/dev/null; return 1; fi
  echo "ok: UI listening on 127.0.0.1:$port"
  local routes=(/ /rpc /mcp /api /api/rpc /api/projects /api/schema /api/snippet /api/layout /api/repo-info
    /api/index /api/index-status /api/ui-config /api/project /api/browse /api/adr /api/project-health
    /api/processes /api/logs /sse /messages)
  for route in "${routes[@]}"; do
    for method in POST GET; do
      while IFS= read -r msg; do
        [[ -z $msg ]] && continue
        out="$WORK/r.body"
        code="$(curl -s -o "$out" -w '%{http_code}' -m 5 -X "$method" -H 'Content-Type: application/json' \
          -H "Host: 127.0.0.1:$port" --data "$msg" "http://127.0.0.1:$port$route")"
        body="$(head -c 2000 "$out")"
        if grep -q '"jsonrpc"' <<<"$body" || grep -q '"protocolVersion"' <<<"$body"; then
          echo "FAIL: $method $route answered JSON-RPC ($code): ${body:0:200}"; fail=1
        fi
      done <<<"$JSONRPC_MSGS"
    done
    echo "ok: $route (GET/POST × initialize, initialized, tools/list, tools/call) no JSON-RPC"
  done
  kill -INT "$pid" 2>/dev/null; bounded "$pid" 5
  ((RC == 0)) || { echo "FAIL: UI exit rc=$RC after SIGINT"; fail=1; }
  return $fail
}

a7_parity() {
  sandbox_env
  local fail=0 help tools cap cmd
  help="$("$BIN" --help)"
  tools="$(sed -n '/^Tools:/,$p' <<<"$help" | tr ',' '\n' | sed 's/Tools://; s/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$')"
  # capability|required CLI surface (tool name, or a help pattern prefixed with '=')
  local parity=(
    "browse projects|list_projects" "browse graph|search_graph" "graph/layout data|query_graph"
    "graph/layout data (overview)|get_architecture" "schema|get_graph_schema" "code snippet|get_code_snippet"
    "index|index_repository" "index status|index_status" "project health|index_status"
    "delete project|delete_project" "ADR read/write|manage_adr"
    "logs|=--verbose" "processes (in-process indexing progress)|=--progress")
  for entry in "${parity[@]}"; do
    cap=${entry%%|*}; cmd=${entry#*|}
    if [[ $cmd == =* ]]; then
      if grep -qF -- "${cmd#=}" <<<"$help"; then echo "ok: $cap -> cli ${cmd#=}"; else echo "FAIL: $cap: '${cmd#=}' not in --help"; fail=1; fi
    elif grep -qx "$cmd" <<<"$tools"; then echo "ok: $cap -> cli $cmd"
    else echo "FAIL: $cap: tool $cmd not listed in --help"; fail=1; fi
  done
  # Parity table is documented for users.
  grep -q 'UI capability' docs/CLI_BUILD_RUN_GUIDE.md || { echo "FAIL: parity table missing from docs/CLI_BUILD_RUN_GUIDE.md"; fail=1; }
  # Live: index a fixture and drive the UI capabilities through the CLI.
  local repo="$WORK/repo" p
  mkdir -p "$repo"; printf 'int helper(void){return 1;}\nint main(void){return helper();}\n' >"$repo/main.c"
  (cd "$repo" && git init -q && git add . && git -c user.email=a@b -c user.name=a commit -qm init) || return 1
  "$BIN" cli --quiet index_repository "{\"repo_path\":\"$repo\"}" >"$WORK/idx.json" || { echo "FAIL: index_repository"; return 1; }
  p="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["project"])' "$WORK/idx.json")" || return 1
  echo "ok: cli index_repository indexed fixture as project $p"
  for cmd in "list_projects|{}" "index_status|{\"project\":\"$p\"}" "get_graph_schema|{\"project\":\"$p\"}" \
    "search_graph|{\"project\":\"$p\",\"query\":\"helper\"}" \
    "query_graph|{\"project\":\"$p\",\"query\":\"MATCH (n) RETURN n.name LIMIT 5\"}" \
    "get_code_snippet|{\"project\":\"$p\",\"qualified_name\":\"helper\"}" \
    "get_architecture|{\"project\":\"$p\"}" "manage_adr|{\"project\":\"$p\",\"mode\":\"get\"}" \
    "delete_project|{\"project\":\"$p\"}"; do
    if "$BIN" cli --quiet "${cmd%%|*}" "${cmd#*|}" >"$WORK/a7.out" 2>&1 && [[ -s "$WORK/a7.out" ]]; then
      echo "ok: cli ${cmd%%|*} rc 0"
    else echo "FAIL: cli ${cmd%%|*}:"; head -c 400 "$WORK/a7.out"; echo; fail=1; fi
  done
  # `ui` takes argv flags only: unknown flags and stdin are refused/ignored.
  "$BIN" ui --config x </dev/null >/dev/null 2>&1; [[ $? -eq 2 ]] && echo "ok: ui rejects non-argv config (--config → rc 2)" \
    || { echo "FAIL: ui accepted --config"; fail=1; }
  return $fail
}

a5_deps() {
  local bin fail=0 libs
  for bin in "$BIN" ${HAVE_UI_BIN:+"$UI_BIN"}; do
    if [[ $(uname -s) == Darwin ]]; then
      libs="$(otool -L "$bin" | tail -n +2 | awk '{print $1}')"
      echo "$bin:"; echo "$libs" | sed 's/^/  /'
      if grep -vE '^(/usr/lib/|/System/Library/)' <<<"$libs" | grep -q .; then echo "FAIL: non-system dylib"; fail=1; fi
    else
      libs="$(ldd "$bin" 2>&1)"
      echo "$bin:"; echo "$libs" | sed 's/^/  /'
      if grep -vE '(linux-vdso|ld-linux|libc\.so|libm\.so|libpthread|libdl\.so|librt\.so|libstdc\+\+|libgcc_s|libz\.so|statically linked)' <<<"$libs" | grep -q .; then
        echo "FAIL: non-system shared library"; fail=1
      fi
    fi
  done
  return $fail
}

g6_review() {
  local base="${FORK_ACCEPTANCE_UPSTREAM_BASE:-}" diff
  if [[ -z $base ]]; then
    if git rev-parse -q --verify upstream/main >/dev/null; then base="$(git merge-base HEAD upstream/main)"
    else base=$PINNED_UPSTREAM_BASE; fi
  fi
  git rev-parse -q --verify "$base^{commit}" >/dev/null || { echo "FAIL: upstream base $base not in this clone"; return 1; }
  echo "upstream base: $(git log -1 --format='%h %s' "$base")"
  diff="$(git diff --stat "$base" -- "${SHARED_CORE[@]}")"
  if [[ -n $diff ]]; then echo "FAIL (A3): shared core differs from upstream base:"; echo "$diff"; return 1; fi
  echo "ok (A3): shared core identical to upstream base (${SHARED_CORE[*]})"
  echo "guarded fork edits (grep -rn CBM_FORK_CLI_ONLY src):"
  grep -rn 'CBM_FORK_CLI_ONLY' src | awk -F: '{print $1}' | sort | uniq -c
  echo "non-fork-only upstream files changed since base:"
  git diff --name-only "$base" -- src | grep -vE '^src/cli/cli_only_' || true
}

g4_unit() { "${MK[@]}" test-par; }
g5_security() { "${MK[@]}" security; }

# ── the gate ─────────────────────────────────────────────────────────────────
echo "fork-acceptance: $(git rev-parse --short HEAD) on $(uname -sm) (strict=$STRICT)"

step G1      "G1"                 "build cbm-cli + default cbm (-Werror)"          g1_build
step G2      "G2 E3 E4 M1 M4"     "verify-cli-only-link (symbols, strings, inert argv)" "${MK[@]}" verify-cli-only-link
step U1      "U1 N"               "verify-cli-only-no-http (no listener/egress imports)" "${MK[@]}" verify-cli-only-no-http
step N       "N"                  "update refused and not advertised"             n_no_network
step M5      "M5"                 "warning suppressions limited to main.c"        m5_suppressions
step G3      "G3 E3-E6 M6 M7 Q6"  "test-cli-only (smoke + install round-trip)"    "${MK[@]}" test-cli-only
step M2      "M2"                 "guarded httpd suite (/rpc 404, JSON-RPC rejected)" "${MK[@]}" test-cli-only-ui
step M3a     "M3"                 "no /rpc in graph-ui/src"                       m3_grep_rpc
if ((HAVE_NODE_MODULES)); then step M3b "M3" "graph-ui vitest (offline)" m3_npm_test
else skip M3b "M3" "graph-ui vitest (offline)" "graph-ui/node_modules missing (cd graph-ui && npm ci)"; fi
step Q1-3    "Q1 Q2 Q3"           "scripts/verify-docs.sh"                        scripts/verify-docs.sh
if ((HAVE_SHELLCHECK)); then step Q4 "Q4" "shellcheck scripts/cbm" q4_shellcheck
else skip Q4 "Q4" "shellcheck scripts/cbm" "shellcheck not installed"; fi
HAVE_UI_BIN=""
if ((HAVE_NODE_MODULES)); then
  step U2-6  "U2-U6"              "test-cli-only-ui-live (ASan UI binary)"        u_live
  step UIBIN "M1 A6"              "build release UI variant ($(basename "$UI_BIN"))" build_ui_release
  HAVE_UI_BIN=1
else
  skip U2-6  "U2-U6"              "test-cli-only-ui-live (ASan UI binary)"        "graph-ui/node_modules missing"
fi
step A6a     "A6"                 "stdin JSON-RPC under every argv shape + nm/strings" a6_stdin
if [[ -n $HAVE_UI_BIN ]]; then step A6b "A6 M1" "UI variant: nm/strings + JSON-RPC to every HTTP route" a6_ui
else skip A6b "A6 M1" "UI variant: nm/strings + JSON-RPC to every HTTP route" "no UI binary (graph-ui/node_modules missing)"; fi
step A7      "A7"                 "UI capability ↔ CLI command parity"            a7_parity
step A5      "A5"                 "runtime deps are system libraries only"        a5_deps
step G6      "G6 A3"              "shared-core diff vs upstream base empty; guard inventory" g6_review
step G4      "G4"                 "unit/sanitizer suite (make test-par)"          g4_unit
step G5      "G5"                 "make security"                                 g5_security
record E7 "E7" "daemon-vs-guarded byte diff" N/A 0 "dropped in 01 (D-1 E2); guards reviewed in G6"
manual U7 "U7" "graph renders in a browser" "recorded in 03 plan.md (2026-09-29)"
manual Q5 "Q5" "VS Code agent answers via CLI, no MCP" "see planning/ACCEPTANCE.md"

if [[ -n ${FORK_ACCEPTANCE_ONLY:-} ]]; then write_report PARTIAL; else write_report PASS; fi
exit 0
