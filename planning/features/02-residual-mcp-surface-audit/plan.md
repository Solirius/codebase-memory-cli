# Plan 02 — `residual-mcp-surface-audit`

**Spec:** `spec.md` (this folder) | **Status:** COMPLETED | **Order:** strictly sequential, TASK-1 → TASK-9

The reference IDs used below (API-*, ARCH-*, FAIL-*, TEST-*, GUARD-*, AUDIT-*) are defined in `spec.md`. No task edits the shared core.
The shared core is `src/foundation`, `src/store`, `src/cypher`, `src/pipeline` and `internal/cbm`.

Most of the live-server tests below use `tests/test_httpd.c`, suite `httpd`, which already has `th_server_start` and `th_http_raw` helpers.
The fastest way to run them is `scripts/test.sh --suites httpd`.

---

## [TASK-1] Link gate: forbid router symbols and protocol strings (red first)
- **Files:** `cli-only.mk`
- **Behaviour:** `verify-cli-only-link` fails when either of the following is present in `$(CLI_ONLY_BIN)`:
  - `nm` finds a symbol with prefix `cbm_mcp_server_handle` or `cbm_jsonrpc_`;
  - `strings` finds any of `"jsonrpc"`, `"tools/list"`, `"protocolVersion"` or `"notifications/initialized"`.

  The check prints up to 5 hits per token (ARCH-8).
- **[STEP-2] Red:** `make -f Makefile.cbm verify-cli-only-link` → FAIL on `cbm_mcp_server_handle` and `jsonrpc`. This shows the current D-2 leak. Record the output in the Outcome section.
- **[STEP-3]** Leave the check red. TASK-2 and TASK-4 turn it green.
- **Verify:** the failure lists the expected tokens and nothing unexpected, for example no false positive from `"uninitialized"`.
- **Risk:** `strings` may produce false positives from the vendored SQLite or yyjson. If a token hits there, inspect the hit before narrowing the check. Do not drop a token without a comment explaining why.

## [TASK-2] Compile `mcp.c` and `http_server.c` under the guard in `cbm-cli`
- **Files:** `cli-only.mk`
- **Behaviour:** `cbm-cli` compiles `src/mcp/mcp.c` and `src/ui/http_server.c` with `-DCBM_FORK_CLI_ONLY=1` into separate objects. It `filter-out`s both files from `CLI_ONLY_REST_SRCS`. The header comment is updated so it no longer says "mcp.c stays unguarded" (ARCH-6 a, b).
- **[STEP-2] Red:** `make -f Makefile.cbm cbm-cli` → link error. `http_server.c` still references `cbm_mcp_server_handle`, which the guarded `mcp.c` no longer defines. This is the expected red, and TASK-4 fixes it.
- **Verify:** confirmed after TASK-4 by `scripts/build.sh --cli-only` (zero warnings).
- **Risk:** ABI. The guard only fences declarations and bodies; `cbm_mcp_server_t` has the same layout under both settings. Check this by reading the `mcp.h` guards before building.

## [TASK-3] View routes `/api/projects`, `/api/schema`, `/api/snippet` (unguarded, additive)
- **Files:** `src/ui/http_server.c`, `tests/test_httpd.c`
- **Behaviour:** implements API-1 to API-5 and FAIL-1 to FAIL-7 with:
  - three static GET handlers;
  - the helper `view_reply_tool`, which builds args with `yyjson_mut_doc` and `yyjson_mut_strcpy`, calls `cbm_mcp_handle_tool` and unwraps `content[0].text`.

  All params are decoded into bounded stack buffers (4096 bytes), and integers are parsed with `strtol` plus an end-pointer and range check. The handlers are registered in the dispatcher before the existing `/api/*` fallthrough. Estimated size is ~120 LOC.
- **[STEP-2] Red:** add these tests to `test_httpd.c`:
  - `ui_view_projects_ok`, `ui_view_schema_ok`, `ui_view_snippet_ok` (200, body has `projects`/`node_labels`/`source`, no `"jsonrpc"`);
  - `ui_view_missing_param_400`, `ui_view_bad_int_400`, `ui_view_oversize_param_400`, `ui_view_wrong_method_rejected`.

  `scripts/test.sh --suites httpd` → the new tests fail with 404.
- **[STEP-3] Green:** implement the handlers, then rerun `--suites httpd`.
- **Verify:** `scripts/test.sh --suites httpd` is ASan/UBSan clean, and `make -f Makefile.cbm cbm` builds with zero warnings.
- **Risk:** check the ownership order from MEM-2 and MEM-3 on every exit path; ASan leak checking must pass. Engine errors pass through with status 200 (FAIL-6). No JSON is built by string concatenation.

## [TASK-4] Guard out `/rpc` in fork builds
- **Files:** `src/ui/http_server.c`, `tests/test_httpd.c`
- **Behaviour:** `#ifndef CBM_FORK_CLI_ONLY` wraps `handle_rpc`, `rpc_is_allowed_for_ui` (plus the JSON helpers only they use), the `/rpc` dispatch branch and the `/rpc` clause in `route_is_protected` (ARCH-1). The default build is unchanged.
- **[STEP-2] Red:** in `test_httpd.c`, add `ui_fork_rejects_jsonrpc_everywhere` wrapped in `#ifdef CBM_FORK_CLI_ONLY`. It POSTs `initialize`, `tools/list` and `tools/call` to `/`, `/rpc`, `/api/projects`, `/api/schema`, `/api/snippet` and `/api/nope`, and asserts status ≠ 200 and no `"jsonrpc"` in the body. Also wrap the existing `/rpc` live tests in `#ifndef CBM_FORK_CLI_ONLY`, because they are upstream behaviour.
- **[STEP-3] Green:** add the guards. Then run TASK-5's guarded runner and `scripts/test.sh --suites httpd` (default build still green).
- **Verify:** `scripts/build.sh --cli-only` builds (TASK-2 now links), and `make -f Makefile.cbm verify-cli-only-link` → PASS, which turns TASK-1 green.
- **Risk:** GUARD-1. The guard must not change the default build's `/rpc` behaviour (the existing tests prove this). Helpers that are used only inside the guard must go inside it too, so the fork build has no unused-function warnings.

## [TASK-5] Guarded HTTP test runner `test-cli-only-ui`
- **Files:** `cli-only.mk`
- **Behaviour:** a new phony target, `test-cli-only-ui`. It builds the existing test runner with `http_server.c`, `mcp.c` and `tests/test_httpd.c` compiled with `-DCBM_FORK_CLI_ONLY=1` into a separate `BUILD_DIR` (for example `build/c-cli-only-test`). It runs only the `httpd` suite. Test seams follow `scripts/test.sh` rules, and the target is not a prerequisite of `cbm-cli`.
- **[STEP-2] Red:** with TASK-4's test present and its guards temporarily reverted, `make -f Makefile.cbm test-cli-only-ui` → `ui_fork_rejects_jsonrpc_everywhere` FAILS (`/rpc` returns 200). This is the negative control.
- **[STEP-3] Green:** restore the guards and rerun → PASS.
- **Verify:** `make -f Makefile.cbm test-cli-only-ui` is ASan/UBSan clean.
- **Risk:** a separate build dir prevents guarded objects from mixing into the default `test-runner`. If reusing the runner's source list turns out to be heavy, reuse `$(TEST_HTTPD_SRCS)` and the existing link line only. Do not duplicate other suites.

## [TASK-6] Front end: replace `rpc.ts` with `views.ts`
- **Files:** `graph-ui/src/api/views.ts` (new), `graph-ui/src/api/views.test.ts` (new), `graph-ui/src/api/rpc.ts` (delete), `graph-ui/src/hooks/useProjects.ts`, `graph-ui/src/hooks/useProjects.test.tsx`, `graph-ui/src/components/NodeDetailPanel.tsx`, `graph-ui/src/components/NodeDetailPanel.test.tsx`
- **Behaviour:** implements FE-1 and FE-2. `getProjects`, `getSchema` and `getSnippet` send GET requests with `encodeURIComponent`, and throw `ViewError(status, message)` when the response is not ok. Pagination loops and rendered data are unchanged.
- **[STEP-2] Red:** write `views.test.ts` and update the two component/hook tests to mock GET `/api/projects|schema|snippet`, including 2-page pagination. `cd graph-ui && npm test` → fails because `views.ts` is missing.
- **[STEP-3] Green:** add `views.ts`, switch the callers, delete `rpc.ts`, then run `npm test`.
- **Verify:** `npm test` passes offline, and `grep -rn "/rpc\|jsonrpc" graph-ui/src` → empty (M3).
- **Risk:** an offline install only. If `node_modules` is missing, stop and report; do not fetch packages. The UI bundle must work on both builds, which TASK-3's unguarded routes guarantee.

## [TASK-7] `install` refusal and MCP-free help (D-5, M6, M7)
- **Files:** `src/cli/cli.c`, `tests/test_cli_only_install.sh` (new), `tests/test_cli_only_smoke.sh`, `cli-only.mk` (wire the new script into `test-cli-only`)
- **Behaviour:**
  - Under `#ifdef CBM_FORK_CLI_ONLY`, `cbm_cmd_install` prints the CLI-2 JSON error and returns non-zero before any filesystem access.
  - The help text that tells users to register or configure an MCP server is guarded (CLI-4).
  - `uninstall` is unchanged. Check it is remove-only (ARCH-5): if any branch writes new keys, guard only that branch in `agent_clients.c`/`agent_profiles.c`, and record the result in the Outcome section.
- **[STEP-2] Red:** write `test_cli_only_install.sh`:
  - create a temp `HOME` with fixture configs for every client in `agent_clients.c`;
  - take a `find … -exec shasum` baseline;
  - run `install` and `install -y` → assert exit ≠ 0, the CLI-2 JSON and an identical checksum;
  - seed a `codebase-memory-mcp` entry and run `uninstall` → the entry is removed, and there is no new or changed `mcpServers|"mcp"|.mcp.json|codebase-memory-mcp` match.

  Extend the smoke test to case-insensitively grep `--help`, every `<cmd> --help` and `install`/`uninstall` output for `mcp server|mcpServers|\.mcp\.json|claude mcp add`. `make -f Makefile.cbm test-cli-only` → FAIL.
- **[STEP-3] Green:** add the guards to `cli.c`, then rerun `test-cli-only`.
- **Verify:** `make -f Makefile.cbm test-cli-only` and `scripts/test.sh --suites cli` pass; `tests/test_cli.c` covers upstream install behaviour in the default build and must not change.
- **Risk:** the temp `HOME` is created with `mktemp -d` and removed by `trap`, and the real `$HOME` must never be touched (assert `HOME` ≠ original). The guard sits before argument parsing, so no partial writes are possible.

## [TASK-8] Narrow or justify warning suppressions (D-3, M5)
- **Files:** `cli-only.mk`
- **Behaviour:** remove `-Wno-unused-function -Wno-unused-variable` from `CLI_ONLY_EDGE_CFLAGS`. Add them back only for TUs that fail `-Werror`, per TU, with a comment listing the guarded-out helpers that cause each warning (ARCH-7). The new guarded `mcp.c`/`http_server.c` objects get no suppressions.
- **[STEP-2] Red (negative control):** with both flags removed, run `make -f Makefile.cbm cbm-cli`. The warnings name the failing TUs and helpers, and that output is the justification. Record it.
- **[STEP-3] Green:** apply the minimal per-TU flags, then run `scripts/build.sh --cli-only` → zero warnings.
- **Verify:** `scripts/build.sh --cli-only`, `verify-cli-only-link`.
- **Risk:** do not wrap upstream helpers in `main.c`/`cli.c` to silence warnings, because that would enlarge the upstream diff.

## [TASK-9] Engine-only include audit and full gates (M4, G1–G9)
- **Files:** `planning/features/02-residual-mcp-surface-audit/plan.md` (Outcome section only), `planning/ROADMAP.md` (status row and D-2/D-3/D-5 closure)
- **Behaviour:** for every TU linked into `cbm-cli`, list each `#include` of `src/mcp/*`/`src/daemon/*` with the symbols it uses, classified as `engine` / `lock` / `classifier` / `FORBIDDEN` (AUDIT-1).
- **TDD-BYPASS:** this is a review artefact, not behaviour — the substitute evidence is the audit table plus the TASK-1 link gate.
- **[STEP-5] Full run:** `scripts/test.sh`, `make -f Makefile.cbm cbm`, `scripts/build.sh --cli-only`, `make -f Makefile.cbm verify-cli-only-link`, `make -f Makefile.cbm test-cli-only`, `make -f Makefile.cbm test-cli-only-ui`, `cd graph-ui && npm test`.
- **Verify:** all green with zero warnings. A diff review confirms GUARD-1 (the only unguarded C change is the additive TASK-3 code) and no shared-core edits.
- **Risk:** any `FORBIDDEN` row blocks completion. If one appears, fix it with a guard at the edge TU, not in `src/mcp`/`src/daemon`.

---

## Outcome
### Status (2026-09-28): COMPLETED

TASK-9 gates (2026-09-28), all zero warnings:
- `make -f Makefile.cbm cbm` ✅; `scripts/build.sh --cli-only` ✅; `verify-cli-only-link` PASS
- `test-cli-only` PASS (smoke + `test_cli_only_install`); `test-cli-only-ui` 70 passed, 1 skipped
- `graph-ui`: `npm ci --offline` (cache now complete), vitest 51/51, `tsc -b` clean, no `/rpc|jsonrpc` in `src`
- Full C suite via `bash scripts/run-tests-parallel.sh build/c/test-runner`: 7994 passed, 0 failed, 8 skipped (141 suites)
- Diff review: no edits in `src/foundation|store|cypher|pipeline|mcp|daemon` or `internal/cbm`; C changes in
  `main.c`/`cli.c` are guarded; the only unguarded C change is the additive TASK-3 view code (GUARD-1 ✅).
- `scripts/test.sh` unquoted-`$(CURDIR)` bug recorded as roadmap debt D-6 (owned by 06), not fixed here.

### Evidence per task
- **TASK-1**
  - Red: `verify-cli-only-link` hit the string `jsonrpc` from `src/main.c` `main_report_client_failure` (~l.1698). The symbol `cbm_mcp_server_handle` was already dead-stripped.
  - Green: after TASK-4, the gate passes.
- **TASK-2**
  - Red: compile error at `http_server.c:1800`, where `cbm_mcp_server_handle` is undeclared under the guard.
  - Green: after TASK-4.
- **TASK-3**
  - Red: the 7 new `ui_view_*` tests got 404 (6 failed).
  - Green: the `httpd` suite passed 71.
  - The oversize test is rejected by the transport's 2K cap with 400, which counts as FAIL-2 end-to-end.
- **TASK-4**
  - `/rpc`, `rpc_is_allowed_for_ui`, `json_unique_member` and the `/rpc` clause in `route_is_protected` are all guarded.
  - The JSON-RPC stdout frame in `main.c` is guarded.
  - The `/rpc`-only tests are wrapped in `#ifndef`, and the #798 watchdog test has a fork variant that uses `GET /api/projects`.
- **TASK-5**
  - Negative control: with an unguarded `http_server.o`, `ui_fork_rejects_jsonrpc_everywhere` FAILED (69 passed, 1 failed).
  - Green: 70 passed, 1 skipped.
- **TASK-6**
  - Baseline: 47 vitest tests passed.
  - Green: 51 passed and `tsc -b` is clean. `rpc.ts` was deleted, and grepping `src` for `/rpc|jsonrpc` finds nothing.
  - Needed a one-time online `npm ci`, approved by the user, because the offline cache was missing `zustand`.
- **TASK-7**
  - Red: `install` wrote configs (11 failures).
  - Green: `test_cli_only_install.sh` PASS.
  - Help check red on the upstream binary ("Run MCP server on stdio"); `test-cli-only` passes.
- **TASK-8**
  - Negative control: only `main.c` fails `-Werror` (19 unused helpers). `cli.c`, `mcp.c` and `http_server.c` build clean.
  - Per-TU flags (`CLI_ONLY_MAIN_CFLAGS`); `--cli-only` builds with 0 warnings.
- **TASK-9:** the AUDIT-1 table is below. TDD-BYPASS applies (this is a review artefact).

### Findings and deviations
- **ARCH-5:** `uninstall` is remove-only; it removes only canonical upstream entries. No edits to `agent_clients.c` or `agent_profiles.c` were needed.
  - Its output includes removal-report lines such as "mcp: removed canonical entry from …". The output checks exclude lines containing `removed`.
- **D-3 justification:** the `main.c` helpers left unreferenced by the guards:
  - the variable `g_daemon_client`;
  - the functions `client_start_parent_watchdog`, `main_build_identity_status_name`, `main_hook_report_absent_daemon`, `main_hook_report_conflicted_daemon`, `main_local_command_cancel`, `main_local_maintenance_context_init`, `main_local_maintenance_finish`, `main_local_transition_acquire`, `main_local_transition_close`, `main_report_client_bootstrap_failure`, `main_run_daemon_ctl`, `main_run_hook_frontend`, `main_version_cohort_close`, `parse_ui_flags`, `setup_signal_handlers`, `worker_containment_unavailable`, `worker_prepare_process_group` and `worker_start_parent_watchdog`.
- `test-cli-only-ui` keeps `mcp.c` unguarded, because `test_mcp.c` and the probe re-exec modes need the router. The guarded `mcp.c` is covered by `verify-cli-only-link`.
- `DELETE /api/projects` (the exact path) now returns 405, because view dispatch runs before the other routes.
- `CLI_ACTIVATION_BUSY_MESSAGE` (cli.c:176, "MCP server") is left unguarded. In the fork it is reachable only through test-injected activation ops.
- `update` still downloads over the network in the fork; only its message was guarded. Egress is owned by 04.

### AUDIT-1: symbols that survive in `codebase-memory-cli` (no FORBIDDEN rows)
| TU | Include | Symbols | Class |
|---|---|---|---|
| main.c | daemon/bootstrap.h | cbm_daemon_process_role / bootstrap_endpoint_new | classifier / lock |
| main.c | daemon/ipc.h | ipc_endpoint_free, ipc_validation_detail | lock |
| main.c | daemon/project_lock.h | acquire, try_acquire, lease_release, manager_new/free | lock |
| main.c | mcp/mcp.h | handle_tool, server_new/free, setters, parse_tool_profile_args, tools_help_list | engine |
| main.c | mcp/index_supervisor.h | set_worker_role_options, worker_active, worker_memory_budget_bytes, worker_response_out | engine |
| main.c | application.h, frontend.h, host.h, version_cohort.h | none (declarations used only in guarded code) | — |
| cli.c | ipc.h / mcp.h | validation_detail / cbm_mcp_tool_input_schema | lock / engine |
| cli.c | bootstrap.h, runtime.h, version_cohort.h, index_supervisor.h | none | — |
| client_adapter.c | mcp.h | tool_input_schema | engine |
| hook_augment.c | mcp.h | handle_tool, server_new/free, server_session_root | engine |
| index_supervisor.c | runtime.h | none | — |
| service.c | — | none (dead-stripped) | — |
| bootstrap.c | ipc.h | endpoint_new, cbm_daemon_rendezvous_key | classifier / lock |
| ipc.c | — | none | — |
| project_lock.c | ipc.h | ipc_private_lock_directory_new | lock |
| http_server.c | mcp.h | handle_tool, server_new/free, setters, cbm_mcp_text_result | engine |

