#!/bin/bash
set -e

IOS_MIN_VERSION="12.0"
OUT_DIR="$(pwd)/build/ios"
OPENSSL_VERSION="${OPENSSL_VERSION:-v3.6.1-1}"

mkdir -p "$OUT_DIR"

echo "Building libcurl for iOS via CMake (Min iOS $IOS_MIN_VERSION) with OpenSSL $OPENSSL_VERSION..."

# Download OpenSSL artifacts if not already present
OPENSSL_ZIP="openssl-ios.zip"
if [ ! -f "$OPENSSL_ZIP" ]; then
    echo "Downloading OpenSSL iOS artifacts from GitHub..."
    curl -L -o "$OPENSSL_ZIP" \
        "https://github.com/XDcobra/openssl-ios-android-prebuilt-and-buildscripts/releases/download/${OPENSSL_VERSION}/openssl-ios.zip"
fi

# Extract OpenSSL artifacts (non-interactive)
echo "Extracting OpenSSL artifacts..."
rm -rf openssl_extracted
mkdir -p openssl_extracted
unzip -oq "$OPENSSL_ZIP" -d openssl_extracted

find_first_existing_file() {
    for candidate in "$@"; do
        if [ -f "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
    done
    return 1
}

OPENSSL_XCFW_ROOT="$(pwd)/openssl_extracted/openssl.xcframework"
if [ ! -d "$OPENSSL_XCFW_ROOT" ]; then
    echo "Error: Missing OpenSSL XCFramework at $OPENSSL_XCFW_ROOT"
    exit 1
fi

# Prepare OpenSSL staging folders per slice expected by FindOpenSSL
prepare_openssl_stage() {
    local slice_name="$1"
    local stage_dir="$2"
    local slice_dir="$OPENSSL_XCFW_ROOT/$slice_name"

    if [ ! -f "$slice_dir/libopenssl.a" ]; then
        echo "Error: Missing $slice_dir/libopenssl.a"
        exit 1
    fi

    if [ ! -d "$slice_dir/Headers" ]; then
        echo "Error: Missing $slice_dir/Headers"
        exit 1
    fi

    rm -rf "$stage_dir"
    mkdir -p "$stage_dir/lib" "$stage_dir/include/openssl"

    cp -R "$slice_dir/Headers/." "$stage_dir/include/openssl/"
    cp "$slice_dir/libopenssl.a" "$stage_dir/lib/libssl.a"
    cp "$slice_dir/libopenssl.a" "$stage_dir/lib/libcrypto.a"
}

prepare_openssl_stage "ios-arm64" "$OUT_DIR/openssl_stage/device"
prepare_openssl_stage "ios-arm64_x86_64-simulator" "$OUT_DIR/openssl_stage/simulator"

# Setup libcurl source code
if [ ! -d "libcurl" ]; then
    echo "Cloning libcurl from GitHub..."
    git clone --depth 1 https://github.com/curl/curl.git libcurl
fi

LIBCURL_SRC="$(pwd)/libcurl"

CURL_LICENSE_FILE="$(find_first_existing_file \
    "$LIBCURL_SRC/COPYING" \
    "$LIBCURL_SRC/LICENSE" \
    "$LIBCURL_SRC/LICENSE.txt")"

if [ -z "$CURL_LICENSE_FILE" ]; then
    echo "Error: Could not locate libcurl license file in source checkout"
    exit 1
fi

OPENSSL_LICENSE_FILE="$(find_first_existing_file \
    "$OPENSSL_XCFW_ROOT/Resources/LICENSES/OPENSSL-LICENSE.txt" \
    "$(pwd)/openssl_extracted/licenses/openssl/OPENSSL-LICENSE.txt" \
    "$(pwd)/openssl_extracted/licenses/openssl/LICENSE.txt" \
    "$(pwd)/openssl_extracted/licenses/OPENSSL-LICENSE.txt")"

build_with_cmake() {
    local variant="$1"
    local platform="$2"   # iphoneos | iphonesimulator
    local arch="$3"       # arm64 | x86_64
    local out_name="$4"

    local build_dir="$LIBCURL_SRC/cmake_${variant}_${out_name}"
    local install_dir="$OUT_DIR/install_${variant}_${out_name}"

    rm -rf "$build_dir" "$install_dir"
    mkdir -p "$build_dir" "$install_dir"

    local sdk_path
    sdk_path="$(xcrun -sdk "$platform" --show-sdk-path)"

    local flags
    flags=""
    flags="$flags -DCMAKE_BUILD_TYPE=Release"
    flags="$flags -DBUILD_SHARED_LIBS=OFF"
    flags="$flags -DBUILD_STATIC_LIBS=ON"
    flags="$flags -DBUILD_CURL_EXE=OFF"
    flags="$flags -DBUILD_TESTING=OFF"
    flags="$flags -DENABLE_MANUAL=OFF"
    flags="$flags -DBUILD_LIBCURL_DOCS=OFF"
    flags="$flags -DCURL_DISABLE_LDAP=ON"
    flags="$flags -DCURL_USE_LIBPSL=OFF"
    flags="$flags -DCMAKE_SYSTEM_NAME=iOS"
    flags="$flags -DCMAKE_OSX_SYSROOT=$sdk_path"
    flags="$flags -DCMAKE_OSX_ARCHITECTURES=$arch"
    flags="$flags -DCMAKE_OSX_DEPLOYMENT_TARGET=$IOS_MIN_VERSION"
    flags="$flags -DCMAKE_INSTALL_PREFIX=$install_dir"

    if [ "$platform" = "iphonesimulator" ]; then
        flags="$flags -DCMAKE_C_FLAGS=-mios-simulator-version-min=$IOS_MIN_VERSION"
        flags="$flags -DCMAKE_CXX_FLAGS=-mios-simulator-version-min=$IOS_MIN_VERSION"
    else
        flags="$flags -DCMAKE_C_FLAGS=-miphoneos-version-min=$IOS_MIN_VERSION"
        flags="$flags -DCMAKE_CXX_FLAGS=-miphoneos-version-min=$IOS_MIN_VERSION"
    fi

    if [ "$variant" = "openssl" ]; then
        local stage_dir
        if [ "$platform" = "iphonesimulator" ]; then
            stage_dir="$OUT_DIR/openssl_stage/simulator"
        else
            stage_dir="$OUT_DIR/openssl_stage/device"
        fi

        flags="$flags -DCURL_USE_OPENSSL=ON"
        flags="$flags -DOPENSSL_ROOT_DIR=$stage_dir"
        flags="$flags -DOPENSSL_INCLUDE_DIR=$stage_dir/include"
        flags="$flags -DOPENSSL_SSL_LIBRARY=$stage_dir/lib/libssl.a"
        flags="$flags -DOPENSSL_CRYPTO_LIBRARY=$stage_dir/lib/libcrypto.a"
        flags="$flags -DOPENSSL_USE_STATIC_LIBS=TRUE"
        flags="$flags -DCURL_USE_SECTRANSP=OFF"
    else
        flags="$flags -DCURL_USE_OPENSSL=OFF"
    fi

    echo "============================================="
    echo "Configuring $variant for $out_name ($platform/$arch)..."
    echo "============================================="

    cmake -S "$LIBCURL_SRC" -B "$build_dir" $flags
    cmake --build "$build_dir" -j"$(sysctl -n hw.ncpu 2>/dev/null || nproc)"
    cmake --install "$build_dir"

    local built_lib
    built_lib="$(find "$build_dir" -name libcurl.a | head -1)"
    if [ -z "$built_lib" ]; then
        echo "Error: libcurl.a not found in $build_dir"
        exit 1
    fi

    local variant_dir="$OUT_DIR/libcurl-$variant"
    mkdir -p "$variant_dir/$out_name"
    cp "$built_lib" "$variant_dir/$out_name/libcurl.a"

    if [ ! -d "$variant_dir/include/curl" ]; then
        mkdir -p "$variant_dir/include"
        cp -R "$LIBCURL_SRC/include/curl" "$variant_dir/include/"
    fi

    echo "✓ Built $variant for $out_name"
}

for VARIANT in "core" "openssl"; do
    echo ""
    echo "=========================================="
    echo "Building libcurl-$VARIANT variants (CMake)"
    echo "=========================================="

    rm -rf "$OUT_DIR/libcurl-$VARIANT" "$OUT_DIR/libcurl-$VARIANT.xcframework"

    # Device
    build_with_cmake "$VARIANT" "iphoneos" "arm64" "device_arm64"

    # Simulator arm64 + x86_64
    build_with_cmake "$VARIANT" "iphonesimulator" "arm64" "sim_arm64"
    build_with_cmake "$VARIANT" "iphonesimulator" "x86_64" "sim_x86_64"

    # Universal simulator archive
    mkdir -p "$OUT_DIR/libcurl-$VARIANT/simulator"
    lipo -create \
        -output "$OUT_DIR/libcurl-$VARIANT/simulator/libcurl.a" \
        "$OUT_DIR/libcurl-$VARIANT/sim_arm64/libcurl.a" \
        "$OUT_DIR/libcurl-$VARIANT/sim_x86_64/libcurl.a"

    echo "============================================="
    echo "Creating libcurl-$VARIANT.xcframework..."
    echo "============================================="

    xcodebuild -create-xcframework \
        -library "$OUT_DIR/libcurl-$VARIANT/device_arm64/libcurl.a" -headers "$OUT_DIR/libcurl-$VARIANT/include" \
        -library "$OUT_DIR/libcurl-$VARIANT/simulator/libcurl.a" -headers "$OUT_DIR/libcurl-$VARIANT/include" \
        -output "$OUT_DIR/libcurl-$VARIANT.xcframework"

    XCFRAMEWORK_LICENSE_DIR="$OUT_DIR/libcurl-$VARIANT.xcframework/Resources/LICENSES"
    mkdir -p "$XCFRAMEWORK_LICENSE_DIR/libcurl"
    cp "$CURL_LICENSE_FILE" "$XCFRAMEWORK_LICENSE_DIR/libcurl/CURL-LICENSE.txt"

    if [ "$VARIANT" = "openssl" ]; then
        if [ -z "$OPENSSL_LICENSE_FILE" ]; then
            echo "Error: Could not locate OpenSSL license in extracted artifacts"
            echo "Please use an OpenSSL release that contains license files in the ZIP artifact."
            exit 1
        fi

        mkdir -p "$XCFRAMEWORK_LICENSE_DIR/openssl"
        cp "$OPENSSL_LICENSE_FILE" "$XCFRAMEWORK_LICENSE_DIR/openssl/OPENSSL-LICENSE.txt"
    fi

    echo "✓ Created $OUT_DIR/libcurl-$VARIANT.xcframework"
done

echo ""
echo "=========================================="
echo "iOS build completed!"
echo "XCFrameworks located in: $OUT_DIR"
echo "=========================================="
