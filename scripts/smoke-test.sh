#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ ! -f build/Ocean.saver/Contents/MacOS/OceanScreenSaver ]]; then
    printf 'Build Ocean.saver first with scripts/build.sh.\n' >&2
    exit 1
fi
dependencies="$(/usr/bin/otool -L build/Ocean.saver/Contents/MacOS/OceanScreenSaver)"
if [[ "$dependencies" == *"/WebKit.framework/"* ]]; then
    printf 'The saver still links WebKit; rebuild the native Metal bundle first.\n' >&2
    exit 1
fi
printf 'Verified: screensaver has no WebKit framework dependency.\n'
python3 - <<'PY_CLOUDLESS'
from pathlib import Path
import re
for name in ('sky', 'ocean'):
    source = Path(f'Resources/Web/js/wgsl/{name}.js').read_text()
    assert not re.search(r'\b(cloudLayers|cloudFbm|hitLayer|lowEdge|highEdge)\b', source), f'Cloud renderer remains in {name}'
print('Verified: cloud rendering functions and calls are absent in day and night shaders.')
PY_CLOUDLESS
host="$PWD/build/ScreenSaverSmoke.app"
mkdir -p "$host/Contents/MacOS" build/module-cache
cat > "$host/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.ocean.smoke</string>
<key>CFBundleName</key><string>Ocean Screensaver Verification</string>
<key>CFBundleExecutable</key><string>ScreenSaverHost</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
</dict></plist>
PLIST
xcrun swiftc -swift-version 5 -parse-as-library -module-cache-path "$PWD/build/module-cache" \
    -framework AppKit -framework ScreenSaver \
    Tests/ScreenSaverHost.swift -o "$host/Contents/MacOS/ScreenSaverHost"
"$host/Contents/MacOS/ScreenSaverHost" "$PWD/build/Ocean.saver" "$PWD/build/screensaver-preview.png"
