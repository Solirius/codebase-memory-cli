/* cli_only_install.c — fork milestone 05: `install` / `uninstall --copilot`.
 *
 * Writes the command-based GitHub Copilot integration into one repository and
 * removes it again. Copilot drives codebase-memory-cli by running terminal
 * commands; nothing here registers a server with any agent or IDE.
 *
 * Ownership rules (what makes install idempotent and uninstall safe):
 *   - copilot-instructions.md: only the text between CBM_BEGIN and CBM_END is
 *     ours. Install replaces it in place or appends it; uninstall cuts it out
 *     and deletes the file only when nothing else is left.
 *   - prompt files and tasks.json: whole files carrying CBM_OWNED. A file of
 *     the same name without the marker belongs to the user and is skipped.
 *   - Paths come from a repository, so symlinked targets are refused (a
 *     checked-in link must not redirect a write) and directories are created
 *     with cbm_mkdir_p (follows only root-owned links). */
#include "cli/cli_only_install.h"

#include "foundation/compat.h"
#include "foundation/compat_fs.h"

#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#include <yyjson/yyjson.h>

enum {
    CBM_CI_PATH_MAX = 4096,
    CBM_CI_MAX_FILE = 4 * 1024 * 1024,
    CBM_CI_EXIT_ERROR = 1,
    CBM_CI_EXIT_USAGE = 2,
};

#define CBM_OWNED "codebase-memory-cli:managed"
#define CBM_BEGIN "<!-- codebase-memory-cli:begin"
#define CBM_END "<!-- codebase-memory-cli:end -->"

static const char kInstructionsSection[] =
    CBM_BEGIN " (managed by `codebase-memory-cli install`; remove with "
              "`codebase-memory-cli uninstall --copilot`) -->\n"
              "## Code graph: codebase-memory-cli (terminal commands, no server)\n"
              "\n"
              "This repository can be queried as a structural code graph with the local\n"
              "`codebase-memory-cli` binary. Run it as a terminal command. There is no server to\n"
              "configure, and it makes no network calls.\n"
              "\n"
              "1. Find the project name: `codebase-memory-cli cli list_projects --format json`\n"
              "2. If this repository is missing or stale, index it:\n"
              "   `codebase-memory-cli cli --quiet index_repository --repo-path \"$PWD\"`\n"
              "3. Query it (add `--format json` for machine-readable output):\n"
              "   - Find symbols: `codebase-memory-cli cli search_graph --project <name> "
              "--name-pattern '<regex>' --format json`\n"
              "   - Who calls X: `codebase-memory-cli cli trace_path --project <name> "
              "--function-name X --direction inbound --format json`\n"
              "   - What X calls: the same with `--direction outbound`\n"
              "   - Source of X: `codebase-memory-cli cli get_code_snippet --project <name> "
              "--qualified-name X --format json`\n"
              "   - Module overview: `codebase-memory-cli cli get_architecture --project <name> "
              "--format json`\n"
              "   - Cypher: `codebase-memory-cli cli query_graph --project <name> --query "
              "'MATCH (f:Function)-[:CALLS]->(g) RETURN f.name, g.name LIMIT 20' --format json`\n"
              "4. Tool errors are printed on stderr as JSON (`{\"error\": \"...\", \"hint\": \"...\"}`)\n"
              "   with exit code 1. Follow the hint (usually: run `list_projects`, or index first).\n"
              "\n"
              "Prefer these commands over text search for structural questions: callers, callees,\n"
              "definitions and architecture. `codebase-memory-cli cli <tool> --help` lists every "
              "flag.\n" CBM_END "\n";

static const char kPromptWhoCalls[] =
    "---\n"
    "description: \"Find the callers of a function with the codebase-memory-cli code graph\"\n"
    "mode: agent\n"
    "---\n"
    "<!-- " CBM_OWNED " (remove with `codebase-memory-cli uninstall --copilot`) -->\n"
    "Find every caller of `${input:symbol:function name}` in this repository by running\n"
    "terminal commands. Do not use a server integration.\n"
    "\n"
    "1. Run `codebase-memory-cli cli list_projects --format json` and pick the project whose\n"
    "   `root_path` is this workspace. If there is none, run\n"
    "   `codebase-memory-cli cli --quiet index_repository --repo-path \"$PWD\"` first.\n"
    "2. Run `codebase-memory-cli cli trace_path --project <name> --function-name "
    "${input:symbol:function name} --direction inbound --depth 2 --format json`.\n"
    "3. Report the callers grouped by file, with line numbers, and quote the command you ran.\n";

static const char kPromptArchitecture[] =
    "---\n"
    "description: \"Summarize this repository's architecture from the codebase-memory-cli "
    "graph\"\n"
    "mode: agent\n"
    "---\n"
    "<!-- " CBM_OWNED " (remove with `codebase-memory-cli uninstall --copilot`) -->\n"
    "Summarize the architecture of this repository by running terminal commands.\n"
    "\n"
    "1. Run `codebase-memory-cli cli list_projects --format json` to find the project name\n"
    "   (index with `codebase-memory-cli cli --quiet index_repository --repo-path \"$PWD\"` "
    "if it is missing).\n"
    "2. Run `codebase-memory-cli cli get_architecture --project <name> --aspects '[\"overview\"]' "
    "--format json`.\n"
    "3. Describe languages, packages, entry points and the main dependencies between them.\n";

static const char kPromptFindSymbol[] =
    "---\n"
    "description: \"Locate a symbol and show its source with the codebase-memory-cli graph\"\n"
    "mode: agent\n"
    "---\n"
    "<!-- " CBM_OWNED " (remove with `codebase-memory-cli uninstall --copilot`) -->\n"
    "Locate `${input:symbol:symbol name}` in this repository by running terminal commands.\n"
    "\n"
    "1. Find the project name with `codebase-memory-cli cli list_projects --format json`.\n"
    "2. Run `codebase-memory-cli cli search_graph --project <name> --name-pattern "
    "'${input:symbol:symbol name}' --format json`.\n"
    "3. For the best match, run `codebase-memory-cli cli get_code_snippet --project <name> "
    "--qualified-name <qualified_name> --format json` and explain what it does.\n";

static const char kTasksJson[] =
    "// " CBM_OWNED ": generated by `codebase-memory-cli install`;\n"
    "// remove with `codebase-memory-cli uninstall --copilot`. Edit freely after deleting "
    "this line.\n"
    "{\n"
    "  \"version\": \"2.0.0\",\n"
    "  \"tasks\": [\n"
    "    {\n"
    "      \"label\": \"cbm: index repository\",\n"
    "      \"type\": \"process\",\n"
    "      \"command\": \"codebase-memory-cli\",\n"
    "      \"args\": [\"cli\", \"--quiet\", \"index_repository\", \"--repo-path\", "
    "\"${workspaceFolder}\"],\n"
    "      \"problemMatcher\": []\n"
    "    },\n"
    "    {\n"
    "      \"label\": \"cbm: list projects\",\n"
    "      \"type\": \"process\",\n"
    "      \"command\": \"codebase-memory-cli\",\n"
    "      \"args\": [\"cli\", \"--quiet\", \"list_projects\", \"--format\", \"json\"],\n"
    "      \"problemMatcher\": []\n"
    "    },\n"
    "    {\n"
    "      \"label\": \"cbm: who calls\",\n"
    "      \"type\": \"process\",\n"
    "      \"command\": \"codebase-memory-cli\",\n"
    "      \"args\": [\"cli\", \"--quiet\", \"trace_path\", \"--project\", \"${input:cbmProject}\",\n"
    "               \"--function-name\", \"${input:cbmSymbol}\", \"--direction\", \"inbound\",\n"
    "               \"--format\", \"json\"],\n"
    "      \"problemMatcher\": []\n"
    "    },\n"
    "    {\n"
    "      \"label\": \"cbm: architecture\",\n"
    "      \"type\": \"process\",\n"
    "      \"command\": \"codebase-memory-cli\",\n"
    "      \"args\": [\"cli\", \"--quiet\", \"get_architecture\", \"--project\", "
    "\"${input:cbmProject}\",\n"
    "               \"--format\", \"json\"],\n"
    "      \"problemMatcher\": []\n"
    "    },\n"
    "    {\n"
    "      \"label\": \"cbm: graph UI (127.0.0.1)\",\n"
    "      \"type\": \"process\",\n"
    "      \"command\": \"codebase-memory-cli\",\n"
    "      \"args\": [\"ui\"],\n"
    "      \"isBackground\": true,\n"
    "      \"problemMatcher\": []\n"
    "    }\n"
    "  ],\n"
    "  \"inputs\": [\n"
    "    {\n"
    "      \"id\": \"cbmProject\",\n"
    "      \"type\": \"promptString\",\n"
    "      \"description\": \"Project name (run the 'cbm: list projects' task)\"\n"
    "    },\n"
    "    {\n"
    "      \"id\": \"cbmSymbol\",\n"
    "      \"type\": \"promptString\",\n"
    "      \"description\": \"Function name\"\n"
    "    }\n"
    "  ]\n"
    "}\n";

typedef struct {
    const char *rel_path;
    const char *content;
} cbm_ci_owned_file_t;

static const cbm_ci_owned_file_t kOwnedFiles[] = {
    {".github/prompts/cbm-who-calls.prompt.md", kPromptWhoCalls},
    {".github/prompts/cbm-architecture.prompt.md", kPromptArchitecture},
    {".github/prompts/cbm-find-symbol.prompt.md", kPromptFindSymbol},
    {".vscode/tasks.json", kTasksJson},
};

static const char kInstructionsRel[] = ".github/copilot-instructions.md";

/* Removed (only if empty) after uninstall, deepest first. */
static const char *const kOwnedDirs[] = {".github/prompts", ".github", ".vscode"};

typedef struct {
    const char *project;
    bool dry_run;
    bool help;
} cbm_ci_opts_t;

typedef struct {
    yyjson_mut_doc *doc;
    yyjson_mut_val *files;
    int errors;
    bool dry_run;
} cbm_ci_report_t;

static void ci_report(cbm_ci_report_t *r, const char *rel, const char *action, const char *reason) {
    yyjson_mut_val *o = yyjson_mut_arr_add_obj(r->doc, r->files);
    if (!o) {
        return;
    }
    yyjson_mut_obj_add_strcpy(r->doc, o, "path", rel);
    yyjson_mut_obj_add_strcpy(r->doc, o, "action", action);
    if (reason) {
        yyjson_mut_obj_add_strcpy(r->doc, o, "reason", reason);
    }
}

static void ci_error(cbm_ci_report_t *r, const char *rel, const char *reason) {
    r->errors++;
    ci_report(r, rel, "error", reason);
}

static void print_json_error(const char *message) {
    yyjson_mut_doc *doc = yyjson_mut_doc_new(NULL);
    if (!doc) {
        (void)fputs("{\"error\":\"out of memory\"}\n", stdout);
        return;
    }
    yyjson_mut_val *root = yyjson_mut_obj(doc);
    yyjson_mut_doc_set_root(doc, root);
    yyjson_mut_obj_add_strcpy(doc, root, "error", message);
    char *json = yyjson_mut_write(doc, 0, NULL);
    if (json) {
        (void)printf("%s\n", json);
        free(json);
    }
    yyjson_mut_doc_free(doc);
}

static void print_usage(bool uninstall) {
    if (uninstall) {
        (void)printf("Usage: codebase-memory-cli uninstall --copilot [--project DIR] "
                     "[--dry-run]\n\n"
                     "Removes the Copilot integration files written by `install` from DIR\n"
                     "(default: current directory). Files without the codebase-memory-cli\n"
                     "marker are never touched.\n");
        return;
    }
    (void)printf("Usage: codebase-memory-cli install [--copilot] [--project DIR] [--dry-run]\n\n"
                 "Writes the command-based GitHub Copilot integration into DIR (default:\n"
                 "current directory):\n"
                 "  .github/copilot-instructions.md   managed section (appended or updated)\n"
                 "  .github/prompts/cbm-*.prompt.md   reusable prompts\n"
                 "  .vscode/tasks.json                only if absent or already generated\n"
                 "Copilot runs codebase-memory-cli as a terminal command; no server is\n"
                 "registered anywhere. Re-running is safe. Undo with `uninstall --copilot`.\n");
}

static int parse_opts(int argc, char **argv, bool uninstall, cbm_ci_opts_t *opts) {
    opts->project = ".";
    opts->dry_run = false;
    opts->help = false;
    for (int i = 0; i < argc; i++) {
        const char *a = argv[i];
        if (!a) {
            continue;
        }
        if (i == 0 && strcmp(a, uninstall ? "uninstall" : "install") == 0) {
            continue;
        }
        if (strcmp(a, "--help") == 0 || strcmp(a, "-h") == 0) {
            opts->help = true;
        } else if (strcmp(a, "--dry-run") == 0) {
            opts->dry_run = true;
        } else if (strcmp(a, "--copilot") == 0 || strcmp(a, "-y") == 0 ||
                   strcmp(a, "--yes") == 0) {
            /* --copilot is the only integration; -y is accepted for habit. */
        } else if (strncmp(a, "--project=", strlen("--project=")) == 0) {
            opts->project = a + strlen("--project=");
            if (!opts->project[0]) {
                print_json_error("--project requires a directory");
                return -1;
            }
        } else if (strcmp(a, "--project") == 0) {
            if (i + 1 >= argc || !argv[i + 1] || !argv[i + 1][0]) {
                print_json_error("--project requires a directory");
                return -1;
            }
            opts->project = argv[++i];
        } else {
            char msg[256];
            (void)snprintf(msg, sizeof(msg), "unknown %s option: %s",
                           uninstall ? "uninstall" : "install", a);
            print_json_error(msg);
            return -1;
        }
    }
    return 0;
}

bool cbm_cli_only_copilot_requested(int argc, char **argv) {
    for (int i = 0; i < argc; i++) {
        if (argv[i] && strcmp(argv[i], "--copilot") == 0) {
            return true;
        }
    }
    return false;
}

static bool join_path(char *out, size_t cap, const char *root, const char *rel) {
    int n = snprintf(out, cap, "%s/%s", root, rel);
    return n > 0 && (size_t)n < cap;
}

/* 0 = read, 1 = absent, -1 = error (including symlink / not a regular file). */
static int read_file(const char *path, char **out, size_t *len) {
    *out = NULL;
    *len = 0;
    struct stat st;
    if (lstat(path, &st) != 0) {
        return errno == ENOENT ? 1 : -1;
    }
    if (!S_ISREG(st.st_mode) || st.st_size > CBM_CI_MAX_FILE) {
        return -1;
    }
    FILE *f = fopen(path, "rb");
    if (!f) {
        return -1;
    }
    size_t cap = (size_t)st.st_size;
    char *buf = malloc(cap + 1);
    if (!buf) {
        (void)fclose(f);
        return -1;
    }
    size_t n = fread(buf, 1, cap, f);
    bool bad = ferror(f) != 0;
    (void)fclose(f);
    if (bad) {
        free(buf);
        return -1;
    }
    buf[n] = '\0';
    *out = buf;
    *len = n;
    return 0;
}

/* The parent must already exist. Writes via a temp file + rename so a crash
 * never leaves a half-written file. */
static int write_file_atomic(const char *path, const char *data, size_t len) {
    char tmp[CBM_CI_PATH_MAX];
    int n = snprintf(tmp, sizeof(tmp), "%s.cbm-tmp.%ld", path, (long)getpid());
    if (n <= 0 || (size_t)n >= sizeof(tmp)) {
        return -1;
    }
    FILE *f = fopen(tmp, "wb");
    if (!f) {
        return -1;
    }
    bool ok = fwrite(data, 1, len, f) == len;
    ok = (fclose(f) == 0) && ok;
    if (!ok || cbm_rename_replace(tmp, path) != 0) {
        (void)cbm_unlink(tmp);
        return -1;
    }
    return 0;
}

static bool ensure_parent_dir(const char *path) {
    char dir[CBM_CI_PATH_MAX];
    int n = snprintf(dir, sizeof(dir), "%s", path);
    if (n <= 0 || (size_t)n >= sizeof(dir)) {
        return false;
    }
    char *slash = strrchr(dir, '/');
    if (!slash) {
        return true;
    }
    *slash = '\0';
    return cbm_mkdir_p(dir, 0755);
}

static bool is_blank(const char *s, size_t len) {
    for (size_t i = 0; i < len; i++) {
        if (s[i] != ' ' && s[i] != '\t' && s[i] != '\n' && s[i] != '\r') {
            return false;
        }
    }
    return true;
}

/* Locates the managed section. Returns 1 if found (sets [*b, *e) including
 * one trailing newline), 0 if absent, -1 if the markers are malformed. */
static int find_section(const char *text, size_t *b, size_t *e) {
    const char *begin = strstr(text, CBM_BEGIN);
    if (!begin) {
        return strstr(text, CBM_END) ? -1 : 0;
    }
    const char *end = strstr(begin, CBM_END);
    if (!end || strstr(end + strlen(CBM_END), CBM_BEGIN)) {
        return -1;
    }
    end += strlen(CBM_END);
    if (*end == '\n') {
        end++;
    }
    *b = (size_t)(begin - text);
    *e = (size_t)(end - text);
    return 1;
}

static char *concat3(const char *a, size_t alen, const char *b, size_t blen, const char *c,
                     size_t clen, size_t *out_len) {
    if (alen > SIZE_MAX - blen - 1 || alen + blen > SIZE_MAX - clen - 1) {
        return NULL;
    }
    size_t total = alen + blen + clen;
    char *out = malloc(total + 1);
    if (!out) {
        return NULL;
    }
    memcpy(out, a, alen);
    memcpy(out + alen, b, blen);
    memcpy(out + alen + blen, c, clen);
    out[total] = '\0';
    *out_len = total;
    return out;
}

static void install_instructions(cbm_ci_report_t *r, const char *root) {
    char path[CBM_CI_PATH_MAX];
    if (!join_path(path, sizeof(path), root, kInstructionsRel)) {
        ci_error(r, kInstructionsRel, "path too long");
        return;
    }
    char *old = NULL;
    size_t old_len = 0;
    int rc = read_file(path, &old, &old_len);
    if (rc < 0) {
        ci_error(r, kInstructionsRel, "not a readable regular file (symlinks are refused)");
        return;
    }
    const size_t sec_len = strlen(kInstructionsSection);
    char *next = NULL;
    size_t next_len = 0;
    const char *action = "created";
    if (rc == 1) {
        next = concat3("", 0, kInstructionsSection, sec_len, "", 0, &next_len);
    } else {
        size_t b = 0;
        size_t e = 0;
        int found = find_section(old, &b, &e);
        if (found < 0) {
            free(old);
            ci_error(r, kInstructionsRel, "malformed codebase-memory-cli markers; fix by hand");
            return;
        }
        if (found == 1) {
            action = "updated";
            next = concat3(old, b, kInstructionsSection, sec_len, old + e, old_len - e, &next_len);
        } else {
            action = "appended";
            const char *sep = "";
            if (old_len > 0) {
                sep = old[old_len - 1] == '\n' ? "\n" : "\n\n";
            }
            size_t head_len = 0;
            char *head = concat3(old, old_len, sep, strlen(sep), "", 0, &head_len);
            if (head) {
                next = concat3(head, head_len, kInstructionsSection, sec_len, "", 0, &next_len);
                free(head);
            }
        }
    }
    if (!next) {
        free(old);
        ci_error(r, kInstructionsRel, "out of memory");
        return;
    }
    if (rc == 0 && next_len == old_len && memcmp(next, old, old_len) == 0) {
        action = "unchanged";
    } else if (!r->dry_run &&
               (!ensure_parent_dir(path) || write_file_atomic(path, next, next_len) != 0)) {
        free(old);
        free(next);
        ci_error(r, kInstructionsRel, "write failed");
        return;
    }
    ci_report(r, kInstructionsRel, action, NULL);
    free(old);
    free(next);
}

static void uninstall_instructions(cbm_ci_report_t *r, const char *root) {
    char path[CBM_CI_PATH_MAX];
    if (!join_path(path, sizeof(path), root, kInstructionsRel)) {
        ci_error(r, kInstructionsRel, "path too long");
        return;
    }
    char *old = NULL;
    size_t old_len = 0;
    int rc = read_file(path, &old, &old_len);
    if (rc == 1) {
        ci_report(r, kInstructionsRel, "absent", NULL);
        return;
    }
    if (rc < 0) {
        ci_error(r, kInstructionsRel, "not a readable regular file (symlinks are refused)");
        return;
    }
    size_t b = 0;
    size_t e = 0;
    int found = find_section(old, &b, &e);
    if (found <= 0) {
        free(old);
        if (found < 0) {
            ci_error(r, kInstructionsRel, "malformed codebase-memory-cli markers; fix by hand");
        } else {
            ci_report(r, kInstructionsRel, "skipped", "no managed section");
        }
        return;
    }
    /* Drop the blank separator line install added before the section. */
    if (b >= 2 && old[b - 1] == '\n' && old[b - 2] == '\n') {
        b--;
    }
    size_t next_len = 0;
    char *next = concat3(old, b, old + e, old_len - e, "", 0, &next_len);
    free(old);
    if (!next) {
        ci_error(r, kInstructionsRel, "out of memory");
        return;
    }
    bool remove_file = is_blank(next, next_len);
    int wrc = 0;
    if (!r->dry_run) {
        wrc = remove_file ? cbm_unlink(path) : write_file_atomic(path, next, next_len);
    }
    free(next);
    if (wrc != 0) {
        ci_error(r, kInstructionsRel, "write failed");
        return;
    }
    ci_report(r, kInstructionsRel, remove_file ? "removed" : "section_removed", NULL);
}

static void install_owned(cbm_ci_report_t *r, const char *root, const cbm_ci_owned_file_t *f) {
    char path[CBM_CI_PATH_MAX];
    if (!join_path(path, sizeof(path), root, f->rel_path)) {
        ci_error(r, f->rel_path, "path too long");
        return;
    }
    char *old = NULL;
    size_t old_len = 0;
    int rc = read_file(path, &old, &old_len);
    if (rc < 0) {
        ci_error(r, f->rel_path, "not a readable regular file (symlinks are refused)");
        return;
    }
    const size_t len = strlen(f->content);
    const char *action = "created";
    if (rc == 0) {
        bool ours = strstr(old, CBM_OWNED) != NULL;
        bool same = old_len == len && memcmp(old, f->content, len) == 0;
        free(old);
        if (!ours) {
            ci_report(r, f->rel_path, "skipped", "exists and is not managed by codebase-memory-cli");
            return;
        }
        if (same) {
            ci_report(r, f->rel_path, "unchanged", NULL);
            return;
        }
        action = "updated";
    }
    if (!r->dry_run &&
        (!ensure_parent_dir(path) || write_file_atomic(path, f->content, len) != 0)) {
        ci_error(r, f->rel_path, "write failed");
        return;
    }
    ci_report(r, f->rel_path, action, NULL);
}

static void uninstall_owned(cbm_ci_report_t *r, const char *root, const cbm_ci_owned_file_t *f) {
    char path[CBM_CI_PATH_MAX];
    if (!join_path(path, sizeof(path), root, f->rel_path)) {
        ci_error(r, f->rel_path, "path too long");
        return;
    }
    char *old = NULL;
    size_t old_len = 0;
    int rc = read_file(path, &old, &old_len);
    if (rc == 1) {
        ci_report(r, f->rel_path, "absent", NULL);
        return;
    }
    if (rc < 0) {
        ci_error(r, f->rel_path, "not a readable regular file (symlinks are refused)");
        return;
    }
    bool ours = strstr(old, CBM_OWNED) != NULL;
    free(old);
    if (!ours) {
        ci_report(r, f->rel_path, "skipped", "not managed by codebase-memory-cli");
        return;
    }
    if (!r->dry_run && cbm_unlink(path) != 0) {
        ci_error(r, f->rel_path, "remove failed");
        return;
    }
    ci_report(r, f->rel_path, "removed", NULL);
}

int cbm_cli_only_copilot_main(int argc, char **argv, bool uninstall) {
    cbm_ci_opts_t opts;
    if (parse_opts(argc, argv, uninstall, &opts) != 0) {
        return CBM_CI_EXIT_USAGE;
    }
    if (opts.help) {
        print_usage(uninstall);
        return 0;
    }
    char root[CBM_CI_PATH_MAX];
    struct stat st;
    if (stat(opts.project, &st) != 0 || !S_ISDIR(st.st_mode) || !realpath(opts.project, root)) {
        print_json_error("--project must be an existing directory");
        return CBM_CI_EXIT_ERROR;
    }

    cbm_ci_report_t r = {.doc = yyjson_mut_doc_new(NULL), .dry_run = opts.dry_run};
    if (!r.doc) {
        print_json_error("out of memory");
        return CBM_CI_EXIT_ERROR;
    }
    yyjson_mut_val *out = yyjson_mut_obj(r.doc);
    yyjson_mut_doc_set_root(r.doc, out);
    r.files = yyjson_mut_arr(r.doc);

    const size_t owned_count = sizeof(kOwnedFiles) / sizeof(kOwnedFiles[0]);
    if (uninstall) {
        uninstall_instructions(&r, root);
        for (size_t i = 0; i < owned_count; i++) {
            uninstall_owned(&r, root, &kOwnedFiles[i]);
        }
        if (!opts.dry_run) {
            for (size_t i = 0; i < sizeof(kOwnedDirs) / sizeof(kOwnedDirs[0]); i++) {
                char dir[CBM_CI_PATH_MAX];
                if (join_path(dir, sizeof(dir), root, kOwnedDirs[i])) {
                    (void)rmdir(dir); /* only succeeds when empty */
                }
            }
        }
    } else {
        install_instructions(&r, root);
        for (size_t i = 0; i < owned_count; i++) {
            install_owned(&r, root, &kOwnedFiles[i]);
        }
    }

    const char *status = uninstall ? "uninstalled" : "installed";
    if (r.errors > 0) {
        status = "error";
    } else if (opts.dry_run) {
        status = "dry_run";
    }
    yyjson_mut_obj_add_str(r.doc, out, "status", status);
    yyjson_mut_obj_add_str(r.doc, out, "integration", "copilot-cli-commands");
    yyjson_mut_obj_add_strcpy(r.doc, out, "project", root);
    yyjson_mut_obj_add_bool(r.doc, out, "dry_run", opts.dry_run);
    yyjson_mut_obj_add_val(r.doc, out, "files", r.files);
    char *json = yyjson_mut_write(r.doc, 0, NULL);
    if (json) {
        (void)printf("%s\n", json);
        free(json);
    }
    yyjson_mut_doc_free(r.doc);
    return r.errors > 0 ? CBM_CI_EXIT_ERROR : 0;
}
