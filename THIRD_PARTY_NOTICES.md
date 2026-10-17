# Third-party notices

The ocean renderer in `Resources/Web/js/` is adapted from [Noniv/web-ocean](https://github.com/Noniv/web-ocean), commit `a07c7fd522ef0a897601c114f927a49d93d95520`.

Copyright (c) 2026 Maksymilian Dendura. Used under the MIT License; the full license is preserved in `Resources/Web/LICENSE` and both built bundles.

The port retains the original six-cascade Tessendorf FFT waves, CDLOD surface, foam, atmosphere, reflections, bloom and tone mapping. Cloud rendering is removed. The WGSL shaders are translated to checked-in Metal Shading Language in `Resources/Metal/`, and the original CPU uniform packing and CDLOD selection are ported to Swift. Changes add astronomical lunar illumination and star reflections, remove interactive controls and network debugging, cap rendering resolution/frame rate, support small previews and correct direct illumination below the horizon.

Shader translation uses the development-only `naga-wasi-cli` 0.1.0 tool, based on [Naga](https://github.com/gfx-rs/wgpu/tree/trunk/naga). The normal build compiles the checked-in Metal source and needs no translator or external runtime dependency. `Resources/Metal/Bindings.json` pins the translator archive integrity and source/output hashes.

Solar geometry implements the published [NOAA equations](https://gml.noaa.gov/grad/solcalc/calcdetails.html) and is checked against the [NREL SPA reference example](https://docs.nrel.gov/docs/fy08osti/34302.pdf). The system IANA time-zone table supplies an explicitly approximate initial location until configured.

The real all-sky atlas derives from [Deep Star Maps 2020](https://svs.gsfc.nasa.gov/4851/) by Ernie Wright. Credit: NASA/Goddard Space Flight Center Scientific Visualization Studio. Gaia DR2: ESA/Gaia/DPAC. See `Resources/Sky/README.md` and `metadata.json` for source catalogs, mapping, checksums and reproduction. No NASA or ESA endorsement is implied.

Lunar astronomy implements Meeus periodic models and is validated against public [NASA/JPL Horizons](https://ssd.jpl.nasa.gov/horizons/) DE441 topocentric ephemerides and NASA phase dates. No ephemeris or location service is contacted at rendering time.
