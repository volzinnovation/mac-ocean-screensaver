// Generated from Resources/Web/js/wgsl by scripts/generate-metal.py.
// Original ocean renderer: Noniv/web-ocean, MIT; see THIRD_PARTY_NOTICES.md.
// Edit the WGSL source and regenerate; native builds use this vendored MSL.
// language: metal2.4
#include <metal_stdlib>
#include <simd/simd.h>

using metal::uint;


struct main_Input {
};
kernel void main_(
  metal::uint3 id [[thread_position_in_grid]]
, metal::texture2d<float, metal::access::sample> src [[texture(0)]]
, metal::texture2d<float, metal::access::write> dst [[texture(1)]]
) {

    metal::uint2 size = metal::uint2(dst.get_width(), dst.get_height());
    if ((id.x >= size.x) || (id.y >= size.y)) {
        return;
    }
    metal::int2 p = static_cast<metal::int2>(id.xy) * 2;
    metal::float4 _e16 = src.read(metal::uint2(p), 0);
    metal::float4 _e23 = src.read(metal::uint2(p + metal::int2(1, 0)), 0);
    metal::float4 _e31 = src.read(metal::uint2(p + metal::int2(0, 1)), 0);
    metal::float4 _e39 = src.read(metal::uint2(p + metal::int2(1, 1)), 0);
    metal::float4 v = 0.25 * (((_e16 + _e23) + _e31) + _e39);
    dst.write(v, metal::uint2(id.xy));
    return;
}
