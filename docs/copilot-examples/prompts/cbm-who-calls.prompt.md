---
description: "Find the callers of a function with the codebase-memory-cli code graph"
mode: agent
---
<!-- codebase-memory-cli:managed (remove with `codebase-memory-cli uninstall --copilot`) -->
Find every caller of `${input:symbol:function name}` in this repository by running
terminal commands. Do not use a server integration.

1. Run `codebase-memory-cli cli list_projects --format json` and pick the project whose
   `root_path` is this workspace. If there is none, run
   `codebase-memory-cli cli --quiet index_repository --repo-path "$PWD"` first.
2. Run `codebase-memory-cli cli trace_path --project <name> --function-name ${input:symbol:function name} --direction inbound --depth 2 --format json`.
3. Report the callers grouped by file, with line numbers, and quote the command you ran.
