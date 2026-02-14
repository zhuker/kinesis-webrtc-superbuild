# Kinesis WebRTC Superbuild

Root CMake project that builds the [Amazon Kinesis Video Streams WebRTC SDK](https://github.com/awslabs/amazon-kinesis-video-streams-webrtc-sdk-c) and all its dependencies from local git submodules using `add_subdirectory`.

## Prerequisites

- CMake 3.14+
- C/C++ compiler (GCC, Clang, or MSVC)
- pkg-config
- Perl (for OpenSSL's Configure script)
- **macOS**: Xcode command-line tools (`xcode-select --install`)
- **Android**: Android SDK with NDK 28.2.13676358, `platform-tools`, `cmdline-tools`

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

### Pushing a local fix in a submodule

If you made a fix inside a submodule (e.g. `amazon-kinesis-video-streams-pic`)
and want to push it to the submodule's remote branch and update the parent repo:

```bash
cd amazon-kinesis-video-streams-pic
git checkout android-fixes              # switch from detached HEAD to the branch
git merge <commit> --ff-only            # fast-forward the branch to include your fix
git push origin android-fixes           # push to remote
cd ..
git add amazon-kinesis-video-streams-pic
git commit -m "update pic submodule"
```

## Build

All platforms use the same core CMake settings: OpenSSL built from the submodule, signaling disabled, static libraries.

```bash
cmake -B build -S . \
    -DBUILD_TEST=ON \
    -DBUILD_SAMPLE=OFF \
    -DBUILD_STATIC_LIBS=ON \
    -DENABLE_SIGNALING=OFF
cmake --build build -j$(sysctl -n hw.ncpu 2>/dev/null || nproc)
```

### CMake Options

| Option | Default | Description |
|---|---|---|
| `USE_SYSTEM_OPENSSL` | `OFF` | Use system OpenSSL instead of building from submodule |
| `BUILD_STATIC_LIBS` | `OFF` | Build all libraries statically |
| `BUILD_SAMPLE` | `ON` | Build WebRTC SDK sample applications |
| `ENABLE_SIGNALING` | `ON` | Enable AWS signaling client (requires libwebsockets) |
| `ENABLE_DATA_CHANNEL` | `ON` | Enable data channel support |
| `ENABLE_KVS_THREADPOOL` | `OFF` | Enable KVS thread pool in signaling |
| `BUILD_TEST` | `OFF` | Build WebRTC SDK tests |
| `BUILD_ANDROID_JNI_TEST` | `OFF` | Build Android JNI test library instead of test executable |
| `ENABLE_AWS_SDK_IN_TESTS` | `OFF` | Enable AWS SDK in tests (requires AWS C++ SDK) |
| `BUILD_BENCHMARK` | `OFF` | Build WebRTC SDK benchmarks |
| `BUILD_OPENSSL_PLATFORM` | `""` | OpenSSL target platform for cross-compilation |
| `OPENSSL_NO_ASM` | `OFF` | Disable OpenSSL assembly optimizations (needed for QEMU) |

## Testing

### macOS (arm64)

```bash
./test-mac.sh
```

Builds to `build-mac-arm64/` and runs all gtest tests.

| Flag | Description |
|---|---|
| `--skip-build` | Reuse existing build |
| `--filter 'StunApiTest.*'` | Run specific tests |

### Linux (Docker, arm64)

```bash
./test-docker.sh
```

Builds a Docker image (`--platform linux/arm64`) and runs tests in a container.

```bash
./test-docker.sh build   # build image only
./test-docker.sh run     # run tests only (reuse image)
```

### Android -- native binary

Builds a standalone gtest executable, pushes it to a device via `adb`, and runs it.
Requires a connected device or running emulator.

```bash
# arm64 (default)
./emulator.sh start          # start emulator if needed
./test-android.sh

# arm32 (requires physical device)
./test-android.sh --abi armeabi-v7a

# target a specific device (ABI auto-detected)
./test-android.sh --serial emulator-5554
```

| Flag | Description |
|---|---|
| `--abi <abi>` | Target ABI: `arm64-v8a` (default) or `armeabi-v7a` |
| `--serial <serial>` | Target a specific device (ABI auto-detected from device) |
| `--skip-build` | Reuse existing build |
| `--filter 'StunApiTest.*'` | Run specific tests |

If `--serial` is not given, the script scans connected devices for one matching the
target ABI. Build output goes to `build-android-<abi>/`.

### Android -- instrumented app

Builds an APK via Gradle (both arm64 + arm32), installs it on a device, and runs
gtest tests through Android instrumentation. This exercises the JNI bridge and runs
tests in the `untrusted_app` SELinux domain, which is more restrictive than the shell
domain used by the native binary test.

```bash
./emulator.sh start          # start emulator if needed
./test-android-app.sh
```

Options are the same as `test-android.sh` (`--abi`, `--serial`, `--skip-build`, `--filter`).

To run on all connected devices in parallel:

```bash
./all-test-android-app.sh
```

### Emulator management

```bash
./emulator.sh start              # start API 26 emulator (error if already running)
./emulator.sh start -f           # no-op if already running
./emulator.sh start --api 30    # start API 30 emulator
./emulator.sh stop               # stop running emulator
./emulator.sh restart            # stop + start
./emulator.sh status             # list all connected devices/emulators
```

`status` shows serial, type (emulator/device), API level, and supported ABIs for
every connected device.

## Project structure

```
CMakeLists.txt                              Root superbuild
openssl/                                    Git submodule (OpenSSL_1_1_1t)
libwebsockets/                              Git submodule (v4.3.5)
libsrtp/                                    Git submodule
usrsctp/                                    Git submodule
jsmn/                                       Git submodule (v1.0.0)
amazon-kinesis-video-streams-pic/           Git submodule (kvspic)
amazon-kinesis-video-streams-producer-c/    Git submodule (kvsCommonLws)
amazon-kinesis-video-streams-webrtc-sdk-c/  WebRTC SDK
googletest/                                 Git submodule (release-1.12.1)
android-test-app/                           Gradle project for instrumented tests
```

### Build order

```
OpenSSL (built at configure time)
  |
  v
usrsctp -> jsmn -> libsrtp -> kvspic -> WebRTC SDK
```

With `ENABLE_SIGNALING=ON`, libwebsockets and producer-c are also built between jsmn and libsrtp.

### Architecture

All CMake-based dependencies are integrated via `add_subdirectory`. OpenSSL is built at configure time via `execute_process` since it has no CMakeLists.txt (autotools-based).

The SDK's `find_library()` calls are bypassed by pre-setting CACHE variables (`SRTP_LIBRARIES`, `Usrsctp`, `LIBWEBSOCKETS_LIBRARIES`) to CMake target names. This allows `target_link_libraries` to resolve them as in-tree targets, propagating include directories and link flags automatically.

## Scripts summary

| Script | Purpose |
|--------|---------|
| `test-mac.sh` | Build + test on macOS arm64 |
| `test-docker.sh` | Build + test in Docker (linux/arm64) |
| `test-android.sh` | Build + push + test native binary on Android |
| `test-android-app.sh` | Build + install + test instrumented APK on Android |
| `all-test-android-app.sh` | Run instrumented tests on all connected devices in parallel |
| `emulator.sh` | Manage Android emulator (start/stop/restart/status) |
| `run-tests-on-device.sh` | Test runner executed on the Android device (pushed by test-android.sh) |

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
| `amazon-kinesis-video-streams-webrtc-sdk-c/` | [zhuker/amazon-kinesis-video-streams-webrtc-sdk-c](https://github.com/zhuker/amazon-kinesis-video-streams-webrtc-sdk-c) | gcc-custom-signaling |
