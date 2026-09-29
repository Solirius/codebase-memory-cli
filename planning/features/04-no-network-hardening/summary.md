# 04 — `no-network-hardening`

**Milestone:** 04 of 06 | **Status:** COMPLETED | **Carries over:** old F6

## Scope (deliberately light)
MCP is already gone (02). The CLI only needs to be unable to make network calls. Nothing more.

- `update` refuses in the CLI-only build (`src/cli/cli.c`, guarded by `CBM_FORK_CLI_ONLY`) and is
  dropped from the fork's `--help` (`src/main.c`). Before this change it pointed users at the
  upstream `install.sh`, which downloads from GitHub.
- `verify-cli-only-no-http` (`cli-only.mk`) also checks that the plain `cbm-cli` binary does not
  import `connect`, `sendto`, `getaddrinfo` or `gethostbyname`, on top of the existing
  `socket`/`bind`/`listen`/`accept` checks.
- No curl/download code ships: those helpers exist only in `CBM_CLI_ENABLE_TEST_API` (test) builds.
- The optional with-UI binary keeps its 127.0.0.1-only listener (03), and makes no outbound calls.

Dropped as over-engineering: dynamic strace/dtruss tracing, fork allowlist/source-audit profiles,
`security-cli` target, and network-namespace runs. D-1 E1 and D-4 are closed by the nm import check.

## Verification
`make -f Makefile.cbm verify-cli-only-no-http verify-cli-only-link test-cli-only` → PASS;
the upstream `cbm` build is unchanged (`update` is still listed in its help).
