/* cli_only_ui.c — fork milestone 03: `codebase-memory-cli ui [--port N]`.
 *
 * Runs the graph UI HTTP server in-process for as long as the command runs.
 * No daemon, no watcher, no /rpc (http_server.c is compiled with
 * CBM_FORK_CLI_ONLY). httpd binds 127.0.0.1 by construction and nothing here
 * can change the interface. SIGINT/SIGTERM stop the server cleanly.
 *
 * Without CBM_FORK_CLI_ONLY_UI only the argument parser and the
 * "built without UI" refusal are compiled, so the plain cbm-cli binary links
 * no HTTP server code. */
#include "cli/cli_only_ui.h"

#include <errno.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef CBM_FORK_CLI_ONLY_UI
#include "foundation/compat.h"
#include "foundation/compat_thread.h"
#include "mcp/mcp.h"
#include "ui/http_server.h"

#include <signal.h>
#include <yyjson/yyjson.h>
#endif

enum {
    CLI_ONLY_UI_DEFAULT_PORT = 9749,
    CLI_ONLY_UI_MAX_PORT = 65535,
    CLI_ONLY_UI_EXIT_USAGE = 2,
};

typedef struct {
    int port;
    bool json;
    bool help;
} cli_only_ui_opts_t;

static void cli_only_ui_error(bool json, const char *code, const char *message) {
    if (json) {
        printf("{\"error\":{\"code\":\"%s\",\"message\":\"%s\"}}\n", code, message);
        (void)fflush(stdout);
    } else {
        (void)fprintf(stderr, "codebase-memory-cli ui: %s\n", message);
    }
}

static void cli_only_ui_usage(FILE *out) {
    (void)fprintf(out, "Usage: codebase-memory-cli ui [--port N] [--format json|text]\n\n"
                       "Serve the graph UI on http://127.0.0.1:N (default %d; 0 picks a free\n"
                       "port) until Ctrl-C. Binds the loopback interface only.\n",
                  CLI_ONLY_UI_DEFAULT_PORT);
}

static bool cli_only_ui_parse_port(const char *text, int *port) {
    if (!text || !text[0]) {
        return false;
    }
    char *end = NULL;
    errno = 0;
    long value = strtol(text, &end, 10);
    if (errno != 0 || !end || *end != '\0' || value < 0 || value > CLI_ONLY_UI_MAX_PORT) {
        return false;
    }
    *port = (int)value;
    return true;
}

static bool cli_only_ui_parse_format(const char *text, bool *json) {
    if (text && strcmp(text, "json") == 0) {
        *json = true;
        return true;
    }
    if (text && strcmp(text, "text") == 0) {
        *json = false;
        return true;
    }
    return false;
}

/* Returns NULL on success, else a static description of the bad argument. */
static const char *cli_only_ui_parse(int argc, char **argv, cli_only_ui_opts_t *opts) {
    opts->port = CLI_ONLY_UI_DEFAULT_PORT;
    opts->json = false;
    opts->help = false;
    const char *error = NULL;
    for (int i = 2; i < argc; i++) {
        const char *arg = argv[i];
        if (strcmp(arg, "-h") == 0 || strcmp(arg, "--help") == 0) {
            opts->help = true;
        } else if (strcmp(arg, "--port") == 0) {
            if (i + 1 >= argc || !cli_only_ui_parse_port(argv[++i], &opts->port)) {
                error = "--port requires an integer 0-65535";
            }
        } else if (strncmp(arg, "--port=", 7) == 0) {
            if (!cli_only_ui_parse_port(arg + 7, &opts->port)) {
                error = "--port requires an integer 0-65535";
            }
        } else if (strcmp(arg, "--format") == 0) {
            if (i + 1 >= argc || !cli_only_ui_parse_format(argv[++i], &opts->json)) {
                error = "--format must be json or text";
            }
        } else if (strncmp(arg, "--format=", 9) == 0) {
            if (!cli_only_ui_parse_format(arg + 9, &opts->json)) {
                error = "--format must be json or text";
            }
        } else if (!error) {
            error = "unknown argument";
        }
    }
    return error;
}

#ifdef CBM_FORK_CLI_ONLY_UI

enum {
    CLI_ONLY_UI_POLL_US = 100000,
    CLI_ONLY_UI_FREE_RETRY_US = 50000,
    CLI_ONLY_UI_LEASE_RELEASE_US = 1000,
};

static volatile sig_atomic_t g_cli_only_ui_stop = 0;

static void cli_only_ui_on_signal(int sig) {
    (void)sig;
    g_cli_only_ui_stop = 1;
}

/* Thread-safe project mutation leases: the HTTP thread (ADR save, delete) and
 * index job threads may take and drop leases concurrently. */
typedef struct cli_only_ui_lease {
    char *project;
    cbm_project_lock_lease_t *lease;
    struct cli_only_ui_lease *next;
} cli_only_ui_lease_t;

typedef struct {
    cbm_project_lock_manager_t *manager;
    cbm_mutex_t mutex;
    cli_only_ui_lease_t *leases;
} cli_only_ui_mutations_t;

static void cli_only_ui_lease_release(cbm_project_lock_lease_t **lease) {
    while (lease && *lease) {
        (void)cbm_project_lock_lease_release(lease);
        if (*lease) {
            cbm_usleep(CLI_ONLY_UI_LEASE_RELEASE_US);
        }
    }
}

static bool cli_only_ui_mutation_begin(void *context, const char *project) {
    cli_only_ui_mutations_t *mutations = context;
    if (!mutations || !mutations->manager || !project || !project[0]) {
        return false;
    }
    cbm_project_lock_lease_t *lease = NULL;
    if (cbm_project_lock_try_acquire(mutations->manager, project, &lease) !=
            CBM_PRIVATE_FILE_LOCK_OK ||
        !lease) {
        cli_only_ui_lease_release(&lease);
        return false;
    }
    cli_only_ui_lease_t *held = calloc(1, sizeof(*held));
    char *name = held ? strdup(project) : NULL;
    if (!held || !name) {
        free(held);
        cli_only_ui_lease_release(&lease);
        return false;
    }
    held->project = name;
    held->lease = lease;
    cbm_mutex_lock(&mutations->mutex);
    held->next = mutations->leases;
    mutations->leases = held;
    cbm_mutex_unlock(&mutations->mutex);
    return true;
}

static void cli_only_ui_mutation_end(void *context, const char *project) {
    cli_only_ui_mutations_t *mutations = context;
    if (!mutations || !project) {
        return;
    }
    cbm_mutex_lock(&mutations->mutex);
    cli_only_ui_lease_t **cursor = &mutations->leases;
    while (*cursor && strcmp((*cursor)->project, project) != 0) {
        cursor = &(*cursor)->next;
    }
    cli_only_ui_lease_t *held = *cursor;
    if (held) {
        *cursor = held->next;
    }
    cbm_mutex_unlock(&mutations->mutex);
    if (held) {
        cli_only_ui_lease_release(&held->lease);
        free(held->project);
        free(held);
    }
}

static void cli_only_ui_mutations_release_all(cli_only_ui_mutations_t *mutations) {
    cbm_mutex_lock(&mutations->mutex);
    cli_only_ui_lease_t *held = mutations->leases;
    mutations->leases = NULL;
    cbm_mutex_unlock(&mutations->mutex);
    while (held) {
        cli_only_ui_lease_t *next = held->next;
        cli_only_ui_lease_release(&held->lease);
        free(held->project);
        free(held);
        held = next;
    }
}

/* POST /api/index executor: one in-process engine per job, exactly like a
 * one-shot `cli index_repository`, guarded by the same project leases. */
static int cli_only_ui_index(void *context, const char *root_path, const char *project_name) {
    (void)project_name;
    if (!root_path || !root_path[0]) {
        return -1;
    }
    yyjson_mut_doc *doc = yyjson_mut_doc_new(NULL);
    if (!doc) {
        return -1;
    }
    yyjson_mut_val *obj = yyjson_mut_obj(doc);
    yyjson_mut_doc_set_root(doc, obj);
    yyjson_mut_obj_add_strcpy(doc, obj, "repo_path", root_path);
    char *args = yyjson_mut_write(doc, 0, NULL);
    yyjson_mut_doc_free(doc);
    if (!args) {
        return -1;
    }
    int rc = -1;
    cbm_mcp_server_t *engine = cbm_mcp_server_new(NULL);
    if (engine) {
        cbm_mcp_server_set_background_tasks(engine, false);
        if (context) {
            cbm_mcp_server_set_project_mutation_guard(engine, cli_only_ui_mutation_begin,
                                                      cli_only_ui_mutation_end, context);
            cbm_mcp_server_set_project_mutation_try_guard(engine, cli_only_ui_mutation_begin);
        }
        char *result = cbm_mcp_handle_tool(engine, "index_repository", args);
        if (result) {
            yyjson_doc *parsed = yyjson_read(result, strlen(result), 0);
            yyjson_val *root = parsed ? yyjson_doc_get_root(parsed) : NULL;
            yyjson_val *is_error = root ? yyjson_obj_get(root, "isError") : NULL;
            rc = (root && !yyjson_get_bool(is_error)) ? 0 : -1;
            yyjson_doc_free(parsed);
            free(result);
        }
        cbm_mcp_server_free(engine);
    }
    free(args);
    return rc;
}

static void *cli_only_ui_http_thread(void *server) {
    cbm_http_server_run(server);
    return NULL;
}

static int cli_only_ui_serve(const cli_only_ui_opts_t *opts, const char *argv0,
                             cbm_project_lock_manager_t *project_locks) {
    cbm_http_server_set_binary_path(argv0);

    cli_only_ui_mutations_t mutations = {.manager = project_locks, .leases = NULL};
    cbm_mutex_init(&mutations.mutex);

    cbm_http_server_t *server = cbm_http_server_new(opts->port);
    if (!server) {
        cli_only_ui_error(opts->json, "port_in_use",
                          "could not listen on 127.0.0.1 (port in use or unavailable)");
        cbm_mutex_destroy(&mutations.mutex);
        return EXIT_FAILURE;
    }
    if (project_locks) {
        cbm_http_server_set_project_mutation_guard(server, cli_only_ui_mutation_begin,
                                                   cli_only_ui_mutation_end, &mutations);
    }
    cbm_http_server_set_index_executor(server, cli_only_ui_index,
                                       project_locks ? &mutations : NULL);

    struct sigaction action;
    struct sigaction old_int;
    struct sigaction old_term;
    struct sigaction old_pipe;
    memset(&action, 0, sizeof(action));
    action.sa_handler = cli_only_ui_on_signal;
    (void)sigemptyset(&action.sa_mask);
    g_cli_only_ui_stop = 0;
    (void)sigaction(SIGINT, &action, &old_int);
    (void)sigaction(SIGTERM, &action, &old_term);
    action.sa_handler = SIG_IGN;
    (void)sigaction(SIGPIPE, &action, &old_pipe);

    int exit_code = EXIT_SUCCESS;
    cbm_thread_t thread;
    if (!cbm_http_server_schedule_run(server) ||
        cbm_thread_create(&thread, 0, cli_only_ui_http_thread, server) != 0) {
        (void)cbm_http_server_cancel_scheduled_run(server);
        cli_only_ui_error(opts->json, "internal", "could not start the HTTP server thread");
        exit_code = EXIT_FAILURE;
    } else {
        int port = cbm_http_server_port(server);
        if (opts->json) {
            printf("{\"status\":\"listening\",\"url\":\"http://127.0.0.1:%d\"}\n", port);
        } else {
            printf("Graph UI listening on http://127.0.0.1:%d (Ctrl-C to stop)\n", port);
        }
        (void)fflush(stdout);
        while (!g_cli_only_ui_stop) {
            cbm_usleep(CLI_ONLY_UI_POLL_US);
        }
        cbm_http_server_stop(server);
        if (cbm_thread_join(&thread) != 0) {
            exit_code = EXIT_FAILURE;
        }
    }

    /* Refuses while an index job thread is still running; wait it out. */
    while (!cbm_http_server_free(server)) {
        cbm_usleep(CLI_ONLY_UI_FREE_RETRY_US);
    }
    cli_only_ui_mutations_release_all(&mutations);
    cbm_mutex_destroy(&mutations.mutex);

    (void)sigaction(SIGINT, &old_int, NULL);
    (void)sigaction(SIGTERM, &old_term, NULL);
    (void)sigaction(SIGPIPE, &old_pipe, NULL);
    return exit_code;
}

#endif /* CBM_FORK_CLI_ONLY_UI */

int cbm_cli_only_ui_main(int argc, char **argv, cbm_project_lock_manager_t *project_locks) {
    cli_only_ui_opts_t opts;
    const char *bad = cli_only_ui_parse(argc, argv, &opts);
    if (opts.help) {
        cli_only_ui_usage(stdout);
        return EXIT_SUCCESS;
    }
    if (bad) {
        cli_only_ui_error(opts.json, "invalid_argument", bad);
        if (!opts.json) {
            cli_only_ui_usage(stderr);
        }
        return CLI_ONLY_UI_EXIT_USAGE;
    }
#ifdef CBM_FORK_CLI_ONLY_UI
    return cli_only_ui_serve(&opts, argv[0], project_locks);
#else
    (void)project_locks;
    cli_only_ui_error(opts.json, "ui_not_built",
                      "built without UI; rebuild with scripts/build.sh --cli-only --with-ui");
    return CLI_ONLY_UI_EXIT_USAGE;
#endif
}
