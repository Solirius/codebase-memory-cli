#!/usr/bin/env bash
# fork-merge-rehearsal.sh — fork milestone 06 (A2): rehearse an upstream merge.
#
# 1. If an upstream remote is configured, `git fetch` it (skipped with
#    --no-fetch; no network is needed when the ref is already fetched).
# 2. Create a throwaway git worktree under build/c/ on a new local branch at
#    HEAD and merge the upstream ref into it. Your working tree and branches
#    are never touched.
# 3. Report conflicting files, and flag any that are NOT fork-edge files.
# 4. If the merge is clean, run
#    `make -f Makefile.cbm fork-acceptance` inside the worktree.
# 5. Remove the worktree and the throwaway branch (unless --keep).
# It never pushes and never changes any existing branch.
#
# Usage: scripts/fork-merge-rehearsal.sh [--remote NAME] [--ref REF] [--no-fetch]
#                                        [--no-acceptance] [--keep]
#   --remote NAME     upstream remote (default: upstream)
#   --ref REF         ref to merge (default: <remote>/main)
#   --no-fetch        do not fetch; use the ref as already present locally
#   --no-acceptance   only merge and report conflicts
#   --keep            keep the worktree and branch for inspection
# Exit: 0 clean merge (+ acceptance PASS); 1 conflicts outside the fork edge or
# acceptance FAIL; 3 conflicts only in fork-edge files (resolve by hand); 2 usage.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 2
REMOTE=upstream
REF=""
FETCH=1
ACCEPT=1
KEEP=0
while (($#)); do
  case "$1" in
    --remote) REMOTE=${2:?}; shift ;;
    --ref) REF=${2:?}; shift ;;
    --no-fetch) FETCH=0 ;;
    --no-acceptance) ACCEPT=0 ;;
    --keep) KEEP=1 ;;
    -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done
REF=${REF:-$REMOTE/main}

# Files the fork is allowed to conflict in (A2).
FORK_EDGE_RE='^(src/main\.c|src/cli/cli\.c|src/mcp/mcp\.c|src/mcp/mcp\.h|src/ui/http_server\.c|graph-ui/src/api/.*|Makefile\.cbm|cli-only\.mk|scripts/build\.sh|README\.md|docs/.*|planning/.*|\.github/.*)$'

if git remote | grep -qx "$REMOTE"; then
  if ((FETCH)); then
    echo "==> git fetch $REMOTE"
    git fetch --no-tags "$REMOTE" || { echo "fetch failed; retry with --no-fetch to use the local ref" >&2; exit 2; }
  fi
else
  echo "note: no '$REMOTE' remote configured; using local ref '$REF' as is"
fi
git rev-parse -q --verify "$REF^{commit}" >/dev/null || {
  echo "ref '$REF' not found. Add the remote once:" >&2
  echo "  git remote add upstream https://github.com/DeusData/codebase-memory-mcp.git && git fetch upstream" >&2
  exit 2
}

STAMP="$(date +%Y%m%d%H%M%S)"
BRANCH="rehearsal/upstream-merge-$STAMP"
WT="$ROOT/build/c/merge-rehearsal-$STAMP"
mkdir -p "$ROOT/build/c"
cleanup() {
  ((KEEP)) && { echo "kept: worktree $WT, branch $BRANCH"; return; }
  git worktree remove --force "$WT" >/dev/null 2>&1
  git branch -D "$BRANCH" >/dev/null 2>&1
}
trap cleanup EXIT

echo "==> worktree $WT on $BRANCH (from $(git rev-parse --short HEAD)); merging $REF ($(git rev-parse --short "$REF"))"
git worktree add -q -b "$BRANCH" "$WT" HEAD || exit 2

if git -C "$WT" -c user.name=rehearsal -c user.email=rehearsal@localhost \
     merge --no-edit --no-ff -q "$REF"; then
  echo "merge: clean"
else
  CONFLICTS=()
  while IFS= read -r f; do CONFLICTS+=("$f"); done < <(git -C "$WT" diff --name-only --diff-filter=U)
  if ((${#CONFLICTS[@]} == 0)); then echo "merge failed without conflicts" >&2; exit 1; fi
  echo "merge: ${#CONFLICTS[@]} conflicting file(s):"
  outside=0
  for f in "${CONFLICTS[@]}"; do
    if [[ $f =~ $FORK_EDGE_RE ]]; then echo "  fork-edge  $f"
    else echo "  OUTSIDE    $f"; outside=1; fi
  done
  if ((outside)); then
    echo "A2 FAIL: conflicts outside the fork edge (shared core or upstream-only files)"
    exit 1
  fi
  echo "A2 PASS: conflicts only in fork-edge files. Resolve them by hand (e.g. rerun with --keep)"
  echo "then run 'make -f Makefile.cbm fork-acceptance' in the worktree."
  exit 3
fi

echo "==> shared core vs merged upstream (must be empty):"
git -C "$WT" diff --stat "$REF" -- src/foundation src/store src/cypher src/pipeline internal/cbm

((ACCEPT)) || exit 0
echo "==> make -f Makefile.cbm fork-acceptance (in the worktree)"
# graph-ui/node_modules is not tracked; reuse the main checkout's copy if any.
[[ -d "$ROOT/graph-ui/node_modules" && ! -e "$WT/graph-ui/node_modules" ]] &&
  ln -s "$ROOT/graph-ui/node_modules" "$WT/graph-ui/node_modules"
make -C "$WT" -f Makefile.cbm --no-print-directory fork-acceptance
rc=$?
((rc == 0)) || rc=1  # make exits 2 on failure; 2 is reserved for usage errors
[[ -f "$WT/build/c/fork-acceptance.json" ]] &&
  cp "$WT/build/c/fork-acceptance.json" "$ROOT/build/c/fork-merge-rehearsal-acceptance.json" &&
  echo "acceptance json: build/c/fork-merge-rehearsal-acceptance.json"
exit $rc
