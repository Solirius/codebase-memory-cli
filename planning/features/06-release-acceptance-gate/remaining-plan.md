# 06 — remaining items: plan

**Baseline:** `da7dfc16`. `FORK_ACCEPTANCE_STRICT=1 make -f Makefile.cbm fork-acceptance` →
PASS with no SKIPs on macOS (see `planning/ACCEPTANCE.md`).

| # | Item | Owner | Blocking release? |
|---|---|---|---|
| R1 | Commit the post-`da7dfc16` changes (shellcheck clean-up, updated `ACCEPTANCE.md`) | agent | yes |
| R2 | Mark A1 on Linux as **DEFERRED** | agent | no (decision 2026-09-30) |
| R3 | A4: review the milestone 06 diff and `ACCEPTANCE.md` → PASS | agent + human sign-off | yes |
| R4 | Q5: manual VS Code Copilot transcript | human | yes |
| R5 | Close out: statuses and the final evidence run | agent | yes |
| R6 | Upstream sync: resolve the A2 fork-edge conflicts | agent, next sync | no |

## R1 — Commit pending changes
- Stage `scripts/fork-acceptance.sh` and `planning/ACCEPTANCE.md`. Commit them as
  `chore(acceptance): shellcheck clean-up and strict-run evidence`, with the Co-authored-by trailer.
- Never stage `graph-ui/tsconfig.tsbuildinfo`: the UI build rewrites it, so restore it with
  `git checkout` before committing.

## R2 — Linux deferred
- `ACCEPTANCE.md`: move A1 (Linux) from "Open items" to a "Deferred" section. Give the reason
  (Linux is out of scope for now) and say how to revive it (run the gate in the devcontainer;
  A5 uses `ldd` there).
- Update the status column for 06 in `planning/ROADMAP.md` §3 to
  `COMPLETED (A4 review, Q5 manual open; Linux deferred)`. Add a line to §6 "Deferred":
  Linux acceptance run.
- `06 summary.md` §6 A1: add "macOS only; Linux deferred 2026-09-30".

## R3 — A4 review
1. Run a code-review pass over `git diff 2f0e35e1..HEAD` (the milestone 06 range). Focus on:
   - `scripts/fork-acceptance.sh`: fail-fast, whether any step can falsely PASS, subshell
     isolation, the scratch paths staying under `build/c/`, and bash 3.2 compatibility.
   - `scripts/fork-merge-rehearsal.sh`: it never pushes, never touches the user's branch or
     working tree, and always cleans up the worktree and branch; the exit codes are correct.
   - `cli-only.mk` `fork-acceptance`: purely additive, and not a dependency of any default target.
   - The `Makefile.cbm` D-6 quoting: behaviour unchanged apart from paths that contain spaces.
   - `ACCEPTANCE.md`: every claim traces to a log in `build/c/fork-acceptance/logs/`.
2. Fix any real findings, then re-run only the affected steps with
   `FORK_ACCEPTANCE_ONLY="<ids>"`.
3. Record the verdict in `ACCEPTANCE.md` under a new "A4 review" section: reviewer, date,
   findings, fixes and result. A human signs off by changing it to PASS.

## R4 — Q5 manual transcript (human)
1. Open this repo in VS Code with Copilot agent mode on and **no MCP servers configured**. Check
   this in the Copilot settings and `.vscode/mcp.json`: it must be absent.
2. Run `build/c/codebase-memory-cli install` in a sample project, then index that project.
3. Ask the agent: "Who calls `<some function>`?"
4. Pass if the agent answers by running `codebase-memory-cli` / `scripts/cbm` commands (visible in
   the terminal tool calls), and no MCP tool call appears.
5. Paste the transcript excerpt (or a screenshot path) into `ACCEPTANCE.md` under "Q5". Follow the
   steps in `docs/COPILOT_CLI_INTEGRATION.md` §6.

## R5 — Close out
- Once R1–R4 are done: run `FORK_ACCEPTANCE_STRICT=1 make -f Makefile.cbm fork-acceptance` again
  on the final commit, and update the `ACCEPTANCE.md` run table (commit, date, result).
- Change Q5 from MANUAL-open to PASS in `ACCEPTANCE.md`, and change the `manual Q5` note in
  `scripts/fork-acceptance.sh` to point at the recorded transcript.
- Set ROADMAP 06 to `COMPLETED`, and the 05 row to drop "(Q5 manual open)".
- Commit as `docs(acceptance): milestone 06 sign-off`.

## R6 — Next upstream sync (not part of this milestone)
- `git remote add upstream https://github.com/DeusData/codebase-memory-mcp.git` (once), then
  `scripts/fork-merge-rehearsal.sh --keep`.
- Resolve the conflicts in `Makefile.cbm`, `src/cli/cli.c` and `src/main.c` (as of `80eb92a7`).
  Keep the upstream control flow and re-apply the `CBM_FORK_CLI_ONLY` guards.
- Run `fork-acceptance` in the worktree. Merge onto the real branch only after it passes.

## Order
R1 → R2 → R3 → R4 (can run in parallel with R3) → R5. R6 is independent.
