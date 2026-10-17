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
    metal::float4 p;
    metal::float4 q;
};

metal::float3 agxContrast(
    metal::float3 x
) {
    metal::float3 x2_ = x * x;
    metal::float3 x4_ = x2_ * x2_;
    return (((((((15.5 * x4_) * x2_) - ((40.14 * x4_) * x)) + (31.96 * x4_)) - ((6.868 * x2_) * x)) + (0.4298 * x2_)) + (0.1191 * x)) - metal::float3(0.00232);
}

metal::float3 agx(
    metal::float3 v
) {
    metal::float3 x_1 = {};
    metal::float3x3 m = metal::float3x3(metal::float3(0.84247905, 0.042328242, 0.042375654), metal::float3(0.0784336, 0.87846863, 0.0784336), metal::float3(0.079223745, 0.07916613, 0.879143));
    x_1 = m * metal::max(v, metal::float3(0.0000000001));
    metal::float3 _e21 = x_1;
    x_1 = metal::clamp(metal::log2(_e21), metal::float3(-12.47393), metal::float3(4.026069));
    metal::float3 _e26 = x_1;
    x_1 = (_e26 - metal::float3(-12.47393)) / metal::float3(4.026069 - -12.47393);
    metal::float3 _e32 = x_1;
    metal::float3 _e33 = agxContrast(_e32);
    return _e33;
}

metal::float3 agxEotf(
    metal::float3 v_1
) {
    metal::float3x3 mi = metal::float3x3(metal::float3(1.196879, -0.052896854, -0.052971635), metal::float3(-0.09802088, 1.1519032, -0.09804345), metal::float3(-0.09902974, -0.098961174, 1.1510737));
    return mi * v_1;
}

metal::float3 agxLook(
    metal::float3 v_2,
    float sat,
    float power
) {
    float l = metal::dot(v_2, metal::float3(0.2126, 0.7152, 0.0722));
    metal::float3 p_1 = metal::pow(metal::max(v_2, metal::float3(0.0)), metal::float3(power));
    return metal::float3(l) + (sat * (p_1 - metal::float3(l)));
}

float ign(
    metal::float2 p
) {
    return metal::fract(52.982918 * metal::fract(metal::dot(p, metal::float2(0.06711056, 0.00583715))));
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
    metal::float2 p_2 = metal::float2(static_cast<float>((i << 1u) & 2u), static_cast<float>(i & 2u));
    o.pos = metal::float4((p_2 * 2.0) - metal::float2(1.0), 0.0, 1.0);
    o.uv = metal::float2(p_2.x, 1.0 - p_2.y);
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
, metal::texture2d<float, metal::access::sample> hdr [[texture(0)]]
, metal::texture2d<float, metal::access::sample> bloom [[texture(1)]]
, metal::sampler samp [[sampler(2)]]
, constant P& U [[buffer(3)]]
) {
    const VO in = { pos, varyings_1.uv };
    metal::float3 c = {};
    metal::float3 o_1 = {};
    metal::float2 dims = static_cast<metal::float2>(metal::uint2(hdr.get_width(), hdr.get_height()));
    metal::int2 pc = static_cast<metal::int2>(in.pos.xy);
    metal::float4 _e9 = hdr.read(metal::uint2(pc), 0);
    c = _e9.xyz;
    metal::float4 _e16 = bloom.sample(samp, in.uv, metal::level(0.0));
    float _e21 = U.q.w;
    metal::float3 b = _e16.xyz * (1.0 / metal::max(_e21, 1.0));
    metal::float3 _e27 = c;
    float _e31 = U.p.y;
    c = metal::mix(_e27, b, _e31);
    float _e36 = U.p.x;
    metal::float3 _e37 = c;
    c = _e37 * _e36;
    metal::float2 d = (in.uv - metal::float2(0.5)) * metal::float2(dims.x / dims.y, 1.0);
    float _e52 = U.p.w;
    metal::float3 _e57 = c;
    c = _e57 * (1.0 - (_e52 * metal::dot(d, d)));
    float _e62 = U.q.z;
    float _e68 = U.q.z;
    metal::float3 _e73 = c;
    c = _e73 * metal::float3(1.0 + _e62, 1.0, 1.0 - _e68);
    metal::float3 _e75 = c;
    float lum = metal::dot(_e75, metal::float3(0.2126, 0.7152, 0.0722));
    metal::float3 _e81 = c;
    c = metal::mix(_e81, metal::float3(lum), metal::smoothstep(0.7, 6.0, lum) * 0.55);
    metal::float3 _e89 = c;
    metal::float3 _e90 = agx(_e89);
    o_1 = _e90;
    metal::float3 _e92 = o_1;
    float _e96 = U.q.x;
    float _e100 = U.q.y;
    metal::float3 _e101 = agxLook(_e92, _e96, _e100);
    o_1 = _e101;
    metal::float3 _e102 = o_1;
    metal::float3 _e103 = agxEotf(_e102);
    o_1 = _e103;
    float _e109 = U.p.z;
    float _e114 = ign(in.pos.xy + metal::float2(_e109 * 5.588238));
    float _e125 = U.p.z;
    float _e130 = ign(((in.pos.xy * 1.37) + metal::float2(17.0)) + metal::float2(_e125 * 3.1));
    float n = (_e114 + _e130) - 1.0;
    metal::float3 _e136 = o_1;
    o_1 = _e136 + metal::float3(n / 255.0);
    metal::float3 _e139 = o_1;
    return fsOutput { metal::float4(metal::clamp(_e139, metal::float3(0.0), metal::float3(1.0)), 1.0) };
}
