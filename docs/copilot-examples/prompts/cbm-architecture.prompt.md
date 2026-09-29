---
description: "Summarize this repository's architecture from the codebase-memory-cli graph"
mode: agent
---
<!-- codebase-memory-cli:managed (remove with `codebase-memory-cli uninstall --copilot`) -->
Summarize the architecture of this repository by running terminal commands.

1. Run `codebase-memory-cli cli list_projects --format json` to find the project name
   (index with `codebase-memory-cli cli --quiet index_repository --repo-path "$PWD"` if it is missing).
2. Run `codebase-memory-cli cli get_architecture --project <name> --aspects '["overview"]' --format json`.
3. Describe languages, packages, entry points and the main dependencies between them.
