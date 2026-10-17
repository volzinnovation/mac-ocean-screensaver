# Ocean screensaver

This project is a native macOS 26 Metal screensaver porting the MIT-licensed Noniv/web-ocean renderer. Keep the renderer faithful to the upstream simulation and retain its license and attribution. Never embed WKWebView in the saver: macOS 26.4+ breaks web-content layers in the actual legacy host.

## Project map

- `Sources/ScreenSaver`: ScreenSaverView entry point and Options sheet.
- `Sources/Settings`: native preview/settings app and diagnostic capture host.
- `Sources/Shared`: solar geometry, settings/location, native Metal scene and CPU state.
- `Resources/Metal`: generated, checked-in MSL and shader binding metadata.
- `Resources/Web/js`: editable renderer and shader sources.
- `Resources/Web/index.html`: minimal scene shell, no HUD or instructions.
- `Resources/*Info.plist`: native bundle metadata.
- `Tests`: deterministic solar/preferences tests and native bundle smoke host.
- `scripts`: bundling, universal build, tests.
- `build`: ignored generated bundles, binaries, caches, screenshots. Regenerate these from source.

## Product invariants

- Face the Sun's azimuth by day and the Moon's after standard sunset (Sun below −0.833°). Use actual signed elevations, topocentric lunar phase and the correctly rotated J2000 sky. Never lift a below-horizon Moon.
- No clouds in any mode. Preserve real measured stars and Milky Way geometry and NASA/Gaia attribution.
- No on-screen instructions, keyboard controls, or HUD in the screensaver.
- Never prompt for location from the locked-screen host. Use the settings app.
- Keep coordinates local. No renderer network dependencies.
- Settings app writes only its own ordinary Application Support JSON. Saver reads the newest valid local/canonical document. Never mirror into another app's protected container from the helper.
- Stop GPU submission and release rendering resources when the screensaver stops.

## Checks

- `make test`: deterministic solar, persistence, original CPU-state parity, and generated-shader checks.
- `make build`: universal arm64/x86_64 bundles, plist validation, local ad-hoc signature verification.
- `./scripts/smoke-test.sh`: logged-in Mac/WindowServer required; loads built saver, exercises 36 seconds of native rendering/resizing/stop/restart. No installation or preferences changes. This does not replace an actual macOS full-screen host test.
- For UI changes, inspect a native rendered screenshot.

## Git and installation

The repository is `volzinnovation/mac-ocean-screensaver`. Discover its default branch from the remote instead of assuming a branch name. Commit, push, or open PRs only when requested. Preserve the upstream Git history, MIT license and attribution. Keep generated bundles and local settings out of Git; publish approved distribution archives as GitHub release assets. Never merge, install/select a screensaver, deploy, publish, or delete branches without explicit user approval.
