#!/bin/bash
set -eo pipefail

export SCRIPT_DIR=$(realpath "$(dirname "${BASH_SOURCE[0]}")")
source "$SCRIPT_DIR/common.sh"
set_keys

export VERSION=$(grep -m1 -oE '[0-9]+(\.[0-9]+){3}' "$SCRIPT_DIR/vanadium/args.gn")
export CHROMIUM_SOURCE="https://chromium.googlesource.com/chromium/src.git"
export DEBIAN_FRONTEND=noninteractive

echo "=== Target Chromium Version: $VERSION ==="

# ─── APT зависимости ───────────────────────────────────────────────────────
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
    sudo lsb-release file nano git curl python3 python3-pillow \
    imagemagick librsvg2-bin ccache

sudo dpkg --add-architecture i386
sudo apt-get update
sudo apt-get install -y libgcc-s1:i386

# ─── Настройка ccache под Chromium Clang ──────────────────────────────────
export CCACHE_DIR="$HOME/.cache/ccache"
mkdir -p "$CCACHE_DIR"

# Критичные флаги для 95%+ Cacheable и 90%+ Hits:
export CCACHE_BASEDIR="$SCRIPT_DIR"
export CCACHE_NOHASHDIR=1
export CCACHE_COMPILERCHECK=content
export CCACHE_SLOPPINESS="clang_index_store,file_stat_matches,include_file_ctime,include_file_mtime,modules,pch_defines,system_headers,time_macros"

# Быстрое сжатие для экономии CPU времени GitHub Runner
ccache --max-size=9.5G
ccache --set-config=compression=true
ccache --set-config=compression_level=1
ccache --set-config=run_second_cpp=true

echo "=== ccache initial stats ==="
ccache -s

# ─── depot_tools ───────────────────────────────────────────────────────────
if [ ! -d "depot_tools/.git" ]; then
    git clone --depth 1 https://chromium.googlesource.com/chromium/tools/depot_tools.git
else
    echo "depot_tools already exists, updating..."
    git -C depot_tools pull --ff-only || true
fi
export PATH="$PWD/depot_tools:$PATH"

# ─── Chromium source ───────────────────────────────────────────────────────
CHROMIUM_CACHED=false
if [ -d "chromium/src/.git" ]; then
    CACHED_TAG=$(git -C chromium/src describe --tags --exact-match 2>/dev/null || echo "none")
    if [ "$CACHED_TAG" = "$VERSION" ]; then
        echo "✅ Chromium $VERSION already cached, skipping fetch (~90min saved)"
        CHROMIUM_CACHED=true
    else
        echo "⚠️ Cached version ($CACHED_TAG) != target ($VERSION), fetching new..."
    fi
fi

mkdir -p chromium/src/out/Default
cd chromium/src

if [ "$CHROMIUM_CACHED" = "false" ]; then
    git init
    git remote remove origin 2>/dev/null || true
    git remote add origin "$CHROMIUM_SOURCE"
    git fetch --depth 1 "$CHROMIUM_SOURCE" "+refs/tags/$VERSION:chromium_$VERSION"
    git checkout "$VERSION"
fi

cp "$SCRIPT_DIR/.gclient" ../.gclient

# ─── Патчи Vanadium -> Titanium ──────────────────────────────────────────
rm -rf "$SCRIPT_DIR"/vanadium/patches/trichrome-{apk-build-targets,browser-apk-targets}.patch
rm -rf "$SCRIPT_DIR"/vanadium/patches/{detailed,supported}-language*.patch
rm -rf "$SCRIPT_DIR"/vanadium/patches/javascript-optimizer-{site-setting,settings-UI}.patch
rm -rf "$SCRIPT_DIR"/vanadium/patches/component-updates.patch
rm -rf "$SCRIPT_DIR"/vanadium/patches/{pdf,PDF,for-content-public,toolbar-button,configs-from-config-app,new-tab-card,predictive-back}*.patch
rm -rf "$SCRIPT_DIR"/vanadium/patches/crashpad.patch

replace "$SCRIPT_DIR/vanadium/patches" "VANADIUM" "TITANIUM"
replace "$SCRIPT_DIR/vanadium/patches" "Vanadium" "Titanium"
replace "$SCRIPT_DIR/vanadium/patches" "vanadium" "titanium"

git am --whitespace=nowarn --keep-non-patch "$SCRIPT_DIR"/vanadium/patches/*.patch || {
    echo "Patching failed or already applied, resetting state..."
    git am --abort 2>/dev/null || true
}

# ─── gclient sync ─────────────────────────────────────────────────────────
if [ ! -d "third_party/llvm-build/Release+Asserts/bin" ]; then
    echo "Running gclient sync (cold start)..."
    gclient sync -D --no-history --nohooks
    gclient runhooks
else
    echo "✅ third_party toolchain cached, running only runhooks..."
    gclient runhooks
fi

./build/install-build-deps.sh --no-prompt

# ─── GN + Генерация ───────────────────────────────────────────────────────
source "$SCRIPT_DIR/patch.sh"
cp "$SCRIPT_DIR/args.gn" out/Default/args.gn
gn gen out/Default

mkdir -p out/tmp out/release

echo "=== ccache stats before compile ==="
ccache -s

# ─── Сборка chrome_public_apk ────────────────────────────────────────────
autoninja -C out/Default chrome_public_apk

echo "=== ccache stats after compile ==="
ccache -s

# ─── Сборка и подпись APK ────────────────────────────────────────────────
mv $(find out/Default/apks -name 'Chrome*.apk') out/tmp/$VERSION-arm64-v8a.apk
touch out/tmp/$VERSION-armeabi-v7a.apk
touch out/tmp/$VERSION-arm64-v8a.aab

export PATH="$PWD/third_party/jdk/current/bin/:$PATH"
export ANDROID_HOME="$PWD/third_party/android_sdk/public"

sign_apk "out/tmp/$VERSION-arm64-v8a.apk" "out/release/$VERSION-arm64-v8a.apk"
cp "out/tmp/$VERSION-armeabi-v7a.apk" "out/release/$VERSION-armeabi-v7a.apk"
cp "out/tmp/$VERSION-arm64-v8a.aab" "out/release/$VERSION-arm64-v8a.aab"

echo "=== Build finished successfully! ==="
ccache -s
rm -rf "$SCRIPT_DIR/keys"
