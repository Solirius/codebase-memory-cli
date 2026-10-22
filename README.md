# codebase-memory-cli

[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![Languages](https://img.shields.io/badge/languages-162-orange)](#language-support)
[![Hybrid LSP](https://img.shields.io/badge/Hybrid_LSP-10_languages-blue)](#hybrid-lsp)
[![Pure C](https://img.shields.io/badge/pure_C-no_language_runtime-blue)](#architecture)
[![No MCP](https://img.shields.io/badge/MCP-none-lightgrey)](#-about-this-fork--cli-only-no-mcp-no-network)
[![No network](https://img.shields.io/badge/network-loopback_UI_only-lightgrey)](#security)
[![Upstream](https://img.shields.io/badge/fork_of-DeusData%2Fcodebase--memory--mcp-blue)](https://github.com/DeusData/codebase-memory-mcp)

**A local, CLI-only code intelligence engine for AI coding agents such as GitHub Copilot.** It builds a persistent knowledge graph of your code — functions, classes, call chains, HTTP routes, cross-service links — and answers structural questions (*who calls X?*, *what does this module depend on?*) in milliseconds through plain one-shot terminal commands that print JSON.

High-quality parsing through [tree-sitter](https://tree-sitter.github.io/tree-sitter/) AST analysis across all 162 languages, enhanced with [**Hybrid LSP** semantic type resolution](#hybrid-lsp) for Python, TypeScript / JavaScript / JSX / TSX, PHP, C#, Go, C, C++, Java, Kotlin, Rust, and Perl. No MCP server, no daemon, no language runtime, hosted service, or API key.

> **Research** — The design and benchmarks of the upstream engine are described in the preprint [*Codebase-Memory: Tree-Sitter-Based Knowledge Graphs for LLM Code Exploration via MCP*](https://arxiv.org/abs/2603.27277) (arXiv:2603.27277). This fork reuses the same indexing engine and graph; only the delivery mechanism (CLI instead of MCP) differs.

> **Security & Trust** — All processing happens 100% locally; your code never leaves your machine. The binary makes no outbound network requests, and the optional graph UI binds to `127.0.0.1` only. You build it yourself from this source. See [Security](#security) and [SECURITY.md](SECURITY.md).

<p align="center">
  <img src="docs/graph-ui-screenshot.png" alt="Graph visualization UI showing a codebase knowledge graph" width="800">
  <br>
  <em>Optional 3D graph visualization — <code>codebase-memory-cli ui</code>, served on 127.0.0.1:9749</em>
</p>

---

## 🔒 About this fork — CLI-only, no MCP, no network

> **This is a fork of upstream [`codebase-memory-mcp`](https://github.com/DeusData/codebase-memory-mcp) with a different goal than the project above.** If your organization forbids MCP servers or outbound-network developer tools, this fork is for you.

**What it produces:** a single, locally-compiled binary — **`codebase-memory-cli`** — that delivers the same tree-sitter code-graph intelligence (`search_graph`, `trace_path`, `get_architecture`, Cypher `query_graph`, `get_code_snippet`, `index_repository`, …) **entirely through one-shot CLI subcommands** with `--json` output.

**What is removed:**
- ❌ **No MCP** — no JSON-RPC 2.0 server, no stdio protocol. The binary never speaks MCP.
- ❌ **No coordination daemon** — no Unix-domain-socket IPC, no cross-session ownership, no background service. Every command runs one-shot and exits. (This also eliminates a whole class of daemon-startup failures.)
- ❌ **No outbound network** — no update checks, no telemetry. All processing is 100% local, and this is enforced by an auditable security gate.

**What is kept:**
- ✅ **All the code-graph tools**, exposed as `codebase-memory-cli cli <tool> [--flags] --format json`.
- ✅ **The 3D graph-viz UI**, started on demand by the CLI and bound to **`127.0.0.1` only** — never a non-loopback interface. It is a local viewer, not remote networking or MCP.

**How you use it with GitHub Copilot:** this fork is *not* an MCP server. Copilot (VS Code, Visual Studio, JetBrains/IntelliJ, Android Studio, Copilot CLI) drives it by **running the CLI as terminal commands** from its agent. Copilot's native external-tool protocol *is* MCP, so this integration is command-driven by design. `codebase-memory-cli install` writes the Copilot instructions, prompt files and VS Code tasks into a repository, and `uninstall --copilot` removes them. See [`docs/COPILOT_CLI_INTEGRATION.md`](docs/COPILOT_CLI_INTEGRATION.md).

**Upstream-mergeable:** every removal lives behind an additive `CBM_FORK_CLI_ONLY` compile guard; the shared core (`src/foundation`, `src/store`, `src/cypher`, `src/pipeline`, `internal/cbm`) is left untouched so upstream language/pipeline improvements keep flowing in via `git pull`.

> **Build and run:** `scripts/build.sh --cli-only` produces `build/c/codebase-memory-cli` (add `--with-ui` for the loopback graph UI). `scripts/cbm <tool> [flags]` is a thin JSON wrapper. See [`docs/CLI_QUICKSTART.md`](docs/CLI_QUICKSTART.md) (verified by `scripts/verify-docs.sh`) and [`docs/CLI_BUILD_RUN_GUIDE.md`](docs/CLI_BUILD_RUN_GUIDE.md) (JSON shapes and error shape).

---

## 🚀 Step-by-step: build, run, connect to GitHub Copilot — and prove it works

Follow these steps in order. Each one ends with a **✅ Proof** you can see with your own eyes.

> **Prefer to be guided?** Run the wizard from the project you want Copilot to understand. It walks through Steps 1–6 with sensible defaults, asks only what needs your input, shows the plan for confirmation, and runs the proof checks:
>
> ```bash
> cd /path/to/your/repo
> /path/to/codebase-memory-cli/scripts/installer-wizard.sh          # add --dry-run to preview, --yes to accept all defaults
> ```

### Step 1 — Prerequisites

You need a C/C++ compiler (`clang` or `gcc`), `make`, `git`, and zlib.

```bash
# macOS
xcode-select --install
# Debian/Ubuntu
sudo apt install build-essential zlib1g-dev git
```

✅ **Proof:** `cc --version && git --version` both print a version.

### Step 2 — Build the CLI binary

From the root of this repository:

```bash
scripts/build.sh --cli-only              # CLI only
scripts/build.sh --cli-only --with-ui    # optional: also embed the 127.0.0.1 graph UI
```

✅ **Proof:** the build ends with `=== Build complete: build/c/codebase-memory-cli ===`, and

```bash
build/c/codebase-memory-cli --version
build/c/codebase-memory-cli --help       # lists: cli, install, uninstall, config (and ui with --with-ui)
```

### Step 3 — Make it available in your project (no copying, nothing global)

Copilot must be able to run the binary **from the project where it works**. Nothing needs to be copied, and every rebuild is picked up automatically. Below, `/path/to/codebase-memory-cli` is where you cloned this repository.

**Recommended: a project-local link.** This is what the wizard sets up. Copilot calls the binary by a fixed relative path, so it never depends on `PATH`, shell start-up files, direnv or which Copilot surface you use (VS Code, JetBrains, Visual Studio or the Copilot CLI):

```bash
cd /path/to/your/repo
mkdir -p .cbm
ln -sfn /path/to/codebase-memory-cli/build/c/codebase-memory-cli .cbm/codebase-memory-cli
echo '.cbm/' >> .gitignore            # the link is machine-specific; each teammate creates their own
```

With the link, every `codebase-memory-cli` command in this guide becomes `./.cbm/codebase-memory-cli`, run from the project root. Step 5 points the Copilot files at the link.

✅ **Proof:** `./.cbm/codebase-memory-cli --version` prints a version line from the project root.

<details>
<summary>Alternatives: put <code>build/c</code> on <code>PATH</code> inside the project (less reliable for Copilot)</summary>

These let you type the bare name, but they depend on how Copilot's terminal is started. Agent shells may skip shell hooks.

**VS Code only.** Create or extend the project's `.vscode/settings.json`. The path is machine-specific, so keep this setting local in shared projects:

```jsonc
{
  "terminal.integrated.env.osx":   { "PATH": "/path/to/codebase-memory-cli/build/c:${env:PATH}" },
  "terminal.integrated.env.linux": { "PATH": "/path/to/codebase-memory-cli/build/c:${env:PATH}" }
}
```

**[direnv](https://direnv.net/)** (macOS/Linux; needs direnv installed and hooked into your shell):

```bash
echo 'PATH_add "/path/to/codebase-memory-cli/build/c"' >> .envrc && direnv allow
```

**Per session, nothing to install:** `export PATH="/path/to/codebase-memory-cli/build/c:$PATH"`

✅ **Proof:** in a **new** terminal inside the project, `command -v codebase-memory-cli` prints `/path/to/codebase-memory-cli/build/c/codebase-memory-cli`.

</details>

### Step 4 — Index the repository you want Copilot to understand

```bash
cd /path/to/your/repo
codebase-memory-cli cli --quiet index_repository --repo-path "$PWD"
```

✅ **Proof:** one line of JSON ending in `"status":"indexed"`, with non-zero `"nodes"` and `"edges"`. Then:

```bash
codebase-memory-cli cli list_projects --format json      # your repo appears; note its "name"
codebase-memory-cli cli index_status --project <name> --format json   # "status":"ready"
codebase-memory-cli cli trace_path --project <name> --function-name <someFunction> --direction inbound --format json
```

The last command returns the real callers of a function in your code — the graph is working.

### Step 5 — Connect it to GitHub Copilot

Still inside your repository:

```bash
codebase-memory-cli install --dry-run    # preview: shows which files would be written
codebase-memory-cli install              # write them
```

This writes only:

- `.github/copilot-instructions.md` — a managed section teaching Copilot which `codebase-memory-cli` commands to run;
- `.github/prompts/cbm-*.prompt.md` — reusable prompts (e.g. *who calls*, *architecture*);
- `.vscode/tasks.json` — only if absent or previously generated by `install`.

No MCP server is registered anywhere. Re-running is safe; `codebase-memory-cli uninstall --copilot` removes everything.

**Using the project-local link (Step 3)?** `install` writes bare `codebase-memory-cli` commands. The wizard rewrites them to `./.cbm/codebase-memory-cli` for you. To do it by hand, run (macOS `sed`; on Linux drop the `''`):

```bash
sed -i '' 's#`codebase-memory-cli cli#`./.cbm/codebase-memory-cli cli#g' .github/copilot-instructions.md .github/prompts/cbm-*.prompt.md
sed -i '' 's#"command": "codebase-memory-cli"#"command": "${workspaceFolder}/.cbm/codebase-memory-cli"#g' .vscode/tasks.json
```

A later plain `install` puts the bare name back, so re-run the wizard instead.

✅ **Proof:** `install` prints JSON with `"status":"installed"` and one `action` per file (`created`, `appended`, `updated`, `unchanged`); `git status` shows exactly those files.

Then, in your IDE:

1. Reload the window (VS Code: *Developer: Reload Window*) so Copilot picks up the new instructions.
2. Open Copilot Chat and switch to **Agent** mode (terminal commands are only run in agent mode).
3. When Copilot asks to run `codebase-memory-cli`, click **Allow** (or add it to `chat.tools.terminal.autoApprove` if your policy permits).

Per-IDE notes (VS Code, Visual Studio, JetBrains, Android Studio, Copilot CLI): [`docs/COPILOT_CLI_INTEGRATION.md`](docs/COPILOT_CLI_INTEGRATION.md).

### Step 6 — Prove Copilot is really using it

Ask Copilot Chat (Agent mode) a structural question about your code, for example:

> *Who calls `<someFunction>`? Use codebase-memory-cli.*

✅ **Proof — what you should see:**

1. **The command itself.** The chat shows a terminal tool call such as
   `codebase-memory-cli cli trace_path --project <name> --function-name <someFunction> --direction inbound --format json`.
2. **Its JSON output.** Expand the tool call: the JSON contains `"callers":…` from your graph.
3. **A matching answer.** Copilot's reply names the same callers you got by running the command yourself in Step 4.
4. **The prompt files work.** Type `/cbm-` in chat — the `cbm-*` prompts from Step 5 appear.

✅ **Proof — what you should *not* see (it really is CLI-only):**

```bash
ps aux | grep -i '[c]odebase-memory'     # nothing left running after a command finishes
```

and in VS Code, *MCP: List Servers* shows no `codebase-memory` server — Copilot reached the graph only through terminal commands.

### Step 7 (optional) — See the graph in your browser

Requires the `--with-ui` build from Step 2:

```bash
codebase-memory-cli ui --format json     # prints {"status":"listening","url":"http://127.0.0.1:9749"}
```

Open <http://127.0.0.1:9749>. Stop it with Ctrl-C.

✅ **Proof it is local-only:** in another terminal, `lsof -nP -iTCP:9749 -sTCP:LISTEN` shows `TCP 127.0.0.1:9749 (LISTEN)` — loopback, never `*:9749`.

### Troubleshooting

| Symptom | Fix |
|---|---|
| `command not found: codebase-memory-cli` | Use `./.cbm/codebase-memory-cli` from the project root (Step 3 link), or re-run the wizard. If you chose a `PATH` alternative, open a new terminal and restart the IDE. |
| Copilot answers without running a command | Make sure you're in **Agent** mode, reload the window, ask it explicitly to "use codebase-memory-cli". |
| `project not found` error | Use the exact `name` from `list_projects`, or re-run Step 4. |
| Answers look stale | Re-run `index_repository` after large changes. |
| `ui` is an unknown command | Rebuild with `scripts/build.sh --cli-only --with-ui`. |

---

## Why codebase-memory-cli

- **Extreme indexing speed** — Linux kernel (28M LOC, 75K files) in 3 minutes. RAM-first pipeline: LZ4 compression, in-memory SQLite, fused Aho-Corasick pattern matching. Memory released after indexing.
- **Works with GitHub Copilot without MCP** — Copilot's agent runs `codebase-memory-cli` as an ordinary terminal command; `codebase-memory-cli install` writes the repository instructions and prompt files that teach it how.
- **One-shot, nothing left running** — every command starts, answers, and exits. No daemon, no socket, no background watcher.
- **162 languages** — vendored tree-sitter grammars compiled into the binary. Nothing to install, nothing that breaks.
- **120x fewer tokens** — 5 structural queries: ~3,400 tokens vs ~412,000 via file-by-file search. One graph query replaces dozens of grep/read cycles.
- **Optional graph visualization** — 3D interactive UI on `127.0.0.1:9749`, served from the binary itself (build with `--with-ui`).
- **Infrastructure-as-code indexing** — Dockerfiles, Kubernetes manifests, and Kustomize overlays indexed as graph nodes with cross-references.
- **17 CLI tools** — search, trace, architecture, impact analysis, index-coverage checks, Cypher queries, dead code detection, cross-service HTTP linking, ADR management, and more. See [CLI Tools](#cli-tools).

## Quick Start

There are no pre-built downloads or install scripts for this fork — you build the binary from source. The short version (macOS / Linux):

```bash
scripts/build.sh --cli-only                      # add --with-ui for the graph UI

cd /path/to/your/repo                            # the project Copilot should understand
/path/to/codebase-memory-cli/scripts/installer-wizard.sh   # links, indexes, wires up Copilot, proves it works
```

The wizard creates a git-ignored link `.cbm/codebase-memory-cli` in your project, indexes it, writes the Copilot files (pointed at `./.cbm/codebase-memory-cli`) and runs the proof checks. To do it by hand, follow Steps 3–5 below.

Then reload your IDE, open Copilot Chat in **Agent** mode and ask *"Who calls `<someFunction>`?"*.

For the full walkthrough with a verification check after every step, follow [Step-by-step: build, run, connect to GitHub Copilot — and prove it works](#-step-by-step-build-run-connect-to-github-copilot--and-prove-it-works).

### Graph Visualization UI

Only in binaries built with `scripts/build.sh --cli-only --with-ui`:

```bash
codebase-memory-cli ui                 # http://127.0.0.1:9749, until Ctrl-C
codebase-memory-cli ui --port 0        # pick a free port
codebase-memory-cli ui --format json   # prints {"status":"listening","url":"..."}
```

The UI is started and stopped directly by you; it binds the loopback interface only and needs no daemon.

### Keeping the Index Fresh

This fork has no background watcher or auto-index on session start. Re-run indexing whenever the code has changed meaningfully — it is incremental, so repeat runs are fast:

```bash
codebase-memory-cli cli --quiet index_repository --repo-path "$PWD"
```

The installed Copilot instructions tell the agent to do the same when results look stale.

### Updating

There is no `update` command (it reports `update is not available in the CLI-only build`) and the binary never checks for new versions. To update, pull this repository and rebuild. Projects linking to `build/c` (Step 3) pick up the new binary immediately:

```bash
git pull
scripts/build.sh --cli-only
```

### Uninstall

```bash
codebase-memory-cli uninstall --copilot --project /path/to/repo   # remove the Copilot files from a repo (add --dry-run to preview)
rm -r /path/to/repo/.cbm                                          # remove the project-local link (or the build/c PATH entry, if you used one)
rm -rf ~/.cache/codebase-memory-mcp/                              # optional: delete all indexes
```

To drop the index of a single project instead: `codebase-memory-cli cli delete_project --project <name>`.

## Features

### Graph & analysis
- **Architecture overview**: `get_architecture` returns languages, packages, entry points, routes, hotspots, boundaries, layers, and clusters in a single call
- **Architecture Decision Records**: `manage_adr` persists architectural decisions across sessions
- **Louvain community detection**: Discovers functional modules by clustering call edges
- **Git diff impact mapping**: `detect_changes` maps uncommitted changes to affected symbols with risk classification
- **Call graph**: Resolves function calls across files and packages (import-aware, type-inferred)
- **Dead code detection**: Finds functions with zero callers, excluding entry points
- **Cypher-like queries**: `MATCH (f:Function)-[:CALLS]->(g) WHERE f.name = 'main' RETURN g.name`

### Search
- **Semantic search** (`semantic_query`): vector search across the entire graph, powered by bundled Nomic `nomic-embed-code` embeddings (40K tokens, 768d int8) compiled into the binary — no API key, no Ollama, no Docker. 11-signal combined scoring (TF-IDF, RRI, API/Type/Decorator signatures, AST profiles, data flow, Halstead-lite, MinHash, module proximity, graph diffusion).
- **BM25 full-text search** via SQLite FTS5 with `cbm_camel_split` tokenizer (camelCase / snake_case aware)
- **Structural search** (`search_graph`): regex name patterns, label filters, min/max degree, file scoping
- **Code search** (`search_code`): graph-augmented grep over indexed files only

### Cross-service linking
- **HTTP** route ↔ call-site matching with confidence scoring
- **gRPC, GraphQL, tRPC** service detection with protobuf Route extraction
- **Channel detection** (`EMITS` / `LISTENS_ON`) for Socket.IO, EventEmitter, and generic pub-sub patterns across 8 languages with constant resolution

### Cross-repo intelligence
- **`CROSS_*` edges** link nodes across multiple repos indexed under the same store
- **Multi-galaxy 3D UI layout** for cross-repo architecture visualization
- **Cross-repo architecture summary** combining services, routes, and dependencies across the indexed fleet

### Edge types (selected)
- `CALLS` — a callable is invoked at the source site
- `CALL_REFERENCE` — a callable is used at a supported reference site (for example, a direct value argument) and resolves to one exact target
- `USAGE` — an identifier is used, but a unique callable target is not proven (including ambiguous or complex expressions)
- `IMPORTS`, `DEFINES`, `IMPLEMENTS`, `INHERITS`
- `HTTP_CALLS`, `ASYNC_CALLS` (cross-service)
- `EMITS`, `LISTENS_ON` (channels)
- `DATA_FLOWS` with arg-to-param mapping + field access chains
- `SIMILAR_TO` (MinHash + LSH near-clone detection, Jaccard scored)
- `SEMANTICALLY_RELATED` (vocabulary-mismatch, same-language, score ≥ 0.80)

### Indexing pipeline
- **158 vendored tree-sitter grammars** compiled into the binary
- **Generic package / module resolution** — bare specifiers like `@myorg/pkg`, `github.com/foo/bar`, `use my_crate::foo` resolved via manifest scanning (`package.json`, `go.mod`, `Cargo.toml`, `pyproject.toml`, `composer.json`, `pubspec.yaml`, `pom.xml`, `build.gradle`, `mix.exs`, `*.gemspec`)
- **Infrastructure-as-code indexing** — Dockerfiles, Kubernetes manifests, Kustomize overlays as graph nodes
- **[Hybrid LSP semantic type resolution](#hybrid-lsp)** for Python, TypeScript / JavaScript / JSX / TSX, PHP, C#, Go, C, C++, Java, Kotlin, Rust, and Perl — a lightweight C implementation of language type-resolution algorithms, structurally inspired by and compatible with major language servers including tsserver / typescript-go, pyright, gopls, Roslyn, Eclipse JDT, and rust-analyzer (parameter binding, return-type inference, generic substitution, JSX component dispatch, JSDoc inference for plain JS files, namespace + trait + late-static-binding resolution for PHP, file-scoped namespaces + records + LINQ method syntax for C#, class-hierarchy + overload + lambda resolution for Java, extension-function + scope-function resolution for Kotlin, trait-method + UFCS resolution for Rust)
- **RAM-first pipeline**: LZ4 compression, in-memory SQLite, single dump at end. Memory released after.

### Distribution & operation
- **Single local binary, zero infrastructure services**: SQLite-backed, persists to `~/.cache/codebase-memory-mcp/`
- **Explicit refresh**: re-run `index_repository` to pick up changes (incremental; no background watcher in this fork)
- **Route nodes**: REST endpoints are first-class graph entities
- **CLI-only**: `codebase-memory-cli cli search_graph --project my-project --name-pattern '.*Handler.*' --format json`
- **Built from source**: `scripts/build.sh --cli-only` — no package-manager or release downloads for this fork

## Team-Shared Graph Artifact

Commit a single compressed file to your repo and your teammates skip the reindex.

`.codebase-memory/graph.db.zst` is a zstd-compressed snapshot of the knowledge graph that lives next to your source. When you index, the artifact is written or refreshed; when a teammate clones the repo and runs `codebase-memory-cli cli index_repository` for the first time, the artifact is decompressed and incremental indexing fills in their local diff.

- **Format**: SQLite database, indexes stripped, `VACUUM INTO` compacted, then zstd 1.5.7 compressed (8–13:1 ratio typical)
- **Two tiers**:
  - **Best** (`zstd -9` + index strip + `VACUUM INTO`) — written on explicit `index_repository`
  - **Fast** (`zstd -3`) — written by upstream's background watcher (not present in this fork)
- **Bootstrap**: when no local DB exists but the artifact is present, `index_repository` imports the artifact first, then runs incremental indexing — avoiding the full reindex cost
- **No merge pain**: a `.codebase-memory/.gitattributes` line with `merge=ours` is auto-created on first export, so concurrent edits don't produce conflicts on the binary artifact
- **Commit it deliberately**: the artifact is rewritten on every index, and git stores each rewrite as a full new blob. Committing every refresh is what turns a 20 MB file into gigabytes of history — one team reached ~6 GB across ~350 commits of this single path. Pick a cadence (a release, a milestone, a nightly job) rather than committing every save.
- **Git LFS, if it must move on every commit**: track it from the **repo-root** `.gitattributes` and leave the auto-created `.codebase-memory/.gitattributes` in place — the nearer file goes on supplying `merge=ours`, and only `filter` comes from the root:
  ```gitattributes
  .codebase-memory/graph.db.zst filter=lfs diff=lfs merge=lfs -text
  ```
  Track only the `.zst`; `artifact.json` is small and carries the schema version. The attribute applies to future commits only, so a repo that already has the blobs in history needs `git-filter-repo` to rewrite them first. Two costs to weigh before adopting it: GitHub meters LFS storage and bandwidth, and its objects cannot be pruned without contacting support; and every teammate needs `git lfs install` — without it their checkout leaves a pointer file where the artifact should be, the integrity-checked import refuses it, and they fall back to a full reindex.
- **Optional**: never committed unless you want it. Add `.codebase-memory/` to `.gitignore` if you prefer everyone to reindex from scratch.

The result is similar in spirit to graphify's `graphify-out/` directory, but as a single compressed file with explicit two-tier export, integrity-checked import, and zero merge friction.

## How It Works

codebase-memory-cli is a **structural analysis backend** — it builds and queries the knowledge graph. It does **not** include an LLM. Your coding agent (e.g. GitHub Copilot in Agent mode) is the intelligence layer, and it talks to the graph by running terminal commands:

```
You: "what calls ProcessOrder?"

Copilot runs: codebase-memory-cli cli trace_path --project my-project \
                --function-name ProcessOrder --direction inbound --format json

codebase-memory-cli: executes the graph query, prints JSON, exits

Copilot: presents the call chain in plain English
```

**Why no built-in LLM?** Other code graph tools embed an LLM for natural language → graph query translation. That means extra API keys, extra cost, and another model to configure. Here, the agent you're already talking to *is* the query translator.

**Why CLI instead of MCP?** Some organizations do not permit MCP servers or long-running developer daemons. A one-shot CLI is auditable, needs no registration in any agent config, and leaves nothing running.

## Performance

Benchmarked on Apple M3 Pro:

| Operation | Time | Notes |
|-----------|------|-------|
| **Linux kernel full index** | **3 min** | 28M LOC, 75K files → 4.81M nodes, 7.72M edges |
| Linux kernel fast index | 1m 12s | 1.88M nodes |
| Django full index | ~6s | 49K nodes, 196K edges |
| Cypher query | <1ms | Relationship traversal |
| Name search (regex) | <10ms | SQL LIKE pre-filtering |
| Dead code detection | ~150ms | Full graph scan with degree filtering |
| Trace call path (depth=5) | <10ms | BFS traversal |

**RAM-first pipeline**: All indexing runs in memory (LZ4 HC compressed read, in-memory SQLite, single dump at end). Memory is released back to the OS after indexing completes.

**Token efficiency**: Five structural queries consumed ~3,400 tokens via the code graph versus ~412,000 tokens via file-by-file grep exploration — a **99.2% reduction**.

To measure comparable quality, latency, and agent-efficiency metrics on your own workload, see [Measuring quality, latency, and agent savings](docs/MEASURING_SAVINGS.md). Exact reproduction of the figures above requires the original inputs and raw artifacts.

## Troubleshooting & Diagnostics

codebase-memory-cli runs **100% locally and collects no telemetry**. When something goes wrong, the information is on your own terminal:

- **stdout** carries only the command result (JSON with `--format json`).
- **stderr** carries progress and errors. On failure a command prints a JSON `error` object on stderr and exits with status `1`.
- Add `--verbose` (outer flag, e.g. `codebase-memory-cli cli --verbose index_repository ...`) to see informational diagnostics, or set `CBM_LOG_LEVEL=debug`.
- Add `--progress` to see indexing progress even when stderr is redirected.

When reporting an issue, include the exact command, its stderr output, `codebase-memory-cli --version`, and your OS. The output contains paths and symbol names from your project — review it before sharing.

## Installation

This fork is distributed as **source only**. The upstream release archives, install scripts, package-manager packages (npm, PyPI, Homebrew, AUR, Nix, …) and "install via agent" flows all install the upstream MCP server, **not** this CLI.

### Build from Source

<details>
<summary>Prerequisites: C compiler + zlib</summary>

| Requirement | Check | Install |
|-------------|-------|---------|
| **C compiler** (gcc or clang) | `gcc --version` or `clang --version` | macOS: `xcode-select --install`, Linux: `apt install build-essential` |
| **C++ compiler** | `g++ --version` or `clang++ --version` | Same as above |
| **zlib** | — | macOS: included, Linux: `apt install zlib1g-dev` |
| **Git** | `git --version` | Pre-installed on most systems |

</details>

```bash
git clone https://github.com/shendricks555/codebase-memory-cli.git
cd codebase-memory-cli
scripts/build.sh --cli-only              # CLI only
scripts/build.sh --cli-only --with-ui    # CLI + loopback graph UI
# Binary at: build/c/codebase-memory-cli
```

Then make it reachable from each project where Copilot should use it: run `scripts/installer-wizard.sh`, or create the git-ignored `.cbm/codebase-memory-cli` link by hand. No copy is needed; see [Step 3](#step-3--make-it-available-in-your-project-no-copying-nothing-global).

Run the test suite:

```bash
scripts/test.sh                     # full: clean sanitizer build (ASan + UBSan) + all suites + guards
scripts/test.sh --suites <name>     # one suite, incremental, seconds
build/c/test-runner --list-suites   # what is available
scripts/verify-docs.sh              # checks the documented CLI commands still work
make -f Makefile.cbm security       # security gates: no MCP/daemon, no network egress, loopback-only UI
```

After cloning, enable the pre-commit checks with `git config core.hooksPath scripts/hooks`.

## GitHub Copilot Integration

This fork integrates with **GitHub Copilot** only, and only through terminal commands — nothing is registered as an MCP server in any client config.

```bash
codebase-memory-cli install [--project DIR] [--dry-run]          # write the integration files
codebase-memory-cli uninstall --copilot [--project DIR] [--dry-run]   # remove them
```

`install` writes into the target repository:

| File | Purpose |
|------|---------|
| `.github/copilot-instructions.md` | A managed section (appended or updated; your own text is preserved) telling Copilot which `codebase-memory-cli` commands answer which questions. |
| `.github/prompts/cbm-*.prompt.md` | Reusable chat prompts (e.g. *who calls*, *architecture*). |
| `.vscode/tasks.json` | VS Code tasks for indexing; written only if absent or previously generated. |

It prints a JSON report of every file and its `action` (`created`, `appended`, `updated`, `unchanged`, `skipped`). Re-running is safe. Commit these files so your whole team gets the integration.

Works in VS Code, Visual Studio 2022 17.14+, JetBrains IDEs, Android Studio, and Copilot CLI — anywhere Copilot's agent can run terminal commands. Per-IDE notes and the full command table: [`docs/COPILOT_CLI_INTEGRATION.md`](docs/COPILOT_CLI_INTEGRATION.md). Example output files: [`docs/copilot-examples/`](docs/copilot-examples/).

The upstream multi-agent installer (Claude Code, Codex, Cursor, and 40+ other MCP clients, plus their hooks and skills) is not part of this fork.

## CLI Mode

Every graph tool is a local, one-shot command: `codebase-memory-cli cli <tool> [flags]`. There is no daemon to start or connect to, and no process is left running afterwards. `index_repository` may use a temporary supervised worker internally, which is stopped before the command exits.

Commands that mutate graph data use shared OS-backed, per-project locks. This serializes conflicting CLI commands on the same project while allowing unrelated projects to proceed independently.

When stderr is an interactive terminal, the CLI automatically shows lifecycle and indexing progress. Pass `--progress` to force the same feedback when stderr is redirected or the command is run non-interactively. Pass `--quiet` to disable automatic terminal progress and ordinary diagnostics while retaining errors; it cannot be combined with `--progress` or outer `cli --verbose`. Routine informational logs are quiet by default; pass outer `cli --verbose` to include them. Progress and logs use stderr while stdout remains reserved for the command result. Read tools return a compact tree by default; pass a tool's `--format json` for machine-readable payload JSON, or outer `--json` for the full result envelope.

Large compact-tree tables may start with a response-local `<section>_refs` directory and an explicit `<section>_ref_rule`. A cell such as `@0+handler.go` reconstructs to ref `0`'s prefix plus `handler.go`. References are local to that sibling `<section>` table and expansion is non-recursive: entries inside `<section>_refs` are always literal prefixes. This is limited to declared path and qualified-name columns and activates only when the exact rendered table is at least 15% and 64 bytes smaller and a conservative model-neutral token-shape proxy also improves by at least 1%. Search and trace likewise render direct and prefix-grouped tree shapes and keep the smaller complete representation, so singleton or scattered answers do not pay directory overhead. Keys are declared once per table but never cryptically abbreviated, and `--format json` keeps stable literal strings for machine consumers. Both gates are deterministic; exact token counts still depend on the caller's tokenizer.

Lean responses truncate semantically, never by cutting arbitrary bytes from code or identifiers. Ranked graph rows are retained ahead of raw grep rows and diagnostic summaries; omitted rows/sections report totals, `has_more`, and a strictly advancing continuation offset or cursor. If even the first whole row cannot fit, CBM asks for a higher budget and emits no self-looping cursor. `max_output_tokens` is model-neutral sizing guidance: CBM enforces a deterministic ceiling of four UTF-8 bytes per requested token, so it is not a tokenizer-exact count. Detail flags such as `diagnostics`, `source_mode`, and `detail` opt into heavier fields. `search_code` pages ranked rows with `result_limit`/`result_offset` (`limit` remains a compatibility alias), raw rows with `raw_limit`/`raw_offset`, and directory summaries with `directory_limit`/`directory_offset`. Raw lines default to a UTF-8-safe match-centered preview; each row reports `content_start_byte`, returned/total byte counts, match byte bounds when known, and a content continuation offset. Pass `raw_content_offset` to page the original line without moving the raw-row cursor. `match_limit` and `source_max_lines` bound per-result details, with exact omission metadata. `detect_changes` pages changed files, impacted symbols, and module summaries independently; prefer its snapshot-bound `*_cursor` continuations, which reject changed commits, worktree bytes, graph generation, or semantic arguments instead of silently skipping or duplicating rows.

Every response is standard UTF-8. Identifiers, paths, and raw search previews preserve POSIX byte-string identities: a preserved value containing malformed UTF-8 is emitted reversibly as `@bytes:<lowercase hex of every original byte>`. A valid preserved value that literally begins with the reserved `@bytes:` or `@utf8:` prefix is emitted as `@utf8:<original value>`, so decoding is unambiguous: strip one `@utf8:` prefix for literal UTF-8, or hex-decode one `@bytes:` prefix for original bytes. Ordinary valid UTF-8 is unchanged and pays no output-token overhead. To keep code readable, source bodies replace malformed UTF-8 with U+FFFD; use the pageable raw search preview when byte-exact source inspection is required.

Use `cli <tool> --help` to see the flags generated from that tool's input schema:

```bash
codebase-memory-cli cli index_repository --repo-path /path/to/repo
codebase-memory-cli cli list_projects

# Use the "name" returned by list_projects as the project value.
codebase-memory-cli cli search_graph --project my-project --name-pattern '.*Handler.*' --label Function
codebase-memory-cli cli trace_path --project my-project --function-name Search --direction both
codebase-memory-cli cli query_graph --project my-project --query 'MATCH (f:Function) RETURN f.name LIMIT 5'

# Force human-readable progress without contaminating stdout.
codebase-memory-cli cli --progress index_repository --repo-path /path/to/repo
# Suppress automatic terminal progress and non-error diagnostics.
codebase-memory-cli cli --quiet list_projects --format json
codebase-memory-cli cli search_graph --project my-project --label Function --format json
codebase-memory-cli cli list_projects --format json --detail stats | jq '.projects[].name'
```

JSON arguments can also be piped on stdin, for tools that take arguments. A tool whose input schema declares none — `list_projects` — never reads stdin, so it stays responsive when it inherits a pipe the caller never closes (the default for `child_process.spawn` and similar wrappers). Inline JSON remains accepted for backward compatibility but is deprecated in favor of flags, `--args-file`, or stdin.

## CLI Tools

Run any of these as `codebase-memory-cli cli <tool> --help` to see its flags. `scripts/cbm <tool> [flags]` is a shorthand that adds `--quiet --format json`.

### Indexing

| Tool | Description |
|------|-------------|
| `index_repository` | Index (or incrementally re-index) a repository into the graph. Re-run it after changes. |
| `list_projects` | List all indexed projects with node/edge counts. |
| `delete_project` | Remove a project and all its graph data. |
| `index_status` | Check indexing status of a project. |

### Querying

| Tool | Description |
|------|-------------|
| `search_graph` | Structural, BM25, and semantic search. Page structural rows with `offset`/`limit` and ranked semantic rows independently with `semantic_offset`/`semantic_limit`. |
| `trace_path` | BFS traversal — who calls a function and what it calls (alias: `trace_call_path`). Depth 1-5. |
| `detect_changes` | Map git diff to affected symbols + blast radius with risk classification. |
| `query_graph` | Execute Cypher-like graph queries (read-only). |
| `get_graph_schema` | Node/edge counts, relationship patterns, property definitions per label. Run this first. |
| `get_code_snippet` | Read source code for a function by qualified name. |
| `get_architecture` | Codebase overview: languages, packages, routes, hotspots, clusters, ADR. |
| `search_code` | Grep-like text search within indexed project files. |
| `manage_adr` | CRUD for Architecture Decision Records (`get` reads, `update` replaces the whole document, `set_sections` rewrites only the named sections and leaves every other byte untouched, `sections` lists headings). Query modes do not wait behind a same-project reindex; writes remain serialized. |
| `ingest_traces` | Ingest runtime traces to validate HTTP_CALLS edges. |

`manage_adr(mode='set_sections')` writes one or more sections by name and splices them into the stored document, so text outside the named sections — including a preamble, code fences and section ordering — is preserved byte-for-byte. Any `## Heading` works, not just the conventional PURPOSE / STACK / ARCHITECTURE / PATTERNS / TRADEOFFS / PHILOSOPHY set; names match exactly, including case. Writing the same section twice is a no-op, so a retry after a lost response cannot duplicate content.

`manage_adr` updates are serialized through the per-project mutation lock.

## Graph Data Model

### Node Labels

`Project`, `Package`, `Folder`, `File`, `Module`, `Class`, `Function`, `Method`, `Interface`, `Enum`, `Type`, `Route`, `Resource`

### Edge Types

`CONTAINS_PACKAGE`, `CONTAINS_FOLDER`, `CONTAINS_FILE`, `DEFINES`, `DEFINES_METHOD`, `IMPORTS`, `CALLS`, `CALL_REFERENCE`, `HTTP_CALLS`, `ASYNC_CALLS`, `IMPLEMENTS`, `HANDLES`, `USAGE`, `CONFIGURES`, `WRITES`, `MEMBER_OF`, `TESTS`, `USES_TYPE`, `FILE_CHANGES_WITH`

### Qualified Names

`get_code_snippet` uses qualified names: `<project>.<path_parts>.<name>`. Use `search_graph` to discover them first.

### Supported Cypher (openCypher read subset)

`query_graph` is a read-only openCypher subset:

- **Clauses**: `MATCH`, `OPTIONAL MATCH`, multiple `MATCH`, `WHERE`, `WITH` (+ `WITH … WHERE`), `RETURN`, `ORDER BY`, `SKIP`, `LIMIT`, `DISTINCT`, `UNWIND`, `UNION` / `UNION ALL`, `CASE`.
- **Patterns**: labelled nodes, label alternation `(n:A|B)`, relationship types/direction, variable-length paths `[*1..3]`, inline property maps.
- **WHERE**: `= <> < <= > >=`, `AND/OR/XOR/NOT`, `IN`, `CONTAINS`, `STARTS WITH`, `ENDS WITH`, `IS [NOT] NULL`, regex `=~`, label test `n:Label`, and `EXISTS { (n)-[:TYPE]->() }` (single-hop existence — great for dead-code, e.g. `WHERE NOT EXISTS { (f)<-[:CALLS]-() }`).
- **Aggregates**: `count` (+`DISTINCT`), `sum`, `avg`, `min`, `max`, `collect`.
- **Functions**: `labels`, `type`, `id`, `keys`, `properties`; `toLower/toUpper/toString/toInteger/toFloat/toBoolean`; `size`, `length`, `trim/ltrim/rtrim`, `reverse`; `coalesce`, `substring`, `replace`, `left`, `right`.

Anything outside this subset (write/`MERGE`/`CALL` clauses, unsupported functions, list/map literals, comprehensions, path functions, parameters) **fails with a clear `unsupported …` error** rather than returning empty results.

## Ignoring Files

Layered: hardcoded patterns (`.git`, `node_modules`, etc.) → `.gitignore` hierarchy → `.cbmignore` (project-specific, gitignore syntax). Symlinks are always skipped.

See [docs/cbmignore.md](docs/cbmignore.md) for the full `.cbmignore` how-to: syntax, precedence across the ignore layers, and negation semantics.

## Configuration

```bash
codebase-memory-cli config list            # show all settings
codebase-memory-cli config set ui_port 9750
codebase-memory-cli config reset ui_port   # reset to default
```

`config list` also shows upstream session settings (`auto_index`, `auto_index_limit`, `auto_watch`, `watcher_enabled`, `ui_enabled`). They only affect upstream's MCP sessions and daemon, which do not exist in this build — in the CLI you index explicitly and start the UI with `codebase-memory-cli ui`.

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CBM_ALLOWED_ROOT` | *(unset)* | Confine `index_repository` to paths within this directory. A `repo_path` that resolves (after symlink / `..` resolution) outside this root is refused; the same check applies to the graph UI's `POST /api/index` route. Useful when commands may be driven by an untrusted caller such as an autonomous agent. |
| `CBM_CACHE_DIR` | `~/.cache/codebase-memory-mcp` | Override the database storage directory. All project indexes and config are stored here. |
| `CBM_LOG_LEVEL` | `warn` | Minimum log level on stderr: `debug`, `info`, `warn`, `error`, `none` (or `0`–`4`). Stdout is reserved for command results. |
| `CBM_WORKERS` | *(detected)* | Override the parallel-indexing worker count. Useful inside containers where the reported CPU count exceeds the cgroup quota. Range 1–256; invalid values are ignored with a warning. |
| `CBM_MEM_BUDGET_MB` | *(detected)* | Explicit in-memory graph budget in MiB, overriding the `ram_fraction × total_RAM` default. Clamped to detected total RAM; invalid values are ignored with a warning. |
| `CBM_DUMP_VERIFY_MIN_RATIO` | `0.5` | After indexing, if persisted nodes fall below this fraction of committed nodes (and committed > 50), `index_repository` returns `status:"degraded"` instead of `indexed`. Range 0–1; `0` disables. |

```bash
# Store indexes in a custom directory
export CBM_CACHE_DIR=~/my-projects/cbm-data
```

## Custom File Extensions

The JSON config files support a single key, `extra_extensions`, which maps additional file extensions to supported languages. Useful for framework-specific extensions like `.blade.php` (Laravel) or `.mjs` (ES modules). (For other tunables, see [Environment Variables](#environment-variables) and the `config` subcommand above.)

Need the full config-file reference? See [docs/CONFIGURATION.md](docs/CONFIGURATION.md).

**Per-project** (in your repo root):
```json
// .codebase-memory.json
{"extra_extensions": {".blade.php": "php", ".mjs": "javascript"}}
```

**Global** (applies to all projects):
```json
// ~/.config/codebase-memory-mcp/config.json  (or $XDG_CONFIG_HOME/...)
{"extra_extensions": {".twig": "html", ".phtml": "php"}}
```

Each entry maps an extension (which **must** start with `.`) to a language name. Language names are matched **case-insensitively**. Accepted values (aliases in parentheses) are:

`bash` (`sh`), `c`, `c++` (`cpp`), `c#` (`csharp`), `clojure`, `cmake`, `cobol`, `common lisp` (`commonlisp`, `lisp`), `css`, `cuda`, `dart`, `dockerfile`, `elixir`, `elm`, `emacs lisp` (`emacslisp`), `erlang`, `f#` (`fsharp`), `form`, `fortran`, `glsl`, `go`, `graphql`, `groovy`, `haskell`, `hcl` (`terraform`), `html`, `ini`, `java`, `javascript`, `json`, `julia`, `kotlin`, `lean`, `lua`, `magma`, `makefile`, `markdown`, `matlab`, `meson`, `nix`, `objective-c` (`objc`), `ocaml`, `perl`, `php`, `protobuf`, `python`, `r`, `ruby`, `rust`, `scala`, `scss`, `sql`, `svelte`, `swift`, `toml`, `tsx`, `typescript`, `verilog`, `vimscript`, `vue`, `wolfram`, `xml`, `yaml`, `zig`.

Project config overrides global for conflicting extensions. An entry whose language name is unknown, or whose extension does not start with `.`, is skipped and a warning is logged to stderr (shown at the default `info` log level). Missing config files are ignored.

## Persistence

SQLite databases stored at `~/.cache/codebase-memory-mcp/` (the directory name is shared with upstream). Persists across runs (WAL mode, ACID-safe). To reset: `rm -rf ~/.cache/codebase-memory-mcp/`.

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `command not found: codebase-memory-cli` | Run it as `./.cbm/codebase-memory-cli` from the project root; create the link with `scripts/installer-wizard.sh` or by hand ([Step 3](#step-3--make-it-available-in-your-project-no-copying-nothing-global)). |
| Copilot answers without running `codebase-memory-cli` | Use Copilot Chat **Agent** mode, run `codebase-memory-cli install` in the repo, reload the window, and ask it explicitly to use codebase-memory-cli. |
| `index_repository` fails | Pass an absolute path: `--repo-path "$PWD"`. Check `CBM_ALLOWED_ROOT` if set. |
| `trace_path` returns 0 results | Find the exact name first: `cli search_graph --project <name> --name-pattern '.*Partial.*'`. |
| Wrong or missing project | Use the exact `name` from `cli list_projects --format json`. |
| Results look stale | Re-run `cli index_repository` — there is no background watcher. |
| `ui` is an unknown command / UI not loading | Rebuild with `scripts/build.sh --cli-only --with-ui`, run `codebase-memory-cli ui`, open `http://127.0.0.1:9749`. |
| `update is not available in the CLI-only build` | Expected — `git pull` and rebuild instead. |

## Hybrid LSP

**Semantic type resolution beyond tree-sitter.**

Tree-sitter alone gives a syntactic AST. That handles naming, structure, and call sites well, but it can't tell you that `user.profile.display_name()` resolves to `Profile.display_name` declared three modules away — tree-sitter doesn't track imports, generics, inheritance, or stdlib types.

codebase-memory-cli ships a **lightweight C implementation of language type-resolution algorithms, structurally inspired by and compatible with major language servers** (tsserver / typescript-go, pyright, gopls, Roslyn, Eclipse JDT, rust-analyzer), embedded directly into the native executable. No language server process, no per-project setup, no API key. We call this layer **Hybrid LSP**: it runs alongside tree-sitter on every parse and refines invocation resolution (`CALLS` / `RESOLVED_CALLS`) and callable-value resolution (`CALL_REFERENCE`, with ambiguous values retained as `USAGE`) using type information, so the resulting graph mirrors what an IDE "Go to Definition" would resolve.

**Languages with full Hybrid LSP:**

| Language | What it handles |
|----------|-----------------|
| **Python** *(new in v0.7.0)* | imports + dotted submodule walks, dataclasses, `Self` return types, generics, `@property`, `match/case` class patterns, SQLAlchemy 2.0 `Mapped[T]`, Pydantic `BaseModel`, `typing.Annotated` / `ClassVar` / `Final` / `InitVar`, async/await, classmethod/staticmethod, narrowing (`isinstance` / `is not None` / walrus), `typing.cast` / `assert_type`, common stdlib (logging, pathlib, json, functools). Target ~95% resolution on idiomatic code. |
| **TypeScript / JavaScript / JSX / TSX** | generics, JSX component dispatch, JSDoc inference for plain JS, `.d.ts` declarations, module re-exports, method chaining via return-type propagation, per-file overlay chained to a shared cross-file registry |
| **PHP** *(new in v0.7.0)* | namespaces, traits, late-static-binding, PHPDoc inference, parameter binding, return-type inference |
| **C#** *(new in v0.7.0)* | global usings, file-scoped namespaces, records (incl. C# 12 primary constructors), LINQ method syntax, `async Task<T>` / `ValueTask<T>` unwrap, generic methods, `this` / `base` dispatch, `var` inference, common BCL stdlib |
| **Go** *(sharpened in v0.7.0)* | pre-built per-package cross-file registry, generics, embedded structs, interface satisfaction, package-aware import resolution |
| **C / C++** *(sharpened in v0.7.0)* | pre-built per-language cross-file registry shared across C and C++; C side handles macros + `typedef` chains + header-vs-source linking; C++ side handles templates, namespaces, `auto` inference, and method resolution via class hierarchy |
| **Java** *(new in v0.8.0)* | imports (single-type, on-demand, static), class hierarchies with `this` / `super` dispatch, generics, annotations, overload matching by arity and parameter types, lambdas / method references bound to functional interfaces, field-type inference, common JDK stdlib |
| **Kotlin** *(new in v0.8.0)* | imports + same-package resolution, classes / objects / companion objects, extension functions, data classes, nullable-type unwrapping, scope functions (`let` / `apply` / `run` / `also` / `with`), infix calls, common stdlib |
| **Rust** *(new in v0.8.0)* | `use` declarations + module paths, `impl` blocks and trait methods, struct fields, generics with trait bounds, operator-trait desugaring, derive-macro method synthesis, UFCS static paths, common std prelude |
| **Perl** | packages + `@ISA` / `use parent` / `use base` inheritance with method-resolution-order dispatch, `SUPER::` calls, Exporter (`use Foo qw(...)`) import maps, `bless` / `ref($class)\|\|$class` self-type inference, qualified `Pkg::sub` static calls, curated perlfunc + CPAN OOP stdlib; unresolved receivers emit no edge (zero-edge guarantee) |

**Two-layer architecture:**

1. **Tree-sitter pass** — fast, syntactic, runs for every one of the 162 languages. Extracts definitions, calls, imports.
2. **Hybrid LSP pass** — type-aware, runs above the tree-sitter pass per-language. Refines call edges using the import graph plus a per-file or pre-built cross-file definition registry. Languages without a Hybrid LSP pass yet fall back to textual resolution, so you always get *some* answer.

The result is a knowledge graph accurate enough to drive `trace_path` across packages, inheritance hierarchies, and stdlib calls — without paying for a language server process per project.

## Language Support

162 languages, all parsed via vendored tree-sitter grammars compiled into the binary. Benchmarked against 64 real open-source repositories (78 to 49K nodes):

| Tier | Score | Languages |
|------|-------|-----------|
| **Excellent** (>= 90%) | | Lua, Kotlin, C++, Perl, Objective-C, Groovy, C, Bash, Zig, Swift, CSS, YAML, TOML, HTML, SCSS, HCL, Dockerfile |
| **Good** (75-89%) | | Python, TypeScript, TSX, Go, Rust, Java, R, Dart, JavaScript, Erlang, Elixir, Scala, Ruby, PHP, C#, SQL |
| **Functional** (< 75%) | | OCaml, Haskell |

Also supported (not yet benchmarked): Ada, Agda, Apex, Assembly (NASM), Astro, AWK, Beancount, BibTeX, Bicep, Bitbake, Blade, Cairo, Cap'n Proto, Clojure, CMake, COBOL, Common Lisp, Crystal, CSV, CUDA, D, Devicetree, Diff, .env, Elm, Emacs Lisp, F#, Fennel, Fish, FORM, Fortran, FunC, GDScript, .gitattributes, .gitignore, Gleam, GLSL, GN, Go module, Go template, GraphQL, Hare, HLSL, Hyprlang, INI, ISPC, Janet, Jinja2, JSDoc, JSON, JSON5, Jsonnet, Julia, Just, Kconfig, KDL, Lean 4, Linker Script, Liquid, LLVM IR, Luau, Magma, Makefile, Markdown, MATLAB, Mermaid, Meson, Move, Nickel, Nim, Nix, Odin, Pascal, Pkl, PO (gettext), Pony, PowerShell, Prisma, .properties, Protobuf, Puppet, PureScript, Racket, Regex, requirements.txt, ReScript, RON, reStructuredText, Scheme, Slang, Smali, Smithy, Solidity, SOQL, SOSL, Squirrel, SSH config, Starlark, Svelte, Sway, SystemVerilog, TableGen, Tcl, Teal, Templ, Thrift, TLA+, Typst, Verilog, VHDL, Vim script, Vue, WGSL, WIT, Wolfram, XML, Zsh.

## Architecture

```
src/
  main.c              Entry point (CLI dispatch: cli / install / uninstall / config / ui)
  cli/                One-shot CLI commands, Copilot install/uninstall, config
  store/              SQLite graph storage (nodes, edges, traversal, search, Louvain)
  pipeline/           Multi-pass indexing (structure → definitions → calls → HTTP links → config → tests)
  cypher/             Cypher query lexer, parser, planner, executor
  discover/           File discovery (.gitignore, .cbmignore, symlink handling)
  traces/             Runtime trace ingestion
  ui/                 Loopback-only HTTP server for the 3D graph UI (--with-ui builds)
  foundation/         Platform abstractions (threads, filesystem, logging, memory)
  mcp/, daemon/,      Upstream MCP server, coordination daemon and watcher —
  watcher/            excluded from the CLI-only binary via CBM_FORK_CLI_ONLY
internal/cbm/         Vendored tree-sitter grammars (162 languages) + AST extraction engine
```

Upstream-mergeability: fork changes live behind the `CBM_FORK_CLI_ONLY` compile guard and at the CLI/build boundary; the shared core (`src/foundation`, `src/store`, `src/cypher`, `src/pipeline`, `internal/cbm`) tracks upstream.

## Security

This fork is built locally from source, so its guarantees are enforced by repository gates rather than by signed releases:

- **No MCP, no daemon in the binary** — `make -f Makefile.cbm security` runs a static allow-list and string scan of the built binary.
- **No outbound network** — a network-egress test and a source audit (`scripts/security-network.sh`, `scripts/security-network-source-audit.py`) fail the gate if any non-loopback connection or listener appears.
- **Loopback-only UI** — `scripts/security-ui.sh` checks that the graph UI binds `127.0.0.1` only.
- **Fuzzing and sanitizers** — `scripts/security-fuzz.sh`, and `scripts/test.sh` runs every suite under ASan + UBSan.
- **No test seams in production builds** — `TEST_SEAMS` is enabled only by `scripts/test.sh`, never by `scripts/build.sh`.
- **Vendored dependencies** — all libraries are vendored and checksum-pinned (`scripts/vendored-checksums.txt`); the build needs no network access.

Upstream's release-signing and VirusTotal process covers the upstream MCP binaries, not this fork. Report vulnerabilities as described in [SECURITY.md](SECURITY.md).

## License

MIT
