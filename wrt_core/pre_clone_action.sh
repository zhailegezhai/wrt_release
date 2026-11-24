#!/usr/bin/env bash

# Determine wrt_core path
if [ -d "wrt_core" ]; then
    WRT_CORE_PATH="wrt_core"
elif [ -d "../wrt_core" ]; then
    WRT_CORE_PATH="../wrt_core"
else
    # Fallback to script directory if wrt_core is current dir or relative
    WRT_CORE_PATH=$(dirname "$0")
fi

BASE_PATH=$(cd "$WRT_CORE_PATH" && pwd)

source "$BASE_PATH/modules/network.sh"

Dev=$1

INI_FILE="$BASE_PATH/compilecfg/$Dev.ini"

if [[ ! -f $INI_FILE ]]; then
    echo "INI file not found: $INI_FILE"
    exit 1
fi

read_ini_by_key() {
    local key=$1
    awk -F"=" -v key="$key" '$1 == key {print $2}' "$INI_FILE"
}

REPO_URL=$(read_ini_by_key "REPO_URL")
REPO_BRANCH=$(read_ini_by_key "REPO_BRANCH")
REPO_BRANCH=${REPO_BRANCH:-main}
COMMIT_HASH=$(read_ini_by_key "COMMIT_HASH")
COMMIT_HASH=${COMMIT_HASH:-none}
# GitHub Actions usually runs in root of repo, so build dir should be relative to repo root
# We need to construct absolute path or ensure context is correct.
# Assuming this script is run from repo root or wrt_core.
# Let's use relative path "action_build" next to wrt_core if possible or just use what works.
# Original script used BASE_PATH/action_build.
BUILD_DIR="$BASE_PATH/../action_build"

echo $REPO_URL $REPO_BRANCH
git_retry clone --depth 1 -b "$REPO_BRANCH" "$REPO_URL" "$BUILD_DIR"

# Cache identity includes the actual upstream commit so incompatible host/toolchain
# caches are not treated as an exact hit after the source branch advances.
SOURCE_HASH=$(git -C "$BUILD_DIR" rev-parse HEAD)
if [[ $COMMIT_HASH != "none" ]]; then
    SOURCE_HASH=$COMMIT_HASH
fi
echo "$REPO_URL/$REPO_BRANCH/$SOURCE_HASH" >"$BASE_PATH/../repo_flag"

# GitHub Action 移除国内下载源
PROJECT_MIRRORS_FILE="$BUILD_DIR/scripts/projectsmirrors.json"

if [ -f "$PROJECT_MIRRORS_FILE" ]; then
    sed -i '/.cn\//d; /tencent/d; /aliyun/d' "$PROJECT_MIRRORS_FILE"
fi

# ---- Generic DTS/device injection hook (per-model) ----
# If wrt_core/dts_inject/<model>/ exists, copy DTS/DTSI into the kernel dts dir
# and append device definition snippets to the target image makefile.
# This is a no-op for all other models (directory absent).
INJECT_DIR="$BASE_PATH/dts_inject/$Dev"
if [[ -d "$INJECT_DIR" ]]; then
    echo "DTS injection: detected $INJECT_DIR"

    # 1) DTS / DTSI files -> target/linux/mediatek/dts/
    DTS_TARGET_DIR="$BUILD_DIR/target/linux/mediatek/dts"
    if [[ -d "$DTS_TARGET_DIR" ]]; then
        for f in "$INJECT_DIR"/*.dts "$INJECT_DIR"/*.dtsi; do
            [[ -f "$f" ]] || continue
            \cp -f "$f" "$DTS_TARGET_DIR/"
            echo "DTS injection: copied $(basename "$f")"
        done
    else
        echo "DTS injection: WARNING dts dir not found: $DTS_TARGET_DIR"
    fi

    # 2) device definition snippets -> append to median image makefile
    # Auto-detect the filogic image makefile used by this source tree.
    IMG_MK=""
    for cand in \
        "$BUILD_DIR/target/linux/mediatek/image/filogic.mk" \
        "$BUILD_DIR/target/linux/mediatek/filogic.mk"; do
        if [[ -f "$cand" ]]; then
            IMG_MK="$cand"
            break
        fi
    done
    if [[ -n "$IMG_MK" ]]; then
        for f in "$INJECT_DIR"/*.mk; do
            [[ -f "$f" ]] || continue
            # skip if already injected (idempotent): use a non-empty marker line
            marker=$(grep -m1 '^define Device/' "$f" || true)
            if [[ -n "$marker" ]] && grep -qF "$marker" "$IMG_MK"; then
                echo "DTS injection: already present, skip $(basename "$f")"
                continue
            fi
            cat "$f" >> "$IMG_MK"
            echo "DTS injection: appended $(basename "$f") -> $IMG_MK"
        done
    else
        echo "DTS injection: WARNING image makefile not found"
    fi
fi
