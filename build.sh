#!/bin/bash
set -eo pipefail

export SCRIPT_DIR=$(realpath "$(dirname "${BASH_SOURCE[0]}")")
source "$SCRIPT_DIR/common.sh"
set_keys

export VERSION=$(grep -m1 -oE '[0-9]+(\.[0-9]+){3}' "$SCRIPT_DIR/vanadium/args.gn")
export CHROMIUM_SOURCE="https://chromium.googlesource.com/chromium/src.git"
export DEBIAN_FRONTEND=noninteractive

echo "=== Target Chromium Version: $VERSION | CPUs: $(nproc) | $(date) ==="

# ─── APT зависимости ───────────────────────────────────────────────────────
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
    lsb-release \
    file \
    nano \
    git \
    curl \
    python3 \
    python3-pillow \
    imagemagick \
    librsvg2-bin \
    ccache

sudo dpkg --add-architecture i386
sudo apt-get update
sudo apt-get install -y libgcc-s1:i386

# ─── ccache ────────────────────────────────────────────────────────────────
export CCACHE_DIR="$HOME/.cache/ccache"
mkdir -p "$CCACHE_DIR"

export CCACHE_BASEDIR="$SCRIPT_DIR"
export CCACHE_NOHASHDIR=1

# use_clang_modules=false задан в args.gn, поэтому "modules" здесь не нужен.
export CCACHE_SLOPPINESS="time_macros,include_file_mtime,include_file_ctime,file_stat_matches,pch_defines"

# Лимит меньше GitHub cache quota 10 GiB.
ccache --set-config=max_size=6G
ccache --set-config=compression=true
ccache --set-config=compression_level=1

echo "=== ccache: version/config ==="
ccache --version | head -1
ccache -p | grep -E 'cache_dir|max_size|compression|sloppiness|base_dir|hash_dir' || true

echo "=== ccache: restored cache stats ==="
ccache -s

# Дальнейшие счётчики будут относиться только к текущему запуску.
ccache -z

# ─── depot_tools ───────────────────────────────────────────────────────────
git clone --depth 1 https://chromium.googlesource.com/chromium/tools/depot_tools.git
export PATH="$PWD/depot_tools:$PATH"

# ─── Chromium source ───────────────────────────────────────────────────────
mkdir -p chromium/src/out/Default
cd chromium/src

git init -q
git remote add origin "$CHROMIUM_SOURCE"
git fetch --depth 1 "$CHROMIUM_SOURCE" "+refs/tags/$VERSION:chromium_$VERSION"
git checkout "$VERSION"

cp "$SCRIPT_DIR/.gclient" ../.gclient

# ─── Патчи Vanadium -> Titanium ────────────────────────────────────────────
rm -rf "$SCRIPT_DIR"/vanadium/patches/trichrome-{apk-build-targets,browser-apk-targets}.patch
rm -rf "$SCRIPT_DIR"/vanadium/patches/{detailed,supported}-language*.patch
rm -rf "$SCRIPT_DIR"/vanadium/patches/javascript-optimizer-{site-setting,settings-UI}.patch
rm -rf "$SCRIPT_DIR"/vanadium/patches/component-updates.patch
rm -rf "$SCRIPT_DIR"/vanadium/patches/{pdf,PDF,for-content-public,toolbar-button,configs-from-config-app,new-tab-card,predictive-back}*.patch
rm -rf "$SCRIPT_DIR"/vanadium/patches/crashpad.patch

# Удаление всех патчей Vanadium, обращающихся к app.vanadium.config и GrapheneOS connectivity checks (устраняет вылет и ошибки git am)
find "$SCRIPT_DIR/vanadium/patches" -type f -name '*config*.patch' ! -name '*cross-origin-referrer*' -delete
find "$SCRIPT_DIR/vanadium/patches" -type f -name '*content-filtering*.patch' -delete
find "$SCRIPT_DIR/vanadium/patches" -type f -name '*connectivity-check*' -delete
rm -f "$SCRIPT_DIR"/vanadium/patches/{0198,0204,0222,0223,0280,0300}*.patch

replace "$SCRIPT_DIR/vanadium/patches" "VANADIUM" "TITANIUM"
replace "$SCRIPT_DIR/vanadium/patches" "Vanadium" "Titanium"
replace "$SCRIPT_DIR/vanadium/patches" "vanadium" "titanium"

if ! git am -3 --whitespace=nowarn --keep-non-patch "$SCRIPT_DIR"/vanadium/patches/*.patch; then
    echo "::error::Патчи Vanadium не применились"
    git am --show-current-patch=diff | head -40 || true
    exit 1
fi

# ─── gclient sync ─────────────────────────────────────────────────────────
echo "=== STAGE: gclient sync $(date) ==="
gclient sync -D --no-history --nohooks
gclient runhooks

./build/install-build-deps.sh --no-prompt

# ─── Проверка версии Clang для ccache ──────────────────────────────────────
CLANG_REV=$(cat third_party/llvm-build/Release+Asserts/cr_build_revision 2>/dev/null || true)

if [ -n "$CLANG_REV" ]; then
    export CCACHE_COMPILERCHECK="string:$CLANG_REV"
    echo "clang revision: $CLANG_REV"
else
    export CCACHE_COMPILERCHECK=content
    echo "::warning::cr_build_revision не найден; используется CCACHE_COMPILERCHECK=content"
fi

# ─── GN ───────────────────────────────────────────────────────────────────
echo "=== STAGE: gn gen $(date) ==="

source "$SCRIPT_DIR/patch.sh"
cp "$SCRIPT_DIR/args.gn" out/Default/args.gn

gn gen out/Default

mkdir -p out/tmp out/release

echo "=== ccache toolchain check ==="
if ! grep -q 'ccache' out/Default/toolchain.ninja; then
    echo "::error::ccache отсутствует в out/Default/toolchain.ninja"
    grep -m3 -E 'command = .*clang' out/Default/toolchain.ninja || true
    exit 1
fi

grep -m1 -E 'command = .*ccache' out/Default/toolchain.ninja | cut -c1-220

# ─── Короткая проверка ccache ──────────────────────────────────────────────
echo "=== ccache SELF-TEST ==="

export CCACHE_LOGFILE=/tmp/ccache-selftest.log
rm -f "$CCACHE_LOGFILE"

if ninja -C out/Default obj/base/base/values.o; then
    rm -f out/Default/obj/base/base/values.o
    ninja -C out/Default obj/base/base/values.o

    unset CCACHE_LOGFILE

    echo "--- self-test statistics ---"
    ccache -s

    echo "--- ccache results ---"
    grep -h 'Result:' /tmp/ccache-selftest.log \
        | sed -E 's/^.*Result: //' \
        | sort \
        | uniq -c \
        | sort -rn \
        || echo "ccache was not called"

else
    unset CCACHE_LOGFILE
    echo "::warning::ccache self-test skipped: values.o failed"
fi

echo "=== end SELF-TEST ==="

# ─── Сборка chrome_public_apk ─────────────────────────────────────────────
echo "=== System before compilation ==="
df -h / | tail -1
free -g | head -2

# Workflow видит этот маркер и сохраняет ccache даже после timeout.
touch /tmp/compile_started

echo "=== STAGE: compile start $(date) ==="
ninja -C out/Default chrome_public_apk
echo "=== STAGE: compile done $(date) ==="

ccache -s

# ─── Подпись реального arm64 APK ──────────────────────────────────────────
APK_INPUT=$(find out/Default/apks -maxdepth 1 -type f -name 'Chrome*.apk' -print -quit)

if [ -z "$APK_INPUT" ]; then
    echo "::error::APK не найден в out/Default/apks"
    find out/Default -type f -name '*.apk' -print || true
    exit 1
fi

UNSIGNED_APK="out/tmp/${VERSION}-arm64-v8a-unsigned.apk"
SIGNED_APK="out/release/${VERSION}-arm64-v8a.apk"

cp "$APK_INPUT" "$UNSIGNED_APK"

export PATH="$PWD/third_party/jdk/current/bin:$PATH"
export ANDROID_HOME="$PWD/third_party/android_sdk/public"

echo "=== Signing APK ==="
echo "Input:  $UNSIGNED_APK"
echo "Output: $SIGNED_APK"

sign_apk "$UNSIGNED_APK" "$SIGNED_APK"

if [ ! -s "$SIGNED_APK" ]; then
    echo "::error::Подписанный APK отсутствует или пустой: $SIGNED_APK"
    ls -lah out/release || true
    exit 1
fi

echo "=== Release artifacts ==="
ls -lh out/release/
sha256sum "$SIGNED_APK"

echo "=== Build finished successfully! $(date) ==="
ccache -s

rm -rf "$SCRIPT_DIR/keys"
