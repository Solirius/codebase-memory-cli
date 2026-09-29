# Roadmap: codebase-memory-cli — finish the CLI-only, no-MCP, no-network fork

**Created:** 2026-09-24 | **Supersedes:** `.claude/planning/active/ROADMAP.md` (deleted in `82dd58c5`; readable via `git show 4c69055f:.claude/planning/active/ROADMAP.md`)

## 1. Executive Objective

Ship `build/c/codebase-memory-cli` as a single standalone C11 binary that you can prove is free of
MCP and daemons. It must make no outbound network calls. It keeps the upstream tree-sitter
code-graph tools as one-shot `cli <tool> --format json` commands. The only listener it may open is
an opt-in graph UI bound to `127.0.0.1`. You drive it from GitHub Copilot by running commands, not
by registering an MCP server. It must stay easy to merge from upstream: every removal sits behind
`CBM_FORK_CLI_ONLY`, and the shared core (`src/foundation`, `src/store`, `src/cypher`,
`src/pipeline`, `internal/cbm`) is not edited.

## 2. Progress carried over from the previous roadmap

| Old # | Feature | Outcome | Evidence |
|---|---|---|---|
| F1 | Fork framing & doc correction | ✅ COMPLETED | README "About this fork"; CLI docs moved from Go/Cobra to C11 |
| F2 | Split MCP engine from stdio/JSON-RPC transport | ✅ COMPLETED | Guards in `src/mcp/mcp.c` (3 blocks) and `mcp.h`; `verify-mcp-engine-split` PASS; quality gate PASS |
| F3 | Daemon-free in-process CLI execution | ✅ COMPLETED | `run_cli` routed in-process under guard; `project_lock` kept, `version_cohort` dropped; quality gate WARN accepted with substitute evidence (E1 strace and E2 live-daemon diff were deferred) |
| F4 | CLI-only build target & entry dispatch | ✅ COMPLETED (via new 01) | `cli-only.mk` `cbm-cli`, `scripts/build.sh --cli-only`, `verify-cli-only-link` PASS, main.c role guard, section-GC link isolation; smoke test `make -f Makefile.cbm test-cli-only` |
| F5 | Loopback UI subcommand | ✅ COMPLETED (via new 03) | `cbm-cli-with-ui`, `codebase-memory-cli ui`, `verify-cli-only-no-http`, `test-cli-only-ui-live` |
| F6 | No-network hardening | ⬜ not started → **new 04** |
| F7 | Copilot CLI integration + quickstart | ⬜ not started → **new 05** |

Debt carried forward (each item has an owner below):
- **D-1** F3 E1 (dynamic strace no-network proof) and E2 (daemon-vs-guarded byte diff) were only
  covered by substitute evidence. → E1 is owned by 04 (dynamic egress/listen audit). E2 is dropped: the
  guards are reviewed in the diff instead of proven by a byte-for-byte build comparison.
- **D-2** ✅ CLOSED by 02 (`/rpc` guarded out; UI uses `/api/projects|schema|snippet`). `src/ui/http_server.c:1800` calls `cbm_mcp_server_handle`, so part of the MCP JSON-RPC
  handler stays reachable through the UI (`/rpc`, used by `graph-ui/src/api/rpc.ts`). → owned by 02.
- **D-3** ✅ CLOSED by 02 (narrowed to `main.c` only, 19 guarded-out helpers listed in 02 plan.md). `cli-only.mk` builds main.c/cli.c with `-Wno-unused-function -Wno-unused-variable`. →
  02 either justifies this or narrows it.
- **D-5** ✅ CLOSED by 02 (`install` refuses in the fork; `uninstall` is remove-only). `install`/agent setup (`src/cli/agent_clients.c`, `agent_profiles.c`, `cli.c`) writes
  `mcpServers`/`.mcp.json` entries into Copilot and other agent configs. That registers the app
  as an MCP server, which the company ban forbids. → owned by 02; its CLI-only replacement is in 05.
- **D-6** `Makefile.cbm` `test-par` runs `cd $(CURDIR)` unquoted, so `scripts/test.sh` fails (Error 127)
  when the repo path contains a space. Pre-existing; workaround `bash scripts/run-tests-parallel.sh
  build/c/test-runner`. → owned by 06 (acceptance gate must run from any path).
- **D-4** `service.c`, `bootstrap.c` and `ipc.c` are still linked, and only section GC removes
  their socket code. → 04 must prove it both statically (nm) and dynamically.

## 3. Milestone Sequence (strictly sequential)

| # | Feature Slug | Scope Summary | Dependencies | Status |
|---|---|---|---|---|
| 01 | `cli-only-dispatch-verification` | Finish old F4: smoke test (`tests/test_cli_only_smoke.sh`) for inert non-CLI argv, all 17 tools returning JSON, concurrent indexing serialized | F1–F3 (done) | COMPLETED |
| 02 | `residual-mcp-surface-audit` | Remove `/rpc` and every MCP JSON-RPC router path (D-2); stop `install`/agent setup writing MCP server configs (D-5); rewire `graph-ui/src/api/rpc.ts` to plain `/api/*`; resolve D-3; nm/strings gate | 01 | COMPLETED |
| 03 | `loopback-ui-subcommand` | Optional `cbm-cli-with-ui` build; `codebase-memory-cli ui [--port N]` starts the graph UI in-process, bound to 127.0.0.1 only; plain `cbm-cli` contains no HTTP code | 02 | COMPLETED (U7 manual pending) |
| 04 | `no-network-hardening` | Compile out the GitHub update check; `security-network.sh` forbids all egress and every socket/bind/listen except the loopback UI; prune the allowlist; fork `security-cli` target; closes D-1 and D-4 | 03 | PENDING |
| 05 | `copilot-cli-and-quickstart` | Copilot command-invocation recipes (VS Code, Visual Studio, JetBrains, Android Studio), wrapper script, verified quickstart and JSON shapes | 04 | PENDING |
| 06 | `release-acceptance-gate` | One `make -f Makefile.cbm fork-acceptance` that runs the fork checks; upstream-merge rehearsal | 05 | PENDING |

## 4. Global Invariants (apply to every milestone)

1. **Pure C (C11, POSIX-compliant)**, plus the vendored grammars. No Go, no new runtime, no network fetches during the build.
2. **Strict compilation guard:** every fork-specific removal or replacement is wrapped in
   `#ifdef CBM_FORK_CLI_ONLY` / `#ifndef CBM_FORK_CLI_ONLY`. With the guard undefined, the default
   `codebase-memory-mcp` build behaves as upstream (checked by reviewing the diff, not by byte comparison).
3. **Zero background daemons, zero network sockets, zero MCP runtime** in `codebase-memory-cli`:
   no AF_UNIX daemon socket, no cohort/lock artifacts beyond `project_lock`.
   **End-state (non-negotiable):** users have no way to reach MCP JSON-RPC. That means no stdio
   transport, no `initialize`/`tools/list`/`tools/call` handling on any channel (stdin, the UI's
   HTTP endpoint, or anything else), and the router symbols (`cbm_mcp_server_handle`,
   `cbm_mcp_server_run`, `cbm_jsonrpc_*`) are absent from the shipped binary, and no command
   writes MCP server registrations (`mcpServers`, `.mcp.json`) into any agent/IDE config. Only the
   tool *engine* (`cbm_mcp_handle_tool`) survives, as an internal C call. Internal "mcp" names are
   acceptable (**protocol-only policy**, decided 2026-09-24). Copilot agents integrate **only** by
   running CLI commands. Since 02 the UI no longer routes to
   the router and `verify-cli-only-link` forbids the router symbols/protocol strings; 06 A6 re-proves it.
4. **CLI arguments are the only input interface** (decided 2026-09-24). You drive every capability
   with `codebase-memory-cli <command> [flags]`. There is no stdin protocol, no RPC endpoint, and
   no behaviour that requires a config file. Every capability the UI offers has an equivalent CLI
   command (parity is checked in 06 A7).
5. **The UI is optional and off by default:** it is compiled in only by `scripts/build.sh --cli-only
   --with-ui` (`cbm-cli-with-ui`). The plain `cbm-cli` binary contains no HTTP server code at all.
   When it is built in, the UI uses its own view endpoints (`/api/*`) only; **`/rpc` is removed**.
6. **Loopback only (127.0.0.1)** for the local UI (default port 9749). Never `0.0.0.0` or `::`.
   The listener opens only when you run `ui`.
7. **Shared core untouched** (`src/foundation`, `src/store`, `src/cypher`, `src/pipeline`,
   `internal/cbm`). Any exception needs a written justification in the feature's `spec.md`.
8. **Test seams are opt-in:** `scripts/test.sh` sets TEST_SEAMS=1; `scripts/build.sh --cli-only` never does.
9. **Memory/FD hygiene:** ASan + UBSan clean; no leaked FDs or SQLite handles; no `sprintf`/`strcpy`/`strcat`/`gets`.

## 5. Quality Gates (keep them proportional)

A milestone is COMPLETED when the checks that match its change pass:

| Check | When | Command |
|---|---|---|
| Build | always | `scripts/build.sh --cli-only` (and `make -f Makefile.cbm cbm` if `src/` changed), zero warnings |
| Link isolation | always | `make -f Makefile.cbm verify-cli-only-link` |
| Smoke | always | `make -f Makefile.cbm test-cli-only` |
| Unit/sanitizer suite | only when `src/` changes | `scripts/test.sh` (or `--suites <name>` for the touched area) |
| Security | from 04 onward | `make -f Makefile.cbm security` |
| Review | always | code review of the diff: guards in place, no shared-core edits |

Workflow: `summary.md` → short `plan.md` → build → the checks above → update the status here.
Record the outcome in the milestone's `plan.md`. There is no separate evidence file.

## 6. Deferred across the roadmap (needs new sign-off)

- Packaging and distribution (Homebrew, npm, signed release archives, CI wiring for fork gates).
- Native VS Code / JetBrains plugins beyond command snippets.
- Deleting `src/mcp/` or `src/daemon/` from the tree. We exclude them at link time and behind
  guards so merges stay cheap; physical deletion is not planned.
- UI auth beyond loopback binding and the existing readiness/Host checks.
- Migrating the Go parity tests (an upstream concern).
