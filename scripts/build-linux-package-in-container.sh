#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 x86_64|aarch64" >&2
    exit 2
fi
target_architecture=$1
case "$target_architecture" in
    x86_64 | aarch64) ;;
    *) echo "usage: $0 x86_64|aarch64" >&2; exit 2 ;;
esac
if [[ "$(uname -s)" != Linux ]]; then
    echo "this build must run in a Linux container" >&2
    exit 2
fi
host_architecture=$(uname -m)

# The build machine's own architecture is compiled and tested natively. Any
# other architecture is cross-compiled with the GNU toolchain and exercised
# under the matching user-mode emulator: compiling libtorrent, Boost, and
# OpenSSL stays at native speed and only the test suite runs emulated.
cross_prefix=""
target_sysroot=""
emulator=()
if [[ "$target_architecture" != "$host_architecture" ]]; then
    cross_prefix="$target_architecture-linux-gnu-"
    target_sysroot="/usr/$target_architecture-linux-gnu"
    emulator=("/usr/bin/qemu-$target_architecture-static" "-L" "$target_sysroot")
    for tool in "${cross_prefix}gcc" "${cross_prefix}g++" "${cross_prefix}strip" "${emulator[0]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            echo "missing cross build tool: $tool" >&2
            exit 2
        fi
    done
    if [[ ! -d "$target_sysroot" ]]; then
        echo "missing target sysroot: $target_sysroot" >&2
        exit 2
    fi
fi
c_compiler=${cross_prefix:+${cross_prefix}gcc}
c_compiler=${c_compiler:-cc}
cxx_compiler=${cross_prefix:+${cross_prefix}g++}
cxx_compiler=${cxx_compiler:-g++}

engine_root=/source
dependency_root="$engine_root/platform/linux/.deps"
build_root="$engine_root/platform/linux/build/$target_architecture"
distribution_root="$engine_root/platform/linux/dist"
package_name="nuvio-engine-linux-$target_architecture"
stage="$build_root/package/$package_name"
openssl_root="$dependency_root/openssl/install/$target_architecture"
boost_source="$dependency_root/sources/boost_1_86_0"
libtorrent_source="$dependency_root/sources/libtorrent-2.0.12"
jobs=${NUVIO_BUILD_JOBS:-$(nproc)}
if (( jobs > 8 )); then
    jobs=8
fi

"$engine_root/scripts/prepare-native-dependencies.sh" "$dependency_root"
"$engine_root/scripts/build-linux-openssl.sh" "$dependency_root" "$target_architecture"
mkdir -p "$build_root" "$distribution_root"

cross_arguments=()
if [[ -n "$cross_prefix" ]]; then
    cross_arguments=(
        -DCMAKE_TOOLCHAIN_FILE="$engine_root/cmake/linux-cross-toolchain.cmake"
        -DNUVIO_LINUX_TARGET_ARCH="$target_architecture"
        -DCMAKE_CROSSCOMPILING_EMULATOR="$(IFS=';'; printf '%s' "${emulator[*]}")"
    )
fi

configure_log="$build_root/configure.log"
build_log="$build_root/build.log"
if ! cmake \
    -S "$engine_root" \
    -B "$build_root" \
    -G Ninja \
    "${cross_arguments[@]}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_FLAGS='-ffile-prefix-map=/source/platform/linux/.deps=/nuvio-engine/dependencies -ffile-prefix-map=/source=/nuvio-engine/source' \
    -DCMAKE_CXX_FLAGS='-ffile-prefix-map=/source/platform/linux/.deps=/nuvio-engine/dependencies -ffile-prefix-map=/source=/nuvio-engine/source' \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DNUVIO_ENGINE_BUILD_SHARED=ON \
    -DNUVIO_ENGINE_BUILD_TESTS=ON \
    -DNUVIO_ENGINE_ENABLE_LIBTORRENT=ON \
    -DOPENSSL_ROOT_DIR="$openssl_root" \
    -DOPENSSL_INCLUDE_DIR="$openssl_root/include" \
    -DOPENSSL_SSL_LIBRARY="$openssl_root/lib/libssl.a" \
    -DOPENSSL_CRYPTO_LIBRARY="$openssl_root/lib/libcrypto.a" \
    -DOPENSSL_USE_STATIC_LIBS=TRUE \
    -DFETCHCONTENT_SOURCE_DIR_NUVIO_BOOST="$boost_source" \
    -DFETCHCONTENT_SOURCE_DIR_NUVIO_LIBTORRENT="$libtorrent_source" \
    >"$configure_log" 2>&1; then
    cat "$configure_log" >&2
    exit 1
fi
if ! cmake --build "$build_root" --parallel "$jobs" >"$build_log" 2>&1; then
    cat "$build_log" >&2
    exit 1
fi
ctest --test-dir "$build_root" --output-on-failure

engine_version=$(sed -n 's/^CMAKE_PROJECT_VERSION:STATIC=//p' "$build_root/CMakeCache.txt")
if [[ ! "$engine_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "could not resolve the configured engine version" >&2
    exit 1
fi
engine_soversion=${engine_version%%.*}
library_name="libnuvio_engine.so.$engine_version"
if [[ ! -f "$build_root/$library_name" ]]; then
    echo "built shared library is missing: $build_root/$library_name" >&2
    exit 1
fi

cmake -E remove_directory "$build_root/package"
mkdir -p "$stage/lib" "$stage/include/nuvio_engine" "$stage/licenses"
cp "$build_root/$library_name" "$stage/lib/$library_name"
"${cross_prefix}strip" --strip-unneeded "$stage/lib/$library_name"
ln -s "$library_name" "$stage/lib/libnuvio_engine.so.$engine_soversion"
ln -s "libnuvio_engine.so.$engine_soversion" "$stage/lib/libnuvio_engine.so"
cp "$engine_root/include/nuvio_engine/nuvio_engine.h" "$stage/include/nuvio_engine/"
cp "$engine_root/include/nuvio_engine/export.h" "$stage/include/nuvio_engine/"
cp "$engine_root/LICENSE" "$stage/licenses/NUVIO-ENGINE-LICENSE.txt"
cp "$engine_root/THIRD_PARTY_NOTICES.md" "$stage/licenses/THIRD_PARTY_NOTICES.md"
cp "$libtorrent_source/LICENSE" "$stage/licenses/LIBTORRENT-LICENSE.txt"
cp "$libtorrent_source/COPYING" "$stage/licenses/LIBTORRENT-COPYING.txt"
cp "$libtorrent_source/deps/try_signal/LICENSE" "$stage/licenses/TRY_SIGNAL-LICENSE.txt"
cp "$boost_source/LICENSE_1_0.txt" "$stage/licenses/BOOST-LICENSE_1_0.txt"
cp "$dependency_root/sources/openssl-3.5.7/LICENSE.txt" "$stage/licenses/OPENSSL-LICENSE.txt"
cp "$engine_root/README.md" "$stage/README.md"

# A cross toolchain reports the glibc it compiles against through its own
# headers; the build machine's ldd would describe the wrong architecture.
if [[ -n "$cross_prefix" ]]; then
    target_glibc_version=$(
        printf '#include <features.h>\nNUVIO_GLIBC __GLIBC__ __GLIBC_MINOR__\n' \
            | "$c_compiler" -E -P -xc - \
            | awk '$1 == "NUVIO_GLIBC" { print $2 "." $3 }'
    )
else
    target_glibc_version=$(ldd --version | awk 'NR == 1 { print $NF }')
fi
if [[ ! "$target_glibc_version" =~ ^[0-9]+\.[0-9]+$ ]]; then
    echo "could not resolve the target glibc version" >&2
    exit 1
fi

cat > "$stage/BUILD-INFO.txt" <<EOF
Nuvio Engine: $engine_version
Target: Linux $target_architecture
Minimum glibc: 2.35
Libtorrent: 2.0.12 commit 740a0b9aeabe00e762cc0efe4a0f27593db2550b
Boost: 1.86.0 sha256 1bed88e40401b2cb7a1f76d4bab499e352fa4d0c5f31c0dbae64e24d34d7513b
OpenSSL: 3.5.7 sha256 a8c0d28a529ca480f9f36cf5792e2cd21984552a3c8e4aa11a24aa31aeac98e8
Builder: Ubuntu 22.04
Builder base: ubuntu:22.04@sha256:0e0a0fc6d18feda9db1590da249ac93e8d5abfea8f4c3c0c849ce512b5ef8982
Toolchain: ${cross_prefix:-native} ($host_architecture host)
GCC: $("$cxx_compiler" -dumpfullversion -dumpversion)
CMake: $(cmake --version | awk 'NR == 1 { print $3 }')
glibc: $target_glibc_version
EOF

smoke="$build_root/package-smoke"
"$c_compiler" \
    "$engine_root/tests/c_api_smoke.c" \
    -I "$stage/include" \
    -L "$stage/lib" \
    -lnuvio_engine \
    -Wl,-rpath,"$stage/lib" \
    -o "$smoke"
"${emulator[@]}" "$smoke"

archive="$distribution_root/$package_name.tar.gz"
tar \
    --sort=name \
    --mtime='@0' \
    --owner=0 \
    --group=0 \
    --numeric-owner \
    -C "$build_root/package" \
    -cf - \
    "$package_name" \
    | gzip -n > "$archive"
(
    cd "$distribution_root"
    sha256sum "$(basename "$archive")" > "$(basename "$archive").sha256"
)

"$engine_root/scripts/verify-linux-package-in-container.sh" \
    "$archive" \
    "$target_architecture"

echo "created $archive"
