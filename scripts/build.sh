#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/module-cache
python3 scripts/bundle-renderer.py build/ocean.html
./scripts/compile-metal.sh build/metal-shaders
saver="build/Ocean.saver"
app="build/Ocean Settings.app"
mkdir -p "$saver/Contents/MacOS" "$saver/Contents/Resources" "$app/Contents/MacOS" "$app/Contents/Resources"
sdk="$(xcrun --sdk macosx --show-sdk-path)"
architectures="${ARCHS:-arm64 x86_64}"
for architecture in $architectures; do
    common=(-swift-version 5 -O -sdk "$sdk" -target "$architecture-apple-macosx26.0" -module-cache-path "$PWD/build/module-cache" -framework AppKit -framework Metal -framework MetalKit -framework QuartzCore -framework ScreenSaver -framework CoreLocation)
    shared=(Sources/Shared/SolarPosition.swift Sources/Shared/LunarPosition.swift Sources/Shared/CelestialUniforms.swift Sources/Shared/OceanPreferences.swift Sources/Shared/OceanFrameState.swift Sources/Shared/OceanMetalRenderer.swift Sources/Shared/OceanMetalView.swift)
    xcrun swiftc "${common[@]}" -emit-library -module-name OceanScreenSaver "${shared[@]}" Sources/ScreenSaver/OceanScreenSaverView.swift -o "build/saver-$architecture"
    xcrun swiftc "${common[@]}" -parse-as-library "${shared[@]}" Sources/Shared/SettingsWindowController.swift Sources/Shared/LocationRefreshService.swift Sources/Settings/AppMain.swift -o "build/settings-$architecture"
done
saver_inputs=()
app_inputs=()
for architecture in $architectures; do
    saver_inputs+=("build/saver-$architecture")
    app_inputs+=("build/settings-$architecture")
done
xcrun lipo -create "${saver_inputs[@]}" -output "$saver/Contents/MacOS/OceanScreenSaver"
xcrun lipo -create "${app_inputs[@]}" -output "$app/Contents/MacOS/OceanSettings"
cp Resources/ScreenSaver-Info.plist "$saver/Contents/Info.plist"
cp Resources/Settings-Info.plist "$app/Contents/Info.plist"
for resource_dir in "$app/Contents/Resources" "$saver/Contents/Resources"; do
    mkdir -p "$resource_dir/Metal"
    cp build/metal-shaders/*.metallib build/metal-shaders/Bindings.json "$resource_dir/Metal/"
    mkdir -p "$resource_dir/Sky"
    cp Resources/Sky/starmap_2020_4k_srgb.png Resources/Sky/README.md Resources/Sky/metadata.json "$resource_dir/Sky/"
    cp build/ocean.html "$resource_dir/ocean.html"
    cp Resources/Web/LICENSE "$resource_dir/LICENSE-web-ocean.txt"
    cp THIRD_PARTY_NOTICES.md "$resource_dir/THIRD_PARTY_NOTICES.md"
done
# Sign the nested app before its containing screen saver. Ad-hoc signing is local only.
codesign --force --sign - "$app"
ditto "$app" "$saver/Contents/Resources/Ocean Settings.app"
codesign --force --sign - "$saver"
plutil -lint "$saver/Contents/Info.plist" "$app/Contents/Info.plist"
codesign --verify --deep --strict "$saver"
if otool -L "$saver/Contents/MacOS/OceanScreenSaver" "$app/Contents/MacOS/OceanSettings" | grep -q WebKit; then
    printf 'Native Ocean must not link WebKit.\n' >&2
    exit 1
fi
ditto -c -k --sequesterRsrc --keepParent "$saver" build/Ocean.saver.zip
printf 'Built %s and %s\n' "$saver" "$app"
