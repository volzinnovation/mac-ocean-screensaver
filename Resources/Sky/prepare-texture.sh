#!/bin/bash
set -euo pipefail
sky_source_directory="$(cd "$(dirname "$0")" && pwd)"
sky_temporary_directory="$(mktemp -d)"
trap 'rm -rf "$sky_temporary_directory"' EXIT
curl --fail --location --retry 2 \
    https://svs.gsfc.nasa.gov/vis/a000000/a004800/a004851/starmap_2020_4k.exr \
    --output "$sky_temporary_directory/source.exr"
printf '69b841cd048c2ef35543eb1c5819b322530e78aa4b0cab97ec1de3ef56a4ddcd  %s/source.exr\n' \
    "$sky_temporary_directory" | shasum -a 256 -c -
# pkg-config supplies compiler flags for the already-installed OpenEXR toolchain.
c++ -O2 -std=c++17 "$sky_source_directory/export-starmap.cpp" \
    $(pkg-config --cflags --libs OpenEXR) -o "$sky_temporary_directory/export-starmap"
"$sky_temporary_directory/export-starmap" "$sky_temporary_directory/source.exr" \
    "$sky_temporary_directory/starmap.ppm"
magick "$sky_temporary_directory/starmap.ppm" -set colorspace sRGB -intent perceptual \
    -depth 8 -define png:color-type=2 -define png:exclude-chunk=date,time \
    "$sky_source_directory/starmap_2020_4k_srgb.png"
shasum -a 256 "$sky_source_directory/starmap_2020_4k_srgb.png"
