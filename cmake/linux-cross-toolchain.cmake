# Cross-compiles the Linux engine with an Ubuntu GNU cross toolchain.
#
# The package architecture is passed as NUVIO_LINUX_TARGET_ARCH. Compiling runs
# at native speed on the build machine; the test suite is executed through the
# user-mode emulator the caller sets as CMAKE_CROSSCOMPILING_EMULATOR.

set(CMAKE_SYSTEM_NAME Linux)
list(APPEND CMAKE_TRY_COMPILE_PLATFORM_VARIABLES NUVIO_LINUX_TARGET_ARCH)

if(NOT DEFINED NUVIO_LINUX_TARGET_ARCH)
    message(FATAL_ERROR "NUVIO_LINUX_TARGET_ARCH must select aarch64 or x86_64")
endif()

if(NOT NUVIO_LINUX_TARGET_ARCH MATCHES "^(aarch64|x86_64)$")
    message(FATAL_ERROR "unsupported Linux architecture: ${NUVIO_LINUX_TARGET_ARCH}")
endif()

set(CMAKE_SYSTEM_PROCESSOR "${NUVIO_LINUX_TARGET_ARCH}")

set(NUVIO_LINUX_TARGET_TRIPLE "${NUVIO_LINUX_TARGET_ARCH}-linux-gnu")
set(CMAKE_C_COMPILER "${NUVIO_LINUX_TARGET_TRIPLE}-gcc")
set(CMAKE_CXX_COMPILER "${NUVIO_LINUX_TARGET_TRIPLE}-g++")
set(CMAKE_AR "${NUVIO_LINUX_TARGET_TRIPLE}-ar")
set(CMAKE_RANLIB "${NUVIO_LINUX_TARGET_TRIPLE}-ranlib")
set(CMAKE_STRIP "${NUVIO_LINUX_TARGET_TRIPLE}-strip")

# Host tools stay off the target sysroot. Libraries and headers may also come
# from the pinned dependency prefixes the build passes in explicitly.
set(CMAKE_FIND_ROOT_PATH "/usr/${NUVIO_LINUX_TARGET_TRIPLE}")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY BOTH)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE BOTH)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE BOTH)
