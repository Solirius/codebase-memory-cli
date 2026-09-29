# Codebase Memory CLI — Quickstart

Quick reference for building this **pure-C11** project from source and running it as a local
CLI to generate and query a code graph. For the full walkthrough with a diagram, see
[CLI_BUILD_RUN_GUIDE.md](./CLI_BUILD_RUN_GUIDE.md).

> **This is the CLI-only, no-MCP, no-network fork.** See the "About this fork" section in the
> top-level [README](../README.md). There is **no Go toolchain** here — the project was rewritten
> from Go to pure C11 at upstream v0.5.0. Do not run `go build`.

## 1. Prerequisites

A C11 toolchain (clang or gcc), `make`, and — only if you want the graph UI bundled — `node`.
Everything else (tree-sitter grammars, SQLite, yyjson, mimalloc, …) is **vendored** and compiled
into the binary. No language runtime, no network fetch at build time.

The repo also ships a `.devcontainer` (Docker Compose); JetBrains IDEs and VS Code will offer to
reopen the project in the container, where your workspace is mounted at `/workspace`.

## 2. Build

Standard release build:

```bash
scripts/build.sh
# -> build/c/codebase-memory-mcp
```

With the localhost graph-viz UI bundled in (needs node):

```bash
scripts/build.sh --with-ui
```

Equivalent via make:

```bash
make -f Makefile.cbm cbm
```

> **Fork roadmap:** a dedicated CLI-only binary (`codebase-memory-cli`, built via
> `scripts/build.sh --cli-only`, with the MCP server and coordination daemon compiled out) is
> tracked on the roadmap and not yet wired up. Until then, use the standard build above and the
> `cli` subcommand below — the query behavior is identical.

## 3. Run a tool (one-shot CLI)

The binary runs any tool locally and exits via the `cli` subcommand:

```bash
build/c/codebase-memory-mcp --help
build/c/codebase-memory-mcp cli --json <tool> [args]
```

## 4. Index a repository, then query it

```bash
# Build/refresh the code graph for the current repo
build/c/codebase-memory-mcp cli --json index_repository

# Structural search
build/c/codebase-memory-mcp cli --json search_graph --query cbm_mcp_handle_tool

# Orient on module structure
build/c/codebase-memory-mcp cli --json get_architecture

# Callers/callees of a symbol
build/c/codebase-memory-mcp cli --json trace_path --from run_cli
```

Available tools include: `index_repository`, `search_graph`, `query_graph` (Cypher), `trace_path`,
`get_code_snippet`, `get_architecture`, `search_code`, `list_projects`, `index_status`,
`check_index_coverage`, `detect_changes`, `manage_adr`, and more — run `--help` to list them.

## 5. Graph UI (localhost only)

Build with `scripts/build.sh --cli-only --with-ui` (needs an existing `graph-ui/node_modules`; the
build never fetches), then run:

```bash
build/c/codebase-memory-cli ui                 # http://127.0.0.1:9749, Ctrl-C to stop
build/c/codebase-memory-cli ui --port 0 --format json
# {"status":"listening","url":"http://127.0.0.1:54321"}
```

The server binds **`127.0.0.1` only** (no option changes the interface), runs in-process only while
`ui` runs, and rejects foreign `Host`/`Origin` headers. A busy port prints
`{"error":{"code":"port_in_use",...}}` and exits non-zero. The plain `--cli-only` binary contains no
HTTP server: its `ui` prints `ui_not_built` and exits 2.

## Notes

- Machine-readable output: `cli --json <tool>` prints the raw result envelope; most query tools
  also accept `--format json` for a stable per-tool JSON shape. This is the intended path for
  scripting and for driving the tool from an editor/agent.
- Confirm exact subcommands and flags with `build/c/codebase-memory-mcp --help` and
  `... cli <tool> --help`.
