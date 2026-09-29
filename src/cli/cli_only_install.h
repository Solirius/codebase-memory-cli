/* cli_only_install.h — fork milestone 05: CLI-only Copilot integration files.
 *
 * Fork-only (CBM_FORK_CLI_ONLY). Linked only into cbm-cli / cbm-cli-with-ui via
 * cli-only.mk; never part of the upstream PROD_SRCS. Writes (or removes) the
 * command-based GitHub Copilot integration for one repository:
 *   .github/copilot-instructions.md   (a marker-delimited managed section)
 *   .github/prompts/cbm-*.prompt.md   (whole files, marker-tagged)
 *   .vscode/tasks.json                (only when absent or already ours)
 * It never writes an MCP server registration of any kind. */
#ifndef CBM_CLI_ONLY_INSTALL_H
#define CBM_CLI_ONLY_INSTALL_H

#include <stdbool.h>

/* argv holds the options after the subcommand. `uninstall` selects removal.
 * Prints one JSON document on stdout. Returns 0 on success, 1 on a file
 * error or conflict, 2 on a usage error. */
int cbm_cli_only_copilot_main(int argc, char **argv, bool uninstall);

/* True when argv (options after `uninstall`) asks for the Copilot removal. */
bool cbm_cli_only_copilot_requested(int argc, char **argv);

#endif /* CBM_CLI_ONLY_INSTALL_H */
