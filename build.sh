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
    lsb-release file nano git curl python3 python3-pillow \
    imagemagick librsvg2-bin ccache
sudo dpkg --add-architecture i386
sudo apt-get update
sudo apt-get install -y libgcc-s1:i386

# ─── ccache: базовые настройки ────────────────────────────────────────────
export CCACHE_DIR="$HOME/.cache/ccache"
mkdir -p "$CCACHE_DIR"
export CCACHE_BASEDIR="$SCRIPT_DIR"
export CCACHE_NOHASHDIR=1
# include_file_mtime/ctime обязательны: исходники каждый раз свежие после git checkout
# time_macros обязателен: файлы с __DATE__/__TIME__ иначе некэшируемы
export CCACHE_SLOPPINESS="time_macros,include_file_mtime,include_file_ctime,file_stat_matches,pch_defines"

# 6G, а не 9.5G: у GitHub лимит 10 ГБ на весь репозиторий, новая запись должна помещаться
ccache --set-config=max_size=6G
ccache --set-config=compression=true
ccache --set-config=compression_level=1

echo "=== ccache: версия и конфиг ==="
ccache --version | head -1
ccache -p | grep -E 'cache_dir|max_size|compression|sloppiness|base_dir|hash_dir' || true
echo "=== ccache: статистика восстановленного кэша (накопленная) ==="
ccache -s
# Обнуляем счётчики: вся статистика дальше — только за этот прогон
ccache -z

# ─── depot_tools ───────────────────────────────────────────────────────────
git clone --depth 1 https://chromium.googlesource.com/chromium/tools/depot_tools.git
export PATH="$PWD/depot_tools:$PATH"
export DEPOT_TOOLS_UPDATE=0

# ─── Chromium source ───────────────────────────────────────────────────────
mkdir -p chromium/src/out/Default
cd chromium/src
git init -q
git remote add origin "$CHROMIUM_SOURCE"
git fetch --depth 1 "$CHROMIUM_SOURCE" "+refs/tags/$VERSION:chromium_$VERSION"
git checkout "$VERSION"
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

if ! git am --whitespace=nowarn --keep-non-patch "$SCRIPT_DIR"/vanadium/patches/*.patch; then
    echo "::error::Патчи Vanadium не применились — сборка без них бессмысленна"
    git am --show-current-patch=diff | head -40 || true
    exit 1
fi

# ─── gclient sync ─────────────────────────────────────────────────────────
echo "=== STAGE: gclient sync $(date) ==="
gclient sync -D --no-history --nohooks
gclient runhooks
./build/install-build-deps.sh --no-prompt

# ─── ccache: проверка компилятора по ревизии clang ────────────────────────
# Дёшево (в отличие от content — хэша 150 МБ бинарника на каждый вызов)
# и не сбрасывает кэш из-за нового mtime после каждого gclient sync.
CLANG_REV=$(cat third_party/llvm-build/Release+Asserts/cr_build_revision 2>/dev/null || echo "")
if [ -n "$CLANG_REV" ]; then
    export CCACHE_COMPILERCHECK="string:$CLANG_REV"
    echo "clang revision: $CLANG_REV"
else
    export CCACHE_COMPILERCHECK=content
    echo "::warning::cr_build_revision не найден, compiler_check=content"
fi

# ─── GN ───────────────────────────────────────────────────────────────────
echo "=== STAGE: gn gen $(date) ==="
source "$SCRIPT_DIR/patch.sh"
cp "$SCRIPT_DIR/args.gn" out/Default/args.gn
gn gen out/Default
mkdir -p out/tmp out/release

echo "=== проверка: ccache присутствует в тулчейне? ==="
if ! grep -q 'ccache' out/Default/toolchain.ninja; then
    echo "::error::ccache отсутствует в out/Default/toolchain.ninja — cc_wrapper не применился"
    grep -m3 -E 'command = .*clang' out/Default/toolchain.ninja || true
    exit 1
fi
grep -m1 -E 'command = .*ccache' out/Default/toolchain.ninja | cut -c1-200

# ─── ccache: самопроверка на одном файле (1-2 минуты) ─────────────────────
# Компилируем один объект дважды. Ожидание: 2 вызова, 1 промах + 1 попадание.
# Если оба "uncacheable" — ниже будет напечатана точная причина и флаги компилятора.
echo "=== ccache SELF-TEST ==="
export CCACHE_LOGFILE=/tmp/ccache-selftest.log
if ninja -C out/Default obj/base/base/values.o; then
    rm -f out/Default/obj/base/base/values.o
    ninja -C out/Default obj/base/base/values.o
    unset CCACHE_LOGFILE
    ccache -s
    echo "--- результаты вызовов ccache ---"
    grep -h 'Result:' /tmp/ccache-selftest.log | sort | uniq -c || echo "!!! ccache не вызывался вообще"
    echo "--- флаги компилятора (без -D/-I/-W) ---"
    grep -h -m1 'Command line:' /tmp/ccache-selftest.log \
        | tr ' ' '\n' | grep -E '^-' | grep -vE '^-(D|I|isystem|W)' | sort -u | tr '\n' ' ' || true
    echo
else
    unset CCACHE_LOGFILE
    echo "::warning::self-test пропущен: цель obj/base/base/values.o не собралась"
fi
echo "=== end SELF-TEST ==="

# ─── Сборка chrome_public_apk ────────────────────────────────────────────
df -h / | tail -1
free -g | head -2
touch /tmp/compile_started
echo "=== STAGE: compile start $(date) ==="

ninja -C out/Default chrome_public_apk

echo "=== STAGE: compile done $(date) ==="
ccache -s

# ─── Подпись ──────────────────────────────────────────────────────────────
mv $(find out/Default/apks -name 'Chrome*.apk') out/tmp/$VERSION-arm64-v8a.apk
touch out/tmp/$VERSION-armeabi-v7a.apk
touch out/tmp/$VERSION-arm64-v8a.aab

export PATH="$PWD/third_party/jdk/current/bin/:$PATH"
export ANDROID_HOME="$PWD/third_party/android_sdk/public"

sign_apk "out/tmp/$VERSION-arm64-v8a.apk" "out/release/$VERSION-arm64-v8a.apk"
cp "out/tmp/$VERSION-armeabi-v7a.apk" "out/release/$VERSION-armeabi-v7a.apk"
cp "out/tmp/$VERSION-arm64-v8a.aab" "out/release/$VERSION-arm64-v8a.aab"

echo "=== Build finished successfully! $(date) ==="
ccache -s
rm -rf "$SCRIPT_DIR/keys"
