# Kinesis WebRTC Superbuild

Root CMake project that builds the [Amazon Kinesis Video Streams WebRTC SDK](https://github.com/awslabs/amazon-kinesis-video-streams-webrtc-sdk-c) and all its dependencies from local git submodules using `add_subdirectory`.

## Prerequisites

- CMake 3.14+
- C/C++ compiler (GCC, Clang, or MSVC)
- pkg-config
- OpenSSL development headers (if using `-DUSE_SYSTEM_OPENSSL=ON`)

## Clone

```bash
git clone --recurse-submodules https://github.com/zhuker/kinesis-webrtc-superbuild.git
cd kinesis-webrtc-superbuild
```

If you already cloned without `--recurse-submodules`:

```bash
git submodule update --init
```

### Updating when both local and remote have changes

If you have local (uncommitted) modifications inside a submodule and the remote
branch also has new commits:

```bash
cd amazon-kinesis-video-streams-webrtc-sdk-c
git stash                                   # save local changes
git fetch origin
git reset --hard origin/gcc-custom-signaling # update to remote
git stash pop                               # re-apply local changes
cd ..
git add amazon-kinesis-video-streams-webrtc-sdk-c
```

If the remote already includes your fixes, drop the stash instead:

```bash
git stash drop
```

If `git stash pop` produces conflicts, resolve them, then `git stash drop`.

### Updating after a force push

If a submodule's remote branch was force-pushed (rebased/squashed), a regular
`git submodule update` will fail. Reset the submodule to the commit recorded in
the parent repo:

```bash
git submodule update --init --force
```

To pull the latest from a submodule's remote branch and update the parent repo:

```bash
cd amazon-kinesis-video-streams-webrtc-sdk-c
git fetch origin
git reset --hard origin/gcc-custom-signaling
cd ..
git add amazon-kinesis-video-streams-webrtc-sdk-c
```

## Build

```bash
mkdir build && cd build
cmake .. -DUSE_SYSTEM_OPENSSL=ON
cmake --build . -j$(nproc)
```

Build OpenSSL from submodule instead of using the system one:

```bash
cmake ..
```

### CMake Options

| Option | Default | Description |
|---|---|---|
| `USE_SYSTEM_OPENSSL` | `OFF` | Use system OpenSSL instead of building from submodule |
| `BUILD_STATIC_LIBS` | `OFF` | Build all libraries statically |
| `BUILD_SAMPLE` | `ON` | Build WebRTC SDK sample applications |
| `ENABLE_DATA_CHANNEL` | `ON` | Enable data channel support |
| `ENABLE_KVS_THREADPOOL` | `OFF` | Enable KVS thread pool in signaling |
| `BUILD_TEST` | `OFF` | Build WebRTC SDK tests |
| `ENABLE_AWS_SDK_IN_TESTS` | `OFF` | Enable AWS SDK in tests (requires AWS C++ SDK) |
| `BUILD_BENCHMARK` | `OFF` | Build WebRTC SDK benchmarks |
| `BUILD_OPENSSL_PLATFORM` | `""` | OpenSSL target platform for cross-compilation |
| `OPENSSL_NO_ASM` | `OFF` | Disable OpenSSL assembly optimizations (needed for QEMU) |

## Android Build

Requires the Android NDK. Set `NDK` to your NDK path:

```bash
NDK=$HOME/Library/Android/sdk/ndk/25.2.9519653

cmake -B build-android-arm64 \
  -DCMAKE_TOOLCHAIN_FILE=$NDK/build/cmake/android.toolchain.cmake \
  -DANDROID_ABI=arm64-v8a \
  -DANDROID_PLATFORM=android-26 \
  -DBUILD_SAMPLE=OFF \
  -DBUILD_STATIC_LIBS=ON

cmake --build build-android-arm64 -j$(nproc)
```

OpenSSL is automatically cross-compiled for the target ABI. The `BUILD_OPENSSL_PLATFORM` is auto-detected from `ANDROID_ABI` (e.g. `arm64-v8a` maps to `android-arm64`).

Supported ABIs: `arm64-v8a`, `armeabi-v7a`, `x86_64`, `x86`.

### Android Testing

Use `test-android.sh` to build, push, and run unit tests on an Android emulator:

```bash
./test-android.sh
```

Prerequisites:
- Android SDK with NDK 25.2.9519653 (or set `ANDROID_NDK`)
- System image: `system-images;android-26;default;arm64-v8a`

The script automatically creates an AVD named `test-android26-arm64` and starts the emulator if needed. To set up the emulator manually:

```bash
sdkmanager "system-images;android-26;default;arm64-v8a"
avdmanager create avd -n test-android26-arm64 \
  -k "system-images;android-26;default;arm64-v8a" -f <<< "no"
```

Script options:

| Flag | Description |
|---|---|
| `--skip-build` | Push and run only (reuse existing build) |
| `--filter 'Pattern.*'` | Run specific tests matching a gtest filter |
| `--all` | Run all tests (including those requiring network/credentials) |
| `--serial <id>` | Target a specific device (default: auto-detect emulator) |

To build with tests and run manually:

```bash
NDK=$HOME/Library/Android/sdk/ndk/25.2.9519653

cmake -B build-android-arm64 \
  -DCMAKE_TOOLCHAIN_FILE=$NDK/build/cmake/android.toolchain.cmake \
  -DANDROID_ABI=arm64-v8a \
  -DANDROID_PLATFORM=android-26 \
  -DBUILD_SAMPLE=OFF \
  -DBUILD_STATIC_LIBS=ON \
  -DBUILD_TEST=ON

cmake --build build-android-arm64 -j$(nproc)

adb push build-android-arm64/amazon-kinesis-video-streams-webrtc-sdk-c/tst/webrtc_client_test /data/local/tmp/
adb push build-android-arm64/amazon-kinesis-video-streams-producer-c/libkvsCommonLws.so /data/local/tmp/
adb push build-android-arm64/libwebsockets/lib/libwebsockets.so /data/local/tmp/
adb shell chmod +x /data/local/tmp/webrtc_client_test
adb shell "LD_LIBRARY_PATH=/data/local/tmp /data/local/tmp/webrtc_client_test --gtest_filter='StunApiTest.*:SdpApiTest.*'"
```

## Docker Build (Linux/amd64)

```bash
docker build --platform=linux/amd64 -t kinesis-webrtc-superbuild .
```

Sample binaries end up in `build-linux-amd64/amazon-kinesis-video-streams-webrtc-sdk-c/samples/` inside the image.

## Output

Sample binaries are built to `build/amazon-kinesis-video-streams-webrtc-sdk-c/samples/`:

- `kvsWebrtcClientMaster`
- `kvsWebrtcClientViewer`
- `customSignaling`
- `whepServer`
- `whipServer`
- `discoverNatBehavior`

## Submodules

| Directory | Repository | Version |
|---|---|---|
| `openssl/` | [openssl/openssl](https://github.com/openssl/openssl) | OpenSSL_1_1_1t |
| `usrsctp/` | [sctplab/usrsctp](https://github.com/sctplab/usrsctp) | 1ade45cb |
| `jsmn/` | [zserge/jsmn](https://github.com/zserge/jsmn) | v1.0.0 |
| `libwebsockets/` | [warmcat/libwebsockets](https://github.com/warmcat/libwebsockets) | v4.3.5 |
| `libsrtp/` | [cisco/libsrtp](https://github.com/cisco/libsrtp) | bd0f27ec |
| `amazon-kinesis-video-streams-pic/` | [awslabs/amazon-kinesis-video-streams-pic](https://github.com/awslabs/amazon-kinesis-video-streams-pic) | v1.2.0 |
| `amazon-kinesis-video-streams-producer-c/` | [awslabs/amazon-kinesis-video-streams-producer-c](https://github.com/awslabs/amazon-kinesis-video-streams-producer-c) | v1.6.0 |
| `googletest/` | [google/googletest](https://github.com/google/googletest) | release-1.12.1 |
| `amazon-kinesis-video-streams-webrtc-sdk-c/` | [zhuker/amazon-kinesis-video-streams-webrtc-sdk-c](https://github.com/zhuker/amazon-kinesis-video-streams-webrtc-sdk-c) | 36a82a6f |

## Architecture

All CMake-based dependencies are integrated via `add_subdirectory`. OpenSSL is built at configure time via `execute_process` since it has no CMakeLists.txt (autotools-based). When `USE_SYSTEM_OPENSSL=ON`, the system OpenSSL is used via `find_package`.

```
OpenSSL (execute_process at configure time)
  |
usrsctp -> jsmn -> libwebsockets -> libsrtp -> kvspic -> producer-c -> WebRTC SDK
```

The SDK's `find_library()` calls are bypassed by pre-setting CACHE variables (`SRTP_LIBRARIES`, `Usrsctp`, `LIBWEBSOCKETS_LIBRARIES`) to CMake target names. This allows `target_link_libraries` to resolve them as in-tree targets, propagating include directories and link flags automatically.
