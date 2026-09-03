#!/bin/bash
export SCRIPT_DIR=$(realpath $(dirname "${BASH_SOURCE[0]}"))
source $SCRIPT_DIR/common.sh
set_keys
export VERSION=$(grep -m1 -o '[0-9]\+\(\.[0-9]\+\)\{3\}' $SCRIPT_DIR/vanadium/args.gn)
export CHROMIUM_SOURCE=https://chromium.googlesource.com/chromium/src.git
export DEBIAN_FRONTEND=noninteractive

# ─── APT зависимости ───────────────────────────────────────────────────────
sudo apt-get update
sudo apt-get install -y sudo lsb-release file nano git curl python3 python3-pillow \
  imagemagick librsvg2-bin ccache
sudo dpkg --add-architecture i386
sudo apt-get update
sudo apt-get install -y libgcc-s1:i386

# ─── ccache ────────────────────────────────────────────────────────────────
export CCACHE_DIR=~/.cache/ccache
mkdir -p $CCACHE_DIR

# КРИТИЧНО: include_file_ctime — без него 100% промахи после git checkout
export CCACHE_SLOPPINESS=time_macros,include_file_mtime,include_file_ctime,file_stat_matches,file_macro,pch_defines

# Хэш компилятора по содержимому (clang в third_party имеет непостоянный путь)
export CCACHE_COMPILERCHECK=content

ccache --max-size=9.5G
ccache --set-config=compression=true
ccache --set-config=compression_level=6

echo "=== ccache stats (from cache) ==="
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
# Проверяем: уже скачан нужный тег или нет
CHROMIUM_CACHED=false
if [ -d "chromium/src/.git" ]; then
  CACHED_TAG=$(git -C chromium/src describe --tags --exact-match 2>/dev/null || echo "none")
  if [ "$CACHED_TAG" = "$VERSION" ]; then
    echo "✅ Chromium $VERSION already cached, skipping fetch (~90min saved)"
    CHROMIUM_CACHED=true
  else
    echo "⚠️  Cached version ($CACHED_TAG) != target ($VERSION), fetching new..."
  fi
fi

mkdir -p chromium/src/out/Default
cd chromium/src

if [ "$CHROMIUM_CACHED" = "false" ]; then
  git init
  git remote remove origin 2>/dev/null || true
  git remote add origin $CHROMIUM_SOURCE
  git fetch --depth 1 $CHROMIUM_SOURCE +refs/tags/$VERSION:chromium_$VERSION
  git checkout $VERSION
fi

cp $SCRIPT_DIR/.gclient ../.gclient

# ─── Патчи Vanadium ────────────────────────────────────────────────────────
rm -rf $SCRIPT_DIR/vanadium/patches/*trichrome-{apk-build-targets,browser-apk-targets}.patch
rm -rf $SCRIPT_DIR/vanadium/patches/*{detailed,supported}-language*.patch
rm -rf $SCRIPT_DIR/vanadium/patches/*javascript-optimizer-{site-setting,settings-UI}.patch
rm -rf $SCRIPT_DIR/vanadium/patches/*component-updates.patch
rm -rf $SCRIPT_DIR/vanadium/patches/*{pdf,PDF,for-content-public,toolbar-button,configs-from-config-app,new-tab-card,predictive-back*}*.patch
replace "$SCRIPT_DIR/vanadium/patches" "VANADIUM" "TITANIUM"
replace "$SCRIPT_DIR/vanadium/patches" "Vanadium" "Titanium"
replace "$SCRIPT_DIR/vanadium/patches" "vanadium" "titanium"
git am --whitespace=nowarn --keep-non-patch $SCRIPT_DIR/vanadium/patches/*.patch

# ─── gclient sync ─────────────────────────────────────────────────────────
# Пропускаем sync если llvm-build уже есть (кэширован в workflow)
if [ ! -d "third_party/llvm-build/Release+Asserts/bin" ]; then
  echo "Running gclient sync (cold start)..."
  gclient sync -D --no-history --nohooks
  gclient runhooks
else
  echo "✅ third_party toolchain cached, running only runhooks..."
  gclient runhooks
fi

./build/install-build-deps.sh --no-prompt

# ─── GN + сборка ──────────────────────────────────────────────────────────
source $SCRIPT_DIR/patch.sh
cp $SCRIPT_DIR/args.gn out/Default/args.gn
gn gen out/Default
mkdir -p out/tmp out/release

echo "=== ccache stats before compile ==="
ccache -s

# Сборка 64-битного arm64-v8a APK
autoninja -C out/Default chrome_public_apk

echo "=== ccache stats after compile ==="
ccache -s

mv $(find out/Default/apks -name 'Chrome*.apk') out/tmp/$VERSION-arm64-v8a.apk
touch out/tmp/$VERSION-armeabi-v7a.apk
touch out/tmp/$VERSION-arm64-v8a.aab

export PATH=$PWD/third_party/jdk/current/bin/:$PATH
export ANDROID_HOME=$PWD/third_party/android_sdk/public

sign_apk out/tmp/$VERSION-arm64-v8a.apk out/release/$VERSION-arm64-v8a.apk
cp out/tmp/$VERSION-armeabi-v7a.apk out/release/$VERSION-armeabi-v7a.apk
cp out/tmp/$VERSION-arm64-v8a.aab out/release/$VERSION-arm64-v8a.aab

ccache -s
rm -rf $SCRIPT_DIR/keys
