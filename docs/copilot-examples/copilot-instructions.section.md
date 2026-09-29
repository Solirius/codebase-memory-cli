<!-- codebase-memory-cli:begin (managed by `codebase-memory-cli install`; remove with `codebase-memory-cli uninstall --copilot`) -->
## Code graph: codebase-memory-cli (terminal commands, no server)

This repository can be queried as a structural code graph with the local
`codebase-memory-cli` binary. Run it as a terminal command. There is no server to
configure, and it makes no network calls.

1. Find the project name: `codebase-memory-cli cli list_projects --format json`
2. If this repository is missing or stale, index it:
   `codebase-memory-cli cli --quiet index_repository --repo-path "$PWD"`
3. Query it (add `--format json` for machine-readable output):
   - Find symbols: `codebase-memory-cli cli search_graph --project <name> --name-pattern '<regex>' --format json`
   - Who calls X: `codebase-memory-cli cli trace_path --project <name> --function-name X --direction inbound --format json`
   - What X calls: the same with `--direction outbound`
   - Source of X: `codebase-memory-cli cli get_code_snippet --project <name> --qualified-name X --format json`
   - Module overview: `codebase-memory-cli cli get_architecture --project <name> --format json`
   - Cypher: `codebase-memory-cli cli query_graph --project <name> --query 'MATCH (f:Function)-[:CALLS]->(g) RETURN f.name, g.name LIMIT 20' --format json`
4. Tool errors are printed on stderr as JSON (`{"error": "...", "hint": "..."}`)
   with exit code 1. Follow the hint (usually: run `list_projects`, or index first).

Prefer these commands over text search for structural questions: callers, callees,
definitions and architecture. `codebase-memory-cli cli <tool> --help` lists every flag.
<!-- codebase-memory-cli:end -->
