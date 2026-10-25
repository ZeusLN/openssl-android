#!/bin/bash
# Builds OpenSSL for Android as a prefab AAR, the form op-sqlite's SQLCipher
# build links against in ZEUS (ZeusLN/zeus#4471).
#
#   ./build.sh            # in the pinned builder image (release builds)
#   ./build.sh --native   # with a local NDK, for testing only
#
# Output: out/openssl-$AAR_VERSION.aar and its sha256. Two builds of the
# same commit in the builder image produce identical files.
set -euo pipefail

OPENSSL_VERSION=3.6.2
# From openssl-3.6.2.tar.gz.sha256, checked against the release signature
# (key BA5473A2B0587B07FB27CF2D216094DFD0CB81EF)
OPENSSL_SHA256=aaf51a1fe064384f811daeaeb4ec4dce7340ec8bd893027eee676af31e83a04f
# Bump the suffix when the recipe changes for the same OpenSSL version
AAR_VERSION=$OPENSSL_VERSION-zeus1
NDK_VERSION=28.0.13004108
API_LEVEL=28
ABIS=${ABIS:-"arm64-v8a armeabi-v7a x86 x86_64"}
# The builder image ZEUS's own build.sh uses; keep the two in step
BUILDER_IMAGE="reactnativecommunity/react-native-android@sha256:d4b8ea0773d62096261cf0ed356004fe2c8292f5e5cdb260d11da953c8c84374"
# 2026-04-07, OpenSSL 3.6.2's release date. Fixes the build date OpenSSL
# records and the AAR's zip timestamps.
export SOURCE_DATE_EPOCH=1775520000

HERE=$(cd "$(dirname "$0")" && pwd)
OUT=$HERE/out

if [ "${1:-}" != "--inside" ] && [ "${1:-}" != "--native" ]; then
    docker run --rm --platform linux/amd64 \
        -e ABIS="$ABIS" \
        -v "$HERE:/zeus-openssl" \
        "$BUILDER_IMAGE" \
        bash /zeus-openssl/build.sh --inside
    exit
fi

if [ "$1" = "--inside" ]; then
    SRC=/zeus-openssl
    WORK=/build
    NDK=${ANDROID_HOME:-/opt/android}/ndk/$NDK_VERSION
    if [ ! -d "$NDK" ]; then
        # The same install the app build's Gradle would do
        # (yes || true): yes dies of SIGPIPE when sdkmanager exits, which
        # pipefail would report as a failure. A failed install is caught by
        # the directory check below.
        { yes || true; } | "${ANDROID_HOME:-/opt/android}"/cmdline-tools/latest/bin/sdkmanager "ndk;$NDK_VERSION" > /dev/null
    fi
else
    SRC=$HERE
    # A fixed path, as in the container: the build directory ends up in
    # debug info
    WORK=/tmp/zeus-openssl-build
    rm -rf "$WORK"
    NDK=${ANDROID_NDK_ROOT:-$HOME/Library/Android/sdk/ndk/$NDK_VERSION}
fi
[ -d "$NDK" ] || { echo "NDK $NDK_VERSION not found at $NDK" >&2; exit 1; }
TOOLCHAIN=$(echo "$NDK"/toolchains/llvm/prebuilt/*/bin)

TARBALL=$SRC/openssl-$OPENSSL_VERSION.tar.gz
if ! echo "$OPENSSL_SHA256  $TARBALL" | sha256sum -c - > /dev/null 2>&1; then
    curl -fsSL -o "$TARBALL" \
        "https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL_VERSION/openssl-$OPENSSL_VERSION.tar.gz"
fi
# Fail closed: an empty or malformed line would make sha256sum -c pass on macOS
echo "$OPENSSL_SHA256" | grep -qE '^[0-9a-f]{64}$'
echo "$OPENSSL_SHA256  $TARBALL" | sha256sum -c -

target_for() {
    case $1 in
        arm64-v8a) echo android-arm64 ;;
        armeabi-v7a) echo android-arm ;;
        x86) echo android-x86 ;;
        x86_64) echo android-x86_64 ;;
        *) echo "unknown ABI $1" >&2; exit 1 ;;
    esac
}

for ABI in $ABIS; do
    BUILD=$WORK/src-$ABI
    PREFIX=$WORK/install/$ABI
    rm -rf "$BUILD" "$PREFIX"
    mkdir -p "$BUILD"
    tar xzf "$TARBALL" -C "$BUILD" --strip-components=1
    (
        cd "$BUILD"
        export ANDROID_NDK_ROOT=$NDK
        export PATH=$TOOLCHAIN:$PATH
        ./Configure "$(target_for "$ABI")" \
            -D__ANDROID_API__=$API_LEVEL \
            --prefix=/zeus-openssl \
            --openssldir=/zeus-openssl/ssl \
            no-sctp no-tests no-docs shared \
            -Wl,-z,max-page-size=16384 \
            -Wl,-z,common-page-size=16384 \
            -fstack-protector-strong \
            -D_FORTIFY_SOURCE=2
        make -j"$(nproc 2>/dev/null || sysctl -n hw.ncpu)" build_libs SHLIB_EXT=.so > /dev/null
        # A fixed prefix, installed through DESTDIR: OpenSSL embeds the
        # prefix in libcrypto (OPENSSLDIR, MODULESDIR), so it must not
        # depend on where the build runs
        make install_dev SHLIB_EXT=.so DESTDIR="$WORK/destdir-$ABI" > /dev/null
        mkdir -p "$WORK/install"
        mv "$WORK/destdir-$ABI/zeus-openssl" "$PREFIX"
        rm -rf "$WORK/destdir-$ABI"
    )
done

mkdir -p "$OUT"
python3 "$SRC/package.py" \
    --work "$WORK" --abis "$ABIS" --version "$OPENSSL_VERSION" \
    --api "$API_LEVEL" --ndk "${NDK_VERSION%%.*}" \
    --license "$WORK/src-${ABIS%% *}/LICENSE.txt" \
    --out "$OUT/openssl-$AAR_VERSION.aar"
cd "$OUT" && sha256sum "openssl-$AAR_VERSION.aar" | tee "openssl-$AAR_VERSION.aar.sha256"
