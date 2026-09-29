/* cli_only_ui.h — fork milestone 03: `codebase-memory-cli ui [--port N]`.
 *
 * Fork-only (CBM_FORK_CLI_ONLY). Linked only into cbm-cli / cbm-cli-with-ui
 * via cli-only.mk; never part of the upstream PROD_SRCS. Compiled with
 * CBM_FORK_CLI_ONLY_UI=1 it runs the loopback graph UI in-process; without it
 * the command reports "built without UI" and exits 2, so the plain binary
 * references no HTTP/socket code at all. */
#ifndef CBM_CLI_ONLY_UI_H
#define CBM_CLI_ONLY_UI_H

#include "daemon/project_lock.h"

/* argv[1] must be "ui". `project_locks` (may be NULL) serializes UI mutations
 * against concurrent `cli` commands; it stays owned by the caller. Returns
 * the process exit code. */
int cbm_cli_only_ui_main(int argc, char **argv, cbm_project_lock_manager_t *project_locks);

#endif /* CBM_CLI_ONLY_UI_H */
