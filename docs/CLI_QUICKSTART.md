# Codebase Memory CLI: Quickstart

This page takes you from a fresh clone to answering "who calls X?" with the fork's
`codebase-memory-cli` binary. For a longer walkthrough, see
[CLI_BUILD_RUN_GUIDE.md](./CLI_BUILD_RUN_GUIDE.md). For GitHub Copilot, see
[COPILOT_CLI_INTEGRATION.md](./COPILOT_CLI_INTEGRATION.md).

> **This is the CLI-only fork: no MCP, no daemon, no network.** Every command runs once and exits.
> The only listener the binary can open is the optional graph UI, and it binds to `127.0.0.1`.
> Read "About this fork" in the top-level [README](../README.md).

Each `sh` block below is run in order, from the repository root, by `scripts/verify-docs.sh`
against a clean copy of the repository. If a command here stops working, that script fails.

## 1. Prerequisites

You need a C11 compiler (clang or gcc), `make` and `git`. Everything else (tree-sitter grammars,
SQLite, yyjson, mimalloc and so on) is vendored and compiled into the binary. The build never
fetches anything from the network.

## 2. Build

```sh
scripts/build.sh --cli-only
build/c/codebase-memory-cli --version
```

The binary is `build/c/codebase-memory-cli`. Put it on your `PATH` (for example, copy it to
`~/.local/bin`) so that editors and Copilot can run it by name.

## 3. Index a small demo repository

The demo lives under `build/c/`, which is git-ignored.

```sh
rm -rf build/c/demo && mkdir -p build/c/demo
cat > build/c/demo/main.c <<'C'
#include <stdio.h>

static int add(int a, int b) { return a + b; }

int compute(int x) { return add(x, 1); }

int main(void) {
    printf("%d\n", compute(41));
    return 0;
}
C
build/c/codebase-memory-cli cli --quiet index_repository --repo-path "$PWD/build/c/demo" --name demo
```

`--name` sets the project name. Without it, the name is derived from the path. To index your own
repository, run the same command with `--repo-path /path/to/your/repo`.

## 4. Query the graph

`scripts/cbm` is a thin wrapper around `codebase-memory-cli cli <tool> ... --format json` (it adds
`--quiet` and `--format json` for you). The raw form works just as well.

```sh
scripts/cbm list_projects
scripts/cbm search_graph --project demo --name-pattern compute
scripts/cbm trace_path --project demo --function-name add --direction inbound
scripts/cbm get_architecture --project demo
scripts/cbm query_graph --project demo --query 'MATCH (f:Function)-[:CALLS]->(g:Function) RETURN f.name, g.name'
scripts/cbm get_code_snippet --project demo --qualified-name compute
build/c/codebase-memory-cli cli --quiet trace_path --project demo --function-name add --direction inbound --format json
```

Tool errors print a JSON object with an `error` key on stderr and exit with status 1:

```sh
if scripts/cbm search_graph --project no-such-project --name-pattern x; then exit 1; fi
```

The JSON shapes of every command above are listed, with real output, in
[CLI_BUILD_RUN_GUIDE.md](./CLI_BUILD_RUN_GUIDE.md#json-output-reference).

## 5. Discover every tool and flag

```sh
build/c/codebase-memory-cli --help
build/c/codebase-memory-cli cli trace_path --help
```

## 6. Graph UI (localhost only, optional)

The plain `--cli-only` binary has no HTTP server. Its `ui` command explains that and exits 2:

```sh
if build/c/codebase-memory-cli ui --format json; then exit 1; fi
```

To get the UI, build with `scripts/build.sh --cli-only --with-ui`. That needs an existing
`graph-ui/node_modules`, because the build never fetches. Then run:

```text
build/c/codebase-memory-cli ui                 # http://127.0.0.1:9749, Ctrl-C to stop
build/c/codebase-memory-cli ui --port 0 --format json
{"status":"listening","url":"http://127.0.0.1:54321"}
```

The server binds `127.0.0.1` only (no option changes the interface), runs only while `ui` runs, and
rejects foreign `Host` and `Origin` headers.

## 7. Set up GitHub Copilot for a repository (optional)

`install` writes command-based Copilot files (instructions, prompt files and VS Code tasks) into one
repository. It registers no server anywhere. `uninstall --copilot` removes them again.

```sh
build/c/codebase-memory-cli install --project build/c/demo
build/c/codebase-memory-cli uninstall --copilot --project build/c/demo
```

## 8. Clean up the demo

```sh
scripts/cbm delete_project --project demo
rm -rf build/c/demo
```
