# libcurl iOS & Android Prebuilt Libraries

Prebuilt static and shared libraries for **libcurl** targeting both iOS and Android platforms, with optional **OpenSSL** support.

## Quick Usage

### Android (via Maven)

Add the repository to your `build.gradle` and add the AAR dependency:

```gradle
repositories {
  maven { url 'https://xdcobra.github.io/maven' }
}

dependencies {
  implementation 'com.xdcobra.libcurl:libcurl-openssl:<VERSION>'
}
```

### iOS (via XCFramework)

1. Download the latest `libcurl-openssl.xcframework` from the [GitHub Releases](https://github.com/XDcobra/libcurl-ios-android-prebuilt-and-buildscripts/releases).
2. Add the `openssl.xcframework` to your Xcode project under **Frameworks, Libraries, and Embedded Content**.
3. Set the embed status to **Embed & Sign** (if linking dynamically) or **Do Not Embed** (if linking statically, which is recommended for `libcurl.a` wrapped in XCFramework).

## Overview

This repository automates the building and distribution of libcurl libraries for iOS and Android. It provides:

- **Two Variants:**
  - `libcurl-core`: libcurl without SSL/TLS support
  - `libcurl-openssl`: libcurl statically linked against OpenSSL

- **Android Artifacts:**
  - Shared libraries (`.so`) for all major ABIs (arm64-v8a, armeabi-v7a, x86, x86_64)
  - Optional static libraries (`.a`)
  - Maven deployment as AAR packages

- **iOS Artifacts:**
  - XCFramework for both device and simulator architectures
  - Supports iOS 12.0 and later

## OpenSSL Dependency

Both variants depend on prebuilt OpenSSL libraries from:
- Repository: [openssl-ios-android-prebuilt-and-buildscripts](https://github.com/XDcobra/openssl-ios-android-prebuilt-and-buildscripts)
- Default Version: `v3.6.1-1`

The build scripts automatically download the required OpenSSL artifacts from GitHub releases.

## Building Locally

### Prerequisites

**For Android:**
- Android NDK (r29 or later)
- Set `ANDROID_NDK_ROOT` or `ANDROID_NDK_HOME` environment variable

**For iOS:**
- Xcode with Command Line Tools
- macOS 12+

### Build Android

```bash
export ANDROID_NDK_ROOT=/path/to/ndk
export OPENSSL_VERSION="v3.6.1-1"  # Optional, defaults to v3.6.1-1
chmod +x build-android.sh
./build-android.sh
```

Output: `build/android/`
- `libcurl-core/jniLibs/{abi}/libcurl.so`
- `libcurl-openssl/jniLibs/{abi}/libcurl.so`

### Build iOS

```bash
export OPENSSL_VERSION="v3.6.1-1"  # Optional, defaults to v3.6.1-1
chmod +x build-ios.sh
./build-ios.sh
```

Output: `build/ios/`
- `libcurl-core.xcframework`
- `libcurl-openssl.xcframework`

## GitHub Releases

Releases are automatically created with:
- `libcurl-android.zip` — All Android build artifacts
- `libcurl-ios.zip` — All iOS XCFrameworks

**Example Release:** https://github.com/XDcobra/libcurl-ios-android-prebuilt-and-buildscripts/releases

## Maven Repository

Both variants are published to the GitHub Pages Maven repository:

**Repository URL:** https://xdcobra.github.io/maven

**Coordinates:**
- `com.xdcobra.libcurl:libcurl-core:VERSION`
- `com.xdcobra.libcurl:libcurl-openssl:VERSION`

### Adding to Gradle

```gradle
repositories {
    maven { url 'https://xdcobra.github.io/maven' }
}

dependencies {
    // With OpenSSL support (recommended)
    implementation 'com.xdcobra.libcurl:libcurl-openssl:1.0.0'
}
```

## Release Workflow

### Creating a Release

1. **Tag a commit:**
   ```bash
   git tag v1.0.0
   git push origin v1.0.0
   ```

2. **The GitHub Actions workflow automatically:**
   - Builds Android libraries
   - Builds iOS libraries
   - Creates a GitHub release with artifacts
   - Deploys to Maven repository (requires `MAVEN_REPO_PAT` secret)

### Workflow Dispatch

Alternatively, trigger manually with custom versions:
- **GitHub UI:** Actions → Release Main → Run workflow
- **CLI:** 
  ```bash
  gh workflow run release-main.yml -f version=v1.0.0 -f openssl_version=v3.6.1-1
  ```

## Secrets

The following GitHub secrets are required for Maven deployment:
- `MAVEN_REPO_PAT`: Personal Access Token with push access to the [maven](https://github.com/XDcobra/maven) repository

## Architecture Support

### Android ABIs
- `arm64-v8a` (64-bit ARM)
- `armeabi-v7a` (32-bit ARM)
- `x86` (32-bit Intel)
- `x86_64` (64-bit Intel)
- **API Level:** 24+

### iOS Architectures
- `arm64` (physical devices)
- `arm64-simulator` 
- `x86_64-simulator`
- **iOS Version:** 12.0+

## Directory Structure

```
.github/workflows/
  ├── build-android.yml      # Build Android libraries
  ├── build-ios.yml          # Build iOS libraries
  ├── release-github.yml      # Create GitHub release
  ├── release-maven.yml       # Deploy to Maven
  └── release-main.yml        # Orchestrate all workflows
build-android.sh             # Android build script
build-ios.sh                 # iOS build script
README.md                    # This file
```

## Troubleshooting

**Issue:** Android build fails with NDK not found
- **Solution:** Set `ANDROID_NDK_ROOT` environment variable

**Issue:** iOS build fails with Xcode not found
- **Solution:** Run `sudo xcode-select -s /Applications/Xcode.app`

**Issue:** Maven deployment fails
- **Solution:** Check that `MAVEN_REPO_PAT` is set with appropriate GitHub access

## Related Projects

- [openssl-ios-android-prebuilt-and-buildscripts](https://github.com/XDcobra/openssl-ios-android-prebuilt-and-buildscripts) — OpenSSL prebuilds
- [Fluttida](https://github.com/XDcobra/fluttida) — Flutter app using these libraries

## License

These prebuilt binaries follow the original licenses:
- libcurl: Licensed under curl License (https://curl.se/docs/copyright.html)
- OpenSSL: Licensed under Apache License 2.0