replace() {
    export org=$2 new=$3
    find $1 -type f -exec sed -i 's@'$org'@'$new'@g' {} \;
}

set_keys() {
    mkdir -p $SCRIPT_DIR/keys
    if [ -n "$LOCAL_TEST_JKS" ] && [ -n "$STORE_TEST_JKS" ]; then
        echo $LOCAL_TEST_JKS | base64 -d > $SCRIPT_DIR/keys/local.properties
        echo $STORE_TEST_JKS | base64 -d > $SCRIPT_DIR/keys/test.jks
    else
        echo "keyAlias=androiddebugkey" > $SCRIPT_DIR/keys/local.properties
        echo "keyPassword=android" >> $SCRIPT_DIR/keys/local.properties
        echo "storePassword=android" >> $SCRIPT_DIR/keys/local.properties
        keytool -genkey -v -keystore $SCRIPT_DIR/keys/test.jks -storepass android -alias androiddebugkey -keypass android -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug,O=Android,C=US"
    fi
    unset LOCAL_TEST_JKS
    unset STORE_TEST_JKS
}

sign_apk() {
    export apksigner=$(find $ANDROID_HOME/build-tools -name apksigner | sort | tail -n 1)
    export zipalign=$(find $ANDROID_HOME/build-tools -name zipalign | sort | tail -n 1)
    source $SCRIPT_DIR/keys/local.properties

    echo "=== Aligning APK (4KB alignment for native .so libraries) ==="
    $zipalign -f -p 4 4096 "$1" "$1.aligned.apk" || exit 1

    echo "=== Signing APK with apksigner ==="
    $apksigner sign -verbose -ks $SCRIPT_DIR/keys/test.jks --ks-pass pass:$storePassword --key-pass pass:$keyPassword --ks-key-alias $keyAlias --out "$2" "$1.aligned.apk" || exit 1

    rm -f "$1.aligned.apk"
}

sign_aab() {
    source $SCRIPT_DIR/keys/local.properties
    jarsigner -verbose -sigalg SHA256withRSA -digestalg SHA-256 -keystore $SCRIPT_DIR/keys/test.jks -storepass $storePassword -keypass $keyPassword -signedjar $2 $1 $keyAlias || exit 1
}

version_lt() {
  [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)" = "$1" ]
}
