#!/usr/bin/env bash
# installer-wizard.sh — guided, project-local setup of codebase-memory-cli for
# GitHub Copilot. Nothing is copied or installed globally.
#
#   scripts/installer-wizard.sh [--project DIR] [--with-ui|--no-ui]
#                               [--path-mode copy|link|vscode|direnv|both|none]
#                               [--rebuild|--skip-build] [--yes] [--dry-run]
#
# The wizard detects sensible defaults, asks only what needs your input, shows
# the full plan for confirmation, then runs it with a proof check per step.
# --yes accepts every default without asking (also used when stdin is not a TTY).
set -euo pipefail

REPO_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
BIN_DIR="$REPO_ROOT/build/c"
BIN="$BIN_DIR/codebase-memory-cli"

PROJECT=""
WITH_UI=""        # 1 / 0 / "" (ask)
PATH_MODE=""      # copy / link / vscode / direnv / both / none / "" (ask)
BUILD=""          # build / keep / "" (ask)
WRITE_COPILOT=1
ASSUME_YES=0
DRY_RUN=0
CHANGES=()

usage() { sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
    case "$1" in
        --project) PROJECT=${2:?--project needs a directory}; shift 2 ;;
        --project=*) PROJECT=${1#*=}; shift ;;
        --with-ui) WITH_UI=1; shift ;;
        --no-ui) WITH_UI=0; shift ;;
        --path-mode) PATH_MODE=${2:?--path-mode needs a value}; shift 2 ;;
        --path-mode=*) PATH_MODE=${1#*=}; shift ;;
        --rebuild) BUILD=build; shift ;;
        --skip-build) BUILD=keep; shift ;;
        -y|--yes) ASSUME_YES=1; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done
case "$PATH_MODE" in ""|copy|link|vscode|direnv|both|none) ;; *) echo "invalid --path-mode: $PATH_MODE" >&2; exit 2 ;; esac
[ -t 0 ] || ASSUME_YES=1

if [ -t 1 ]; then
    B=$'\033[1m'; D=$'\033[2m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; C=$'\033[36m'; N=$'\033[0m'
else
    B=""; D=""; G=""; Y=""; R=""; C=""; N=""
fi

# All interactive output goes to stderr so $(choose …) captures only the answer.
say()   { printf '%s\n' "$*" >&2; }
step()  { printf '\n%s━━ %s ━━%s\n' "$B" "$*" "$N" >&2; }
why()   { printf '   %s%s%s\n' "$D" "$*" "$N" >&2; }
info()  { printf '   %s\n' "$*" >&2; }
ok()    { printf '   %s✅ %s%s\n' "$G" "$*" "$N" >&2; }
warn()  { printf '   %s⚠️  %s%s\n' "$Y" "$*" "$N" >&2; }
die()   { printf '   %s❌ %s%s\n' "$R" "$*" "$N" >&2; exit 1; }

run() {
    printf '   %s$ %s%s\n' "$C" "$*" "$N" >&2
    if [ "$DRY_RUN" -eq 0 ]; then "$@"; fi
}

# confirm "question" y|n — 0 for yes.
confirm() {
    local q=$1 def=$2 ans hint="[y/N]"
    [ "$def" = y ] && hint="[Y/n]"
    if [ "$ASSUME_YES" -eq 1 ]; then info "$q $hint ${D}→ $def (default)${N}"; [ "$def" = y ]; return; fi
    while true; do
        read -r -p "   $q $hint " ans </dev/tty || ans=""
        case "${ans:-$def}" in [Yy]|[Yy][Ee][Ss]) return 0 ;; [Nn]|[Nn][Oo]) return 1 ;; esac
        info "Please answer y or n."
    done
}

# ask "question" default — echoes the answer.
ask() {
    local q=$1 def=$2 ans
    if [ "$ASSUME_YES" -eq 1 ]; then info "$q ${D}→ $def (default)${N}"; printf '%s\n' "$def"; return; fi
    read -r -p "   $q [$def] " ans </dev/tty || ans=""
    printf '%s\n' "${ans:-$def}"
}

# choose "question" default_key key1 "label1" key2 "label2" … — echoes the chosen key.
choose() {
    local q=$1 def=$2; shift 2
    local keys=() labels=() i n defn=1 ans
    while [ $# -gt 0 ]; do keys+=("$1"); labels+=("$2"); shift 2; done
    n=${#keys[@]}
    info "$q"
    for ((i = 0; i < n; i++)); do
        local mark="  "
        if [ "${keys[$i]}" = "$def" ]; then mark="${G}▸${N} "; defn=$((i + 1)); fi
        printf '     %s%d) %s\n' "$mark" "$((i + 1))" "${labels[$i]}" >&2
    done
    if [ "$ASSUME_YES" -eq 1 ]; then info "${D}→ $defn (default)${N}"; printf '%s\n' "$def"; return; fi
    while true; do
        read -r -p "   Choose 1-$n [$defn] " ans </dev/tty || ans=""
        ans=${ans:-$defn}
        if [[ "$ans" =~ ^[0-9]+$ ]] && [ "$ans" -ge 1 ] && [ "$ans" -le "$n" ]; then
            printf '%s\n' "${keys[$((ans - 1))]}"; return
        fi
        info "Please enter a number between 1 and $n."
    done
}

pause() {
    [ "$ASSUME_YES" -eq 1 ] && return
    read -r -p "   Press Enter to continue (Ctrl-C to quit) " _ </dev/tty || true
}

# ════════════════════════════════════════════════════════════════════════════
printf '\n%s🧭 codebase-memory-cli — installer wizard%s\n' "$B" "$N" >&2
info "This wizard sets up codebase-memory-cli for GitHub Copilot in ONE project:"
info "  • builds the binary in this repository (build/c/)"
info "  • puts a copy of the binary in that project (.cbm/, git-ignored) — nothing is installed globally"
info "  • indexes the project and writes the Copilot instruction/prompt files"
info "  • proves that everything works"
info "Press Enter to accept the default shown in [brackets]."
[ "$DRY_RUN" -eq 1 ] && warn "DRY RUN: commands are shown but nothing is executed or written."
pause

# ── 1. Prerequisites ────────────────────────────────────────────────────────
step "Step 1/7 · Checking prerequisites"
why "A C/C++ compiler, make and git are needed to build from source."
missing=0
for tool in cc c++ make git; do
    if command -v "$tool" >/dev/null 2>&1; then ok "$tool"; else warn "$tool not found"; missing=1; fi
done
if [ "$missing" -eq 1 ]; then
    case "$(uname -s)" in
        Darwin) info "Install them with:  xcode-select --install" ;;
        Linux)  info "Install them with:  sudo apt install build-essential zlib1g-dev git" ;;
    esac
    die "Please install the missing tools and run the wizard again."
fi

# ── 2. Questions ────────────────────────────────────────────────────────────
step "Step 2/7 · A few questions"

# Project
why "Which project should Copilot understand? (the folder you open in your IDE)"
default_project=$PWD
[ "$default_project" = "$REPO_ROOT" ] && default_project=""
while true; do
    if [ -z "$PROJECT" ]; then
        if [ -z "$default_project" ] && [ "$ASSUME_YES" -eq 1 ]; then
            die "Run the wizard from your project folder or pass --project DIR."
        fi
        if [ -n "$default_project" ]; then
            PROJECT=$(ask "Project folder:" "$default_project")
        else
            read -r -p "   Project folder (full path): " PROJECT </dev/tty || PROJECT=""
            [ -z "$PROJECT" ] && { warn "Please enter the path to your project."; continue; }
        fi
    fi
    PROJECT=${PROJECT/#\~/$HOME}
    if [ -d "$PROJECT" ]; then
        PROJECT=$(CDPATH='' cd -- "$PROJECT" && pwd)
        break
    fi
    warn "'$PROJECT' is not a folder."
    [ "$ASSUME_YES" -eq 1 ] && exit 1
    PROJECT=""
done
ok "project: $PROJECT"
[ "$PROJECT" = "$REPO_ROOT" ] && warn "That is this tool's own repository — usually you want your app's folder."

# Build
say ""
why "The binary is built once here and shared by your projects via PATH."
if [ -z "$BUILD" ]; then
    if [ -x "$BIN" ]; then
        info "Found an existing build: $("$BIN" --version 2>/dev/null | head -1)"
        BUILD=$(choose "What should I do with it?" keep \
            keep "Use the existing build (fast)" \
            build "Rebuild from the current source")
    else
        info "No build found yet in build/c/."
        BUILD=build
    fi
fi

# UI
ui_ready=0
[ -d "$REPO_ROOT/graph-ui/node_modules" ] && ui_ready=1
if [ "$BUILD" = build ] && [ -z "$WITH_UI" ]; then
    say ""
    why "Optional: a 3D graph viewer on 127.0.0.1 (codebase-memory-cli ui). Not needed for Copilot."
    if [ "$ui_ready" -eq 1 ]; then
        confirm "Include the graph UI?" n && WITH_UI=1 || WITH_UI=0
    else
        info "Skipping the graph UI: graph-ui/node_modules is missing ('cd graph-ui && npm ci' enables it)."
        WITH_UI=0
    fi
fi
WITH_UI=${WITH_UI:-0}
if [ "$WITH_UI" -eq 1 ] && [ "$ui_ready" -eq 0 ]; then
    die "--with-ui needs graph-ui/node_modules: run 'cd graph-ui && npm ci' first."
fi

# How Copilot finds the binary
if [ -z "$PATH_MODE" ]; then
    say ""
    why "Copilot must be able to run the binary from inside this project."
    why "The most reliable way is a binary inside the project that Copilot calls by a fixed relative"
    why "path (./.cbm/codebase-memory-cli), so it never depends on PATH or shell setup."
    PATH_MODE=$(choose "How should Copilot find the binary?" copy \
        copy   "Copy into .cbm/ (recommended — explicit, fixed version, works even if this repo moves)" \
        link   "Symlink in .cbm/ — follows every rebuild of this repo automatically, no extra disk" \
        vscode "VS Code workspace PATH setting (.vscode/settings.json) — VS Code only" \
        direnv "direnv (.envrc) — needs direnv installed and hooked into your shell" \
        both   "VS Code setting and direnv" \
        none   "Skip — I'll handle PATH myself")
fi
case "$PATH_MODE" in copy|link) LOCAL=1 ;; *) LOCAL=0 ;; esac
if [ "$LOCAL" -eq 1 ]; then CMD="./.cbm/codebase-memory-cli"; else CMD="codebase-memory-cli"; fi

# Copilot files
say ""
why "Copilot learns about the CLI from .github/copilot-instructions.md and prompt files."
confirm "Write the Copilot integration files into the project?" y && WRITE_COPILOT=1 || WRITE_COPILOT=0
BOOST=0
if [ "$WRITE_COPILOT" -eq 1 ]; then
    say ""
    why "To make Copilot use the graph reliably, I can also: auto-approve its commands in VS Code,"
    why "write the project name and firm rules into the instructions, add a 'Code Graph' agent and"
    why "AGENTS.md (Copilot CLI / coding agent), and re-index on folder open and after git pulls."
    confirm "Apply these reliability boosters?" y && BOOST=1
fi

# ── 3. Plan ─────────────────────────────────────────────────────────────────
step "Step 3/7 · Review the plan"
label_path() {
    case "$1" in
        copy)   echo "copy the binary to .cbm/codebase-memory-cli (git-ignored); Copilot calls ./.cbm/codebase-memory-cli" ;;
        link)   echo "symlink .cbm/codebase-memory-cli -> build/c binary (git-ignored); Copilot calls ./.cbm/codebase-memory-cli" ;;
        vscode) echo "add build/c to PATH in .vscode/settings.json" ;;
        direnv) echo "add 'PATH_add …/build/c' to .envrc" ;;
        both)   echo ".vscode/settings.json and .envrc" ;;
        none)   echo "skip (you manage PATH)" ;;
    esac
}
if [ "$BUILD" = build ]; then
    plan_build="build with scripts/build.sh --cli-only$([ "$WITH_UI" -eq 1 ] && echo ' --with-ui')"
else
    plan_build="use the existing build/c/codebase-memory-cli"
fi
info "Project ........ $PROJECT"
info "Binary ......... $plan_build"
info "Access ......... $(label_path "$PATH_MODE")"
info "Index .......... index the project into ~/.cache/codebase-memory-mcp/"
info "Copilot files .. $([ "$WRITE_COPILOT" -eq 1 ] && echo 'write .github/copilot-instructions.md + prompts' || echo 'skip')"
[ "$BOOST" -eq 1 ] && info "Boosters ....... auto-approve, project name + rules, Code Graph agent, AGENTS.md, auto re-index"
say ""
confirm "Go ahead with this plan?" y || { info "Nothing was changed. Bye!"; exit 0; }

# ── 4. Build ────────────────────────────────────────────────────────────────
step "Step 4/7 · Building the binary"
if [ "$BUILD" = build ]; then
    why "This can take a few minutes the first time."
    build_args=(--cli-only)
    [ "$WITH_UI" -eq 1 ] && build_args+=(--with-ui)
    (cd "$REPO_ROOT" && run scripts/build.sh "${build_args[@]}")
    [ "$DRY_RUN" -eq 0 ] && CHANGES+=("built $BIN")
else
    info "Using the existing build."
fi
if [ "$DRY_RUN" -eq 0 ]; then
    [ -x "$BIN" ] || die "Binary not found at $BIN"
    ok "binary ready: $BIN"
fi

# ── 5. PATH ─────────────────────────────────────────────────────────────────
step "Step 5/7 · Making it available in the project"
setup_local() {
    local dir="$PROJECT/.cbm" dest="$PROJECT/.cbm/codebase-memory-cli"
    if [ "$PATH_MODE" = copy ]; then
        why "The binary is copied into the project: a fixed, self-contained version you update on purpose."
    else
        why "A symlink inside the project points at the binary built here, so rebuilds apply immediately."
    fi
    if [ "$DRY_RUN" -eq 1 ]; then
        if [ "$PATH_MODE" = copy ]; then info "would copy $BIN -> $dest"; else info "would create $dest -> $BIN"; fi
        info "would add '.cbm/' to $PROJECT/.gitignore"
        return
    fi
    if [ "$PATH_MODE" = copy ]; then
        if [ -f "$dest" ] && [ ! -L "$dest" ] && cmp -s "$BIN" "$dest"; then
            ok ".cbm/codebase-memory-cli is already the latest build"
        else
            if [ -L "$dest" ]; then
                info "Found a symlink at .cbm/codebase-memory-cli; it will be replaced by a copy."
            elif [ -f "$dest" ]; then
                info "The copy in .cbm/ differs from the latest build in $BIN_DIR."
                confirm "Replace it with the latest build?" y || { warn "Kept the existing copy."; return 0; }
            fi
            mkdir -p "$dir"
            rm -f "$dest"
            cp "$BIN" "$dest.tmp" && chmod 755 "$dest.tmp" && mv "$dest.tmp" "$dest"
            {
                echo "source: $BIN"
                echo "copied: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
                echo "sha256: $(shasum -a 256 "$dest" 2>/dev/null | cut -d' ' -f1)"
                echo "update: re-run $REPO_ROOT/scripts/installer-wizard.sh after rebuilding"
            } > "$dir/SOURCE"
            ok "copied the binary to .cbm/codebase-memory-cli ($(du -h "$dest" | cut -f1 | tr -d ' '); provenance in .cbm/SOURCE)"
            CHANGES+=("binary copy $dest (undo: rm -r \"$dir\")")
        fi
    else
        if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$BIN" ]; then
            ok ".cbm/codebase-memory-cli already links to $BIN"
        else
            if [ -f "$dest" ] && [ ! -L "$dest" ]; then
                confirm "Replace the copied binary in .cbm/ with a symlink?" y || { warn "Kept the existing copy."; return 0; }
            fi
            mkdir -p "$dir"
            rm -f "$dir/SOURCE"
            ln -sfn "$BIN" "$dest"
            ok "linked .cbm/codebase-memory-cli -> $BIN"
            CHANGES+=("symlink $dest (undo: rm -r \"$dir\")")
        fi
    fi
    "$dest" --version >/dev/null 2>&1 || die "it does not run: $dest"
    ok "it runs: ./.cbm/codebase-memory-cli --version"
    local gi="$PROJECT/.gitignore"
    if [ -f "$gi" ] && grep -qxE '/?\.cbm/?' "$gi"; then
        ok ".cbm/ is already git-ignored"
    else
        printf '%s\n' '.cbm/' >> "$gi"
        ok "added '.cbm/' to .gitignore (the binary is machine-specific and large)"
        CHANGES+=("'.cbm/' line in $gi")
    fi
}
vscode_snippet() {
    info "  \"terminal.integrated.env.osx\":   { \"PATH\": \"$BIN_DIR:\${env:PATH}\" },"
    info "  \"terminal.integrated.env.linux\": { \"PATH\": \"$BIN_DIR:\${env:PATH}\" }"
}
setup_vscode() {
    local f="$PROJECT/.vscode/settings.json"
    why "VS Code applies this to its integrated terminal, which Copilot's agent uses."
    if [ "$DRY_RUN" -eq 1 ]; then info "would update $f"; return; fi
    if ! command -v python3 >/dev/null 2>&1; then
        warn "python3 not found, so I can't edit $f safely. Please add:"; vscode_snippet; return
    fi
    mkdir -p "$PROJECT/.vscode"
    if python3 - "$f" "$BIN_DIR:\${env:PATH}" <<'PY'
import json, os, sys
path, entry = sys.argv[1], sys.argv[2]
data = {}
if os.path.exists(path):
    text = open(path).read()
    if text.strip():
        try:
            data = json.loads(text)
        except ValueError:
            sys.exit(3)  # JSONC (comments/trailing commas): never rewrite it
for key in ("terminal.integrated.env.osx", "terminal.integrated.env.linux"):
    data.setdefault(key, {})["PATH"] = entry
with open(path, "w") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
PY
    then
        ok "updated .vscode/settings.json"
        CHANGES+=("PATH entry in $f")
        info "This path is specific to your machine — avoid committing it in shared projects."
    else
        warn "$f contains comments, so I left it untouched. Please add:"; vscode_snippet
    fi
}
setup_direnv() {
    local f="$PROJECT/.envrc" line="PATH_add \"$BIN_DIR\""
    why "direnv adds build/c to PATH whenever you cd into the project, and removes it when you leave."
    if [ -f "$f" ] && grep -qxF "$line" "$f"; then
        ok ".envrc already set up"
    elif [ "$DRY_RUN" -eq 1 ]; then
        info "would append to $f: $line"
    else
        printf '%s\n' "$line" >> "$f"
        ok "added to .envrc: $line"
        CHANGES+=("PATH_add line in $f")
    fi
    if command -v direnv >/dev/null 2>&1; then
        (cd "$PROJECT" && run direnv allow) && ok "direnv allowed"
    else
        warn "direnv is not installed. Install it (macOS: brew install direnv), hook it into your"
        info "shell (https://direnv.net/docs/hook.html), then run 'direnv allow' in the project."
    fi
}
case "$PATH_MODE" in
    copy|link) setup_local ;;
    vscode) setup_vscode ;;
    direnv) setup_direnv ;;
    both)   setup_vscode; setup_direnv ;;
    none)   info "Skipped. Make sure 'codebase-memory-cli' resolves to $BIN inside the project." ;;
esac

# ── 6. Index + Copilot files ────────────────────────────────────────────────
step "Step 6/7 · Indexing the project and connecting Copilot"
why "Indexing builds the code graph Copilot will query. Re-run it after big changes."
project_name=""
if [ "$DRY_RUN" -eq 1 ]; then
    run "$BIN" cli --quiet index_repository --repo-path "$PROJECT"
else
    printf '   %s$ codebase-memory-cli cli --quiet index_repository --repo-path "%s"%s\n' "$C" "$PROJECT" "$N" >&2
    out=$("$BIN" cli --quiet index_repository --repo-path "$PROJECT") || die "Indexing failed (see the error above)."
    status=$(printf '%s' "$out" | sed -n 's/.*"status":"\([a-z_]*\)".*/\1/p' | tail -1)
    nodes=$(printf '%s' "$out" | sed -n 's/.*"nodes":\([0-9]*\).*/\1/p' | head -1)
    edges=$(printf '%s' "$out" | sed -n 's/.*"edges":\([0-9]*\).*/\1/p' | head -1)
    project_name=$(printf '%s' "$out" | sed -n 's/^{"project":"\([^"]*\)".*/\1/p')
    [ "$status" = indexed ] || die "Unexpected index status '$status': $out"
    ok "indexed $nodes nodes and $edges edges (project name: $project_name)"
    CHANGES+=("index for $PROJECT in ~/.cache/codebase-memory-mcp/")
fi

# Tune the generated files so Copilot gets complete answers: trace_path excludes
# tests by default, and references to classes/types are mostly USAGE edges, not CALLS.
tune_copilot_files() {
    local f n=0 ci="$PROJECT/.github/copilot-instructions.md" t="$PROJECT/.vscode/tasks.json"
    for f in "$ci" "$PROJECT"/.github/prompts/cbm-*.prompt.md; do
        [ -f "$f" ] || continue
        sed -i.bak -e '/trace_path/{/--include-tests/!s/--direction inbound/--direction inbound --include-tests true/;}' "$f" && rm -f "$f.bak"
        n=$((n + 1))
    done
    local wc="$PROJECT/.github/prompts/cbm-who-calls.prompt.md"
    if [ -f "$wc" ] && ! grep -q 'cbm-wizard:tuning' "$wc"; then
        cat >> "$wc" <<EOF
<!-- cbm-wizard:tuning -->
If the symbol is a class, record, interface or other type, also run
\`$CMD cli trace_path '{"project":"<name>","function_name":"<symbol>","direction":"inbound","depth":1,"include_tests":true,"edge_types":["CALLS","USAGE"]}'\`
because most references to types (constructors, generic arguments, parameter types) are USAGE edges.
Always list test callers separately (\`test: true\`).
EOF
    fi
    if [ -f "$ci" ] && ! grep -q 'cbm-wizard:tuning' "$ci"; then
        local block
        block=$(cat <<EOF
<!-- cbm-wizard:tuning -->
### Getting complete results (tests and type references)

- **Always pass \`--include-tests true\` to \`trace_path\`.** Test callers are excluded by default.
- **Classes, records, interfaces and other types:** most references are \`USAGE\` edges
  (\`new X(...)\`, generic arguments, parameter and return types), not \`CALLS\`. Pass the
  edge types as raw JSON (the \`--edge-types\` flag form is unreliable):
  \`$CMD cli trace_path '{"project":"<name>","function_name":"X","direction":"inbound","depth":1,"include_tests":true,"edge_types":["CALLS","USAGE"]}'\`
- **Cross-check with Cypher** when results look incomplete:
  \`$CMD cli query_graph --project <name> --query "MATCH (a)-[r:CALLS|USAGE]->(b) WHERE b.name = 'X' RETURN type(r), a.name, a.file_path" --format json\`
- Fall back to text search only if the graph returns nothing, and say that you did.
EOF
)
        python3 - "$ci" "$block" <<'PY2'
import sys
p, block = sys.argv[1], sys.argv[2]
s = open(p).read()
end = "<!-- codebase-memory-cli:end -->"
s = s.replace(end, block + "\n" + end, 1) if end in s else s + "\n" + block + "\n"
open(p, "w").write(s)
PY2
    fi
    if [ -f "$t" ] && grep -q 'codebase-memory-cli:managed' "$t" && ! grep -q '"--include-tests"' "$t"; then
        sed -i.bak -e 's/"--direction", "inbound",/"--direction", "inbound", "--include-tests", "true",/' "$t" && rm -f "$t.bak"
        n=$((n + 1))
    fi
    ok "tuned $n files: test callers included, class/type references (USAGE) covered"
}

# Reliability boosters: remove every reason for Copilot not to call the CLI.
boost_copilot() {
    local ci="$PROJECT/.github/copilot-instructions.md" f
    local task_cmd="codebase-memory-cli" approve='/^codebase-memory-cli cli /'
    if [ "$LOCAL" -eq 1 ]; then
        task_cmd='${workspaceFolder}/.cbm/codebase-memory-cli'
        approve='/^\.\/\.cbm\/codebase-memory-cli cli /'
    fi

    # 5. Concrete project name, so Copilot can skip the list_projects step.
    if [ -n "$project_name" ]; then
        for f in "$ci" "$PROJECT"/.github/prompts/cbm-*.prompt.md; do
            [ -f "$f" ] || continue
            sed -i.bak -e "s#--project <name>#--project $project_name#g" \
                -e "s#\"project\":\"<name>\"#\"project\":\"$project_name\"#g" "$f" && rm -f "$f.bak"
        done
        ok "wrote the project name into the instructions and prompts"
    fi

    # 6. Firm, trigger-based rules at the top of the managed section.
    if [ -f "$ci" ] && ! grep -q 'cbm-wizard:rules' "$ci"; then
        python3 - "$ci" "$CMD" "$project_name" <<'PY'
import sys
p, cmd, name = sys.argv[1:4]
s = open(p).read()
rules = f"""<!-- cbm-wizard:rules -->
### Rules (follow these every time)

- **For any question about callers, usages, references, definitions, dependencies, impact or
  architecture, you MUST run `{cmd}` first, before grep or text search,** and quote the command you ran.
- This repository's graph project name is `{name}`. If that name is not listed by
  `{cmd} cli list_projects --format json`, index first:
  `{cmd} cli --quiet index_repository --repo-path "$PWD"`.
- If you have edited code during this session, re-index before answering structural questions.
- Use grep/text search only to confirm or extend graph results, or when the graph returns nothing (say so).
"""
head = "## Code graph: codebase-memory-cli (terminal commands, no server)\n"
s = s.replace(head, head + "\n" + rules, 1) if head in s else s + "\n" + rules
open(p, "w").write(s)
PY
        ok "added firm usage rules to copilot-instructions.md"
    fi

    # 4 + 9a. VS Code: auto-approve the command and allow the folder-open re-index task.
    local vs="$PROJECT/.vscode/settings.json"
    mkdir -p "$PROJECT/.vscode"
    if python3 - "$vs" "$approve" <<'PY'
import json, os, sys
path, pattern = sys.argv[1], sys.argv[2]
data = {}
if os.path.exists(path) and open(path).read().strip():
    try:
        data = json.load(open(path))
    except ValueError:
        sys.exit(3)
data.setdefault("chat.tools.terminal.autoApprove", {})[pattern] = True
data["task.allowAutomaticTasks"] = "on"
with open(path, "w") as fh:
    json.dump(data, fh, indent=2); fh.write("\n")
PY
    then
        ok "VS Code: Copilot may run '$CMD cli …' without asking; folder-open tasks allowed"
        CHANGES+=("auto-approve + task.allowAutomaticTasks in $vs")
    else
        warn "$vs has comments, so I left it untouched. Please add:"
        info "  \"chat.tools.terminal.autoApprove\": { \"$approve\": true },"
        info "  \"task.allowAutomaticTasks\": \"on\""
    fi

    # 9b. Re-index whenever the folder is opened in VS Code.
    local t="$PROJECT/.vscode/tasks.json"
    if [ -f "$t" ] && grep -q 'codebase-memory-cli:managed' "$t" && ! grep -q 'cbm: re-index on folder open' "$t"; then
        python3 - "$t" "$task_cmd" <<'PY'
import sys
p, cmd = sys.argv[1], sys.argv[2]
s = open(p).read()
task = f"""    {{
      "label": "cbm: re-index on folder open",
      "type": "process",
      "command": "{cmd}",
      "args": ["cli", "--quiet", "index_repository", "--repo-path", "${{workspaceFolder}}"],
      "runOptions": {{ "runOn": "folderOpen" }},
      "presentation": {{ "reveal": "never", "panel": "dedicated" }},
      "problemMatcher": []
    }},
"""
anchor = '"tasks": [\n'
if anchor in s:
    s = s.replace(anchor, anchor + task, 1)
    open(p, "w").write(s)
PY
        ok "VS Code re-indexes the project automatically when the folder opens"
    fi

    # 9c. Re-index after pulls, checkouts and commits (background, never blocks git).
    local hooks
    if hooks=$(cd "$PROJECT" && git rev-parse --git-path hooks 2>/dev/null); then
        case "$hooks" in /*) ;; *) hooks="$PROJECT/$hooks" ;; esac
        mkdir -p "$hooks"
        local h hk n=0
        for h in post-merge post-checkout post-commit; do
            hk="$hooks/$h"
            if [ -f "$hk" ] && ! grep -q 'cbm-wizard:hook' "$hk"; then
                warn "kept your existing $h hook; add a re-index line to it yourself if you want"
                continue
            fi
            cat > "$hk" <<EOF
#!/bin/sh
# cbm-wizard:hook — keep the codebase-memory-cli graph fresh (runs in the background).
root=\$(git rev-parse --show-toplevel) || exit 0
bin="\$root/.cbm/codebase-memory-cli"
[ -x "\$bin" ] || bin=\$(command -v codebase-memory-cli) || exit 0
( "\$bin" cli --quiet index_repository --repo-path "\$root" >/dev/null 2>&1 & )
exit 0
EOF
            chmod 755 "$hk"; n=$((n + 1))
        done
        [ "$n" -gt 0 ] && ok "git re-indexes in the background after merge/checkout/commit" &&
            CHANGES+=("git hooks post-merge/post-checkout/post-commit in $hooks (undo: delete files containing cbm-wizard:hook)")
    else
        info "not a git repository: skipped the re-index git hooks"
    fi

    # 7. A dedicated Copilot agent whose whole job is to answer from the graph.
    local ag="$PROJECT/.github/agents/code-graph.agent.md"
    if [ ! -f "$ag" ] || grep -q 'cbm-wizard:managed' "$ag"; then
        mkdir -p "$PROJECT/.github/agents"
        cat > "$ag" <<EOF
---
description: "Answer structural code questions from the codebase-memory-cli graph (callers, usages, architecture, impact)"
---
<!-- cbm-wizard:managed — generated by installer-wizard.sh; delete this line to edit freely -->
You are the Code Graph agent for this repository. Answer every question from the structural
code graph by running \`$CMD\` in the terminal, from the repository root.

1. Project name: \`$project_name\`. If it is missing from \`$CMD cli list_projects --format json\`,
   run \`$CMD cli --quiet index_repository --repo-path "\$PWD"\` first.
2. Callers of a function: \`$CMD cli trace_path --project $project_name --function-name X --direction inbound --include-tests true --format json\`
3. References to a class/type: \`$CMD cli trace_path '{"project":"$project_name","function_name":"X","direction":"inbound","depth":1,"include_tests":true,"edge_types":["CALLS","USAGE"]}'\`
4. Find symbols: \`$CMD cli search_graph --project $project_name --name-pattern 'X' --format json\`;
   source: \`$CMD cli get_code_snippet --project $project_name --qualified-name <qn> --format json\`;
   overview: \`$CMD cli get_architecture --project $project_name --format json\`.
5. Always show the command you ran, list test callers separately, and only use text search to
   confirm graph results or when the graph returns nothing (say so).
EOF
        ok "added the 'Code Graph' Copilot agent (.github/agents/code-graph.agent.md)"
        CHANGES+=("Copilot agent $ag")
    else
        info "kept your own .github/agents/code-graph.agent.md"
    fi

    # 8. AGENTS.md for the Copilot CLI and coding agent (managed section).
    local am="$PROJECT/AGENTS.md"
    local section
    section=$(cat <<EOF
<!-- cbm-wizard:agents:begin -->
## Code graph (codebase-memory-cli)

For questions about callers, usages, definitions, dependencies, impact or architecture, run
\`$CMD\` from the repository root **before** text search, and quote the command.
Project name: \`$project_name\`. Full command reference: \`.github/copilot-instructions.md\`.
Always pass \`--include-tests true\` to \`trace_path\`; for classes/types include \`USAGE\` edges.
<!-- cbm-wizard:agents:end -->
EOF
)
    python3 - "$am" "$section" <<'PY'
import os, re, sys
p, sec = sys.argv[1], sys.argv[2]
s = open(p).read() if os.path.exists(p) else ""
pat = re.compile(r"<!-- cbm-wizard:agents:begin -->.*?<!-- cbm-wizard:agents:end -->", re.S)
s = pat.sub(lambda m: sec, s) if pat.search(s) else (s.rstrip() + "\n\n" if s.strip() else "") + sec + "\n"
open(p, "w").write(s)
PY
    ok "AGENTS.md tells the Copilot CLI / coding agent to use the graph"
    CHANGES+=("managed section in $am")
}

# Make every generated command call the project-local binary instead of relying on PATH.
point_copilot_at_link() {
    local f n=0
    for f in "$PROJECT"/.github/copilot-instructions.md "$PROJECT"/.github/prompts/cbm-*.prompt.md; do
        [ -f "$f" ] || continue
        sed -i.bak -e 's#`codebase-memory-cli cli#`./.cbm/codebase-memory-cli cli#g' "$f" && rm -f "$f.bak"
        n=$((n + 1))
    done
    local ci="$PROJECT/.github/copilot-instructions.md"
    if [ -f "$ci" ] && ! grep -q 'Always run the binary as' "$ci"; then
        sed -i.bak -e '/^## Code graph: codebase-memory-cli/a\
\
**Always run the binary as `./.cbm/codebase-memory-cli` from the repository root** (a\
project-local binary; do not rely on `codebase-memory-cli` being on PATH).' "$ci" && rm -f "$ci.bak"
    fi
    local t="$PROJECT/.vscode/tasks.json"
    if [ -f "$t" ] && grep -q 'codebase-memory-cli:managed' "$t"; then
        sed -i.bak -e 's#"command": "codebase-memory-cli"#"command": "${workspaceFolder}/.cbm/codebase-memory-cli"#g' "$t" && rm -f "$t.bak"
        n=$((n + 1))
    fi
    ok "pointed $n Copilot/VS Code files at ./.cbm/codebase-memory-cli"
}

if [ "$WRITE_COPILOT" -eq 1 ]; then
    say ""
    if [ "$DRY_RUN" -eq 1 ]; then
        run "$BIN" install --project "$PROJECT" --dry-run
    else
        info "These files will be written:"
        "$BIN" install --project "$PROJECT" --dry-run |
            python3 -c 'import json,sys
for f in json.load(sys.stdin)["files"]: print("     • %-45s %s" % (f["path"], f["action"]))' >&2 2>/dev/null ||
            "$BIN" install --project "$PROJECT" --dry-run >&2
        if confirm "Write them now?" y; then
            "$BIN" install --project "$PROJECT" >/dev/null || die "install failed"
            ok "Copilot integration written"
            [ "$LOCAL" -eq 1 ] && point_copilot_at_link
            tune_copilot_files
            [ "$BOOST" -eq 1 ] && boost_copilot
            CHANGES+=("Copilot files in $PROJECT/.github (undo: $CMD uninstall --copilot)")
        else
            warn "Skipped. Run 'codebase-memory-cli install' in the project later."
        fi
    fi
fi

# ── 7. Proof ────────────────────────────────────────────────────────────────
step "Step 7/7 · Proving it works"
if [ "$DRY_RUN" -eq 1 ]; then
    info "Skipped in dry run."
else
    st=$("$BIN" cli --quiet index_status --project "$project_name" --format json) || die "index_status failed"
    if printf '%s' "$st" | grep -q '"status":"ready"'; then ok "graph is ready to query"; else warn "index_status: $st"; fi
    callers=$("$BIN" cli --quiet query_graph --project "$project_name" \
        --query 'MATCH (f)-[:CALLS]->(g) RETURN count(*) AS calls' --format json 2>/dev/null || true)
    calls=$(printf '%s' "$callers" | sed -n 's/.*"rows":\[\["\{0,1\}\([0-9]*\).*/\1/p')
    [ -n "$calls" ] && ok "sample graph query answered: $calls call relationships found"
    tq=$("$BIN" cli --quiet query_graph --project "$project_name" --query \
        "MATCH (a)-[r:CALLS|USAGE]->(b) WHERE a.file_path CONTAINS 'test' OR a.file_path CONTAINS 'Test' OR a.file_path CONTAINS 'spec' RETURN count(r) AS n" \
        --format json 2>/dev/null || true)
    tests=$(printf '%s' "$tq" | sed -n 's/.*"rows":\[\["\{0,1\}\([0-9]*\).*/\1/p')
    if [ -n "$tests" ] && [ "$tests" -gt 0 ]; then
        ok "tests are in the graph: $tests call/usage edges come from test files"
    else
        info "no call/usage edges from test files found (fine if the project has no tests)"
    fi
    if [ -f "$PROJECT/.github/copilot-instructions.md" ] && grep -q 'include-tests true' "$PROJECT/.github/copilot-instructions.md"; then
        ok "Copilot is told to include tests and USAGE references"
    fi
    if [ "$BOOST" -eq 1 ]; then
        grep -q 'chat.tools.terminal.autoApprove' "$PROJECT/.vscode/settings.json" 2>/dev/null &&
            ok "Copilot can run the graph commands without approval prompts"
        [ -f "$PROJECT/.github/agents/code-graph.agent.md" ] && ok "'Code Graph' agent is available in Copilot Chat"
    fi
    if ps -ax -o command= 2>/dev/null | grep -v grep | grep -qF "$BIN"; then
        warn "a codebase-memory-cli process is still running"
    else
        ok "nothing left running in the background (one-shot CLI, no daemon)"
    fi
    if [ -f "$PROJECT/.github/copilot-instructions.md" ] &&
        grep -q 'codebase-memory-cli:begin' "$PROJECT/.github/copilot-instructions.md"; then
        ok "Copilot instructions are in place"
        if [ "$LOCAL" -eq 1 ]; then
            if (cd "$PROJECT" && ./.cbm/codebase-memory-cli cli --quiet list_projects --format json) | grep -qF "\"$project_name\""; then
                ok "the exact command Copilot will run works: ./.cbm/codebase-memory-cli cli list_projects"
            else
                warn "./.cbm/codebase-memory-cli did not list this project"
            fi
            grep -q '`codebase-memory-cli cli' "$PROJECT/.github/copilot-instructions.md" &&
                warn "copilot-instructions.md still has bare 'codebase-memory-cli' commands"
        fi
    fi
fi

# ── Summary ─────────────────────────────────────────────────────────────────
step "🎉 All done"
if [ "${#CHANGES[@]}" -gt 0 ]; then
    info "What changed:"
    for c in "${CHANGES[@]}"; do info "  • $c"; done
    say ""
fi
info "Finish in your IDE:"
info "  1. Open $PROJECT and reload the window (VS Code: 'Developer: Reload Window')."
if [ "$LOCAL" -eq 1 ]; then
    info "  2. In a terminal at the project root, run:  ./.cbm/codebase-memory-cli --version"
else
    info "  2. In a NEW terminal there, run:  command -v codebase-memory-cli"
    info "     It should print: $BIN"
fi
[ "$BOOST" -eq 1 ] && info "     Pick the 'Code Graph' agent in the Copilot Chat agent picker for graph-first answers."
info "  3. In Copilot Chat (Agent mode) ask: \"Who calls <someFunction>? Use codebase-memory-cli.\""
info "     You'll see Copilot run '$CMD cli trace_path …' and answer from its output."
say ""
info "Re-index after big changes:  $CMD cli --quiet index_repository --repo-path \"\$PWD\""
if [ "$LOCAL" -eq 1 ]; then
    [ "$PATH_MODE" = copy ] && info "After rebuilding this repo, re-run the wizard to update the copy in .cbm/."
    info "Teammates: run this wizard once to get their own .cbm/ binary (it is git-ignored)."
    info "Re-run this wizard (not plain 'install') to refresh the Copilot files, so they keep using ./.cbm/."
fi
