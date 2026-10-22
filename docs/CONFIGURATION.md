# Configuration Reference

This page documents the configuration files and environment variables that `codebase-memory-cli` reads or writes.

> The on-disk directory names below still say `codebase-memory-mcp`: they are inherited unchanged from upstream so the shared core stays mergeable. They are the real paths the CLI uses.

| Purpose | Path | Format | Notes |
|---|---|---|---|
| Per-project custom extension mapping | `.codebase-memory.json` in the repository root | JSON | Optional. Overrides the global mapping. |
| Global custom extension mapping | `$XDG_CONFIG_HOME/codebase-memory-mcp/config.json` | JSON | Falls back to `~/.config/codebase-memory-mcp/config.json` when `XDG_CONFIG_HOME` is unset. |
| Indexes | `${CBM_CACHE_DIR:-~/.cache/codebase-memory-mcp}/` | SQLite | One database per indexed project. |
| CLI-managed settings | `${CBM_CACHE_DIR:-~/.cache/codebase-memory-mcp}/_config.db` | SQLite | Written by `codebase-memory-cli config set/reset`. |
| UI settings | `${CBM_CACHE_DIR:-~/.cache/codebase-memory-mcp}/config.json` | JSON | Stores `ui_enabled` and `ui_port`. |
| Copilot integration | `.github/copilot-instructions.md`, `.github/prompts/cbm-*.prompt.md`, `.vscode/tasks.json` in a repository | Markdown / JSON | Written by `codebase-memory-cli install`. See [COPILOT_CLI_INTEGRATION.md](./COPILOT_CLI_INTEGRATION.md). |

## 1. Custom File Extension Mapping

Two optional JSON files let you map additional file extensions to built-in languages.

### Global config

Default path:

```text
$XDG_CONFIG_HOME/codebase-memory-mcp/config.json
```

Fallback when `XDG_CONFIG_HOME` is unset:

```text
~/.config/codebase-memory-mcp/config.json
```

### Per-project config

Place this file in the repository root:

```text
.codebase-memory.json
```

### Format

```json
{
  "extra_extensions": {
    ".blade.php": "php",
    ".mjs": "javascript",
    ".twig": "html"
  }
}
```

Notes:

- Extension keys must include the leading dot.
- Language names are case-insensitive.
- Unknown language names are skipped.
- Missing files are ignored.
- If the same extension appears in both files, the per-project file wins.

## 2. CLI-Managed Settings

The `config` subcommand stores settings in a small SQLite database:

```text
${CBM_CACHE_DIR:-~/.cache/codebase-memory-mcp}/_config.db
```

```bash
codebase-memory-cli config list
codebase-memory-cli config get ui_port
codebase-memory-cli config set ui_port 9750
codebase-memory-cli config reset ui_port
```

| Key | Default | Used by the CLI build? |
|---|---|---|
| `ui_port` | `9749` | Yes — default port for `codebase-memory-cli ui` (`--port` overrides it). |
| `ui-lang` | `auto` | Yes — graph UI language. |
| `ui_enabled` | `false` | No — upstream session setting; start the UI explicitly with `codebase-memory-cli ui`. |
| `auto_index`, `auto_index_limit` | `false`, `50000` | No — upstream session settings; run `cli index_repository` explicitly. |
| `auto_watch`, `watcher_enabled` | `true` | No — there is no background watcher in this build. |

## 3. UI Settings

Binaries built with `scripts/build.sh --cli-only --with-ui` read UI settings from:

```text
${CBM_CACHE_DIR:-~/.cache/codebase-memory-mcp}/config.json
```

```json
{
  "ui_enabled": false,
  "ui_port": 9749
}
```

The UI always binds `127.0.0.1`. `CBM_CACHE_DIR` moves both this file and the settings database.

## 4. Environment Variables

| Variable | Default | Description |
|---|---|---|
| `CBM_ALLOWED_ROOT` | *(unset)* | Confine `index_repository` to paths within this directory. A `repo_path` that resolves (after symlink / `..` resolution) outside this root is refused; the same check applies to the graph UI's `POST /api/index` route. The always-on limits below apply whether or not this is set. Useful when commands may be driven by an autonomous agent. |
| `CBM_CACHE_DIR` | `~/.cache/codebase-memory-mcp` | Override the directory used for indexes, `_config.db`, and UI `config.json`. |
| `CBM_LOG_LEVEL` | `warn` | `debug`, `info`, `warn`, `error`, or `none` (or `0`-`4`). Logs go to stderr; stdout carries only the command result. |
| `CBM_RUNTIME_DIR` | `/private/tmp` (macOS), `/tmp` (Linux), `%LOCALAPPDATA%` (Windows) | Parent of the private lock directory (`cbm-daemon-<uid>`) used for per-project locks. Set it if the default location fails the private-directory check (see below). |
| `CBM_WORKERS` | auto-detected | Override the indexing worker count (1–256). |
| `CBM_MEM_BUDGET_MB` | auto-detected | Explicit in-memory graph budget in MiB. |
| `CBM_DUMP_VERIFY_MIN_RATIO` | `0.5` | Below this persisted/committed node ratio, `index_repository` reports `status:"degraded"`. `0` disables. |

### Relocating the lock directory

Before it is used, the lock directory and every ancestor are checked: each must be owned by you or root, must not be world-writable (except a standard root-owned sticky directory such as `/tmp`), and must carry no allow-ACL. If that check fails, every command fails, `config list` included. Point it at a directory you own:

```bash
export CBM_RUNTIME_DIR="$HOME/cbm-runtime"
```

The named directory goes through the same validation; a value that fails is refused rather than ignored.

### Roots that are always refused

Independently of `CBM_ALLOWED_ROOT`, some directories are refused as an indexing
root because they are too broad or too sensitive to index as a unit:

- a filesystem root, a Windows drive root, or a UNC share root;
- a top-level system tree — `/etc`, `/var`, `/usr`, `/home`, `/Users`, and on
  Windows `C:\Windows`, `C:\Users`, `C:\ProgramData`, `C:\Program Files`;
- your home directory itself (directories *below* it are fine);
- a credential directory at any depth — `.ssh`, `.aws`, `.gnupg`, `.kube`,
  `.docker`, `.netrc`, `.git-credentials`, `.password-store`, macOS `Keychains`.

Two limits are worth stating plainly. This constrains *scope*, not
*sensitivity*: inside a root that is allowed, every file the process can read may
be indexed and later returned. And the credential list is a denylist, so it
raises the cost of a mistake rather than closing the class — a directory it does
not name is permitted.
