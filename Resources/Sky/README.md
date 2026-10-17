# Real all-sky star atlas

`starmap_2020_4k_srgb.png` derives from NASA SVS's
[Deep Star Maps 2020](https://svs.gsfc.nasa.gov/4851/), by Ernie Wright.
The catalog-based atlas contains actual stars and the Milky Way; it is not a
procedural or AI-generated sky. Its source catalogs include Hipparcos-2,
Tycho-2, and Gaia DR2.

Credit: NASA/Goddard Space Flight Center Scientific Visualization Studio.
Gaia DR2: ESA/Gaia/DPAC.

The [NASA media usage guidelines](https://www.nasa.gov/nasa-brand-center/images-and-media/)
govern reuse. NASA identifies computer graphical simulations among the permitted
uses and requests source acknowledgement. This project implies no NASA endorsement.
The image has no NASA logos or constellation overlays.

## Coordinates and sampling

The original celestial atlas uses ICRF/J2000 geocentric right ascension and
declination in an equirectangular projection. It is 4096 by 2048 pixels.
Right ascension zero lies at the horizontal center and increases to the left.
Declination +90° is at the top, zero at the middle, and −90° at the bottom.

For right ascension `ra` and declination `dec` in radians:

```text
u = fract(0.5 - ra / (2 * pi))
v = 0.5 - dec / pi
```

Load using a top-left origin. Repeat U and clamp V. Do not flip the image.
The conversion retains every source pixel in place. Bright-star spot checks
at Sirius, Canopus, Arcturus, Vega, and Polaris confirm the mapping.

## Encoding and reproduction

The source is RGB half-float linear OpenEXR. Its decoded channel values are
within [0,1]. The bundled RGB8 PNG applies the standard sRGB transfer function
and nearest-integer quantization only. There is no exposure adjustment, tone
mapping, resizing, rotation, or compositing. Use sRGB texture decoding to
recover linear samples for lighting. The PNG has 14,602,839 bytes.

Verified native load: `MTKTextureLoader` with `SRGB: true`, `origin: topLeft`,
and generated mipmaps produces a 4096×2048 `bgra8Unorm_srgb` texture with 13 mip levels.

`prepare-texture.sh` reproduces the conversion. OpenEXR, ImageMagick, a C++17
compiler, and pkg-config are development-only conversion tools; the app needs
none of them at runtime. Source URL and checksums are in `metadata.json`.
