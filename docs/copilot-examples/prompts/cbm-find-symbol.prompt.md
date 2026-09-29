---
description: "Locate a symbol and show its source with the codebase-memory-cli graph"
mode: agent
---
<!-- codebase-memory-cli:managed (remove with `codebase-memory-cli uninstall --copilot`) -->
Locate `${input:symbol:symbol name}` in this repository by running terminal commands.

1. Find the project name with `codebase-memory-cli cli list_projects --format json`.
2. Run `codebase-memory-cli cli search_graph --project <name> --name-pattern '${input:symbol:symbol name}' --format json`.
3. For the best match, run `codebase-memory-cli cli get_code_snippet --project <name> --qualified-name <qualified_name> --format json` and explain what it does.
