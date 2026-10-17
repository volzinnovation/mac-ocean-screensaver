// Generated from Resources/Web/js/wgsl by scripts/generate-metal.py.
// Original ocean renderer: Noniv/web-ocean, MIT; see THIRD_PARTY_NOTICES.md.
// Edit the WGSL source and regenerate; native builds use this vendored MSL.
// language: metal2.4
#include <metal_stdlib>
#include <simd/simd.h>

using metal::uint;


metal::float4 box(
    metal::texture2d_array<float, metal::access::sample> t,
    metal::int2 p,
    uint l
) {
    metal::float4 _e4 = t.read(metal::uint2(p), l, 0);
    metal::float4 _e10 = t.read(metal::uint2(p + metal::int2(1, 0)), l, 0);
    metal::float4 _e17 = t.read(metal::uint2(p + metal::int2(0, 1)), l, 0);
    metal::float4 _e24 = t.read(metal::uint2(p + metal::int2(1, 1)), l, 0);
    return 0.25 * (((_e4 + _e10) + _e17) + _e24);
}

struct main_Input {
};
kernel void main_(
  metal::uint3 id [[thread_position_in_grid]]
, metal::texture2d_array<float, metal::access::sample> srcA [[texture(0)]]
, metal::texture2d_array<float, metal::access::sample> srcB [[texture(1)]]
, metal::texture2d_array<float, metal::access::sample> srcC [[texture(2)]]
, metal::texture2d_array<float, metal::access::write> dstA [[texture(3)]]
, metal::texture2d_array<float, metal::access::write> dstB [[texture(4)]]
, metal::texture2d_array<float, metal::access::write> dstC [[texture(5)]]
) {

    metal::uint2 size = metal::uint2(dstA.get_width(), dstA.get_height());
    if ((id.x >= size.x) || (id.y >= size.y)) {
        return;
    }
    metal::int2 p_1 = static_cast<metal::int2>(id.xy) * 2;
    metal::float4 _e19 = box(srcA, p_1, id.z);
    dstA.write(_e19, metal::uint2(id.xy), id.z);
    metal::float4 _e25 = box(srcB, p_1, id.z);
    dstB.write(_e25, metal::uint2(id.xy), id.z);
    metal::float4 _e31 = box(srcC, p_1, id.z);
    dstC.write(_e31, metal::uint2(id.xy), id.z);
    return;
}
