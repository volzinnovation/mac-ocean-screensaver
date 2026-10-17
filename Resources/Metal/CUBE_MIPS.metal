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
, metal::texture2d_array<float, metal::access::sample> src [[texture(0)]]
, metal::texture2d_array<float, metal::access::write> dst [[texture(1)]]
) {

    metal::float4 acc = metal::float4(0.0);
    float wsum = 0.0;
    int j = -1;
    int i = {};
    metal::uint2 size = metal::uint2(dst.get_width(), dst.get_height());
    if ((id.x >= size.x) || (id.y >= size.y)) {
        return;
    }
    metal::int2 srcSize = static_cast<metal::int2>(metal::uint2(src.get_width(), src.get_height()));
    metal::int2 p = static_cast<metal::int2>(id.xy) * 2;
    bool loop_init = true;
    while(true) {
        if (!loop_init) {
            int _e76 = j;
            j = _e76 + 1;
        }
        loop_init = false;
        int _e24 = j;
        if (_e24 <= 2) {
        } else {
            break;
        }
        {
            i = -1;
            bool loop_init_1 = true;
            while(true) {
                if (!loop_init_1) {
                    int _e73 = i;
                    i = _e73 + 1;
                }
                loop_init_1 = false;
                int _e29 = i;
                if (_e29 <= 2) {
                } else {
                    break;
                }
                {
                    int _e32 = i;
                    int _e33 = j;
                    metal::int2 q = metal::clamp(p + metal::int2(_e32, _e33), metal::int2(0), srcSize - metal::int2(1));
                    int _e44 = i;
                    int _e47 = i;
                    int _e54 = j;
                    int _e57 = j;
                    float w = (((_e44 == 0) || (_e47 == 1)) ? 3.0 : 1.0) * (((_e54 == 0) || (_e57 == 1)) ? 3.0 : 1.0);
                    metal::float4 _e66 = src.read(metal::uint2(q), id.z, 0);
                    metal::float4 _e68 = acc;
                    acc = _e68 + (_e66 * w);
                    float _e70 = wsum;
                    wsum = _e70 + w;
                }
#define LOOP_IS_BOUNDED { volatile bool unpredictable_break_from_loop = false; if (unpredictable_break_from_loop) break; }
                LOOP_IS_BOUNDED
            }
        }
        LOOP_IS_BOUNDED
    }
    metal::float4 _e81 = acc;
    float _e82 = wsum;
    dst.write(_e81 / metal::float4(_e82), metal::uint2(id.xy), id.z);
    return;
}
