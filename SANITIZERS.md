# Sanitizers

This project supports Clang/GCC sanitizers for detecting memory errors, undefined
behavior, and data races at runtime. Sanitizers are enabled via `--asan` or `--tsan`
flags on the test scripts.

## Enabled sanitizers

### AddressSanitizer + UndefinedBehaviorSanitizer (ASan + UBSan)

**What they detect:**
- ASan: heap/stack/global buffer overflows, use-after-free, use-after-return,
  double-free, memory leaks (Linux only)
- UBSan: signed integer overflow, null pointer dereference, misaligned access,
  shift out of bounds, unreachable code reached

**Platforms:** macOS, Linux (Docker), Android

**Usage:**
```bash
./test-mac.sh --asan
./test-docker.sh --asan
./test-android.sh --asan
```

**CMake flags:** `-DADDRESS_SANITIZER=ON -DUNDEFINED_BEHAVIOR_SANITIZER=ON`

**Runtime overhead:** ~2x slowdown, ~2-3x memory

**Runtime environment variables:**
- `ASAN_OPTIONS` -- controls ASan behavior (halt_on_error, detect_leaks, etc.)
- `UBSAN_OPTIONS` -- controls UBSan behavior (print_stacktrace, halt_on_error)

UBSan is combined with ASan in a single build (`-fsanitize=address,undefined`)
because it adds negligible overhead and requires no separate build.

**Platform-specific notes:**

| Platform | `detect_leaks` | `alloc_dealloc_mismatch` | Extra setup |
|----------|:-:|:-:|---|
| Linux    | yes | yes | None |
| macOS    | no (unsupported) | yes | None |
| Android  | no (unsupported) | yes | Requires pushing `libclang_rt.asan-<arch>-android.so` to device; `verify_asan_link_order=0` |

### ThreadSanitizer (TSan)

**What it detects:** data races, deadlocks (lock-order inversions), use of
destroyed mutexes, thread leaks.

**Platforms:** Linux (Docker) only

**Usage:**
```bash
./test-docker.sh --tsan
```

**CMake flag:** `-DTHREAD_SANITIZER=ON`

**Runtime overhead:** ~5-15x slowdown, ~5-10x memory

**Runtime environment variable:**
- `TSAN_OPTIONS` -- controls TSan behavior (halt_on_error, suppressions, etc.)

**Suppressions:** Known false positives and test-specific races are suppressed via
`amazon-kinesis-video-streams-webrtc-sdk-c/tst/suppressions/TSAN.supp`. The Docker
script points `TSAN_OPTIONS` at this file automatically.

**Constraints:**
- Cannot be combined with ASan (incompatible shadow memory layouts). The test
  scripts enforce this: `--asan` and `--tsan` are mutually exclusive.
- Requires a separate build directory (`build-*-tsan`).

## Not enabled

### ThreadSanitizer on macOS

TSan works on macOS in principle but has historical instability on Apple Silicon.
Can be added to `test-mac.sh` if needed -- the CMake plumbing already supports it
(`-DTHREAD_SANITIZER=ON`).

### ThreadSanitizer on Android

TSan requires ~128TB of virtual address space for shadow memory. Android emulators
restrict `mmap` ranges and fail with SIGBUS (exit code 138) on startup. Physical
arm64 devices running API 29+ may work but this is fragile and untested. Not
recommended.

### MemorySanitizer (MSan)

**What it detects:** reads of uninitialized memory.

**CMake flag:** `-DMEMORY_SANITIZER=ON`

**Why not enabled:** MSan requires *all* linked code (including libc++, OpenSSL,
libsrtp, usrsctp, etc.) to be compiled with `-fsanitize=memory`. Without this,
every call into an uninstrumented library produces false positives. The upstream
SDK has a `msan-tester.Dockerfile` for this purpose but it is commented out in
their CI. The cost of maintaining a fully-instrumented dependency chain is high
relative to the bugs MSan catches (many of which ASan also finds).

Only available on Linux with Clang. Not supported on macOS, Android, or Windows.

### HWAddressSanitizer (HWASan)

**What it detects:** same class of bugs as ASan (buffer overflows, use-after-free)
but using ARM Memory Tagging Extension (MTE) for lower overhead.

**Why not enabled:** requires arm64 hardware with MTE support. On Android, natively
supported starting API 34. Not relevant for Linux Docker (QEMU doesn't emulate MTE)
or macOS (Apple Silicon doesn't implement MTE). Could be useful for testing on
physical Android 14+ devices in the future.

### DataFlowSanitizer (DFSan)

**What it detects:** tracks data flow through the program (taint analysis).

**Why not enabled:** specialized tool for security research, not general bug
finding. Only available on Linux with Clang.

## Sanitizer compatibility matrix

| | ASan | TSan | MSan | UBSan |
|---|:-:|:-:|:-:|:-:|
| **ASan** | -- | no | no | yes |
| **TSan** | no | -- | no | yes |
| **MSan** | no | no | -- | yes |
| **UBSan** | yes | yes | yes | -- |

UBSan can be combined with any single other sanitizer. ASan, TSan, and MSan are
mutually exclusive.

## Recommended test matrix

For maximum coverage with minimum build configurations:

1. **ASan + UBSan** (all platforms) -- catches memory errors and undefined behavior
2. **TSan** (Linux Docker) -- catches data races and deadlocks
3. **Plain build** (all platforms) -- baseline correctness without instrumentation

This gives 3 sanitizers across 2 extra build configurations.
