#!/bin/bash
# Compile the checked-in MSL; Node and the shader translator are not build dependencies.
set -euo pipefail
cd "$(dirname "$0")/.."
destination="${1:-build/metal-shaders}"
mkdir -p "$destination" build/metal-module-cache
metal="${METAL_COMPILER:-$(xcrun --find metal)}"
metallib="$(dirname "$metal")/metallib"
if [[ ! -x "$metal" || ! -x "$metallib" ]]; then
    printf 'The Xcode Metal Toolchain is required to compile Ocean.\n' >&2
    exit 1
fi
python3 scripts/generate-metal.py --check
for source in Resources/Metal/*.metal; do
    name="$(basename "$source" .metal)"
    "$metal" -std=macos-metal2.4 -fmodules-cache-path="$PWD/build/metal-module-cache" \
        -Wno-unused-variable -Wno-unused-const-variable -c "$source" -o "$destination/$name.air"
    "$metallib" "$destination/$name.air" -o "$destination/$name.metallib"
    rm "$destination/$name.air"
done
cp Resources/Metal/Bindings.json "$destination/Bindings.json"
printf 'Compiled 21 native Metal shader libraries in %s\n' "$destination"
