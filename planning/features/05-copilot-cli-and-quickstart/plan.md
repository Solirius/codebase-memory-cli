# 05 — `copilot-cli-and-quickstart`: plan and outcome

## Plan
- `src/cli/cli_only_install.{c,h}` is a fork-only file, compiled only by `cli-only.mk`. It does
  `install [--project DIR] [--dry-run]` and `uninstall --copilot [--project DIR] [--dry-run]`.
  - It writes a marker-delimited section in `.github/copilot-instructions.md`, three
    marker-tagged prompt files in `.github/prompts/cbm-*.prompt.md`, and `.vscode/tasks.json`
    (only when the file is absent or already ours).
  - It is idempotent and refuses to write through symlinks. It never writes to `$HOME` and never
    writes an MCP registration.
- `cli.c` changes are guarded by `CBM_FORK_CLI_ONLY`: `cbm_cmd_install` calls the writer, and
  `cbm_cmd_uninstall --copilot` calls the remover. The `main.c` fork help lists both.
- `scripts/cbm`: a POSIX sh wrapper around `cli --quiet <tool> ... --format json`.
- `scripts/verify-docs.sh` runs these gates: Q1 (quickstart `sh` blocks on a clean copy), Q2
  (`json-example` blocks in the guide against live output: keys and types), Q3 (text check), and
  a check that the examples match the `install` output.
- Docs: rewrote `CLI_QUICKSTART.md` and `CLI_BUILD_RUN_GUIDE.md` (JSON reference and error
  shapes); added `COPILOT_CLI_INTEGRATION.md` (VS Code, Visual Studio, JetBrains, Android Studio
  and Copilot CLI) and `docs/copilot-examples/`; updated the README fork section.
- Tests: `tests/test_cli_only_install.sh` now runs the Q6 round-trip in place of the old install
  refusal. The smoke test uses `install --dry-run`, and it now only forbids the agent-client
  install surfaces in help.

## Finding
Q2 showed that tool errors print their JSON `error` object on **stderr**, not stdout, with exit
status 1. The docs and the managed instructions now say so.

## Quality gates (2026-09-29)
| Check | Result |
|---|---|
| Q1 / Q2 / Q3 / examples: `scripts/verify-docs.sh` | PASS |
| Q4 `shellcheck -s sh scripts/cbm` (0.11.0) | PASS |
| Q5 manual VS Code agent transcript | **OPEN**: needs a human run (steps in COPILOT_CLI_INTEGRATION.md §6) |
| Q6 `tests/test_cli_only_install.sh` (via `make -f Makefile.cbm test-cli-only`) | PASS |
| Build `scripts/build.sh --cli-only`, `make -f Makefile.cbm cbm` | PASS, 0 warnings |
| Unit/sanitizer suite (D-6 workaround: `bash scripts/run-tests-parallel.sh build/c/test-runner`) | PASS: 7994 passed, 0 failed, 8 skipped (141 suites) |
| `verify-cli-only-link`, `verify-cli-only-no-http`, smoke | PASS |
| `make -f Makefile.cbm security` | PASS |
