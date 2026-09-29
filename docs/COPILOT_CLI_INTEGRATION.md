# Using codebase-memory-cli from GitHub Copilot (no MCP)

This fork works with GitHub Copilot by **running commands**. It does not register a server.

> **Why commands?** Copilot's built-in protocol for external tools *is* MCP. This fork removes MCP
> on purpose, so it cannot appear in Copilot's tool list the way an MCP server would. Instead,
> Copilot's agent runs `codebase-memory-cli` in a terminal and reads the JSON it prints. This works
> anywhere the Copilot agent can run terminal commands.
>
> **Caveat (do not register a server):** never add a `.mcp.json` file or an `mcpServers` entry for this binary.
> It cannot speak that protocol, and it does not need one. Leave your editor's MCP settings alone.

## 1. One-time setup

1. Build the binary and put it on your `PATH` (see [CLI_QUICKSTART.md](./CLI_QUICKSTART.md)):

   ```text
   scripts/build.sh --cli-only
   cp build/c/codebase-memory-cli ~/.local/bin/
   ```

2. Index the repository you are working in:

   ```text
   codebase-memory-cli cli --quiet index_repository --repo-path "$PWD"
   ```

3. Write the Copilot integration files into that repository:

   ```text
   codebase-memory-cli install                 # or: install --project /path/to/repo
   ```

   `install` writes only these files and prints a JSON report of what it did:

   | File | What it is | Ownership |
   |---|---|---|
   | `.github/copilot-instructions.md` | A section that tells Copilot which commands to run | Only the text between the `codebase-memory-cli:begin` and `:end` markers. Your own text is kept |
   | `.github/prompts/cbm-who-calls.prompt.md` | Reusable prompt: find callers | Whole file, marker-tagged |
   | `.github/prompts/cbm-architecture.prompt.md` | Reusable prompt: architecture summary | Whole file, marker-tagged |
   | `.github/prompts/cbm-find-symbol.prompt.md` | Reusable prompt: locate a symbol and show its source | Whole file, marker-tagged |
   | `.vscode/tasks.json` | VS Code tasks (index, list projects, who calls, architecture, UI) | Written only if absent or already generated. An existing file of yours is skipped. Merge the snippet from [`copilot-examples/vscode/tasks.json`](./copilot-examples/vscode/tasks.json) by hand |

   Running `install` again changes nothing (every file reports `unchanged`). It never writes to
   your home directory and never writes a server registration. `--dry-run` shows the plan.

4. To undo it:

   ```text
   codebase-memory-cli uninstall --copilot     # or: --project /path/to/repo
   ```

   This removes the managed section, the marker-tagged files, and any directories left empty.
   Files without the marker are never touched.

Example report (captured):

```json
{"status":"installed","integration":"copilot-cli-commands","project":"/path/to/repo","dry_run":false,
 "files":[{"path":".github/copilot-instructions.md","action":"appended"},
          {"path":".github/prompts/cbm-who-calls.prompt.md","action":"created"},
          {"path":".github/prompts/cbm-architecture.prompt.md","action":"created"},
          {"path":".github/prompts/cbm-find-symbol.prompt.md","action":"created"},
          {"path":".vscode/tasks.json","action":"created"}]}
```

`action` is one of `created`, `appended`, `updated`, `unchanged` or `skipped` (install), and
`removed`, `section_removed`, `absent` or `skipped` (uninstall). A `skipped` entry has a `reason`.
A file problem gives `"action":"error"`, `"status":"error"` and exit status 1. A bad option gives
`{"error":"..."}` and exit status 2.

## 2. The commands Copilot runs

These are the commands the instructions section teaches. On success, each prints one JSON document on
stdout. On failure, it prints a JSON `error` object on stderr and exits 1. See [CLI_BUILD_RUN_GUIDE.md](./CLI_BUILD_RUN_GUIDE.md#json-output-reference) for the
shapes.

| Question | Command |
|---|---|
| Which project name do I use? | `codebase-memory-cli cli list_projects --format json` |
| Index or refresh | `codebase-memory-cli cli --quiet index_repository --repo-path "$PWD"` |
| Who calls X? | `codebase-memory-cli cli trace_path --project P --function-name X --direction inbound --format json` |
| What does X call? | `... trace_path ... --direction outbound --format json` |
| Where is X defined? | `codebase-memory-cli cli search_graph --project P --name-pattern 'X' --format json` |
| Show me X | `codebase-memory-cli cli get_code_snippet --project P --qualified-name X --format json` |
| How is this repo organised? | `codebase-memory-cli cli get_architecture --project P --format json` |
| Anything structural | `codebase-memory-cli cli query_graph --project P --query '<cypher>' --format json` |

`scripts/cbm <tool> [flags]` in this repository is a shorter form of the same thing.

## 3. Per-IDE notes

### VS Code

- Copilot Chat in **Agent** mode reads `.github/copilot-instructions.md` automatically and can run
  terminal commands. Approve the `codebase-memory-cli` command when asked, or add it to the
  terminal auto-approve list (`chat.tools.terminal.autoApprove`) if your policy allows.
- The prompt files show up as slash commands in Chat: `/cbm-who-calls`, `/cbm-architecture`,
  `/cbm-find-symbol`.
- `.vscode/tasks.json` gives you **Terminal → Run Task → cbm: ...** for use without Copilot.
- You need no MCP settings. Leave the MCP server list empty for this tool.

### Visual Studio (2022 17.14+)

- Copilot Chat in **Agent** mode reads `.github/copilot-instructions.md` (custom instructions must
  be enabled in the GitHub Copilot options). The agent runs commands in the terminal after you
  approve them.
- Prompt files in `.github/prompts/` are available through `#prompt:` / the prompt picker in
  recent versions. If your version lacks them, paste the steps from the prompt file into chat.
- `tasks.json` is VS Code only. In Visual Studio, add the commands under *Tools → External Tools*
  if you want menu entries.

### JetBrains IDEs (IntelliJ IDEA, CLion, PyCharm, and others)

- The GitHub Copilot plugin's **Agent** mode reads `.github/copilot-instructions.md` and runs
  terminal commands after you approve them.
- Prompt files are supported in recent plugin versions (type `/` in chat). Otherwise, paste the
  prompt text.
- For menu access without Copilot, add an **External Tool** (*Settings → Tools → External Tools*)
  with program `codebase-memory-cli` and arguments such as
  `cli trace_path --project <name> --function-name $SelectedText$ --direction inbound --format json`.

### Android Studio

- Android Studio uses the same JetBrains Copilot plugin, so the JetBrains notes apply. Install the
  plugin from *Settings → Plugins* and use Agent mode.
- Index the project root (the directory with `settings.gradle(.kts)`); Kotlin and Java are both
  indexed.

### Copilot CLI (terminal)

- The `copilot` terminal agent reads `.github/copilot-instructions.md` and runs shell commands.
  Allow the binary for a session with `--allow-tool 'shell(codebase-memory-cli)'`.

## 4. Graph UI (optional)

With a UI build (`scripts/build.sh --cli-only --with-ui`), `codebase-memory-cli ui` serves the graph
viewer on `http://127.0.0.1:9749` until you press Ctrl-C. It always binds to `127.0.0.1`, and no
option changes that. Do not put it behind a proxy or port forward that exposes it to other
machines.

## 5. Example files

[`docs/copilot-examples/`](./copilot-examples/) contains copies of what `install` writes, so you can
review them or copy them by hand:

- `prompts/cbm-who-calls.prompt.md`, `prompts/cbm-architecture.prompt.md`,
  `prompts/cbm-find-symbol.prompt.md`
- `vscode/tasks.json`
- `copilot-instructions.section.md`

## 6. End-to-end check (manual, Q5)

1. In VS Code, confirm that no MCP servers are configured (*MCP: List Servers* shows none).
2. Run `codebase-memory-cli install` and index the repository.
3. In Copilot Chat Agent mode, ask: "Who calls `compute`?"
4. Expected: the agent runs `codebase-memory-cli cli trace_path ... --direction inbound` in the
   terminal and answers from its JSON output.
