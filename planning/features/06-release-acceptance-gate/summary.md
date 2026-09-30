# 06 — `release-acceptance-gate`

**Milestone:** 06 of 06 | **Status:** COMPLETED | **New**

## 1. Objective & Rationale
Earlier milestones each prove their own slice. This one proves the whole product in one command.
It also proves that the fork survives an upstream merge, because staying mergeable is a design
constraint, not a hope.

## 2. Architectural Scope
- **Add:** `fork-acceptance` target in `cli-only.mk`, which runs G1–G6 plus every milestone's evals (E3–E7, M1–M7, U1–U6, N1–N6, Q1–Q4, Q6; U7 and Q5 are manual and recorded separately) in order and fails fast.
- **Add:** `scripts/fork-merge-rehearsal.sh`. It fetches the upstream remote if one is configured locally (no network needed if the remote is already fetched), merges into a throwaway branch, runs `fork-acceptance`, and reports conflicting files. It never pushes.
- **Add:** `planning/ACCEPTANCE.md`, the evidence record: the commit SHA, the gate outputs, and the list of guarded fork edits (`grep -rn CBM_FORK_CLI_ONLY`).
- **Untouched:** everything in `src/`.

## 3. Boundary & Guard Constraints
Re-checks every global invariant (ROADMAP §4) on the final binary. Nothing new is allowed.

## 4. CLI Contract Expectations
`make -f Makefile.cbm fork-acceptance` → exit 0 and a summary table, with a machine-readable
`build/c/fork-acceptance.json`.

## 5. Pre-conditions
01–05 COMPLETED.

## 6. Acceptance & Verification Gates
| Eval | Check |
|---|---|
| A1 | `fork-acceptance` PASS on a clean clone (macOS host and Linux devcontainer) — macOS only; Linux deferred 2026-09-30 |
| A2 | Merge rehearsal against the latest fetched upstream: conflicts only in fork-edge files (`src/main.c`, `src/cli/cli.c`, `src/mcp/mcp.c` guards, `src/ui/http_server.c` guard, `graph-ui/src/api`, build files) |
| A3 | Shared-core diff against upstream base is empty: `git diff <upstream-base> -- src/foundation src/store src/cypher src/pipeline internal/cbm` |
| A4 | `ACCEPTANCE.md` complete and reviewed via `/review` → PASS |
| A6 | **No MCP JSON-RPC reachable:** send `initialize`, `tools/list` and `tools/call` JSON-RPC to (a) the binary's stdin under every argv shape and (b) every UI HTTP route. None returns a JSON-RPC response. `nm`/`strings` show no router, transport or protocol symbols. Any failure blocks release |
| A7 | **CLI-argument parity:** every UI capability (browse, index, index status, delete project, ADR read/write, project health, processes, logs, graph/layout data) has a documented `codebase-memory-cli` command that works without the UI; `ui` itself takes only argv flags |
| A5 | The binary runs on a machine that has no toolchain installed (dependencies checked with `otool -L` / `ldd`: libc/system only) |

## 7. Sub-Agent Execution Readiness
✅ Ready for `/roadmap-goal` once 05 is COMPLETED.
