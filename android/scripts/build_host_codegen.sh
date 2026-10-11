#!/usr/bin/env bash
# Host (linux-x64) build of the rexglue CLI + WetRecomp codegen.
#
# Reads YOUR default.xex and writes generated/default/*.cpp (repo root) — the
# recompiled source the Android build consumes.
#
# Where the xex comes from (first match wins):
#   1. WET_XEX=/path/to/default.xex
#   2. android/game/default.xex (git-ignored; never commit it, it is game code)
#   3. assets/default.xex at the repo root (already in place)
#
# Inputs:
#   WET_SRC     (default: the repository root)
#   REXSDK_SRC  (default: <repo>/rexglue-sdk)
#   SKIP_CLI_BUILD=1  reuse an existing build/host-codegen
#   FORCE_CODEGEN=1   regenerate even if generated/default exists
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WET_SRC="${WET_SRC:-$(cd "$ROOT/.." && pwd)}"
REXSDK_SRC="${REXSDK_SRC:-$ROOT/rexglue-sdk}"
BUILD_DIR="$ROOT/build/host-codegen"

# Expected build (from WetRecomp's README / xenia game-patches): Title ID
# 425307DB, Media ID 666E3BB8 (USA/Europe disc), module hash 9A084828F85F951B.
EXPECTED_SHA256="${WET_XEX_SHA256:-55160c0ff325e8bca46c879126920ef4e108aeedd1a90d71fc373545b4c5bd9a}"

echo "== [1/3] default.xex =="
XEX_PATH="$WET_SRC/assets/default.xex"
mkdir -p "$WET_SRC/assets"
if [[ -n "${WET_XEX:-}" ]]; then
    cp "$WET_XEX" "$XEX_PATH"
elif [[ -f "$ROOT/game/default.xex" ]]; then
    cp "$ROOT/game/default.xex" "$XEX_PATH"
fi
if [[ ! -f "$XEX_PATH" ]]; then
    echo "ERROR: no default.xex. Put yours at android/game/default.xex or set WET_XEX=/path/to/default.xex." >&2
    exit 1
fi
ACTUAL_SHA256=$(sha256sum "$XEX_PATH" | cut -d' ' -f1)
echo "  sha256: $ACTUAL_SHA256"
if [[ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]]; then
    echo "WARNING: default.xex differs from the verified build. WetRecomp's" >&2
    echo "  function tables target one specific build; codegen may fail." >&2
fi

echo "== [2/3] rexglue CLI (host) =="
HOST_ARCH_FLAGS="-march=x86-64-v2"  # same floor as the SDK's linux-base preset
if [[ "${SKIP_CLI_BUILD:-0}" != "1" || ! -d "$BUILD_DIR" ]]; then
    cmake -S "$REXSDK_SRC" -B "$BUILD_DIR" \
        -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_FLAGS="$HOST_ARCH_FLAGS" \
        -DCMAKE_CXX_FLAGS="$HOST_ARCH_FLAGS" \
        -DREXGLUE_BUILD_TESTS=OFF \
        -DREXGLUE_ENABLE_TRACY=OFF \
        -DREXGLUE_ENABLE_PERF_COUNTERS=OFF
fi
cmake --build "$BUILD_DIR" --target rexglue --parallel "$(nproc)"

echo "== [3/3] Codegen =="
REXGLUE_CLI=$(find "$REXSDK_SRC/out" "$BUILD_DIR" -type f -name rexglue -perm -u+x 2>/dev/null | head -1)
if [[ -z "$REXGLUE_CLI" ]]; then
    echo "ERROR: rexglue binary not found after build" >&2
    exit 1
fi
echo "  CLI: $REXGLUE_CLI"
if [[ -f "$WET_SRC/generated/default/sources.cmake" && "${FORCE_CODEGEN:-0}" != "1" ]]; then
    echo "  codegen output present — skipping (FORCE_CODEGEN=1 to regenerate)"
else
    "$REXGLUE_CLI" codegen "$WET_SRC/wetrecomp_manifest.toml"
fi
ls "$WET_SRC/generated/default/" | head -8
echo "Codegen done."
