// Generated from Resources/Web/js/wgsl by scripts/generate-metal.py.
// Original ocean renderer: Noniv/web-ocean, MIT; see THIRD_PARTY_NOTICES.md.
// Edit the WGSL source and regenerate; native builds use this vendored MSL.
// language: metal2.4
#include <metal_stdlib>
#include <simd/simd.h>

using metal::uint;

struct type_1 {
    float inner[4];
};

struct main_Input {
};
kernel void main_(
  uint k [[thread_index_in_threadgroup]]
, device type_1& sunVis [[buffer(4)]]
) {

    if (k == 0u) {
        sunVis.inner[0] = 1.0;
        return;
    } else {
        return;
    }
}
