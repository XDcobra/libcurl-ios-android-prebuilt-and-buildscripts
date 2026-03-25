#!/bin/bash
set -e

# Verify Android NDK
if [ -z "$ANDROID_NDK_ROOT" ]; then
    if [ -n "$ANDROID_NDK_HOME" ]; then
        export ANDROID_NDK_ROOT="$ANDROID_NDK_HOME"
    else
        echo "Error: ANDROID_NDK_ROOT or ANDROID_NDK_HOME must be set."
        exit 1
    fi
fi

# Determine Host OS for NDK Toolchain path
HOST_OS=$(uname -s | tr '[:upper:]' '[:lower:]')
if [ "$HOST_OS" = "darwin" ]; then
    TOOLCHAIN_HOST="darwin-x86_64"
elif [ "$HOST_OS" = "linux" ]; then
    TOOLCHAIN_HOST="linux-x86_64"
else
    echo "Error: Unsupported host OS: $HOST_OS"
    exit 1
fi

# Add NDK toolchain to PATH
export PATH="$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/$TOOLCHAIN_HOST/bin:$PATH"

API_LEVEL=24
OUT_DIR="$(pwd)/build/android"
OPENSSL_VERSION="${OPENSSL_VERSION:-v3.6.1-1}"

mkdir -p "$OUT_DIR"

echo "Building libcurl for Android (API Level $API_LEVEL) with OpenSSL $OPENSSL_VERSION..."
echo "libcurl-openssl: links dynamically against OpenSSL shared libs; AAR bundles libcurl.so + libcrypto.so + libssl.so per ABI."

# Download OpenSSL artifacts if not already present
OPENSSL_ZIP="openssl-android.zip"
if [ ! -f "$OPENSSL_ZIP" ]; then
    echo "Downloading OpenSSL Android artifacts from GitHub..."
    curl -L -o "$OPENSSL_ZIP" \
        "https://github.com/XDcobra/openssl-ios-android-prebuilt-and-buildscripts/releases/download/${OPENSSL_VERSION}/openssl-android.zip"
fi

# Extract OpenSSL artifacts
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

# Setup libcurl source code
if [ ! -d "libcurl" ]; then
    echo "Cloning libcurl from GitHub..."
    git clone --depth 1 https://github.com/curl/curl.git libcurl
fi

cd libcurl

CURL_LICENSE_FILE="$(find_first_existing_file \
    "$(pwd)/COPYING" \
    "$(pwd)/LICENSE" \
    "$(pwd)/LICENSE.txt")"

if [ -z "$CURL_LICENSE_FILE" ]; then
    echo "Error: Could not locate libcurl license file in source checkout"
    exit 1
fi

OPENSSL_LICENSE_FILE="$(find_first_existing_file \
    "$(pwd)/../openssl_extracted/licenses/openssl/OPENSSL-LICENSE.txt" \
    "$(pwd)/../openssl_extracted/licenses/openssl/LICENSE.txt" \
    "$(pwd)/../openssl_extracted/licenses/OPENSSL-LICENSE.txt" \
    "$(pwd)/../openssl_extracted/Resources/LICENSES/OPENSSL-LICENSE.txt")"

ABIS=("armeabi-v7a" "arm64-v8a" "x86" "x86_64")

# Build two variants: libcurl-core (no SSL) and libcurl-openssl (with SSL)
for VARIANT in "core" "openssl"; do
    echo ""
    echo "========================================== "
    echo "Building libcurl-${VARIANT} for Android"
    echo "=========================================="
    
    VARIANT_OUT="$OUT_DIR/libcurl-${VARIANT}"
    mkdir -p "$VARIANT_OUT/jniLibs"

    VARIANT_LICENSE_DIR="$VARIANT_OUT/licenses"
    mkdir -p "$VARIANT_LICENSE_DIR/libcurl"
    cp "$CURL_LICENSE_FILE" "$VARIANT_LICENSE_DIR/libcurl/CURL-LICENSE.txt"

    if [ "$VARIANT" = "openssl" ]; then
        if [ -z "$OPENSSL_LICENSE_FILE" ]; then
            echo "Error: Could not locate OpenSSL license in extracted artifacts"
            echo "Please use an OpenSSL release that contains license files in the ZIP artifact."
            exit 1
        fi

        mkdir -p "$VARIANT_LICENSE_DIR/openssl"
        cp "$OPENSSL_LICENSE_FILE" "$VARIANT_LICENSE_DIR/openssl/OPENSSL-LICENSE.txt"
    fi
    
    for i in "${!ABIS[@]}"; do
        ABI="${ABIS[$i]}"
        TARGET="$ABI"
        
        echo ""
        echo "--- Building for $ABI ($TARGET)..."
        
        # Clean up previous build
        if [ -f Makefile ]; then
            make clean || true
        fi
        
        # Prepare CMake flags
        CMAKE_FLAGS="-DBUILD_SHARED_LIBS=ON -DBUILD_STATIC_LIBS=OFF"
        CMAKE_FLAGS="$CMAKE_FLAGS -DCURL_USE_LIBPSL=OFF"
        CMAKE_FLAGS="$CMAKE_FLAGS -DCURL_DISABLE_LDAP=ON"
        CMAKE_FLAGS="$CMAKE_FLAGS -DCMAKE_BUILD_TYPE=RelWithDebInfo"
        CMAKE_FLAGS="$CMAKE_FLAGS -DCMAKE_SYSTEM_NAME=Android"
        CMAKE_FLAGS="$CMAKE_FLAGS -DCMAKE_SYSTEM_VERSION=$API_LEVEL"
        CMAKE_FLAGS="$CMAKE_FLAGS -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK_ROOT/build/cmake/android.toolchain.cmake"
        CMAKE_FLAGS="$CMAKE_FLAGS -DANDROID_ABI=$ABI"
        CMAKE_FLAGS="$CMAKE_FLAGS -DANDROID_PLATFORM=android-$API_LEVEL"
        CMAKE_FLAGS="$CMAKE_FLAGS -DCMAKE_ANDROID_PLATFORM=android-$API_LEVEL"
        CMAKE_FLAGS="$CMAKE_FLAGS -DCMAKE_ANDROID_ABI=$ABI"
        CMAKE_FLAGS="$CMAKE_FLAGS -DCMAKE_ANDROID_NDK=$ANDROID_NDK_ROOT"
        
        if [ "$VARIANT" = "openssl" ]; then
            # Link libcurl against OpenSSL shared libs (.so); same files are bundled into the AAR per ABI.
            OPENSSL_LIB_DIR="$(pwd)/../openssl_extracted/jniLibs/$ABI"
            OPENSSL_INCLUDE_DIR="$(pwd)/../openssl_extracted/include"
            OPENSSL_ROOT_DIR="$(pwd)/../openssl_extracted"

            if [ ! -f "$OPENSSL_LIB_DIR/libcrypto.so" ] || [ ! -f "$OPENSSL_LIB_DIR/libssl.so" ]; then
                echo "Error: OpenSSL shared libs not found for ABI '$ABI' in $OPENSSL_LIB_DIR"
                echo "Expected libcrypto.so and libssl.so (from openssl-android.zip / shared OpenSSL build)."
                exit 1
            fi

            if [ ! -f "$OPENSSL_INCLUDE_DIR/openssl/ssl.h" ]; then
                echo "Error: OpenSSL headers not found in $OPENSSL_INCLUDE_DIR"
                exit 1
            fi
            
            CMAKE_FLAGS="$CMAKE_FLAGS -DCURL_USE_OPENSSL=ON"
            CMAKE_FLAGS="$CMAKE_FLAGS -DOPENSSL_ROOT_DIR=$OPENSSL_ROOT_DIR"
            CMAKE_FLAGS="$CMAKE_FLAGS -DOPENSSL_INCLUDE_DIR=$OPENSSL_INCLUDE_DIR"
            CMAKE_FLAGS="$CMAKE_FLAGS -DOPENSSL_USE_STATIC_LIBS=OFF"
            CMAKE_FLAGS="$CMAKE_FLAGS -DOPENSSL_CRYPTO_LIBRARY=$OPENSSL_LIB_DIR/libcrypto.so"
            CMAKE_FLAGS="$CMAKE_FLAGS -DOPENSSL_SSL_LIBRARY=$OPENSSL_LIB_DIR/libssl.so"
        else
            # Build without SSL support
            CMAKE_FLAGS="$CMAKE_FLAGS -DCURL_USE_OPENSSL=OFF"
        fi
        
        # Create build directory
        BUILD_DIR="build_${VARIANT}_${ABI}"
        rm -rf "$BUILD_DIR"
        mkdir -p "$BUILD_DIR"
        cd "$BUILD_DIR"

        # Prevent inherited host/cross compiler settings from forcing wrong ABI.
        unset CC CXX CPP CFLAGS CXXFLAGS CPPFLAGS LDFLAGS AR RANLIB LD
        
        # Configure with CMake
        cmake .. $CMAKE_FLAGS -DCMAKE_INSTALL_PREFIX="$OUT_DIR/tmp_install_${ABI}"
        
        # Build
        cmake --build . -j$(sysctl -n hw.ncpu 2>/dev/null || nproc)
        
        # Go back to libcurl root
        cd ..
        
        # Create directory for current ABI
        ABI_LIB="$VARIANT_OUT/jniLibs/$ABI"
        mkdir -p "$ABI_LIB"
        
        # Copy shared library
        if [ -f "$BUILD_DIR/lib/libcurl.so" ]; then
            cp "$BUILD_DIR/lib/libcurl.so" "$ABI_LIB/libcurl.so"
            echo "✓ Built libcurl.so for $ABI"
        fi

        # Bundle OpenSSL .so into the same jniLibs folder so Gradle packages them with the AAR (runtime DT_NEEDED).
        if [ "$VARIANT" = "openssl" ]; then
            cp -L "$OPENSSL_LIB_DIR/libcrypto.so" "$ABI_LIB/libcrypto.so"
            cp -L "$OPENSSL_LIB_DIR/libssl.so" "$ABI_LIB/libssl.so"
            echo "✓ Bundled libcrypto.so + libssl.so for $ABI"
        fi
        
        # Copy headers (first time only to save space)
        if [ "$i" -eq 0 ]; then
            mkdir -p "$VARIANT_OUT/include"
            cp -r include/curl "$VARIANT_OUT/include/"
        fi
    done
done

cd ..

echo ""
echo "=========================================="
echo "Android build completed!"
echo "All files are located in: $OUT_DIR"
echo "=========================================="
