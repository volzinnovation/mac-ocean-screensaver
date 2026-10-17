#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/module-cache
xcrun swiftc -swift-version 5 -module-cache-path "$PWD/build/module-cache" Sources/Shared/SolarPosition.swift Tests/SolarPositionTests.swift -o build/solar-tests
build/solar-tests
xcrun swiftc -O -swift-version 5 -module-cache-path "$PWD/build/module-cache" Sources/Shared/SolarPosition.swift Sources/Shared/LunarPosition.swift Tests/LunarPositionTests.swift -o build/lunar-tests
build/lunar-tests
xcrun swiftc -swift-version 5 -module-cache-path "$PWD/build/module-cache" Sources/Shared/SolarPosition.swift Sources/Shared/OceanPreferences.swift Tests/PreferencesTests.swift -o build/preferences-tests
build/preferences-tests
xcrun swiftc -O -swift-version 5 -module-cache-path "$PWD/build/module-cache" Sources/Shared/SolarPosition.swift Sources/Shared/OceanFrameState.swift Tests/FrameStateTests.swift -o build/frame-state-tests
build/frame-state-tests
xcrun swiftc -O -swift-version 5 -module-cache-path "$PWD/build/module-cache" Sources/Shared/SolarPosition.swift Sources/Shared/LunarPosition.swift Sources/Shared/CelestialUniforms.swift Sources/Shared/OceanFrameState.swift Tests/CelestialSceneTests.swift -o build/celestial-scene-tests
build/celestial-scene-tests
python3 scripts/generate-metal.py --check
python3 scripts/bundle-renderer.py build/ocean.html
python3 - <<'PY'
from pathlib import Path
import re
page = Path('build/ocean.html').read_text()
assert '<script type="module" src=' not in page
assert not re.search(r'^import .* from ', page, re.M)
assert 'requestPointerLock' not in page
assert "fetch(" not in page
assert 'KeyW' not in page
assert 'KeyH' not in page
print('Self-contained renderer checks passed (no network, key bindings, or external scripts)')
PY
