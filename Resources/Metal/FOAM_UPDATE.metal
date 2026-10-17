// Generated from Resources/Web/js/wgsl by scripts/generate-metal.py.
// Original ocean renderer: Noniv/web-ocean, MIT; see THIRD_PARTY_NOTICES.md.
// Edit the WGSL source and regenerate; native builds use this vendored MSL.
// language: metal2.4
#include <metal_stdlib>
#include <simd/simd.h>

using metal::uint;

struct type_2 {
    metal::int4 inner[2];
};
struct type_5 {
    metal::float4 inner[2];
};
struct FoamU {
    type_2 snap;
    metal::float4 p0_;
    metal::float4 p1_;
    type_5 cascL;
    type_5 cascInvL;
    metal::float4 drift;
};
constant int RES = 1024;

int wrapIdx(
    int i,
    int lo
) {
    return lo + ((((i - lo) % RES) + RES) % RES);
}

struct main_Input {
};
kernel void main_(
  metal::uint3 id [[thread_position_in_grid]]
, constant FoamU& U [[buffer(0)]]
, metal::texture2d_array<float, metal::access::sample> prevTex [[texture(1)]]
, metal::texture2d_array<float, metal::access::write> dst [[texture(2)]]
, metal::texture2d_array<float, metal::access::sample> dispTex [[texture(3)]]
, metal::texture2d_array<float, metal::access::sample> derivTex [[texture(4)]]
, metal::sampler samp [[sampler(5)]]
, metal::sampler sampPrev [[sampler(6)]]
) {

    float jxx = 0.0;
    float jzz = 0.0;
    float jxz = 0.0;
    uint c = 0u;
    metal::float4 prev = metal::float4(0.0);
    float f = {};
    uint lvl = id.z;
    metal::int4 sn = U.snap.inner[lvl];
    float _e9 = U.p0_.x;
    float _e13 = U.p0_.y;
    float ts = (lvl == 1u) ? _e13 : _e9;
    metal::int2 lo_1 = sn.xy - metal::int2(512);
    int _e24 = wrapIdx(static_cast<int>(id.x), lo_1.x);
    int _e28 = wrapIdx(static_cast<int>(id.y), lo_1.y);
    metal::int2 g = metal::int2(_e24, _e28);
    metal::int2 plo = sn.zw - metal::int2(512);
    bool inPrev = metal::all(g >= plo) && metal::all(g < (plo + metal::int2(1024)));
    metal::float2 p = (static_cast<metal::float2>(g) + metal::float2(0.5)) * ts;
    bool loop_init = true;
    while(true) {
        if (!loop_init) {
            uint _e107 = c;
            c = _e107 + 1u;
        }
        loop_init = false;
        uint _e55 = c;
        if (_e55 < 6u) {
        } else {
            break;
        }
        {
            uint _e60 = c;
            uint _e64 = c;
            float _e68 = U.cascL.inner[_e60 >> 2u][_e64 & 3u];
            float texel = _e68 / 256.0;
            float lod = metal::log2(metal::max(ts / texel, 1.0));
            if (lod < 7.5) {
                uint _e79 = c;
                uint _e83 = c;
                float _e87 = U.cascInvL.inner[_e79 >> 2u][_e83 & 3u];
                metal::float2 uv = p * _e87;
                uint _e91 = c;
                metal::float4 d = derivTex.sample(samp, uv, _e91, metal::level(lod));
                uint _e95 = c;
                metal::float4 a = dispTex.sample(samp, uv, _e95, metal::level(lod));
                float _e98 = jxx;
                jxx = _e98 + d.z;
                float _e101 = jzz;
                jzz = _e101 + d.w;
                float _e104 = jxz;
                jxz = _e104 + a.w;
            }
        }
#define LOOP_IS_BOUNDED { volatile bool unpredictable_break_from_loop = false; if (unpredictable_break_from_loop) break; }
        LOOP_IS_BOUNDED
    }
    float _e109 = jxx;
    float _e112 = jzz;
    float _e116 = jxz;
    float _e117 = jxz;
    float J = ((1.0 + _e109) * (1.0 + _e112)) - (_e116 * _e117);
    if (inPrev) {
        metal::float4 _e130 = U.drift;
        float _e135 = U.p0_.z;
        metal::float2 back = ((static_cast<metal::float2>(id.xy) + metal::float2(0.5)) - ((_e130.xy * _e135) / metal::float2(ts))) / metal::float2(1024.0);
        metal::float4 _e146 = prevTex.sample(sampPrev, back, lvl, metal::level(0.0));
        prev = _e146;
    }
    float dt = U.p0_.z;
    float _e154 = U.p1_.x;
    float _e159 = U.p1_.y;
    float inject = metal::clamp((_e154 - J) * _e159, 0.0, 1.0);
    float _e165 = prev.x;
    float _e170 = U.p0_.w;
    f = _e165 * metal::exp(-(dt) * _e170);
    float _e175 = f;
    f = metal::max(_e175, inject);
    float _e177 = f;
    float _e182 = U.p1_.z;
    f = metal::min(_e177 + ((inject * dt) * _e182), 1.6);
    float _e188 = prev.y;
    float fresh = metal::max(_e188 * metal::exp(-(dt) * 1.6), inject);
    float _e197 = f;
    dst.write(metal::float4(_e197, fresh, J, 1.0), metal::uint2(id.xy), lvl);
    return;
}
