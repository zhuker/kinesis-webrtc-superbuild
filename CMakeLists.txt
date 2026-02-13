cmake_minimum_required(VERSION 3.14)
project(KinesisWebRTCSuperbuild VERSION 1.0.0 LANGUAGES C CXX)

# =============================================================================
# Options
# =============================================================================
option(USE_SYSTEM_OPENSSL    "Use system OpenSSL instead of building from submodule" OFF)
option(BUILD_STATIC_LIBS     "Build all libraries statically"                        OFF)
option(BUILD_SAMPLE          "Build WebRTC SDK sample applications"                  ON)
option(ENABLE_DATA_CHANNEL   "Enable data channel support in WebRTC SDK"             ON)
option(ENABLE_SIGNALING      "Enable AWS signaling client (requires libwebsockets)"  ON)
option(ENABLE_KVS_THREADPOOL "Enable KVS thread pool in signaling"                   OFF)
option(BUILD_TEST            "Build WebRTC SDK tests"                                OFF)
option(BUILD_BENCHMARK       "Build WebRTC SDK benchmarks"                           OFF)
option(ENABLE_AWS_SDK_IN_TESTS "Enable AWS SDK in tests (requires AWS C++ SDK)"      OFF)

set(BUILD_OPENSSL_PLATFORM "" CACHE STRING "OpenSSL target platform for cross-compilation")
option(OPENSSL_NO_ASM "Disable OpenSSL assembly optimizations (needed for QEMU)" OFF)
option(BUILD_ANDROID_JNI_TEST "Build Android JNI test library instead of test executable" OFF)

if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE "Release" CACHE STRING "Build type" FORCE)
endif()

set(CMAKE_POLICY_VERSION_MINIMUM 3.5)

# =============================================================================
# Android cross-compilation
# =============================================================================
if(CMAKE_SYSTEM_NAME STREQUAL "Android")
  # Auto-set OpenSSL target platform from ANDROID_ABI.
  if(NOT BUILD_OPENSSL_PLATFORM OR BUILD_OPENSSL_PLATFORM STREQUAL "")
    if(ANDROID_ABI STREQUAL "arm64-v8a")
      set(BUILD_OPENSSL_PLATFORM "android-arm64" CACHE STRING "" FORCE)
    elseif(ANDROID_ABI STREQUAL "armeabi-v7a")
      set(BUILD_OPENSSL_PLATFORM "android-arm" CACHE STRING "" FORCE)
    elseif(ANDROID_ABI STREQUAL "x86_64")
      set(BUILD_OPENSSL_PLATFORM "android-x86_64" CACHE STRING "" FORCE)
    elseif(ANDROID_ABI STREQUAL "x86")
      set(BUILD_OPENSSL_PLATFORM "android-x86" CACHE STRING "" FORCE)
    endif()
  endif()

  # OpenSSL's Configure for Android needs ANDROID_NDK_HOME to find the
  # NDK toolchain. Try several sources for the NDK path.
  if(CMAKE_ANDROID_NDK)
    set(ENV{ANDROID_NDK_HOME} "${CMAKE_ANDROID_NDK}")
  elseif(ANDROID_NDK)
    set(ENV{ANDROID_NDK_HOME} "${ANDROID_NDK}")
  elseif(CMAKE_TOOLCHAIN_FILE)
    # Derive from toolchain path: <NDK>/build/cmake/android.toolchain.cmake
    get_filename_component(_ndk "${CMAKE_TOOLCHAIN_FILE}" DIRECTORY)
    get_filename_component(_ndk "${_ndk}" DIRECTORY)
    get_filename_component(_ndk "${_ndk}" DIRECTORY)
    set(ENV{ANDROID_NDK_HOME} "${_ndk}")
  endif()
  # OpenSSL's Configure checks if `clang` on PATH belongs to the NDK.
  # Add the NDK toolchain bin directory to PATH so it finds NDK clang.
  file(GLOB _ndk_toolchain_bins "$ENV{ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/*/bin")
  list(GET _ndk_toolchain_bins 0 _ndk_bin)
  set(ENV{PATH} "${_ndk_bin}:$ENV{PATH}")
  message(STATUS "Android NDK for OpenSSL: $ENV{ANDROID_NDK_HOME}")

endif()

# Ensure all static libraries are built with -fPIC so they can be linked
# into shared libraries (kvsCommonLws, kvsWebrtcClient, etc.).
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# =============================================================================
# Paths
# =============================================================================
set(OPENSSL_SRC_DIR       "${CMAKE_CURRENT_SOURCE_DIR}/openssl")
set(WEBRTC_SDK_SRC_DIR    "${CMAKE_CURRENT_SOURCE_DIR}/amazon-kinesis-video-streams-webrtc-sdk-c")
set(JSMN_SRC_DIR          "${CMAKE_CURRENT_SOURCE_DIR}/jsmn")

# Prefix where OpenSSL (autotools) gets installed.
set(DEPS_INSTALL_PREFIX "${CMAKE_BINARY_DIR}/deps-install" CACHE PATH
    "Install prefix for non-CMake dependencies (OpenSSL)")

include(ProcessorCount)
ProcessorCount(NPROC)
if(NPROC EQUAL 0)
  set(NPROC 1)
endif()

# =============================================================================
# 1. OpenSSL  (autotools – built at configure time via execute_process)
# =============================================================================
if(USE_SYSTEM_OPENSSL)
  find_package(OpenSSL REQUIRED)
  message(STATUS "Using system OpenSSL: ${OPENSSL_VERSION}")
else()
  if(NOT EXISTS "${OPENSSL_SRC_DIR}/Configure")
    message(FATAL_ERROR
      "OpenSSL source not found at ${OPENSSL_SRC_DIR}. "
      "Run: git submodule update --init openssl")
  endif()

  find_program(MAKE_EXE NAMES make gmake)
  set(OPENSSL_BUILD_SRC "${CMAKE_BINARY_DIR}/openssl-build")

  # OpenSSL is built at configure time (not build time) so that
  # find_package(OpenSSL) succeeds for downstream add_subdirectory
  # dependencies (libwebsockets, libsrtp, WebRTC SDK).
  if(NOT EXISTS "${DEPS_INSTALL_PREFIX}/lib/libssl.a")
    message(STATUS "Building OpenSSL from submodule source...")

    execute_process(
        COMMAND ${CMAKE_COMMAND} -E copy_directory
                ${OPENSSL_SRC_DIR} ${OPENSSL_BUILD_SRC}
        RESULT_VARIABLE _result)
    if(NOT _result EQUAL 0)
      message(FATAL_ERROR "Failed to copy OpenSSL source")
    endif()

    set(OPENSSL_EXTRA_FLAGS "")
    if(BUILD_STATIC_LIBS)
      list(APPEND OPENSSL_EXTRA_FLAGS no-shared no-dso)
    endif()
    if(OPENSSL_NO_ASM)
      list(APPEND OPENSSL_EXTRA_FLAGS no-asm)
    endif()

    if(BUILD_OPENSSL_PLATFORM AND NOT BUILD_OPENSSL_PLATFORM STREQUAL "")
      execute_process(
          COMMAND ./Configure ${OPENSSL_EXTRA_FLAGS} no-async
                  --prefix=${DEPS_INSTALL_PREFIX} --openssldir=${DEPS_INSTALL_PREFIX}
                  ${BUILD_OPENSSL_PLATFORM}
          WORKING_DIRECTORY ${OPENSSL_BUILD_SRC}
          RESULT_VARIABLE _result)
    else()
      execute_process(
          COMMAND ./config ${OPENSSL_EXTRA_FLAGS}
                  --prefix=${DEPS_INSTALL_PREFIX} --openssldir=${DEPS_INSTALL_PREFIX}
          WORKING_DIRECTORY ${OPENSSL_BUILD_SRC}
          RESULT_VARIABLE _result)
    endif()
    if(NOT _result EQUAL 0)
      message(FATAL_ERROR "OpenSSL configure failed")
    endif()

    execute_process(
        COMMAND ${MAKE_EXE} -j${NPROC}
        WORKING_DIRECTORY ${OPENSSL_BUILD_SRC}
        RESULT_VARIABLE _result)
    if(NOT _result EQUAL 0)
      message(FATAL_ERROR "OpenSSL build failed")
    endif()

    execute_process(
        COMMAND ${MAKE_EXE} install_sw
        WORKING_DIRECTORY ${OPENSSL_BUILD_SRC}
        RESULT_VARIABLE _result)
    if(NOT _result EQUAL 0)
      message(FATAL_ERROR "OpenSSL install failed")
    endif()

    message(STATUS "OpenSSL built and installed to ${DEPS_INSTALL_PREFIX}")
  endif()

  # Register OpenSSL installed libs as build-time outputs so ninja can
  # regenerate them if deleted (e.g. by Gradle clean).  `make install_sw`
  # also installs headers to deps-install/include/openssl/.
  # add_dependencies (at end of file) ensures all targets that compile
  # against OpenSSL headers wait for this to complete.
  add_custom_command(
      OUTPUT "${DEPS_INSTALL_PREFIX}/lib/libssl.a"
             "${DEPS_INSTALL_PREFIX}/lib/libcrypto.a"
      COMMAND ${MAKE_EXE} install_sw
      WORKING_DIRECTORY "${OPENSSL_BUILD_SRC}"
      COMMENT "Installing OpenSSL to ${DEPS_INSTALL_PREFIX}...")
  add_custom_target(openssl_install ALL
      DEPENDS "${DEPS_INSTALL_PREFIX}/lib/libssl.a"
              "${DEPS_INSTALL_PREFIX}/lib/libcrypto.a")

  set(OPENSSL_ROOT_DIR ${DEPS_INSTALL_PREFIX} CACHE PATH "" FORCE)
  # When cross-compiling (e.g. Android), the toolchain restricts find_library
  # to the sysroot. Add our install prefix so find_package(OpenSSL) works.
  list(APPEND CMAKE_FIND_ROOT_PATH ${DEPS_INSTALL_PREFIX})
  find_package(OpenSSL REQUIRED)
  message(STATUS "Using submodule OpenSSL: ${OPENSSL_VERSION}")
endif()

# =============================================================================
# 2. usrsctp  (add_subdirectory)
# =============================================================================
set(sctp_werror    OFF CACHE BOOL "" FORCE)
set(sctp_build_programs OFF CACHE BOOL "" FORCE)

add_subdirectory(usrsctp)

# Expose usrsctp.h globally – the WebRTC SDK's Include_i.h includes it even in
# targets that don't link against usrsctp (e.g. kvsWebrtcSignalingClient).
include_directories("${CMAKE_CURRENT_SOURCE_DIR}/usrsctp/usrsctplib")

# =============================================================================
# 3. jsmn  (built directly – no patch needed)
# =============================================================================
add_library(jsmn STATIC "${JSMN_SRC_DIR}/jsmn.c" "${JSMN_SRC_DIR}/jsmn.h")
target_include_directories(jsmn PUBLIC "${JSMN_SRC_DIR}")

# =============================================================================
# 4. libwebsockets  (add_subdirectory – only when ENABLE_SIGNALING is ON)
# =============================================================================
if(ENABLE_SIGNALING)
  set(LWS_WITH_HTTP2          ON  CACHE BOOL "" FORCE)
  set(LWS_HAVE_HMAC_CTX_new  ON  CACHE BOOL "" FORCE)
  set(LWS_HAVE_SSL_EXTRA_CHAIN_CERTS ON CACHE BOOL "" FORCE)
  set(LWS_HAVE_OPENSSL_ECDH_H ON CACHE BOOL "" FORCE)
  set(LWS_HAVE_EVP_MD_CTX_free ON CACHE BOOL "" FORCE)
  set(LWS_WITHOUT_SERVER      ON  CACHE BOOL "" FORCE)
  set(LWS_WITHOUT_TESTAPPS    ON  CACHE BOOL "" FORCE)
  set(LWS_WITHOUT_TEST_SERVER_EXTPOLL ON CACHE BOOL "" FORCE)
  set(LWS_WITHOUT_TEST_PING   ON  CACHE BOOL "" FORCE)
  set(LWS_WITHOUT_TEST_CLIENT ON  CACHE BOOL "" FORCE)
  set(LWS_STATIC_PIC          ON  CACHE BOOL "" FORCE)
  set(LWS_WITH_STATIC         ON  CACHE BOOL "" FORCE)
  set(LWS_WITH_SHARED         ON  CACHE BOOL "" FORCE)
  set(LWS_WITH_MBEDTLS        OFF CACHE BOOL "" FORCE)
  set(LWS_WITH_MINIMAL_EXAMPLES OFF CACHE BOOL "" FORCE)
  set(LWS_HAVE_PTHREAD_H      ON  CACHE BOOL "" FORCE)
  set(LWS_WITH_ZLIB           OFF CACHE BOOL "" FORCE)
  set(LWS_HAVE_EVENTFD        OFF CACHE BOOL "" FORCE)
  set(LWS_IPV6                ON  CACHE BOOL "" FORCE)
  set(LWS_WITH_EXPORT_LWSTARGETS OFF CACHE BOOL "" FORCE)
  set(DISABLE_WERROR          ON  CACHE BOOL "" FORCE)

  add_subdirectory(libwebsockets)
endif()

# =============================================================================
# 5. libsrtp  (add_subdirectory)
# =============================================================================
set(ENABLE_OPENSSL     ON  CACHE BOOL "" FORCE)
set(TEST_APPS          OFF CACHE BOOL "" FORCE)

if(NOT USE_SYSTEM_OPENSSL)
  set(OPENSSL_ROOT_DIR ${DEPS_INSTALL_PREFIX} CACHE PATH "" FORCE)
endif()

add_subdirectory(libsrtp)

# libsrtp's source tree has headers at include/srtp.h, but when installed they go
# to include/srtp2/srtp.h. The WebRTC SDK uses #include <srtp2/srtp.h>.
# Create a compatibility include directory mirroring the installed layout.
set(SRTP_COMPAT_INCLUDE "${CMAKE_BINARY_DIR}/srtp-include/srtp2")
file(MAKE_DIRECTORY "${SRTP_COMPAT_INCLUDE}")
file(COPY "${CMAKE_CURRENT_SOURCE_DIR}/libsrtp/include/srtp.h" DESTINATION "${SRTP_COMPAT_INCLUDE}")
file(COPY "${CMAKE_CURRENT_SOURCE_DIR}/libsrtp/crypto/include/auth.h" DESTINATION "${SRTP_COMPAT_INCLUDE}")
file(COPY "${CMAKE_CURRENT_SOURCE_DIR}/libsrtp/crypto/include/cipher.h" DESTINATION "${SRTP_COMPAT_INCLUDE}")
file(COPY "${CMAKE_CURRENT_SOURCE_DIR}/libsrtp/crypto/include/crypto_types.h" DESTINATION "${SRTP_COMPAT_INCLUDE}")
include_directories("${CMAKE_BINARY_DIR}/srtp-include")

# =============================================================================
# 6. googletest  (add_subdirectory – only when BUILD_TEST is ON)
# =============================================================================
# Must come before kvspic and WebRTC SDK so their tests can find GTest.
if(BUILD_TEST)
  set(BUILD_GMOCK OFF CACHE BOOL "" FORCE)
  set(INSTALL_GTEST OFF CACHE BOOL "" FORCE)
  add_subdirectory(googletest)

  # kvspic and the SDK call find_package(GTest REQUIRED).  Provide a custom
  # FindGTest.cmake that recognises the targets already created above,
  # overriding CMake's built-in FindGTest module.
  file(MAKE_DIRECTORY "${CMAKE_BINARY_DIR}/cmake-modules")
  file(WRITE "${CMAKE_BINARY_DIR}/cmake-modules/FindGTest.cmake"
"# Custom FindGTest – targets provided by add_subdirectory(googletest)
set(GTEST_FOUND TRUE)
set(GTest_FOUND TRUE)
set(GTEST_INCLUDE_DIRS \"${CMAKE_CURRENT_SOURCE_DIR}/googletest/googletest/include\")
set(GTEST_INCLUDE_DIR  \"${CMAKE_CURRENT_SOURCE_DIR}/googletest/googletest/include\")
set(GTEST_LIBRARIES    gtest)
set(GTEST_MAIN_LIBRARIES gtest_main)
set(GTEST_LIBRARY      gtest)
set(GTEST_MAIN_LIBRARY gtest_main)
if(NOT TARGET GTest::GTest)
  add_library(GTest::GTest ALIAS gtest)
endif()
if(NOT TARGET GTest::Main)
  add_library(GTest::Main ALIAS gtest_main)
endif()
")
  list(INSERT CMAKE_MODULE_PATH 0 "${CMAKE_BINARY_DIR}/cmake-modules")

  # The WebRTC SDK's tst/CMakeLists.txt uses find_package(GTest PATHS ...)
  # which triggers config mode.  Provide a GTestConfig.cmake too.
  file(WRITE "${CMAKE_BINARY_DIR}/cmake-modules/GTestConfig.cmake"
"set(GTest_FOUND TRUE)
set(GTEST_FOUND TRUE)
")
  file(WRITE "${CMAKE_BINARY_DIR}/cmake-modules/GTestConfigVersion.cmake"
"set(PACKAGE_VERSION \"1.12.1\")
set(PACKAGE_VERSION_COMPATIBLE TRUE)
")
  set(GTest_DIR "${CMAKE_BINARY_DIR}/cmake-modules" CACHE PATH "" FORCE)
endif()

# =============================================================================
# 7. kvspic  (add_subdirectory)
# =============================================================================
# Disable BUILD_DEPENDENCIES globally – all deps are provided by this superbuild.
set(BUILD_DEPENDENCIES FALSE CACHE BOOL "" FORCE)

# Android's bionic libc includes clock_gettime directly – there is no separate
# librt.  kvspic's CMakeLists.txt does `target_link_libraries(kvspic rt)` on
# UNIX && !APPLE, which would fail on Android.  Providing an empty INTERFACE
# target named "rt" makes CMake resolve the name as a target (no-op) instead
# of passing -lrt to the linker.
if(CMAKE_SYSTEM_NAME STREQUAL "Android")
  if(NOT TARGET rt)
    add_library(rt INTERFACE)
  endif()
endif()

# Disable tests for kvspic (its tests use pthread_cancel which Android lacks).
# We only want the WebRTC SDK tests.  Save and restore BUILD_TEST around kvspic.
set(_SAVE_BUILD_TEST ${BUILD_TEST})
set(BUILD_TEST OFF CACHE BOOL "" FORCE)
add_subdirectory(amazon-kinesis-video-streams-pic)
set(BUILD_TEST ${_SAVE_BUILD_TEST} CACHE BOOL "" FORCE)

# Expose kvspic include directories at root level so producer-c and WebRTC SDK
# can find headers like com/amazonaws/kinesis/video/client/Include.h.
set(KVSPIC_SRC_DIR "${CMAKE_CURRENT_SOURCE_DIR}/amazon-kinesis-video-streams-pic")
file(GLOB KVSPIC_INCLUDE_DIRS "${KVSPIC_SRC_DIR}/src/*/include")
include_directories(${KVSPIC_INCLUDE_DIRS})

# Generate a minimal .pc file so producer-c's pkg_check_modules(KVSPIC libkvspicUtils)
# succeeds and it doesn't try to download kvspic itself.
file(MAKE_DIRECTORY "${CMAKE_BINARY_DIR}/pkgconfig")
file(WRITE "${CMAKE_BINARY_DIR}/pkgconfig/libkvspicUtils.pc"
"Name: libkvspicUtils
Description: KVS PIC utils (provided by superbuild)
Version: 1.2.0
Libs: -lkvspicUtils
Cflags:
")

# =============================================================================
# 7b. kvsCommonLws  (add_subdirectory of amazon-kinesis-video-streams-producer-c)
#     Only needed when signaling is enabled.
# =============================================================================
if(ENABLE_SIGNALING)
  set(BUILD_COMMON_LWS    ON    CACHE BOOL "" FORCE)
  set(BUILD_COMMON_CURL   OFF   CACHE BOOL "" FORCE)
  set(BUILD_DEPENDENCIES  FALSE CACHE BOOL "" FORCE)
  set(USE_OPENSSL         ON    CACHE BOOL "" FORCE)
  set(USE_MBEDTLS         OFF   CACHE BOOL "" FORCE)

  # producer-c uses pkg_check_modules for libwebsockets and libkvspicUtils.
  # Point pkg-config at the .pc files generated by libwebsockets and by us.
  set(ENV{PKG_CONFIG_PATH} "${CMAKE_BINARY_DIR}/libwebsockets:${CMAKE_BINARY_DIR}/pkgconfig:$ENV{PKG_CONFIG_PATH}")

  add_subdirectory(amazon-kinesis-video-streams-producer-c)
endif()

# Always expose producer-c's headers for the WebRTC SDK (common/Include.h provides
# base types like AwsCredentialProvider, Tag, etc. needed even without signaling).
include_directories("${CMAKE_CURRENT_SOURCE_DIR}/amazon-kinesis-video-streams-producer-c/src/include")

# =============================================================================
# 8. WebRTC SDK  (add_subdirectory)
# =============================================================================
# Pre-set variables that the SDK's find_library() calls would populate.
# This lets add_subdirectory work without modifying the SDK's CMakeLists.txt.
# find_library stores results in CACHE; pre-setting them skips the search.
set(SRTP_LIBRARIES             srtp2    CACHE STRING "Pre-set by superbuild" FORCE)
set(Usrsctp                    usrsctp  CACHE STRING "Pre-set by superbuild" FORCE)
if(ENABLE_SIGNALING)
  set(LIBWEBSOCKETS_LIBRARIES    websockets CACHE STRING "Pre-set by superbuild" FORCE)
endif()

# The SDK reads OPEN_SRC_INSTALL_PREFIX for link_directories / include_directories.
# Point it at our deps-install where OpenSSL headers/libs live.
set(OPEN_SRC_INSTALL_PREFIX ${DEPS_INSTALL_PREFIX} CACHE PATH "" FORCE)

set(BUILD_SAMPLE          ${BUILD_SAMPLE}          CACHE BOOL "" FORCE)
set(ENABLE_DATA_CHANNEL   ${ENABLE_DATA_CHANNEL}   CACHE BOOL "" FORCE)
set(ENABLE_SIGNALING      ${ENABLE_SIGNALING}      CACHE BOOL "" FORCE)
set(ENABLE_KVS_THREADPOOL ${ENABLE_KVS_THREADPOOL} CACHE BOOL "" FORCE)

add_subdirectory(amazon-kinesis-video-streams-webrtc-sdk-c)

# On Linux, libm is not linked implicitly (unlike macOS).
# kvsWebrtcClient uses math functions (sqrt, pow) but doesn't link -lm.
# On Linux/Android, libm is not linked implicitly (unlike macOS).
# kvsWebrtcClient uses math functions (sqrt, pow) but doesn't link -lm.
if(UNIX AND NOT APPLE)
  target_link_libraries(kvsWebrtcClient PUBLIC m)
endif()

# =============================================================================
# 9. Android JNI Test Library  (shared lib for instrumented tests)
# =============================================================================
if(BUILD_ANDROID_JNI_TEST AND CMAKE_SYSTEM_NAME STREQUAL "Android" AND BUILD_TEST)
  set(WEBRTC_TST_DIR "${WEBRTC_SDK_SRC_DIR}/tst")
  file(GLOB JNI_TEST_SOURCES "${WEBRTC_TST_DIR}/*.cpp")

  # Exclude original main.cpp – replaced by jni_bridge.cpp
  list(FILTER JNI_TEST_SOURCES EXCLUDE REGEX ".*main\\.cpp$")

  # Same signaling filters as tst/CMakeLists.txt
  if(NOT ENABLE_SIGNALING)
    list(FILTER JNI_TEST_SOURCES EXCLUDE REGEX ".*Signaling.*\\.cpp")
    list(FILTER JNI_TEST_SOURCES EXCLUDE REGEX ".*IngestionFunctionalityTests\\.cpp")
    list(FILTER JNI_TEST_SOURCES EXCLUDE REGEX ".*CustomEndpointTest\\.cpp")
    list(FILTER JNI_TEST_SOURCES EXCLUDE REGEX ".*DualStackEndpointsTest\\.cpp")
    list(FILTER JNI_TEST_SOURCES EXCLUDE REGEX ".*TurnConnectionFunctionalityTest\\.cpp")
    list(FILTER JNI_TEST_SOURCES EXCLUDE REGEX ".*IceConfigParsingTest\\.cpp")
  endif()

  add_library(webrtc_test_jni SHARED
    ${JNI_TEST_SOURCES}
    "${CMAKE_CURRENT_SOURCE_DIR}/android-test-app/jni_bridge.cpp")

  # The SDK uses include_directories() (directory-scoped), which doesn't propagate
  # to targets outside its add_subdirectory scope.  Add them explicitly.
  # The gtest-android-override dir is listed BEFORE the real gtest include path so
  # our wrapper gtest/gtest.h is found first; it #include_next's the real header
  # and then redefines EXPECT_DEATH/ASSERT_DEATH to no-ops (death tests use fork()
  # which crashes the JVM in JNI context).
  target_include_directories(webrtc_test_jni BEFORE PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/android-test-app/gtest-android-override")
  target_include_directories(webrtc_test_jni PRIVATE
    "${WEBRTC_SDK_SRC_DIR}"
    "${WEBRTC_SDK_SRC_DIR}/src/include"
    "${DEPS_INSTALL_PREFIX}/include")
  target_compile_definitions(webrtc_test_jni PRIVATE INSTRUMENTED_ALLOCATORS KVS_USE_OPENSSL)

  # Resolve gtest target name (same logic as tst/CMakeLists.txt)
  set(_JNI_GTEST GTest::gtest)
  if(TARGET GTest::GTest)
    set(_JNI_GTEST GTest::GTest)
  endif()

  if(ENABLE_SIGNALING)
    target_link_libraries(webrtc_test_jni
      kvsWebrtcClient kvsWebrtcSignalingClient kvsCommonLws
      ${OPENSSL_CRYPTO_LIBRARY} kvspicUtils ${_JNI_GTEST} log)
  else()
    target_link_libraries(webrtc_test_jni
      kvsWebrtcClient ${OPENSSL_CRYPTO_LIBRARY} kvspicUtils ${_JNI_GTEST} log)
  endif()
endif()

# =============================================================================
# Build-order: OpenSSL install must complete before any target that uses its
# headers or libraries.  add_dependencies is NOT transitive through
# target_link_libraries, so every target that directly #includes OpenSSL
# headers needs an explicit dependency.
# =============================================================================
if(TARGET openssl_install)
  add_dependencies(srtp2 openssl_install)
  add_dependencies(kvsWebrtcClient openssl_install)
  if(TARGET websockets)
    add_dependencies(websockets openssl_install)
  endif()
  if(TARGET webrtc_client_test)
    add_dependencies(webrtc_client_test openssl_install)
  endif()
  if(TARGET webrtc_test_jni)
    add_dependencies(webrtc_test_jni openssl_install)
  endif()
  if(TARGET kvsCommonLws)
    add_dependencies(kvsCommonLws openssl_install)
  endif()
endif()
