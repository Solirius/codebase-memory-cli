# 04 — `no-network-hardening` — plan & outcome

Plan: see `summary.md` (refuse `update` under `CBM_FORK_CLI_ONLY`, drop it from fork help,
extend `verify-cli-only-no-http` with `connect sendto getaddrinfo gethostbyname`).

## Quality gates (run 2026-09-29, commit `b0158eb6`)

| Check | Command | Result |
|---|---|---|
| Build | `scripts/build.sh --cli-only`; `make -f Makefile.cbm cbm` | PASS, 0 warnings |
| Link isolation | `make -f Makefile.cbm verify-cli-only-link` | PASS |
| Smoke | `make -f Makefile.cbm test-cli-only` | PASS |
| No-network imports | `make -f Makefile.cbm verify-cli-only-no-http` | PASS |
| Unit/sanitizer suite | `scripts/test.sh` fails on D-6 (path with space); ran `bash scripts/run-tests-parallel.sh build/c/test-runner` | PASS — 7994 passed, 0 failed, 8 skipped (141 suites) |
| Security | `make -f Makefile.cbm security` | PASS (all layers) |
| Review | diff of `b0158eb6` | PASS — edits confined to `src/cli/cli.c`, `src/main.c`, `cli-only.mk`, all behind `CBM_FORK_CLI_ONLY`; no shared-core edits. `codebase-memory-cli update` → `{"error":"update is not available in the CLI-only build"}`, rc=1; absent from `--help` |

Open: D-6 remains (owned by 06).
