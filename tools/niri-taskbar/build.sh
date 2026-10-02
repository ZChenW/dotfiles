#!/usr/bin/env bash
# Build the pinned upstream plugin plus our fixed-icon-size patch.
# No live installation: copy the resulting library only after running the test.
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
build_dir="${1:?usage: build.sh EMPTY_BUILD_DIRECTORY}"
revision=c530349fae638141ec58a9d4db0816d950a9295a
archive_sha=cc772b7caf80ec0dc8375b43e3aa1413cca5136ef1cc3f7685c67cadf26f327d
mkdir -p "$build_dir"
build_dir="$(cd -- "$build_dir" && pwd)"
if [[ -e "$build_dir/source" ]]; then
    echo "Refusing to overwrite existing source: $build_dir/source" >&2
    exit 1
fi
curl --fail --location --max-time 60 \
    "https://codeload.github.com/LawnGnome/niri-taskbar/tar.gz/$revision" \
    -o "$build_dir/upstream.tar.gz"
printf '%s  %s\n' "$archive_sha" "$build_dir/upstream.tar.gz" | sha256sum --check
mkdir "$build_dir/source"
tar -xzf "$build_dir/upstream.tar.gz" --strip-components=1 -C "$build_dir/source"
patch -d "$build_dir/source" -p1 < "$script_dir/fixed-icon-size.patch"
cargo build --release --locked -j "${TASKBAR_BUILD_JOBS:-4}" \
    --manifest-path "$build_dir/source/Cargo.toml"
printf 'Built: %s\n' "$build_dir/source/target/release/libniri_taskbar.so"
