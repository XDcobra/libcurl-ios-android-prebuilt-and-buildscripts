#!/bin/bash
# Deploy libcurl variants to Maven Repository
# Usage: ./deploy-maven.sh <version> [maven-repo-path]

set -e

VERSION="${1:?Version is required}"
VERSION="${VERSION#v}"
REPO_ROOT="${2:-.}"
MAVEN_REPO_PATH="$REPO_ROOT/maven-repo"

# Deploy both variants: libcurl-core and libcurl-openssl
for VARIANT in "core" "openssl"; do
  cd "$REPO_ROOT"

    echo "=========================================="
    echo "Deploying libcurl-${VARIANT}..."
    echo "=========================================="
    echo "Maven version: $VERSION"
    
    GROUP_ID="com.xdcobra.libcurl"
    ARTIFACT_ID="libcurl-${VARIANT}"
    
    GROUP_PATH=$(echo "$GROUP_ID" | tr '.' '/')
    ARTIFACT_DIR="$MAVEN_REPO_PATH/$GROUP_PATH/$ARTIFACT_ID"
    VERSION_DIR="$ARTIFACT_DIR/$VERSION"
    
    # Ensure directories exist
    mkdir -p "$VERSION_DIR"
    
    # Create AAR file from the variant's jniLibs
    echo "Creating AAR for $VARIANT..."
    AAR_CONTENT_DIR="/tmp/aar-content-${VARIANT}"
    rm -rf "$AAR_CONTENT_DIR"
    mkdir -p "$AAR_CONTENT_DIR/jni"
    mkdir -p "$AAR_CONTENT_DIR/META-INF/licenses"
    
    # Copy jniLibs safely
    if [ -d "android_out/libcurl-${VARIANT}/jniLibs" ]; then
        cp -r android_out/libcurl-${VARIANT}/jniLibs/* "$AAR_CONTENT_DIR/jni/" || true
    fi

    # Copy license files into AAR to satisfy redistribution requirements
    if [ -d "android_out/libcurl-${VARIANT}/licenses" ]; then
      cp -r android_out/libcurl-${VARIANT}/licenses/* "$AAR_CONTENT_DIR/META-INF/licenses/" || true
    fi

    if [ ! -f "$AAR_CONTENT_DIR/META-INF/licenses/libcurl/CURL-LICENSE.txt" ]; then
      echo "Error: Missing libcurl license file for $VARIANT"
      exit 1
    fi

    if [ "$VARIANT" = "openssl" ] && [ ! -f "$AAR_CONTENT_DIR/META-INF/licenses/openssl/OPENSSL-LICENSE.txt" ]; then
      echo "Error: Missing OpenSSL license file for $VARIANT"
      exit 1
    fi

    if [ "$VARIANT" = "openssl" ]; then
      for abi in armeabi-v7a arm64-v8a x86 x86_64; do
        d="$AAR_CONTENT_DIR/jni/$abi"
        if [ ! -f "$d/libcurl.so" ] || [ ! -f "$d/libcrypto.so" ] || [ ! -f "$d/libssl.so" ]; then
          echo "Error: libcurl-openssl AAR must contain libcurl.so, libcrypto.so, libssl.so in $d"
          ls -la "$d" 2>/dev/null || true
          exit 1
        fi
      done
    fi
    
    # Create a minimal AndroidManifest.xml
    mkdir -p "$AAR_CONTENT_DIR"
    cat > "$AAR_CONTENT_DIR/AndroidManifest.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<manifest package="com.xdcobra.libcurl.${VARIANT}" />
EOF
    
    # Pack everything into an AAR file
    cd "$AAR_CONTENT_DIR"
    zip -q -r "$REPO_ROOT/libcurl-${VARIANT}-$VERSION.aar" *
    cd "$REPO_ROOT"
    
    # Copy the AAR
    AAR_FILE="$VERSION_DIR/$ARTIFACT_ID-$VERSION.aar"
    cp "libcurl-${VARIANT}-$VERSION.aar" "$AAR_FILE"
    
    # Create POM file
    POM_FILE="$VERSION_DIR/$ARTIFACT_ID-$VERSION.pom"
    
    if [ "$VARIANT" = "openssl" ]; then
      DESCRIPTION="libcurl with OpenSSL (shared) for Android — AAR includes libcurl.so, libcrypto.so, libssl.so per ABI"
    else
      DESCRIPTION="libcurl Core (No SSL) for Android"
    fi
    
    cat > "$POM_FILE" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0" 
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd" 
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <modelVersion>4.0.0</modelVersion>
  <groupId>$GROUP_ID</groupId>
  <artifactId>$ARTIFACT_ID</artifactId>
  <version>$VERSION</version>
  <packaging>aar</packaging>
  <description>$DESCRIPTION</description>
</project>
EOF
    
    # Update maven-metadata.xml using external Python script
    python3 scripts/update_maven_metadata.py "$GROUP_ID" "$ARTIFACT_ID" "$VERSION" "$ARTIFACT_DIR"
    
    # Generate checksums
    cd "$VERSION_DIR"
    for f in "$ARTIFACT_ID-$VERSION.aar" "$ARTIFACT_ID-$VERSION.pom"; do
      md5sum "$f" | cut -d' ' -f1 > "${f}.md5"
      sha1sum "$f" | cut -d' ' -f1 > "${f}.sha1"
    done
    
    cd "$ARTIFACT_DIR"
    md5sum "maven-metadata.xml" | cut -d' ' -f1 > "maven-metadata.xml.md5"
    sha1sum "maven-metadata.xml" | cut -d' ' -f1 > "maven-metadata.xml.sha1"
done

echo ""
echo "Maven deployment completed!"
