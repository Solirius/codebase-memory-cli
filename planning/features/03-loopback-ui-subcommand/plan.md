# Plan 03 — `loopback-ui-subcommand`

**Spec:** `summary.md` (this folder) | **Status:** COMPLETED | **Shared core edits:** none

## Design
- **New fork-only TU** `src/cli/cli_only_ui.{c,h}` (never in `PROD_SRCS`; linked only by `cli-only.mk`).
  - Without `CBM_FORK_CLI_ONLY_UI`: parses `ui [--port N] [--format json|text]` and refuses with
    `ui_not_built`, exit 2. It references no HTTP symbol, so section GC strips the server from `cbm-cli`.
  - With `CBM_FORK_CLI_ONLY_UI=1`: `cbm_http_server_new(port)` → project-lock mutation guard
    (thread-safe lease list) → in-process `index_repository` executor for `POST /api/index` →
    `cbm_http_server_run` on a thread. SIGINT/SIGTERM only set a flag; the main thread stops,
    joins and frees the server. No watcher, no readiness secret (daemon-only `daemon start --open`).
- **`src/main.c` (guarded):** `ui` as `argv[1]` is routed before role handling to `main_cli_only_ui`
  (endpoint + `project_lock` manager, then `cbm_cli_only_ui_main`); help text shows `ui`;
  `cbm_http_server_set_binary_path` is skipped on the `cli` path (the `ui` module sets it).
- **`cli-only.mk`:** shared `cli_only_link` macro; `cbm-cli-with-ui` (offline `npm run build` +
  `embed-frontend.sh`, `embedded_assets.c` replaces the stub, same output name as `cbm-cli`,
  `CLI_ONLY_UI_BIN=` overrides); `cbm-cli-with-ui-asan` (CFLAGS_TEST/ASan+UBSan, test only);
  `verify-cli-only-no-http` (U1); `test-cli-only-ui-live` (U1 + U2–U6 on the ASan build).
- **`scripts/build.sh`:** `--cli-only --with-ui` now builds `cbm-cli-with-ui` (was mutually exclusive).
- **Tests:** `tests/test_cli_only_ui.sh`. **Docs:** CLI quickstart + build/run guide UI sections.
- Loopback binding is unchanged upstream `httpd.c` behaviour; there is no interface option.

## Outcome
| Eval | Result | Evidence |
|---|---|---|
| U1 | PASS | `verify-cli-only-no-http`: no `socket/bind/listen/accept` imports; no `cbm_http_server_*`/`cbm_httpd_*` except `cbm_http_server_resolve_binary_path` (filesystem helper used by `main.c`/index supervisor, no socket code); `ui` → `ui_not_built` rc 2 |
| U2 | PASS | `GET /` → 200 with embedded HTML; SIGINT → rc 0 in ~240 ms |
| U3 | PASS | `lsof -iTCP -sTCP:LISTEN`: only `127.0.0.1:<port>` |
| U4 | PASS | foreign `Host` and `Origin` → 403; `scripts/security-ui.sh` passed |
| U5 | PASS | ASan+UBSan build: 10/10 SIGINT/SIGTERM start/stop cycles rc 0, no sanitizer report; FDs 10 → 10 over 50 requests (LeakSanitizer is not enabled by default on macOS) |
| U6 | PASS | `POST /rpc` with `tools/list` answers no JSON-RPC |
| U7 | PASS (manual) | User ran `build/c/codebase-memory-cli ui` on 2026-09-29 and confirmed the graph renders in the browser (no screenshot recorded) |
| extra | PASS | busy port → `port_in_use`, rc 1; `--port 70000` → `invalid_argument` rc 2; `--bind` rejected; `POST /api/index` indexes in-process and the project appears in `/api/projects` |

Standard gates: `make cbm-cli` / `cbm-cli-with-ui` / default `codebase-memory-mcp` build with zero
warnings (`-Werror`); `verify-cli-only-link` PASS; `test-cli-only` (smoke + install) PASS.
Not run: `clang-format`/`clang-tidy` (not installed on this machine); the full `scripts/test.sh`
(no shared or upstream-built TU changed: `main.c` edits are all under `CBM_FORK_CLI_ONLY`).
