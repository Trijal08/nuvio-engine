#!/usr/bin/env bash
set -euo pipefail

script_directory=$(cd "$(dirname "$0")" && pwd -P)
engine_root=$(cd "$script_directory/.." && pwd -P)
dockerfile_root="$engine_root/platform/linux"
distribution_root="$dockerfile_root/dist"

if ! docker info >/dev/null 2>&1; then
    echo "Docker must be running to build Linux packages" >&2
    exit 2
fi

# Both packages are built in a container that matches the build machine, so
# the architecture that is not native is cross-compiled rather than emulated.
# Only its test suite runs under the user-mode emulator.
host_platform=$(docker version --format '{{.Server.Arch}}' 2>/dev/null || true)
case "$host_platform" in
    amd64 | arm64) ;;
    *)
        case "$(uname -m)" in
            x86_64) host_platform=amd64 ;;
            aarch64 | arm64) host_platform=arm64 ;;
            *) echo "unsupported build machine: $(uname -m)" >&2; exit 2 ;;
        esac
        ;;
esac

mkdir -p "$distribution_root"
for target_architecture in x86_64 aarch64; do
    docker build \
        --platform "linux/$host_platform" \
        --build-arg "NUVIO_LINUX_ARCH=$target_architecture" \
        --file "$dockerfile_root/Dockerfile" \
        --target artifact \
        --output "type=local,dest=$distribution_root" \
        "$engine_root"
done

echo "created Linux x86_64 and aarch64 packages in platform/linux/dist"
