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
struct Medium {
    metal::float3 ext;
    metal::packed_float3 rayS;
    float mieS;
};
struct type_11 {
    float inner[4];
};
struct VSOut {
    metal::float4 pos;
    metal::float3 rel;
    metal::float2 xz;
    float height;
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
constant float ENV_MAXMIP = 8.0;
constant float ENV_TEXELS_PER_RAD = 162.97427;
constant float TEX_N = 256.0;

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
    float R_1
) {
    float l = metal::length(ro);
    float b = metal::dot(ro, rd);
    float c_6 = (l - R_1) * (l + R_1);
    float d = (b * b) - c_6;
    if (d < 0.0) {
        return metal::float2(-1.0, -1.0);
    }
    float s_1 = metal::sqrt(d);
    return metal::float2(-(b) - s_1, -(b) + s_1);
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
    float c_2
) {
    return 0.059683103 * (1.0 + (c_2 * c_2));
}

float phaseMie(
    float c_3,
    float g
) {
    float g2_ = g * g;
    return (0.119366206 * ((1.0 - g2_) * (1.0 + (c_3 * c_3)))) / ((2.0 + g2_) * metal::pow(metal::max((1.0 + g2_) - ((2.0 * g) * c_3), 0.0001), 1.5));
}

float phaseHG(
    float c_4,
    float g_1
) {
    float g2_1 = g_1 * g_1;
    return (1.0 - g2_1) / (12.566371 * metal::pow(metal::max((1.0 + g2_1) - ((2.0 * g_1) * c_4), 0.0001), 1.5));
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
    float sl_1 = metal::length(_e52.xz);
    if ((dl > 0.000001) && (sl_1 > 0.000001)) {
        metal::float4 _e65 = F.sunDir;
        lvc = metal::clamp(metal::dot(dir.xz, _e65.xz) / (dl * sl_1), -1.0, 1.0);
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

float fresnelWater(
    float c_5
) {
    float x_1 = 1.0 - metal::clamp(c_5, 0.0, 1.0);
    float x2_ = x_1 * x_1;
    return 0.02 + (((0.98 * x2_) * x2_) * x_1);
}

float lambdaSmith(
    metal::float3 w,
    metal::float3 cov_1
) {
    float xz2_ = metal::max(metal::dot(w.xz, w.xz), 0.00000001);
    float il = metal::rsqrt(xz2_);
    metal::float2 az = w.xz * il;
    float sig2_ = (((az.x * az.x) * cov_1.x) + ((az.y * az.y) * cov_1.y)) + (((2.0 * az.x) * az.y) * cov_1.z);
    float cotT = w.y * il;
    float a = metal::max(cotT, 0.001) / metal::sqrt(2.0 * metal::max(sig2_, 0.0000001));
    if (a >= 1.6) {
        return 0.0;
    }
    return ((1.0 - (1.259 * a)) + ((0.396 * a) * a)) / ((3.535 * a) + ((2.181 * a) * a));
}

metal::float3 moonGlitter(
    metal::float3 V,
    metal::float2 sl,
    metal::float3 cov_2,
    constant Frame& F,
    metal::texture2d<float, metal::access::sample> transLUT,
    metal::sampler sampC,
    constant Celestial& C
) {
    float _e6 = C.moonDir.y;
    float _e12 = C.sunDir.w;
    if ((_e6 <= 0.0) || (_e12 <= 0.0)) {
        return metal::float3(0.0);
    }
    metal::float4 _e20 = C.moonDir;
    metal::float3 moonDirection = _e20.xyz;
    metal::float3 _e22 = moonIlluminance(F, transLUT, sampC, C);
    metal::float3 Hv = metal::normalize(V + moonDirection);
    metal::float2 hs = -(Hv.xz) / metal::float2(metal::max(Hv.y, 0.001));
    metal::float2 dsl = hs - sl;
    float det = metal::max((cov_2.x * cov_2.y) - (cov_2.z * cov_2.z), 0.0000000001);
    float e = ((((dsl.x * dsl.x) * cov_2.y) + ((dsl.y * dsl.y) * cov_2.x)) - (((2.0 * dsl.x) * dsl.y) * cov_2.z)) / det;
    float pdf = metal::exp(-0.5 * e) / (6.2831855 * metal::sqrt(det));
    float hy2_ = Hv.y * Hv.y;
    float Dm = pdf / metal::max(hy2_ * hy2_, 0.000001);
    float _e76 = lambdaSmith(V, cov_2);
    float _e79 = lambdaSmith(moonDirection, cov_2);
    float G = 1.0 / ((1.0 + _e76) + _e79);
    float _e84 = fresnelWater(metal::dot(V, Hv));
    metal::float3 moonSpec = (_e22 * (((_e84 * Dm) * G) / (4.0 * metal::max(V.y, 0.02)))) * metal::step(0.0, moonDirection.y);
    return moonSpec;
}

float foamPattern(
    metal::float2 xz_1,
    float t,
    metal::texture2d<float, metal::access::sample> foamTex,
    metal::sampler sampR
) {
    metal::float4 _e11 = foamTex.sample(sampR, (xz_1 * 0.23) + (metal::float2(0.013, 0.0) * t));
    float a_1 = _e11.x;
    metal::float4 _e21 = foamTex.sample(sampR, (xz_1 * 0.71) + metal::float2(0.37, 0.71));
    float b_1 = _e21.y;
    return (a_1 * 0.78) + (b_1 * 0.22);
}

struct vsInput {
    metal::float4 inst [[attribute(0)]];
};
struct vsOutput {
    metal::float4 pos [[position]];
    metal::float3 rel [[user(loc0), center_perspective]];
    metal::float2 xz [[user(loc1), center_perspective]];
    float height [[user(loc2), center_perspective]];
};
vertex vsOutput vs(
  vsInput varyings [[stage_in]]
, uint vi [[vertex_id]]
, constant Frame& F [[buffer(0)]]
, metal::texture2d_array<float, metal::access::sample> dispTex [[texture(4)]]
, metal::sampler sampR [[sampler(9)]]
) {
    const auto inst = varyings.inst;
    metal::float2 xz = {};
    metal::float3 disp = metal::float3(0.0);
    uint c = 0u;
    VSOut o = {};
    float _e5 = F.lodP.y;
    uint n = static_cast<uint>(_e5);
    metal::float2 g_2 = metal::float2(static_cast<float>(vi % (n + 1u)), static_cast<float>(vi / (n + 1u)));
    float spacing = inst.z / static_cast<float>(n);
    xz = inst.xy + (g_2 * spacing);
    float _e26 = F.lodP.x;
    float R_2 = _e26 * metal::exp2(inst.w);
    float _e31 = xz.x;
    float _e33 = xz.y;
    metal::float4 _e38 = F.camPos;
    float d_3 = metal::distance(metal::float3(_e31, 0.0, _e33), _e38.xyz);
    float mk = metal::clamp((d_3 - (0.8 * R_2)) / (0.2 * R_2), 0.0, 1.0);
    metal::float2 _e57 = xz;
    xz = _e57 - (((metal::fract(g_2 * 0.5) * 2.0) * spacing) * mk);
    float eff = spacing * (1.0 + mk);
    bool loop_init = true;
    while(true) {
        if (!loop_init) {
            uint _e112 = c;
            c = _e112 + 1u;
        }
        loop_init = false;
        uint _e67 = c;
        if (_e67 < 6u) {
        } else {
            break;
        }
        {
            uint _e72 = c;
            uint _e76 = c;
            float _e80 = F.cascL.inner[_e72 >> 2u][_e76 & 3u];
            float texel = _e80 / TEX_N;
            float lod = metal::log2(metal::max(eff / texel, 1.0)) + 0.5;
            if (lod < 8.0) {
                metal::float2 _e93 = xz;
                uint _e96 = c;
                uint _e100 = c;
                float _e104 = F.cascInvL.inner[_e96 >> 2u][_e100 & 3u];
                uint _e106 = c;
                metal::float4 _e107 = dispTex.sample(sampR, _e93 * _e104, _e106, metal::level(lod));
                metal::float3 _e109 = disp;
                disp = _e109 + _e107.xyz;
            }
        }
#define LOOP_IS_BOUNDED { volatile bool unpredictable_break_from_loop = false; if (unpredictable_break_from_loop) break; }
        LOOP_IS_BOUNDED
    }
    float _e116 = xz.x;
    float _e118 = disp.x;
    float _e121 = disp.y;
    float _e123 = xz.y;
    float _e125 = disp.z;
    metal::float3 world = metal::float3(_e116 + _e118, _e121, _e123 + _e125);
    metal::float4 _e131 = F.camPos;
    o.rel = world - _e131.xyz;
    metal::float4x4 _e137 = F.viewProj;
    metal::float3 _e139 = o.rel;
    o.pos = _e137 * metal::float4(_e139, 1.0);
    metal::float2 _e144 = xz;
    o.xz = _e144;
    float _e147 = disp.y;
    o.height = _e147;
    VSOut _e148 = o;
    const auto _tmp = _e148;
    return vsOutput { _tmp.pos, _tmp.rel, _tmp.xz, _tmp.height };
}


struct fsInput {
    metal::float3 rel [[user(loc0), center_perspective]];
    metal::float2 xz [[user(loc1), center_perspective]];
    float height [[user(loc2), center_perspective]];
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
, metal::texture2d_array<float, metal::access::sample> dispTex [[texture(4)]]
, metal::texture2d_array<float, metal::access::sample> derivTex [[texture(5)]]
, metal::texture2d_array<float, metal::access::sample> momTex [[texture(6)]]
, metal::texture2d<float, metal::access::sample> foamTex [[texture(7)]]
, metal::texturecube<float, metal::access::sample> envCube [[texture(8)]]
, metal::sampler sampR [[sampler(9)]]
, metal::texture2d_array<float, metal::access::sample> foamWorld [[texture(10)]]
, device type_11 const& sunVis [[buffer(11)]]
, constant Celestial& C [[buffer(12)]]
) {
    const VSOut in = { pos, varyings_1.rel, varyings_1.xz, varyings_1.height };
    metal::float2 s = metal::float2(0.0);
    float jxx = 0.0;
    float jzz = 0.0;
    float jxz = 0.0;
    metal::float3 cov = metal::float3(0.0);
    uint c_1 = 0u;
    metal::float3 R = {};
    metal::float3 body = {};
    float cover = {};
    float foamMask = {};
    metal::float3 col = {};
    metal::float2 xz_2 = in.xz;
    metal::float4 _e21 = F.windP.inner[0];
    float _e26 = F.camPos.w;
    metal::float4 _e31 = foamTex.sample(sampR, (xz_2 * 0.011) + (_e21.xy * (_e26 * 0.0004)));
    float gustN = _e31.z;
    float gust = metal::mix(0.35, 1.2, metal::smoothstep(0.3, 0.72, gustN));
    bool loop_init_1 = true;
    while(true) {
        if (!loop_init_1) {
            uint _e120 = c_1;
            c_1 = _e120 + 1u;
        }
        loop_init_1 = false;
        uint _e41 = c_1;
        if (_e41 < 6u) {
        } else {
            break;
        }
        {
            uint _e46 = c_1;
            uint _e50 = c_1;
            float _e54 = F.cascInvL.inner[_e46 >> 2u][_e50 & 3u];
            metal::float2 uv_2 = xz_2 * _e54;
            uint _e60 = c_1;
            uint _e64 = c_1;
            float gk = metal::mix(1.0, gust, (_e64 >= 3u) ? ((_e60 >= 4u) ? 1.0 : 0.5) : 0.0);
            uint _e71 = c_1;
            metal::float4 _e72 = derivTex.sample(sampR, uv_2, _e71);
            metal::float4 dv = _e72 * gk;
            uint _e76 = c_1;
            metal::float4 _e77 = momTex.sample(sampR, uv_2, _e76);
            metal::float4 mv = _e77 * (gk * gk);
            uint _e82 = c_1;
            metal::float4 _e83 = dispTex.sample(sampR, uv_2, _e82);
            metal::float4 av = _e83 * gk;
            metal::float2 _e86 = s;
            s = _e86 + dv.xy;
            float _e89 = jxx;
            jxx = _e89 + dv.z;
            float _e92 = jzz;
            jzz = _e92 + dv.w;
            float _e95 = jxz;
            jxz = _e95 + av.w;
            metal::float3 _e117 = cov;
            cov = _e117 + metal::float3(metal::max(mv.x - (dv.x * dv.x), 0.0), metal::max(mv.y - (dv.y * dv.y), 0.0), mv.z - (dv.x * dv.y));
        }
        LOOP_IS_BOUNDED
    }
    float dist = metal::length(in.rel);
    metal::float3 V_1 = -(in.rel) / metal::float3(dist);
    metal::float4 _e130 = F.sunDir;
    metal::float3 Ld = _e130.xyz;
    float _e135 = F.waterCol.w;
    float unres = _e135 + (0.0035 * metal::smoothstep(30.0, 500.0, dist));
    float _e143 = cov.x;
    cov.x = _e143 + unres;
    float _e146 = cov.y;
    cov.y = _e146 + unres;
    float _e148 = jxx;
    float jx = metal::max(1.0 + _e148, 0.15);
    float _e153 = jzz;
    float jz = metal::max(1.0 + _e153, 0.15);
    float _e159 = s.x;
    float _e162 = s.y;
    metal::float2 sl_2 = metal::float2(_e159 / jx, _e162 / jz);
    metal::float3 nrm = metal::normalize(metal::float3(-(sl_2.x), 1.0, -(sl_2.y)));
    metal::float2 dsx = metal::dfdx(sl_2);
    metal::float2 dsy = metal::dfdy(sl_2);
    metal::float3 aa = metal::float3((dsx.x * dsx.x) + (dsy.x * dsy.x), (dsx.y * dsx.y) + (dsy.y * dsy.y), (dsx.x * dsx.y) + (dsy.x * dsy.y)) * 0.5;
    metal::float3 _e208 = cov;
    cov = _e208 + (aa * metal::min(1.0, 0.03 / metal::max(metal::max(aa.x, aa.y), 0.00000001)));
    float _e210 = jxx;
    float _e213 = jzz;
    float _e217 = jxz;
    float _e218 = jxz;
    float J = ((1.0 + _e210) * (1.0 + _e213)) - (_e217 * _e218);
    metal::float3 _e221 = sunIlluminance(F, transLUT, sampC);
    float _e224 = sunVis.inner[0];
    metal::float3 sunE = _e221 * _e224;
    metal::float4 _e233 = envCube.sample(sampC, metal::float3(0.0, 1.0, 0.0), metal::level(ENV_MAXMIP));
    metal::float3 skyUp = _e233.xyz;
    metal::float4 _e244 = envCube.sample(sampC, metal::float3(0.94, 0.34, 0.0), metal::level(7.0));
    metal::float4 _e253 = envCube.sample(sampC, metal::float3(-0.94, 0.34, 0.0), metal::level(7.0));
    metal::float4 _e263 = envCube.sample(sampC, metal::float3(0.0, 0.34, 0.94), metal::level(7.0));
    metal::float4 _e273 = envCube.sample(sampC, metal::float3(0.0, 0.34, -0.94), metal::level(7.0));
    metal::float3 skyHemi = (skyUp * 0.4) + (0.15 * (((_e244.xyz + _e253.xyz) + _e263.xyz) + _e273.xyz));
    metal::float4 _e282 = envCube.sample(sampC, nrm, metal::level(7.0));
    metal::float3 skyN = _e282.xyz;
    metal::float3 halfVector = V_1 + Ld;
    metal::float3 Hv_1 = halfVector * metal::rsqrt(metal::max(metal::dot(halfVector, halfVector), 0.000000000001));
    metal::float2 hs_1 = -(Hv_1.xz) / metal::float2(metal::max(Hv_1.y, 0.001));
    metal::float2 dsl_1 = hs_1 - sl_2;
    float _e299 = cov.x;
    float _e301 = cov.y;
    float _e304 = cov.z;
    float _e306 = cov.z;
    float det_1 = metal::max((_e299 * _e301) - (_e304 * _e306), 0.0000000001);
    float _e315 = cov.y;
    float _e321 = cov.x;
    float _e330 = cov.z;
    float e_1 = ((((dsl_1.x * dsl_1.x) * _e315) + ((dsl_1.y * dsl_1.y) * _e321)) - (((2.0 * dsl_1.x) * dsl_1.y) * _e330)) / det_1;
    float pdf_1 = metal::exp(-0.5 * e_1) / (6.2831855 * metal::sqrt(det_1));
    float hy2_1 = Hv_1.y * Hv_1.y;
    float Dm_1 = pdf_1 / metal::max(hy2_1 * hy2_1, 0.000001);
    metal::float3 _e348 = cov;
    float _e349 = lambdaSmith(V_1, _e348);
    metal::float3 _e352 = cov;
    float _e353 = lambdaSmith(Ld, _e352);
    float G_1 = 1.0 / ((1.0 + _e349) + _e353);
    float _e358 = fresnelWater(metal::dot(V_1, Hv_1));
    metal::float3 spec = (sunE * (((_e358 * Dm_1) * G_1) / (4.0 * metal::max(V_1.y, 0.02)))) * metal::step(0.0, Ld.y);
    float _e373 = cov.x;
    float _e375 = cov.y;
    float sig = metal::sqrt(metal::max(_e373 + _e375, 0.000001) * 0.5);
    metal::float3 vh = metal::normalize(metal::float3(V_1.x, 0.0, V_1.z) + metal::float3(0.00001, 0.0, 0.0));
    float _e396 = cov.x;
    float _e402 = cov.y;
    float _e411 = cov.z;
    float sigV = metal::sqrt(metal::max((((vh.x * vh.x) * _e396) + ((vh.z * vh.z) * _e402)) + (((2.0 * vh.x) * vh.z) * _e411), 0.000001));
    float aV = (metal::max(V_1.y, 0.001) / metal::max(metal::sqrt(1.0 - (V_1.y * V_1.y)), 0.001)) / (1.4142 * sigV);
    float tilt = (0.32 * sigV) * (1.0 - metal::smoothstep(0.0, 2.5, aV));
    metal::float3 nV = metal::normalize(nrm + (vh * tilt));
    R = metal::reflect(-(V_1), nV);
    float _e448 = R.y;
    float _e453 = R.y;
    R.y = (metal::abs(_e448) * 0.4) + (metal::max(_e453, 0.0) * 0.6);
    metal::float3 _e459 = R;
    R = metal::normalize(_e459);
    float envLod = metal::clamp(metal::log2(metal::max((2.0 * sig) * ENV_TEXELS_PER_RAD, 1.0)), 0.0, ENV_MAXMIP);
    metal::float3 _e473 = R;
    metal::float4 _e474 = envCube.sample(sampC, _e473, metal::level(envLod));
    metal::float3 refl = _e474.xyz;
    float NdV = metal::max(metal::dot(nV, V_1), 0.0);
    metal::float3 nF = metal::normalize(metal::mix(nrm, metal::float3(0.0, 1.0, 0.0), 0.45));
    float _e489 = fresnelWater(metal::max(metal::dot(nF, V_1), 0.0));
    metal::float3 ambient = (skyUp * 1.3) + (skyN * 0.5);
    float NdL = metal::max(metal::dot(nrm, Ld), 0.0);
    metal::float4 _e500 = F.waterCol;
    metal::float3 _e508 = moonIlluminance(F, transLUT, sampC, C);
    float _e512 = C.moonDir.y;
    body = _e500.xyz * ((skyHemi * 1.6) + (((sunE * metal::max(Ld.y, 0.0)) + (_e508 * metal::max(_e512, 0.0))) * 0.8));
    float crest = metal::clamp((in.height - 0.05) / 0.9, 0.0, 1.0);
    float toSun = metal::max(metal::dot(Ld, -(V_1)), 0.0);
    float thin = metal::pow(metal::clamp(0.5 - (0.5 * metal::dot(Ld, nrm)), 0.0, 1.0), 3.0);
    float _e547 = F.sssCol.w;
    float k1_ = ((((_e547 * crest) * crest) * metal::pow(toSun, 4.0)) * thin) * metal::exp(-(dist) / 600.0);
    metal::float4 _e561 = F.sssCol;
    metal::float3 _e565 = body;
    body = _e565 + ((_e561.xyz * sunE) * k1_);
    metal::float4 _e569 = F.camPos;
    metal::float2 dc = metal::abs(xz_2 - _e569.xz);
    float cheb = metal::max(dc.x, dc.y);
    float _e579 = F.lodP.z;
    float _e585 = F.lodP.z;
    float w0_ = 1.0 - metal::smoothstep(0.3 * _e579, 0.45 * _e585, cheb);
    float _e594 = F.lodP.w;
    float _e600 = F.lodP.w;
    float w1_ = 1.0 - metal::smoothstep(0.3 * _e594, 0.45 * _e600, cheb);
    float _e611 = F.lodP.z;
    metal::float4 fw0_ = foamWorld.sample(sampR, xz_2 / metal::float2(_e611), 0u);
    float _e621 = F.lodP.w;
    metal::float4 fw1_ = foamWorld.sample(sampR, xz_2 / metal::float2(_e621), 1u);
    metal::float4 fwl = metal::mix(fw1_, fw0_, w0_) * w1_;
    float _e631 = F.foamP.x;
    float _e636 = F.foamP.y;
    float fresh = metal::clamp((_e631 - J) * _e636, 0.0, 1.0);
    float _e655 = F.foamP.z;
    cover = metal::clamp((metal::max(fwl.x, fresh * (1.0 - (w1_ * 0.7))) + (fwl.y * 0.6)) * _e655, 0.0, 1.5);
    metal::float4 _e664 = F.windP.inner[0];
    metal::float2 wd = _e664.xy;
    metal::float2 ws = metal::float2(metal::dot(xz_2, wd), metal::dot(xz_2, metal::float2(-(wd.y), wd.x)));
    metal::float4 _e679 = foamTex.sample(sampR, ws * metal::float2(0.035, 0.11));
    float streak = _e679.w;
    float freshK = metal::clamp((fwl.y * 2.0) + fresh, 0.0, 1.0);
    float _e695 = cover;
    cover = _e695 * metal::mix(metal::smoothstep(0.25, 0.75, streak) * 1.5, 1.0, freshK);
    float _e700 = F.camPos.w;
    float _e701 = foamPattern(xz_2, _e700, foamTex, sampR);
    float _e702 = metal::fwidth(_e701);
    float fw = _e702 + 0.03;
    float _e705 = cover;
    float soft = 0.04 + (0.14 * (1.0 - metal::clamp(_e705, 0.0, 1.0)));
    float _e715 = cover;
    float _e720 = cover;
    float fm = metal::smoothstep(((1.0 - _e715) - fw) - soft, ((1.0 - _e720) + fw) + soft, _e701);
    float _e728 = cover;
    float _e736 = cover;
    foamMask = metal::clamp(fm * metal::smoothstep(0.0, 0.5, _e728), 0.0, 1.0) * (0.68 + (0.32 * metal::smoothstep(0.3, 0.9, _e736)));
    float _e744 = foamMask;
    foamMask = metal::max(_e744, (metal::smoothstep(0.35, 0.9, fwl.y) * metal::smoothstep(0.25, 0.6, _e701 + 0.25)) * 0.95);
    metal::float4 _e760 = F.sssCol;
    float _e768 = cover;
    metal::float3 _e773 = body;
    body = _e773 + ((_e760.xyz * ((sunE * 0.05) + (ambient * 0.35))) * metal::clamp(_e768, 0.0, 1.0));
    metal::float3 _e784 = body;
    body = _e784 + (((metal::float3(0.1, 0.32, 0.3) * skyUp) * fwl.y) * 0.35);
    metal::float4 _e794 = foamTex.sample(sampR, (xz_2 * 1.9) + metal::float2(0.21, 0.53));
    float bub = _e794.y;
    metal::float3 foamAlb = metal::float3(0.82, 0.87, 0.92) * (0.78 + (0.3 * bub));
    metal::float3 foamAmb = (skyHemi * 1.0) + (skyN * 0.3);
    metal::float3 foamAmbN = metal::mix(foamAmb, metal::float3(metal::dot(foamAmb, metal::float3(0.2126, 0.7152, 0.0722))), 0.85);
    metal::float3 foamLit = foamAlb * ((((sunE * metal::max(metal::dot(nrm, Ld), 0.0)) * 0.318) * 0.5) + (foamAmbN * 1.55));
    float _e833 = F.post.w;
    if (_e833 > 0.5) {
        float _e839 = F.post.w;
        if (_e839 < 1.5) {
            float _e842 = cover;
            return fsOutput { metal::float4(_e842, metal::clamp(J * 0.5, 0.0, 1.0), w0_ * 0.3, 1.0) * 0.2 };
        }
        float _e857 = F.post.w;
        float _e863 = F.post.w;
        if ((_e857 > 2.5) && (_e863 < 3.5)) {
            return fsOutput { metal::float4(refl, 1.0) };
        }
        float _e872 = F.post.w;
        float _e878 = F.post.w;
        if ((_e872 > 3.5) && (_e878 < 4.5)) {
            return fsOutput { metal::float4(metal::float3(_e489), 1.0) * 0.5 };
        }
        float _e890 = F.post.w;
        float _e896 = F.post.w;
        if ((_e890 > 4.5) && (_e896 < 5.5)) {
            metal::float3 _e900 = body;
            return fsOutput { metal::float4(_e900 * (1.0 - _e489), 1.0) };
        }
        float _e909 = F.post.w;
        float _e915 = F.post.w;
        if ((_e909 > 5.5) && (_e915 < 6.5)) {
            return fsOutput { metal::float4(foamLit, 1.0) };
        }
        float _e924 = F.post.w;
        float _e930 = F.post.w;
        if ((_e924 > 6.5) && (_e930 < 7.5)) {
            return fsOutput { metal::float4(skyUp, 1.0) };
        }
        return fsOutput { metal::float4(fwl.x, fwl.y, fresh, 1.0) * 0.2 };
    }
    metal::float3 _e942 = body;
    metal::float3 _e949 = cov;
    metal::float3 _e950 = moonGlitter(V_1, sl_2, _e949, F, transLUT, sampC, C);
    col = (((_e942 * (1.0 - _e489)) + (refl * _e489)) + spec) + _e950;
    metal::float3 _e953 = col;
    float _e954 = foamMask;
    col = metal::mix(_e953, foamLit, _e954 * 0.95);
    metal::float4 _e960 = F.fogExt;
    float _e965 = F.fogExt.w;
    metal::float3 T = metal::exp(-(metal::max(_e960.xyz, metal::float3(_e965))) * dist);
    metal::float3 hz = metal::normalize(metal::float3(-(V_1.x), 0.002, -(V_1.z)));
    metal::float3 _e978 = skyAtmo(hz, F, skyLUT, sampC);
    float _e982 = C.night.x;
    metal::float3 fogCol = _e978 + (skyHemi * (0.15 * _e982));
    metal::float3 _e987 = col;
    col = (_e987 * T) + (fogCol * (metal::float3(1.0) - T));
    metal::float3 _e994 = col;
    return fsOutput { metal::float4(_e994, 1.0) };
}
