#!/bin/bash
# Deploy libcurl variants to Maven Repository
# Usage: ./deploy-maven.sh <version> [maven-repo-path]

set -e

VERSION="${1:?Version is required}"
REPO_ROOT="${2:-.}"
MAVEN_REPO_PATH="$REPO_ROOT/maven-repo"

# Deploy both variants: libcurl-core and libcurl-openssl
for VARIANT in "core" "openssl"; do
    echo "=========================================="
    echo "Deploying libcurl-${VARIANT}..."
    echo "=========================================="
    
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
    mkdir -p "$AAR_CONTENT_DIR/jni"
    
    # Copy jniLibs safely
    if [ -d "android_out/libcurl-${VARIANT}/jniLibs" ]; then
        cp -r android_out/libcurl-${VARIANT}/jniLibs/* "$AAR_CONTENT_DIR/jni/" || true
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
      DESCRIPTION="libcurl with OpenSSL Support for Android"
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
