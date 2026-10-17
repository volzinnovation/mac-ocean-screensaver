# Screenshot captures

The four ocean views were captured from the native Metal renderer in Ocean 1.2.0 at **52.52° N, 13.405° E** (Berlin example coordinates). Each image is 1920 × 1080 pixels. They use the renderer's normal exposure and camera; no image adjustments were applied.

| Image | UTC instant | View |
| --- | --- | --- |
| `day.png` | `2026-10-17T13:30:00Z` | Sun at 19.47° geometric elevation |
| `sunrise.png` | `2026-10-17T05:45:00Z` | Rising Sun at 0.60° geometric elevation |
| `sunset.png` | `2026-10-17T16:00:00Z` | Setting Sun at 0.25° geometric elevation |
| `night.png` | `2024-04-12T21:00:00Z` | Crescent Moon at 18.98° elevation, 21% illuminated |

After `make build`, reproduce a view from the repository root by substituting the UTC instant from the table:

```sh
"build/Ocean Settings.app/Contents/MacOS/OceanSettings" \
  --snapshot "$PWD/build/day.png" \
  --date 2026-10-17T13:30:00Z \
  --latitude 52.52 --longitude 13.405 \
  --width 1280 --height 720
```

The captured pixel size also depends on display scale and rendering quality. These captures used Balanced quality on a Retina display. The astronomical view is reproducible; wave animation may differ between runs. Diagnostic arguments do not change saved coordinates or time settings.

`settings.png` shows the unmodified native settings window with isolated manual example coordinates for Berlin and Balanced quality. It contains no personal location data. The window was captured through macOS; no location permission was requested and the user's settings were not changed.

The sky atlas in the night view is credited to NASA/Goddard Space Flight Center Scientific Visualization Studio; Gaia DR2: ESA/Gaia/DPAC. See [third-party notices](../../THIRD_PARTY_NOTICES.md).
