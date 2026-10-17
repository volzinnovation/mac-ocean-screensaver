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
struct Medium {
    metal::float3 ext;
    metal::packed_float3 rayS;
    float mieS;
};
constant float PI = 3.1415927;
constant float RG = 6360.0;
constant float RT = 6460.0;
constant metal::float3 RAY_S = metal::float3(0.005802, 0.013558, 0.0331);
constant float MIE_S = 0.003996;
constant float MIE_E = 0.0044;
constant metal::float3 OZO_A = metal::float3(0.00065, 0.001881, 0.000085);
constant float SUN_ANG_R = 0.004675;
constant float TRANS_W = 256.0;
constant float TRANS_H = 64.0;
constant float MS_SIZE = 32.0;
constant float SKY_W = 256.0;
constant float SKY_H = 144.0;

Medium medium(
    float h,
    float haze
) {
    Medium m = {};
    float hh = metal::max(h, 0.0);
    float dR = metal::exp(-(hh) / 8.0);
    float dM = metal::exp(-(hh) / 1.2);
    float dO = metal::max(0.0, 1.0 - (metal::abs(hh - 25.0) / 15.0));
    m.rayS = RAY_S * dR;
    m.mieS = (MIE_S * dM) * haze;
    metal::float3 _e31 = m.rayS;
    m.ext = (_e31 + metal::float3((MIE_E * dM) * haze)) + (OZO_A * dO);
    Medium _e40 = m;
    return _e40;
}

metal::float2 raySphere(
    metal::float3 ro,
    metal::float3 rd,
    float R
) {
    float l = metal::length(ro);
    float b = metal::dot(ro, rd);
    float c_3 = (l - R) * (l + R);
    float d = (b * b) - c_3;
    if (d < 0.0) {
        return metal::float2(-1.0, -1.0);
    }
    float s = metal::sqrt(d);
    return metal::float2(-(b) - s, -(b) + s);
}

float rhoOf(
    float r
) {
    return metal::sqrt(metal::max(0.0, (r - RG) * (r + RG)));
}

metal::float2 transRMuToUV(
    float r_1,
    float mu
) {
    float _e3 = rhoOf(r_1);
    float disc = ((r_1 * r_1) * ((mu * mu) - 1.0)) + 41731600.0;
    float d_1 = metal::max(0.0, (-(r_1) * mu) + metal::sqrt(metal::max(disc, 0.0)));
    float dMin = RT - r_1;
    float dMax = _e3 + 1132.2544;
    float x = (d_1 - dMin) / (dMax - dMin);
    float y = _e3 / 1132.2544;
    return metal::float2(x, y);
}

metal::float2 transUVToRMu(
    metal::float2 uv_1
) {
    float mu_1 = 1.0;
    float rho = 1132.2544 * uv_1.y;
    float r_4 = metal::sqrt((rho * rho) + 40449600.0);
    float dMin_1 = RT - r_4;
    float dMax_1 = rho + 1132.2544;
    float d_2 = dMin_1 + (uv_1.x * (dMax_1 - dMin_1));
    if (d_2 > 0.0) {
        mu_1 = (((1132.2544 * 1132.2544) - (rho * rho)) - (d_2 * d_2)) / ((2.0 * r_4) * d_2);
    }
    float _e28 = mu_1;
    return metal::float2(r_4, metal::clamp(_e28, -1.0, 1.0));
}

float fromUnitToSubUvs(
    float u,
    float res
) {
    return (u + (0.5 / res)) * (res / (res + 1.0));
}

float fromSubUvsToUnit(
    float u_1,
    float res_1
) {
    return (u_1 - (0.5 / res_1)) * (res_1 / (res_1 - 1.0));
}

float phaseRayleigh(
    float c
) {
    return 0.059683103 * (1.0 + (c * c));
}

float phaseMie(
    float c_1,
    float g
) {
    float g2_ = g * g;
    return (0.119366206 * ((1.0 - g2_) * (1.0 + (c_1 * c_1)))) / ((2.0 + g2_) * metal::pow(metal::max((1.0 + g2_) - ((2.0 * g) * c_1), 0.0001), 1.5));
}

float phaseHG(
    float c_2,
    float g_1
) {
    float g2_1 = g_1 * g_1;
    return (1.0 - g2_1) / (12.566371 * metal::pow(metal::max((1.0 + g2_1) - ((2.0 * g_1) * c_2), 0.0001), 1.5));
}

bool sunBelowHorizon(
    float r_2,
    float mu_2
) {
    float _e2 = rhoOf(r_2);
    return mu_2 < (-(_e2) / r_2);
}

metal::float3 sampleTrans(
    float r_3,
    float mu_3,
    metal::texture2d<float, metal::access::sample> transLUT,
    metal::sampler sampC
) {
    metal::float2 _e4 = transRMuToUV(r_3, mu_3);
    metal::float4 _e6 = transLUT.sample(sampC, _e4, metal::level(0.0));
    return _e6.xyz;
}

struct main_Input {
};
kernel void main_(
  metal::uint3 id [[thread_position_in_grid]]
, constant Frame& F [[buffer(0)]]
, metal::texture2d<float, metal::access::sample> transLUT [[texture(1)]]
, metal::texture2d<float, metal::access::sample> msLUT [[texture(2)]]
, metal::sampler sampC [[sampler(3)]]
, metal::texture2d<float, metal::access::write> dst [[texture(4)]]
) {

    metal::float2 uv = {};
    float vza = {};
    float coord = {};
    float coord_1 = {};
    float tMax = {};
    metal::float3 L = metal::float3(0.0);
    metal::float3 T = metal::float3(1.0);
    float tPrev = 0.0;
    uint i = 0u;
    metal::float3 sunT = {};
    if ((static_cast<float>(id.x) >= SKY_W) || (static_cast<float>(id.y) >= SKY_H)) {
        return;
    }
    uv = (static_cast<metal::float2>(id.xy) + metal::float2(0.5)) / metal::float2(256.0, 144.0);
    float _e21 = uv.x;
    float _e23 = fromSubUvsToUnit(_e21, SKY_W);
    float _e25 = uv.y;
    float _e27 = fromSubUvsToUnit(_e25, SKY_H);
    uv = metal::float2(_e23, _e27);
    float haze_1 = F.atmo.x;
    float _e37 = F.atmo.y;
    float r_5 = RG + _e37;
    float _e39 = rhoOf(r_5);
    float cosBeta = _e39 / r_5;
    float beta = metal::acos(metal::clamp(cosBeta, -1.0, 1.0));
    float zha = PI - beta;
    float _e49 = uv.y;
    if (_e49 < 0.5) {
        float _e53 = uv.y;
        coord = 2.0 * _e53;
        float _e57 = coord;
        coord = 1.0 - _e57;
        float _e60 = coord;
        float _e61 = coord;
        coord = _e61 * _e60;
        float _e63 = coord;
        coord = 1.0 - _e63;
        float _e66 = coord;
        vza = zha * _e66;
    } else {
        float _e69 = uv.y;
        coord_1 = (_e69 * 2.0) - 1.0;
        float _e75 = coord_1;
        float _e76 = coord_1;
        coord_1 = _e76 * _e75;
        float _e78 = coord_1;
        vza = zha + (beta * _e78);
    }
    float _e81 = vza;
    float vzc = metal::cos(_e81);
    float _e83 = vza;
    float vzs = metal::sin(_e83);
    float _e86 = uv.x;
    float _e88 = uv.x;
    float cx = _e86 * _e88;
    float lvc = -(((cx * 2.0) - 1.0));
    float lvs = metal::sqrt(metal::max(0.0, 1.0 - (lvc * lvc)));
    metal::float3 rd_1 = metal::float3(vzs * lvc, vzc, vzs * lvs);
    float smu = F.sunDir.y;
    metal::float3 sun = metal::float3(metal::sqrt(metal::max(0.0, 1.0 - (smu * smu))), smu, 0.0);
    metal::float3 ro_1 = metal::float3(0.0, r_5, 0.0);
    metal::float2 _e120 = raySphere(ro_1, rd_1, RT);
    metal::float2 _e122 = raySphere(ro_1, rd_1, RG);
    tMax = _e120.y;
    if (_e122.x > 0.0) {
        tMax = _e122.x;
    }
    float cosT = metal::dot(rd_1, sun);
    float _e130 = phaseRayleigh(cosT);
    float _e132 = phaseMie(cosT, 0.84);
    bool loop_init = true;
    while(true) {
        if (!loop_init) {
            uint _e225 = i;
            i = _e225 + 1u;
        }
        loop_init = false;
        uint _e144 = i;
        if (_e144 < 48u) {
        } else {
            break;
        }
        {
            uint _e146 = i;
            float fa = (static_cast<float>(_e146) + 1.0) / static_cast<float>(48u);
            float _e152 = tMax;
            float tn = (_e152 * fa) * fa;
            float _e155 = tPrev;
            float dt = tn - _e155;
            float _e157 = tPrev;
            float t = _e157 + (dt * 0.3);
            tPrev = tn;
            metal::float3 p = ro_1 + (rd_1 * t);
            float pr = metal::length(p);
            float h_1 = pr - RG;
            Medium _e166 = medium(h_1, haze_1);
            float pmu = metal::dot(p, sun) / pr;
            metal::float3 _e169 = sampleTrans(pr, pmu, transLUT, sampC);
            sunT = _e169;
            bool _e171 = sunBelowHorizon(pr, pmu);
            if (_e171) {
                sunT = metal::float3(0.0);
            }
            float _e179 = fromUnitToSubUvs((pmu * 0.5) + 0.5, MS_SIZE);
            float _e186 = fromUnitToSubUvs(metal::clamp(h_1 / 100.0, 0.0, 1.0), MS_SIZE);
            metal::float2 msuv = metal::float2(_e179, _e186);
            metal::float4 _e191 = msLUT.sample(sampC, msuv, metal::level(0.0));
            metal::float3 ms = _e191.xyz;
            metal::float3 _e193 = sunT;
            metal::float3 S = (_e193 * ((_e166.rayS * _e130) + metal::float3(_e166.mieS * _e132))) + (ms * (_e166.rayS + metal::float3(_e166.mieS)));
            metal::float3 Ts = metal::exp(-(_e166.ext) * dt);
            metal::float3 ext = metal::max(_e166.ext, metal::float3(0.000000001));
            metal::float3 _e215 = T;
            metal::float3 _e220 = L;
            L = _e220 + ((_e215 * (S - (S * Ts))) / ext);
            metal::float3 _e222 = T;
            T = _e222 * Ts;
        }
#define LOOP_IS_BOUNDED { volatile bool unpredictable_break_from_loop = false; if (unpredictable_break_from_loop) break; }
        LOOP_IS_BOUNDED
    }
    metal::float3 _e229 = L;
    dst.write(metal::float4(_e229, 1.0), metal::uint2(id.xy));
    return;
}
