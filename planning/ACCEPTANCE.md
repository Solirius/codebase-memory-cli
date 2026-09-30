# Release acceptance record — codebase-memory-cli

Evidence for milestone 06 (`release-acceptance-gate`). Regenerate with
`make -f Makefile.cbm fork-acceptance`; the machine-readable result is
`build/c/fork-acceptance.json` and per-step logs are in `build/c/fork-acceptance/logs/`.

## Run

| Field | Value |
|---|---|
| Commit | `da7dfc16` + shellcheck clean-up of `scripts/fork-acceptance.sh` |
| Host | macOS, Darwin arm64, GNU Make 3.81, bash 3.2 |
| Date | 2026-09-30 |
| Command | `FORK_ACCEPTANCE_STRICT=1 make -f Makefile.cbm fork-acceptance` |
| Result | **PASS** (exit 0), strict: no SKIPs |

## Gate output

| Status | Step | Evals | Check |
|---|---|---|---|
| PASS | G1 | G1 | build `cbm-cli` + default `cbm` (`-Werror`) |
| PASS | G2 | G2 E3 E4 M1 M4 | `verify-cli-only-link`: symbols, protocol strings, inert argv |
| PASS | U1 | U1 N | `verify-cli-only-no-http`: no listener/egress imports |
| PASS | N | N | `update` refused and not in help |
| PASS | M5 | M5 | warning suppressions only in `CLI_ONLY_MAIN_CFLAGS` (D-3) |
| PASS | G3 | G3 E3–E6 M6 M7 Q6 | `test-cli-only`: smoke + install round-trip |
| PASS | M2 | M2 | guarded httpd suite: `/rpc` 404, JSON-RPC rejected |
| PASS | M3a / M3b | M3 | no `/rpc` in `graph-ui/src`; `graph-ui` vitest |
| PASS | Q1-3 | Q1 Q2 Q3 | `scripts/verify-docs.sh` |
| PASS | Q4 | Q4 | `shellcheck scripts/cbm` (0.11.0); the gate scripts have no shellcheck warnings |
| PASS | U2-6 | U2–U6 | `test-cli-only-ui-live` on the ASan UI binary |
| PASS | UIBIN | M1 A6 | release UI variant `build/c/codebase-memory-cli-ui` builds |
| PASS | A6a | A6 | `initialize` / `notifications/initialized` / `tools/list` / `tools/call` on stdin under 19 argv shapes: no JSON-RPC reply; nm/strings clean |
| PASS | A6b | A6 M1 | UI variant: nm/strings clean; the same 4 messages as GET and POST to 21 routes (every `/api/*` route plus `/`, `/rpc`, `/mcp`, `/sse`, `/messages`): no JSON-RPC reply |
| PASS | A7 | A7 | UI capability ↔ CLI command parity (table in `docs/CLI_BUILD_RUN_GUIDE.md` §5); each command runs on a fixture; `ui` rejects non-argv config |
| PASS | A5 | A5 | `otool -L`: only `/usr/lib/libSystem`, `libc++`, `libz` (both binaries) |
| PASS | G6 | G6 A3 | shared core identical to upstream base `055fbb7d` |
| PASS | G4 | G4 | unit/sanitizer suite, `make test-par` |
| PASS | G5 | G5 | `make security` |
| N/A | E7 | E7 | byte diff dropped in 01 (D-1 E2); guards are reviewed instead (list below) |
| MANUAL | U7 | U7 | graph renders in a browser — PASS, recorded in 03 `plan.md` (2026-09-29) |
| MANUAL | Q5 | Q5 | VS Code agent transcript — **OPEN** (steps in `docs/COPILOT_CLI_INTEGRATION.md` §6) |

Negative control: the A6/M1 static check run against the upstream `codebase-memory-mcp`
binary fails (it links `cbm_mcp_server_run`, `cbm_jsonrpc_*` and contains `jsonrpc`, `tools/list`).

## A2 — merge rehearsal

`scripts/fork-merge-rehearsal.sh --ref 80eb92a7 --no-acceptance` (upstream `main`,
"Merge pull request #2252", 304 commits past the fork base): exit 3, conflicts only in
fork-edge files — `Makefile.cbm`, `src/cli/cli.c`, `src/main.c`. `src/mcp/mcp.c`,
`src/ui/http_server.c` and the shared core merged cleanly. **A2 PASS.** Resolving those three
conflicts and running `fork-acceptance` on the merged tree belongs to the next upstream sync.

## A3 — shared core

`git diff 055fbb7d -- src/foundation src/store src/cypher src/pipeline internal/cbm` → empty.

## Guarded fork edits (`grep -rn CBM_FORK_CLI_ONLY src`)

| File | Guard sites | What is fenced |
|---|---|---|
| `src/main.c` | 24 | in-process `cli` routing, `ui` dispatch, non-CLI roles inert, fork help, `update`/install lines |
| `src/cli/cli.c` | 13 | version-cohort activation machinery, `install`/`uninstall --copilot`, `update` refusal |
| `src/mcp/mcp.c` | 9 | JSON-RPC/stdio transport, tools/list + prompts builders, session + router + stdio loop |
| `src/mcp/mcp.h` | 6 | transport and router declarations |
| `src/ui/http_server.c` | 5 | `/rpc` bridge removed; `/api/*` view dispatch |
| `src/cli/cli_only_ui.{c,h}`, `src/cli/cli_only_install.h` | — | fork-only files, never in `PROD_SRCS` |

Upstream files touched since the base: `src/cli/cli.c`, `src/main.c`, `src/mcp/mcp.c`,
`src/mcp/mcp.h`, `src/ui/http_server.c`; build/tooling files (`Makefile.cbm`, `CMakeLists.txt`,
`scripts/build.sh`, `scripts/gen_*`); `graph-ui/src` (`api/` moved off `/rpc`, plus the
components/hooks that call it); docs, planning and agent-harness files. Milestone 06 changes no
`src/` file.

## A4 review

| Field | Value |
|---|---|
| Reviewer | GitHub Copilot agent (automated review); human sign-off pending |
| Date | 2026-09-30 |
| Range | `git diff 2f0e35e1..HEAD` (milestone 06) |
| Verdict | **PENDING SIGN-OFF**. A human changes this to PASS. |

Findings and fixes:

1. `scripts/fork-acceptance.sh` A6b: a curl failure (HTTP `000`, UI down) was counted as "no JSON-RPC
   reply", so a crashed UI could falsely PASS. **Fixed:** `000` now fails the step. `UIBIN A6b` re-run: PASS.
2. `scripts/fork-acceptance.sh`: a `FORK_ACCEPTANCE_ONLY` run deleted every step's log, including evidence
   from the last full run. **Fixed:** partial runs keep the other logs. The full strict run in R5
   regenerates every log.
3. `scripts/fork-merge-rehearsal.sh`: when acceptance failed, the script exited with make's rc (2), which
   clashes with the documented "2 = usage". **Fixed:** it now exits 1.

Checked, no change needed:
- Fail-fast: every step stops the gate on a non-zero rc. `step` runs each step in a subshell, so HOME,
  TMPDIR and the cache never leak. Scratch space is `mktemp -d build/c/fork-acceptance/work.XXXXXX`,
  and the script removes it on exit.
- bash 3.2: no associative arrays, `mapfile` or `${var,,}`. Empty arrays are never expanded under `set -u`.
  `shellcheck -S warning` is clean for both scripts.
- Rehearsal: it never pushes. It merges only in a throwaway `build/c/merge-rehearsal-*` worktree on a new
  branch, which the EXIT trap removes (unless `--keep`). The user's branch and tree are never touched.
- `cli-only.mk` `fork-acceptance`: additive `.PHONY` target, not a prerequisite of any other target.
- `Makefile.cbm` D-6: only `cd $(CURDIR)` → `cd "$(CURDIR)"`, so behaviour changes only for paths that
  contain spaces.

## Closed debt

- **D-6** closed: every `cd $(CURDIR)` in `Makefile.cbm` is now `cd "$(CURDIR)"`; `make test-par`
  (G4) passes from a path that contains a space.

## Deferred

- **A1 (Linux devcontainer):** deferred 2026-09-30 — Linux is out of scope for now. To revive,
  run `FORK_ACCEPTANCE_STRICT=1 make -f Makefile.cbm fork-acceptance` inside the devcontainer
  (A5 uses `ldd` there instead of `otool -L`).

## Open items

- **A4:** review done (see "A4 review"); human sign-off pending.
- **Q5:** manual Copilot transcript.
