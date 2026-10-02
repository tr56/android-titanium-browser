export SCRIPT_DIR=$(realpath $(dirname "${BASH_SOURCE[0]}"))

replace() {
    export org=$2 new=$3
    find $1 -type f -exec sed -i 's@'$org'@'$new'@g' {} \;
}

set_keys() {
    mkdir -p "$SCRIPT_DIR/keys"
    if [ -n "${LOCAL_TEST_JKS:-}" ] && [ -n "${STORE_TEST_JKS:-}" ]; then
        echo "$LOCAL_TEST_JKS" | base64 -d > "$SCRIPT_DIR/keys/local.properties"
        echo "$STORE_TEST_JKS" | base64 -d > "$SCRIPT_DIR/keys/test.jks"
    fi
    unset LOCAL_TEST_JKS
    unset STORE_TEST_JKS
}

ensure_keystore() {
    if [ ! -s "$SCRIPT_DIR/keys/test.jks" ] || [ ! -s "$SCRIPT_DIR/keys/local.properties" ]; then
        echo "=== Секреты для подписи не заданы: создаём тестовый keystore ==="
        mkdir -p "$SCRIPT_DIR/keys"
        keytool -genkeypair -v \
            -keystore "$SCRIPT_DIR/keys/test.jks" \
            -alias titanium \
            -keyalg RSA \
            -keysize 2048 \
            -validity 10000 \
            -storepass android \
            -keypass android \
            -dname "CN=Titanium, OU=Titanium, O=Titanium, L=Default, ST=Default, C=US"
        cat << 'PROP_EOF' > "$SCRIPT_DIR/keys/local.properties"
storePassword=android
keyPassword=android
keyAlias=titanium
PROP_EOF
    fi
}

sign_apk() {
    export apksigner=$(find "$ANDROID_HOME/build-tools" -name apksigner | sort | tail -n 1)
    ensure_keystore
    source "$SCRIPT_DIR/keys/local.properties"
    "$apksigner" sign -verbose -ks "$SCRIPT_DIR/keys/test.jks" --ks-pass pass:"$storePassword" --key-pass pass:"$keyPassword" --ks-key-alias "$keyAlias" --out "$2" "$1" || exit 1
}

sign_aab() {
    ensure_keystore
    source "$SCRIPT_DIR/keys/local.properties"
    jarsigner -verbose -sigalg SHA256withRSA -digestalg SHA-256 -keystore "$SCRIPT_DIR/keys/test.jks" -storepass "$storePassword" -keypass "$keyPassword" -signedjar "$2" "$1" "$keyAlias" || exit 1
}

version_lt() {
  [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)" = "$1" ]
}
