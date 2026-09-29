# 03 — `loopback-ui-subcommand`

**Milestone:** 03 of 06 | **Status:** COMPLETED | **Carries over:** old F5

## 1. Objective & Rationale
This brings back the graph **visualization** (a 3D view of nodes and edges, with filters, stats and
node details), which used to depend on the daemon. The UI is optional and compiled in only on
request. It starts from a CLI argument and binds to loopback only.

## 2. Architectural Scope
- **Modify:** `cli-only.mk` splits the build into `cbm-cli` (default: **no** `src/ui` HTTP server linked) and `cbm-cli-with-ui` (embeds the `graph-ui` bundle); `scripts/build.sh --cli-only [--with-ui]`.
- **Modify (guarded):** `src/main.c` / `src/cli/cli.c` add a `ui` command that runs `cbm_http_server_new` → configure (in-process engine bridge from 02, `project_lock`, readiness) → `cbm_http_server_run`. It exists only when built with the UI; without it, `ui` prints "built without UI" and exits 2.
- **Read-only reference:** `src/ui/httpd.c:243-250` (already binds 127.0.0.1 only).
- **Untouched:** shared core, `src/daemon`.

## 3. Boundary & Guard Constraints
- The only input is CLI arguments (`--port N`); no config file is required.
- Binds `127.0.0.1` only; no option exists to change the interface.
- The listener exists only while `ui` is running; SIGINT/SIGTERM → clean shutdown.

## 4. CLI Contract Expectations
```
codebase-memory-cli ui [--port N] [--format json]
```
Default port 9749. With `--format json` it prints `{"status":"listening","url":"http://127.0.0.1:9749"}`.
Port in use → `{"error":{"code":"port_in_use"}}` and a non-zero exit.

## 5. Pre-conditions
02 COMPLETED (`/rpc` is already gone).

## 6. Acceptance & Verification Gates
| Eval | Check |
|---|---|
| U1 | Plain `cbm-cli` binary: `nm` shows no `bind`/`listen`/`cbm_http_server_*` → it contains no socket code at all |
| U2 | With-UI binary: start on an ephemeral port, `curl http://127.0.0.1:<p>/` → 200, SIGINT → rc 0 within 2 s |
| U3 | `lsof -iTCP -sTCP:LISTEN -P`: listener on 127.0.0.1 only |
| U4 | `scripts/security-ui.sh`: a foreign `Host:` header is rejected |
| U5 | ASan start/stop cycle ×10: no leaks, no FD growth |
| U6 | M2 from 02 re-run on the running server: no JSON-RPC answered |
| U7 | Manual: the graph renders, and filters and node details work in a browser (screenshot recorded) |
Plus the standard gates G1–G9.

## 7. Sub-Agent Execution Readiness
✅ Ready for `/roadmap-goal` once 02 is COMPLETED.
