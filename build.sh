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
# https://grapheneos.org/build#browser-and-webview
rm -rf "$SCRIPT_DIR"/vanadium/patches/*trichrome-{apk-build-targets,browser-apk-targets}.patch
rm -rf "$SCRIPT_DIR"/vanadium/patches/*{detailed,supported}-language*.patch
rm -rf "$SCRIPT_DIR"/vanadium/patches/*javascript-optimizer-{site-setting,settings-UI}.patch
rm -rf "$SCRIPT_DIR"/vanadium/patches/*component-updates.patch
rm -rf "$SCRIPT_DIR"/vanadium/patches/*{pdf,PDF,for-content-public,toolbar-button,configs-from-config-app,new-tab-card,predictive-back*}*.patch
# rm -rf "$SCRIPT_DIR"/vanadium/patches/*crashpad*.patch

replace "$SCRIPT_DIR/vanadium/patches" "VANADIUM" "TITANIUM"
replace "$SCRIPT_DIR/vanadium/patches" "Vanadium" "Titanium"
replace "$SCRIPT_DIR/vanadium/patches" "vanadium" "titanium"

# Без -3: replace меняет blob-хеши в заголовках патчей и git am -3 падает
# с "sha1 information is lacking or useless".
if ! git am --whitespace=nowarn --keep-non-patch "$SCRIPT_DIR"/vanadium/patches/*.patch; then
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

# upstream patch.sh рассчитан на запуск БЕЗ set -e: отсутствующая цель sed там
# не роняет сборку. Если это сделать фатальным, любая мелочь убьёт прогон
# через 10 минут. Поэтому: ловим ошибки как предупреждение, но требуем,
# чтобы скрипт дошёл до конца (в конце upstream выставляет PATCHED=1).
set +e
source "$SCRIPT_DIR/patch.sh" > /tmp/patch.log 2>&1
patch_rc=$?
set -e
tail -40 /tmp/patch.log

if [ "$patch_rc" -ne 0 ]; then
    echo "::warning::patch.sh вернул код $patch_rc"
fi

if [ "${PATCHED:-0}" != "1" ]; then
    echo "::error::patch.sh не дошёл до конца (PATCHED != 1) — патчи Titanium применены не полностью"
    exit 1
fi

if grep -q "No such file or directory" /tmp/patch.log; then
    echo "::warning::Часть целей sed не найдена в этой версии Chromium:"
    grep -oE "[^ :]+: No such file or directory" /tmp/patch.log | sort -u | head -20
fi

# Наш патч Минцифры: тут ошибка должна быть фатальной.
source "$SCRIPT_DIR/custom-patch.sh"

if ! grep -q "kRussianTrustedRootCaDer" chrome/browser/net/profile_network_context_service.cc; then
    echo "::error::Корневой сертификат Минцифры не найден в исходнике после custom-patch.sh"
    exit 1
fi
echo "Проверка: корневой сертификат Минцифры в исходнике присутствует"

cp "$SCRIPT_DIR/args.gn" out/Default/args.gn

mkdir -p out/tmp out/release

# Если в этой версии Chromium какой-то аргумент переименовали или удалили,
# gn gen падает с "Assignment had no effect". Убираем такой аргумент и пробуем снова.
gn_gen_retry() {
  local attempt=0
  while :; do
    if gn gen out/Default > /tmp/gn.out 2>/tmp/gn.err; then
      echo "gn gen: OK"
      return 0
    fi

    local unknown
    unknown=$(grep -oE 'You set the variable "[^"]+"' /tmp/gn.err | head -1 | cut -d'"' -f2 || true)

    if [ -z "$unknown" ]; then
      echo "::error::gn gen завершился с ошибкой"
      cat /tmp/gn.err
      return 1
    fi

    attempt=$((attempt + 1))
    if [ "$attempt" -gt 10 ]; then
      echo "::error::Слишком много неизвестных аргументов gn"
      cat /tmp/gn.err
      return 1
    fi

    echo "::warning::Аргумент '$unknown' не поддерживается этой версией Chromium — удаляю из args.gn"
    sed -i "/^[[:space:]]*${unknown}[[:space:]]*=/d" out/Default/args.gn
  done
}

gn_gen_retry

echo "=== ccache toolchain check ==="
TC_FILE=$(find out/Default -maxdepth 1 -name 'toolchain.ninja' -print -quit)

if [ -n "$TC_FILE" ]; then
    if ! grep -q 'ccache' "$TC_FILE"; then
        echo "::error::ccache отсутствует в $TC_FILE"
        grep -m3 -E 'command = .*clang' "$TC_FILE" || true
        exit 1
    fi
    grep -m1 -E 'command = .*ccache' "$TC_FILE" | cut -c1-220
else
    echo "::warning::toolchain.ninja не найден — проверка ccache пропущена"
fi

# ─── Короткая проверка ccache ──────────────────────────────────────────────
echo "=== ccache SELF-TEST ==="

export CCACHE_LOGFILE=/tmp/ccache-selftest.log
rm -f "$CCACHE_LOGFILE"

if timeout 600 ninja -C out/Default obj/base/base/values.o 2>/dev/null; then
    rm -f out/Default/obj/base/base/values.o
    timeout 600 ninja -C out/Default obj/base/base/values.o 2>/dev/null || true

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
    echo "::warning::ccache self-test пропущен: values.o не собрался"
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
