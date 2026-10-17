// Generated from Resources/Web/js/wgsl by scripts/generate-metal.py.
// Original ocean renderer: Noniv/web-ocean, MIT; see THIRD_PARTY_NOTICES.md.
// Edit the WGSL source and regenerate; native builds use this vendored MSL.
// language: metal2.4
#include <metal_stdlib>
#include <simd/simd.h>

using metal::uint;

struct type_3 {
    metal::float4 inner[2];
};
struct Frame {
    metal::float4x4 viewProj;
    metal::float4 camPos;
    metal::float4 camRight;
    metal::float4 camUp;
    metal::float4 camFwd;
    metal::float4 sunDir;
    metal::float4 screen;
    type_3 cascL;
    type_3 cascInvL;
    type_3 windP;
    metal::float4 lodP;
    metal::float4 post;
    metal::float4 atmo;
    metal::float4 waterCol;
    metal::float4 sssCol;
    metal::float4 foamP;
    metal::float4 fogExt;
    metal::float4 cloudP;
};
struct type_6 {
    float inner[4];
};

metal::float3 dispAt(
    metal::float2 xz,
    constant Frame& F,
    metal::texture2d_array<float, metal::access::sample> dispTex,
    metal::sampler samp
) {
    metal::float3 d = metal::float3(0.0);
    uint c = 0u;
    bool loop_init = true;
    while(true) {
        if (!loop_init) {
            uint _e30 = c;
            c = _e30 + 1u;
        }
        loop_init = false;
        uint _e6 = c;
        if (_e6 < 6u) {
        } else {
            break;
        }
        {
            uint _e13 = c;
            uint _e17 = c;
            float _e21 = F.cascInvL.inner[_e13 >> 2u][_e17 & 3u];
            uint _e23 = c;
            metal::float4 _e25 = dispTex.sample(samp, xz * _e21, _e23, metal::level(0.0));
            metal::float3 _e27 = d;
            d = _e27 + _e25.xyz;
        }
#define LOOP_IS_BOUNDED { volatile bool unpredictable_break_from_loop = false; if (unpredictable_break_from_loop) break; }
        LOOP_IS_BOUNDED
    }
    metal::float3 _e32 = d;
    return _e32;
}

kernel void main_(
  constant Frame& F [[buffer(0)]]
, metal::texture2d_array<float, metal::access::sample> dispTex [[texture(1)]]
, metal::sampler samp [[sampler(2)]]
, device type_6& outH [[buffer(3)]]
) {

    metal::float2 x0_ = {};
    int i = 0;
    metal::float4 _e2 = F.camPos;
    metal::float2 goal = _e2.xz;
    x0_ = goal;
    bool loop_init_1 = true;
    while(true) {
        if (!loop_init_1) {
            int _e15 = i;
            i = _e15 + 1;
        }
        loop_init_1 = false;
        int _e7 = i;
        if (_e7 < 4) {
        } else {
            break;
        }
        {
            metal::float2 _e10 = x0_;
            metal::float3 _e11 = dispAt(_e10, F, dispTex, samp);
            x0_ = goal - _e11.xz;
        }
        LOOP_IS_BOUNDED
    }
    metal::float2 _e19 = x0_;
    metal::float3 _e20 = dispAt(_e19, F, dispTex, samp);
    outH.inner[0] = _e20.y;
    return;
}
