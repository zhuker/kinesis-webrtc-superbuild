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
| `BUILD_BENCHMARK` | `OFF` | Build WebRTC SDK benchmarks |
| `BUILD_OPENSSL_PLATFORM` | `""` | OpenSSL target platform for cross-compilation |

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
| `amazon-kinesis-video-streams-webrtc-sdk-c/` | [zhuker/amazon-kinesis-video-streams-webrtc-sdk-c](https://github.com/zhuker/amazon-kinesis-video-streams-webrtc-sdk-c) | 36a82a6f |

## Architecture

All CMake-based dependencies are integrated via `add_subdirectory`. OpenSSL uses `ExternalProject_Add` since it has no CMakeLists.txt (autotools-based).

```
OpenSSL (ExternalProject)
  |
usrsctp -> jsmn -> libwebsockets -> libsrtp -> kvspic -> producer-c -> WebRTC SDK
```

The SDK's `find_library()` calls are bypassed by pre-setting CACHE variables (`SRTP_LIBRARIES`, `Usrsctp`, `LIBWEBSOCKETS_LIBRARIES`) to CMake target names. This allows `target_link_libraries` to resolve them as in-tree targets, propagating include directories and link flags automatically.
