#!/usr/bin/env bash
# build.sh — Clean build of production binary (standard or with UI).
#
# Usage:
#   scripts/build.sh                              # Standard binary
#   scripts/build.sh --with-ui                    # Binary with the UI embedded
#   scripts/build.sh --cli-only [--with-ui]       # Fork codebase-memory-cli (UI optional)
#   scripts/build.sh --help                       # Full usage
#   scripts/build.sh --version v0.8.0             # With version stamp
#   scripts/build.sh --arch x86_64                # Force x86_64 build
#   scripts/build.sh CC=gcc-14 CXX=g++-14        # Override compiler
#
# This script is the SINGLE source of truth for building release binaries.
# Used identically in local development and CI workflows.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

usage() {
    cat <<'EOF'
Usage: scripts/build.sh [--with-ui | --cli-only [--with-ui]] [--version V] [--arch ARCH] [VAR=VAL ...]

The canonical production-build entry: identical in local CI, PR CI, dry run
and release. Always a CLEAN build of BUILD_DIR (build/c by default) — the
content-verified compiler cache (ccache via scripts/env.sh) makes repeat
builds fast without ever reusing a stale object: every object is re-derived
from current sources; a cache hit is byte-identical to a cold compile by
construction (CCACHE_COMPILERCHECK=content).

Options:
  --with-ui       Build the web UI as a content-addressed sidecar (needs node).
  --cli-only      Fork default: build codebase-memory-cli (make cbm-cli) with
                  CBM_FORK_CLI_ONLY: no daemon runtime, no MCP stdio server,
                  never compiled with test seams. Contains no HTTP code.
                  With --with-ui: make cbm-cli-with-ui, adding the loopback
                  graph UI (`codebase-memory-cli ui`). Needs an existing
                  graph-ui/node_modules; the build itself never fetches.
  --version V     Stamp the version string (release venue passes the tag).
  --arch ARCH     Force target arch (arm64 | x86_64), e.g. under Rosetta.
  -h, --help      This text.

Make passthrough (VAR=VAL, forwarded verbatim):
  CC= CXX=        Compiler override (venues pass their matrix compiler).
  BUILD_DIR=      Build in an isolated directory — REQUIRED when a clean
                  product build must not wipe build/c's test-runner (e.g.
                  build/smoke for the local ladder smoke).
  STATIC=1        Fully static portable build (Alpine/musl leg).
  EXTRA_CFLAGS= EXTRA_LDFLAGS=   Sanitizer soak builds (see _soak.yml).

Environment:
  CBM_NO_CCACHE=1  Disable the compiler cache (build correctness is identical;
                   only speed changes).

Callers: _build.yml (all release artifacts) · pr.yml pr-smoke · every
docker-compose build/smoke service · win.sh build (Windows VM ladder).
EOF
}
for arg in "$@"; do
    case "$arg" in
        -h|--help) usage; exit 0 ;;
    esac
done

# Pre-parse --arch flag before sourcing env.sh
for arg in "$@"; do
    case "$arg" in
        --arch=*) export CBM_ARCH="${arg#--arch=}" ;;
    esac
done
prev_arg=""
for arg in "$@"; do
    if [[ "${prev_arg:-}" == "--arch" ]]; then
        export CBM_ARCH="$arg"
    fi
    prev_arg="$arg"
done

# shellcheck source=env.sh
source "$ROOT/scripts/env.sh"
# shellcheck source=path-safety.sh
source "$ROOT/scripts/path-safety.sh"

# Parse remaining arguments. BUILD_DIR is tracked for the clean step below so
# containerized legs can build in their own directory instead of deleting and
# clobbering the host's native build/c artifacts.
WITH_UI=false
CLI_ONLY=false
VERSION=""
BUILD_DIR="build/c"
EXTRA_MAKE_ARGS=()

prev_arg=""
for arg in "$@"; do
    # Skip --arch and its value (already handled)
    if [[ "${prev_arg:-}" == "--arch" ]]; then
        prev_arg="$arg"
        continue
    fi
    case "$arg" in
        --with-ui)
            WITH_UI=true
            ;;
        --cli-only)
            CLI_ONLY=true
            ;;
        TEST_SEAMS=*)
            # E8: release builds never carry test seams.
            echo "build.sh: TEST_SEAMS is not allowed in release builds." >&2
            exit 2
            ;;
        --version)
            prev_arg="$arg"
            continue
            ;;
        --arch|--arch=*)
            ;; # already handled
        -*)
            # STRICT: an unknown flag never falls through into make where it
            # would fail cryptically (or worse, be absorbed).
            echo "build.sh: unknown option '$arg'. Please consult --help." >&2
            exit 2
            ;;
        BUILD_DIR=*)
            BUILD_DIR="${arg#BUILD_DIR=}"
            EXTRA_MAKE_ARGS+=("$arg")
            ;;
        CC=*|CXX=*)
            export "${arg}"
            EXTRA_MAKE_ARGS+=("$arg")
            ;;
        *=*)
            EXTRA_MAKE_ARGS+=("$arg") # VAR=VAL make passthrough
            ;;
        *)
            # Bare words are only ever the value of --version; anything else is
            # a usage error, not a silent make argument.
            if [[ "${prev_arg:-}" == "--version" ]]; then
                VERSION="$arg"
            else
                echo "build.sh: unexpected argument '$arg'. Please consult --help." >&2
                exit 2
            fi
            ;;
    esac
    prev_arg="$arg"
done

# Version flag
CFLAGS_EXTRA=""
if [[ -n "$VERSION" ]]; then
    CLEAN_VERSION="${VERSION#v}"
    CFLAGS_EXTRA="-DCBM_VERSION=\"\\\"$CLEAN_VERSION\\\"\""
fi

print_env "build.sh"
echo "  ui=$WITH_UI cli_only=$CLI_ONLY version=${VERSION:-dev}"

# Verify compiler supports target arch
verify_compiler "$CC"

# Step 1: Clean C build artifacts only (not node_modules — npm ci handles that)
cbm_remove_build_dir "$ROOT" "$BUILD_DIR"

# Step 2: Build (Makefile applies $ARCHFLAGS for the target arch on macOS)
if $CLI_ONLY; then
    CLI_TARGET=cbm-cli
    $WITH_UI && CLI_TARGET=cbm-cli-with-ui
    make -j"$NPROC" -f Makefile.cbm "$CLI_TARGET" \
        CFLAGS_EXTRA="$CFLAGS_EXTRA" "${EXTRA_MAKE_ARGS[@]+"${EXTRA_MAKE_ARGS[@]}"}"
    echo "=== Build complete: ${BUILD_DIR}/codebase-memory-cli ==="
    exit 0
elif $WITH_UI; then
    make -j"$NPROC" -f Makefile.cbm cbm-with-ui \
        CFLAGS_EXTRA="$CFLAGS_EXTRA" "${EXTRA_MAKE_ARGS[@]+"${EXTRA_MAKE_ARGS[@]}"}"
else
    make -j"$NPROC" -f Makefile.cbm cbm \
        CFLAGS_EXTRA="$CFLAGS_EXTRA" "${EXTRA_MAKE_ARGS[@]+"${EXTRA_MAKE_ARGS[@]}"}"
fi

echo "=== Build complete: ${BUILD_DIR}/codebase-memory-mcp ==="
