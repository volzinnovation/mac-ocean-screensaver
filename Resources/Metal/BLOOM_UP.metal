// Generated from Resources/Web/js/wgsl by scripts/generate-metal.py.
// Original ocean renderer: Noniv/web-ocean, MIT; see THIRD_PARTY_NOTICES.md.
// Edit the WGSL source and regenerate; native builds use this vendored MSL.
// language: metal2.4
#include <metal_stdlib>
#include <simd/simd.h>

using metal::uint;

struct VO {
    metal::float4 pos;
    metal::float2 uv;
};
struct P {
    metal::float4 texel;
};

metal::float3 tap(
    metal::float2 uv,
    metal::texture2d<float, metal::access::sample> src,
    metal::sampler samp
) {
    metal::float4 _e4 = src.sample(samp, uv, metal::level(0.0));
    return _e4.xyz;
}

struct vsInput {
};
struct vsOutput {
    metal::float4 pos [[position]];
    metal::float2 uv [[user(loc0), center_perspective]];
};
vertex vsOutput vs(
  uint i [[vertex_id]]
) {
    VO o = {};
    metal::float2 p = metal::float2(static_cast<float>((i << 1u) & 2u), static_cast<float>(i & 2u));
    o.pos = metal::float4((p * 2.0) - metal::float2(1.0), 0.0, 1.0);
    o.uv = metal::float2(p.x, 1.0 - p.y);
    VO _e26 = o;
    const auto _tmp = _e26;
    return vsOutput { _tmp.pos, _tmp.uv };
}


struct fsInput {
    metal::float2 uv [[user(loc0), center_perspective]];
};
struct fsOutput {
    metal::float4 member_1 [[color(0)]];
};
fragment fsOutput fs(
  fsInput varyings_1 [[stage_in]]
, metal::float4 pos [[position]]
, metal::texture2d<float, metal::access::sample> src [[texture(0)]]
, metal::sampler samp [[sampler(1)]]
, constant P& U [[buffer(2)]]
) {
    const VO in = { pos, varyings_1.uv };
    metal::float3 o_1 = {};
    metal::float4 _e3 = U.texel;
    float _e8 = U.texel.z;
    metal::float2 t = _e3.xy * _e8;
    metal::float2 uv_1 = in.uv;
    metal::float3 _e11 = tap(uv_1, src, samp);
    o_1 = _e11 * 4.0;
    metal::float3 _e20 = tap(uv_1 + metal::float2(-(t.x), 0.0), src, samp);
    metal::float3 _e25 = tap(uv_1 + metal::float2(t.x, 0.0), src, samp);
    metal::float3 _e32 = tap(uv_1 + metal::float2(0.0, -(t.y)), src, samp);
    metal::float3 _e38 = tap(uv_1 + metal::float2(0.0, t.y), src, samp);
    metal::float3 _e42 = o_1;
    o_1 = _e42 + ((((_e20 + _e25) + _e32) + _e38) * 2.0);
    metal::float3 _e50 = tap(uv_1 + metal::float2(-(t.x), -(t.y)), src, samp);
    metal::float3 _e56 = tap(uv_1 + metal::float2(t.x, -(t.y)), src, samp);
    metal::float3 _e63 = tap(uv_1 + metal::float2(-(t.x), t.y), src, samp);
    metal::float3 _e69 = tap(uv_1 + metal::float2(t.x, t.y), src, samp);
    metal::float3 _e71 = o_1;
    o_1 = _e71 + (((_e50 + _e56) + _e63) + _e69);
    metal::float3 _e73 = o_1;
    float _e77 = U.texel.w;
    return fsOutput { metal::float4(_e73 * (_e77 / 16.0), 1.0) };
}
