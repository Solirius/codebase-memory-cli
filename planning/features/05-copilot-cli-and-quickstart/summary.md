# 05 — `copilot-cli-and-quickstart`

**Milestone:** 05 of 06 | **Status:** COMPLETED (Q5 manual transcript open) | **Carries over:** old F7

## 1. Objective & Rationale
This milestone makes the finished binary easy to adopt from GitHub Copilot without MCP. Copilot's
native external-tool protocol **is** MCP, so the integration works by running commands, and the
docs must say that plainly.

## 2. Architectural Scope
- **Add:** `scripts/cbm` (a thin POSIX sh wrapper around `codebase-memory-cli cli <tool> --format json`).
- **Modify (guarded):** the fork's `install` command (made MCP-free in 02) optionally writes the CLI-only Copilot integration files: `.github/copilot-instructions.md` section, prompt files, `.vscode/tasks.json` snippet. It never writes `mcpServers`. The files must be idempotent and removable by `uninstall`.
- **Add/modify docs:** `README.md` (fork section), `docs/CLI_QUICKSTART.md`, `docs/CLI_BUILD_RUN_GUIDE.md`, `docs/COPILOT_CLI_INTEGRATION.md`, with per-IDE notes for VS Code, Visual Studio, JetBrains/IntelliJ and Android Studio. Also add example `.github/prompts` / task snippets.
- **No C code changes** expected beyond the guarded `install` writer above.

## 3. Boundary & Guard Constraints
- No `.mcp.json` and no MCP server configuration anywhere in the fork docs or snippets.
- The docs never tell anyone to bind the UI to anything other than 127.0.0.1.

## 4. CLI Contract Expectations
Document these with real captured output: `--help`, `cli index_repository`, `search_graph`,
`trace_path`, `get_architecture`, `query_graph`, `get_code_snippet`, `ui`. Include the JSON shapes
and the error shape.

## 5. Pre-conditions
04 COMPLETED (the documented binary is the hardened one).

## 6. Acceptance & Verification Gates
| Eval | Check |
|---|---|
| Q1 | Doc-test script (`scripts/verify-docs.sh`, fork-owned) pulls every fenced `sh` command out of the quickstart, runs it on a clean clone in a temp dir, and gets exit 0 |
| Q2 | The JSON examples in the docs match captured output (keys and types) |
| Q3 | `grep -ri "mcp.json\|mcpServers\|0.0.0.0"` across the fork docs → no matches, except the explicit caveat text |
| Q4 | The wrapper passes `shellcheck` |
| Q5 | Manual end-to-end test: a VS Code Copilot agent, with **no MCP servers configured**, answers a structural question ("who calls X?") by running `codebase-memory-cli` commands. Transcript recorded in progress.json |
| Q6 | `install` → `uninstall` round-trip under a temp `HOME`: CLI integration files created and then removed; no MCP entries at any point |
Plus G1, G3, G7 and G8 (build and test confirm nothing regressed).

## 7. Sub-Agent Execution Readiness
✅ Ready for `/roadmap-goal` once 04 is COMPLETED.
