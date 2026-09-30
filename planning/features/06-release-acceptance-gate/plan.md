# 06 — `release-acceptance-gate`: plan and outcome

## Built
- `scripts/fork-acceptance.sh` runs every step in order and stops at the first failure. It
  writes a summary table, `build/c/fork-acceptance.json` and per-step logs, and runs each step in a
  subshell so one step's sandbox `HOME`/`TMPDIR` never leaks into the next.
  - Steps without their optional prerequisite (`graph-ui/node_modules`, `shellcheck`) are SKIPped.
    `FORK_ACCEPTANCE_STRICT=1` turns a SKIP into a failure. `FORK_ACCEPTANCE_ONLY="<ids>"` is for
    iteration only, and the result is then `PARTIAL`.
  - New checks: A6 (JSON-RPC on stdin under 19 argv shapes; JSON-RPC to 21 UI routes on the
    release UI variant; nm/strings on both binaries), A7 (parity table + live CLI run), A5
    (`otool -L`/`ldd`), A3/G6 (shared-core diff vs upstream base, guard inventory), M5, N.
- `cli-only.mk` `fork-acceptance` exports `MAKE` and the forbidden symbol/string lists.
- `scripts/fork-merge-rehearsal.sh` merges upstream into a throwaway worktree and branch under
  `build/c/`, classifies conflicts as fork-edge or OUTSIDE, runs the gate on a clean merge, and
  cleans up. It never pushes.
- D-6: `cd $(CURDIR)` → `cd "$(CURDIR)"` in `Makefile.cbm` (17 sites).
- The UI↔CLI parity table (A7) is in `docs/CLI_BUILD_RUN_GUIDE.md` §5.

## Outcome
See `planning/ACCEPTANCE.md`: the gate PASSes on macOS (Q4 SKIP, no shellcheck), and A2 passes
against upstream `80eb92a7`. Still open: A1 on Linux, A4 review, and Q5.
