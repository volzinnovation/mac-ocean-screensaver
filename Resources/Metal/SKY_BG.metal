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
struct Celestial {
    metal::float4 moonDir;
    metal::float4 sunDir;
    metal::float4 eqX;
    metal::float4 eqY;
    metal::float4 eqZ;
    metal::float4 night;
    metal::float4 atlas;
    metal::float4 reserved;
};
struct MoonSample {
    metal::packed_float3 radiance;
    float coverage;
};
struct VO {
    metal::float4 pos;
    metal::float2 ndc;
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
    metal::float2 uv
) {
    float mu_1 = 1.0;
    float rho = 1132.2544 * uv.y;
    float r_4 = metal::sqrt((rho * rho) + 40449600.0);
    float dMin_1 = RT - r_4;
    float dMax_1 = rho + 1132.2544;
    float d_2 = dMin_1 + (uv.x * (dMax_1 - dMin_1));
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

float camR(
    constant Frame& F
) {
    float _e4 = F.atmo.y;
    return RG + _e4;
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

metal::float3 sunIlluminance(
    constant Frame& F,
    metal::texture2d<float, metal::access::sample> transLUT,
    metal::sampler sampC
) {
    float _e0 = camR(F);
    float _e4 = F.sunDir.y;
    bool _e5 = sunBelowHorizon(_e0, _e4);
    if (_e5) {
        return metal::float3(0.0);
    }
    float _e8 = camR(F);
    float _e12 = F.sunDir.y;
    metal::float3 _e13 = sampleTrans(_e8, _e12, transLUT, sampC);
    float _e17 = F.sunDir.w;
    return _e13 * _e17;
}

metal::float2 skyViewUV(
    metal::float3 dir,
    constant Frame& F
) {
    metal::float2 uv_1 = {};
    float coord = {};
    float coord_1 = {};
    float lvc = 1.0;
    float _e1 = camR(F);
    float _e2 = rhoOf(_e1);
    float cosBeta = _e2 / _e1;
    float beta = metal::acos(metal::clamp(cosBeta, -1.0, 1.0));
    float zha = PI - beta;
    float vzc = metal::clamp(dir.y, -1.0, 1.0);
    if (vzc >= -(cosBeta)) {
        coord = metal::acos(vzc) / zha;
        float _e20 = coord;
        coord = 1.0 - _e20;
        float _e23 = coord;
        coord = metal::sqrt(metal::max(_e23, 0.0));
        float _e27 = coord;
        coord = 1.0 - _e27;
        float _e31 = coord;
        uv_1.y = _e31 * 0.5;
    } else {
        coord_1 = (metal::acos(vzc) - zha) / beta;
        float _e38 = coord_1;
        coord_1 = metal::sqrt(metal::max(_e38, 0.0));
        float _e43 = coord_1;
        uv_1.y = (_e43 * 0.5) + 0.5;
    }
    float dl = metal::length(dir.xz);
    metal::float4 _e52 = F.sunDir;
    float sl = metal::length(_e52.xz);
    if ((dl > 0.000001) && (sl > 0.000001)) {
        metal::float4 _e65 = F.sunDir;
        lvc = metal::clamp(metal::dot(dir.xz, _e65.xz) / (dl * sl), -1.0, 1.0);
    }
    float _e74 = lvc;
    uv_1.x = metal::sqrt(metal::max((-(_e74) * 0.5) + 0.5, 0.0));
    float _e84 = uv_1.x;
    float _e86 = fromUnitToSubUvs(_e84, SKY_W);
    float _e88 = uv_1.y;
    float _e90 = fromUnitToSubUvs(_e88, SKY_H);
    return metal::float2(_e86, _e90);
}

metal::float3 skyAtmo(
    metal::float3 dir_1,
    constant Frame& F,
    metal::texture2d<float, metal::access::sample> skyLUT,
    metal::sampler sampC
) {
    metal::float2 _e3 = skyViewUV(dir_1, F);
    metal::float4 _e5 = skyLUT.sample(sampC, _e3, metal::level(0.0));
    float _e10 = F.sunDir.w;
    return _e5.xyz * _e10;
}

metal::float3 moonIlluminance(
    constant Frame& F,
    metal::texture2d<float, metal::access::sample> transLUT,
    metal::sampler sampC,
    constant Celestial& C
) {
    float _e3 = C.moonDir.y;
    if (_e3 <= 0.0) {
        return metal::float3(0.0);
    }
    float _e12 = C.moonDir.w;
    float _e17 = C.moonDir.w;
    float omega = (PI * _e12) * _e17;
    float _e19 = camR(F);
    float _e23 = C.moonDir.y;
    metal::float3 _e24 = sampleTrans(_e19, _e23, transLUT, sampC);
    float _e28 = C.night.y;
    float _e33 = C.sunDir.w;
    return _e24 * ((_e28 * omega) * _e33);
}

MoonSample moonDisk(
    metal::float3 dir_2,
    float pixelAngle,
    constant Frame& F,
    metal::texture2d<float, metal::access::sample> transLUT,
    metal::sampler sampC,
    constant Celestial& C
) {
    MoonSample result = {};
    result.radiance = metal::float3(0.0);
    result.coverage = 0.0;
    float _e14 = C.moonDir.y;
    float _e18 = C.moonDir.w;
    if ((dir_2.y <= 0.0) || (_e14 < -(_e18))) {
        MoonSample _e22 = result;
        return _e22;
    }
    metal::float4 _e25 = C.moonDir;
    metal::float3 center = metal::normalize(_e25.xyz);
    float cosine = metal::clamp(metal::dot(dir_2, center), -1.0, 1.0);
    float angle = metal::sqrt(metal::max(2.0 * (1.0 - cosine), 0.0));
    float _e42 = C.moonDir.w;
    float radius = metal::max(_e42, 0.00001);
    float aa = metal::max(pixelAngle * 0.65, 0.000001);
    result.coverage = 1.0 - metal::smoothstep(radius - aa, radius + aa, angle);
    float _e56 = result.coverage;
    if (_e56 <= 0.0) {
        MoonSample _e59 = result;
        return _e59;
    }
    metal::float3 tangent = (dir_2 - (center * cosine)) / metal::float3(metal::sin(radius));
    metal::float3 surfaceNormal = metal::normalize(tangent - (center * metal::sqrt(metal::max(1.0 - metal::dot(tangent, tangent), 0.0))));
    metal::float4 _e76 = C.sunDir;
    float incidence = metal::max(metal::dot(surfaceNormal, metal::normalize(_e76.xyz)), 0.0);
    float emergence = metal::max(metal::dot(surfaceNormal, -(center)), 0.001);
    float lit = metal::clamp((2.0 * incidence) / metal::max(incidence + emergence, 0.001), 0.0, 1.0);
    float _e98 = C.night.w;
    float _e102 = C.sunDir.w;
    float earthshine = _e98 * (1.0 - _e102);
    float _e106 = camR(F);
    metal::float3 _e110 = sampleTrans(_e106, metal::max(dir_2.y, 0.001), transLUT, sampC);
    float _e119 = C.night.y;
    result.radiance = _e110 * (((metal::float3(0.92, 0.94, 1.0) * _e119) * lit) + (metal::float3(0.55, 0.65, 0.9) * earthshine));
    MoonSample _e129 = result;
    return _e129;
}

metal::float3 stellarRadiance(
    metal::float3 dir_3,
    float pixelAngle_1,
    constant Celestial& C,
    metal::texture2d<float, metal::access::sample> celestialAtlas,
    metal::sampler celestialSampler
) {
    float _e8 = C.night.x;
    if ((dir_3.y <= 0.0) || (_e8 <= 0.0)) {
        return metal::float3(0.0);
    }
    metal::float4 _e16 = C.eqX;
    metal::float4 _e21 = C.eqY;
    metal::float4 _e26 = C.eqZ;
    metal::float3 equatorial = metal::normalize(metal::float3(metal::dot(_e16.xyz, dir_3), metal::dot(_e21.xyz, dir_3), metal::dot(_e26.xyz, dir_3)));
    float ra = metal::atan2(equatorial.z, equatorial.x);
    float dec = metal::asin(metal::clamp(equatorial.y, -1.0, 1.0));
    float _e44 = C.atlas.x;
    float _e49 = C.atlas.y;
    float _e57 = C.atlas.z;
    float _e62 = C.atlas.w;
    metal::float2 uv_2 = metal::float2(metal::fract(((ra / 6.2831855) * _e44) + _e49), metal::clamp(((dec / PI) * _e57) + _e62, 0.0, 1.0));
    float textureWidth = static_cast<float>(metal::uint2(celestialAtlas.get_width(), celestialAtlas.get_height()).x);
    float lod = metal::max(0.0, metal::log2(metal::max((pixelAngle_1 * textureWidth) / 6.2831855, 1.0)));
    metal::float4 _e82 = celestialAtlas.sample(celestialSampler, uv_2, metal::level(lod));
    metal::float3 atlas = _e82.xyz;
    float horizon = metal::smoothstep(0.0, 0.055, dir_3.y);
    float transmission = metal::exp(-0.08 / metal::max(dir_3.y, 0.04));
    float _e97 = C.night.x;
    float _e101 = C.night.z;
    return atlas * (((_e97 * _e101) * horizon) * transmission);
}

metal::float3 sunDisk(
    metal::float3 dir_4,
    constant Frame& F,
    metal::texture2d<float, metal::access::sample> transLUT,
    metal::sampler sampC
) {
    float _e1 = camR(F);
    bool _e3 = sunBelowHorizon(_e1, dir_4.y);
    if (_e3) {
        return metal::float3(0.0);
    }
    metal::float4 _e8 = F.sunDir;
    float c_4 = metal::dot(dir_4, _e8.xyz);
    float ang = metal::sqrt(metal::max(2.0 * (1.0 - c_4), 0.0));
    float _e21 = F.screen.w;
    metal::float4 _e26 = F.camUp;
    float pix = ((_e21 * 2.0) * metal::length(_e26.xyz)) * 0.75;
    float edge = 1.0 - metal::smoothstep(SUN_ANG_R - pix, SUN_ANG_R + pix, ang);
    if (edge <= 0.0) {
        return metal::float3(0.0);
    }
    float x_1 = metal::min(ang / SUN_ANG_R, 1.0);
    float mu_4 = metal::sqrt(metal::max(1.0 - (x_1 * x_1), 0.0));
    metal::float3 limb = metal::float3(1.0) - (metal::float3(0.397, 0.503, 0.652) * (1.0 - mu_4));
    float _e66 = F.sunDir.w;
    float rad = _e66 / 0.00006866147;
    float _e71 = camR(F);
    metal::float3 _e75 = sampleTrans(_e71, metal::max(dir_4.y, -0.01), transLUT, sampC);
    return ((rad * limb) * edge) * _e75;
}

metal::float3 skyRadiance(
    metal::float3 dirIn,
    bool withDiscs,
    float pixelAngle_2,
    constant Frame& F,
    metal::texture2d<float, metal::access::sample> transLUT,
    metal::texture2d<float, metal::access::sample> skyLUT,
    metal::sampler sampC,
    constant Celestial& C,
    metal::texture2d<float, metal::access::sample> celestialAtlas,
    metal::sampler celestialSampler
) {
    metal::float3 atmosphereDir = {};
    metal::float3 radiance = {};
    atmosphereDir = dirIn;
    float _e6 = atmosphereDir.y;
    atmosphereDir.y = metal::max(_e6, 0.0005);
    metal::float3 _e9 = atmosphereDir;
    atmosphereDir = metal::normalize(_e9);
    metal::float3 _e11 = atmosphereDir;
    metal::float3 _e12 = skyAtmo(_e11, F, skyLUT, sampC);
    metal::float3 _e13 = stellarRadiance(dirIn, pixelAngle_2, C, celestialAtlas, celestialSampler);
    radiance = _e13;
    if (withDiscs) {
        metal::float3 _e15 = sunDisk(dirIn, F, transLUT, sampC);
        metal::float3 _e16 = radiance;
        radiance = _e16 + _e15;
        MoonSample _e18 = moonDisk(dirIn, pixelAngle_2, F, transLUT, sampC, C);
        metal::float3 _e19 = radiance;
        radiance = (_e19 * (1.0 - _e18.coverage)) + (_e18.radiance * _e18.coverage);
    }
    metal::float3 _e28 = radiance;
    return _e12 + _e28;
}

struct vsInput {
};
struct vsOutput {
    metal::float4 pos [[position]];
    metal::float2 ndc [[user(loc0), center_perspective]];
};
vertex vsOutput vs(
  uint i [[vertex_id]]
) {
    VO o = {};
    metal::float2 p = (metal::float2(static_cast<float>((i << 1u) & 2u), static_cast<float>(i & 2u)) * 2.0) - metal::float2(1.0);
    o.pos = metal::float4(p, 0.0, 1.0);
    o.ndc = p;
    VO _e21 = o;
    const auto _tmp = _e21;
    return vsOutput { _tmp.pos, _tmp.ndc };
}


struct fsInput {
    metal::float2 ndc [[user(loc0), center_perspective]];
};
struct fsOutput {
    metal::float4 member_1 [[color(0)]];
};
fragment fsOutput fs(
  fsInput varyings_1 [[stage_in]]
, metal::float4 pos [[position]]
, constant Frame& F [[buffer(0)]]
, metal::texture2d<float, metal::access::sample> transLUT [[texture(1)]]
, metal::texture2d<float, metal::access::sample> skyLUT [[texture(2)]]
, metal::sampler sampC [[sampler(3)]]
, constant Celestial& C [[buffer(12)]]
, metal::texture2d<float, metal::access::sample> celestialAtlas [[texture(13)]]
, metal::sampler celestialSampler [[sampler(14)]]
) {
    const VO in = { pos, varyings_1.ndc };
    metal::float4 _e3 = F.camFwd;
    metal::float4 _e9 = F.camRight;
    metal::float4 _e17 = F.camUp;
    metal::float3 dir_5 = metal::normalize((_e3.xyz + (in.ndc.x * _e9.xyz)) + (in.ndc.y * _e17.xyz));
    metal::float4 _e24 = F.camUp;
    float _e32 = F.screen.w;
    float pixAng = (2.0 * metal::length(_e24.xyz)) * _e32;
    metal::float3 _e35 = skyRadiance(dir_5, true, pixAng, F, transLUT, skyLUT, sampC, C, celestialAtlas, celestialSampler);
    return fsOutput { metal::float4(_e35, 1.0) };
}
