#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_grid_scale;
    float u_wave_amp;
    float u_line_width;
    float u_hue;
    float u_bg_darken;
    float u_time;
};

struct fx_dna_helix_out
{
    float4 frag [[color(0)]];
};

struct fx_dna_helix_in
{
    float2 v_uv [[user(locn0)]];
};

static inline __attribute__((always_inline))
float3 hue2rgb(thread const float& h)
{
    float4 K = float4(1.0, 0.666666686534881591796875, 0.3333333432674407958984375, 3.0);
    return fast::clamp(abs((fract(float3(h) + K.xyz) * 6.0) - K.www) - K.xxx, float3(0.0), float3(1.0));
}

fragment fx_dna_helix_out fx_dna_helix(fx_dna_helix_in in [[stage_in]], constant Params& _56 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_dna_helix_out out = {};
    float4 col = u_tex.sample(u_texSmplr, in.v_uv);
    float t = _56.u_time * 0.800000011920928955078125;
    float2 uv = in.v_uv * _56.u_grid_scale;
    float row = floor(uv.y);
    float cell_y = fract(uv.y);
    float phase1 = (row * 0.5) + t;
    float phase2 = ((row * 0.5) + t) + 3.141590118408203125;
    float wave1 = sin((uv.x * 0.60000002384185791015625) + phase1) * _56.u_wave_amp;
    float wave2 = sin((uv.x * 0.60000002384185791015625) + phase2) * _56.u_wave_amp;
    float cy1 = (wave1 + 1.0) * 0.5;
    float cy2 = (wave2 + 1.0) * 0.5;
    float d1 = abs(cell_y - cy1);
    float d2 = abs(cell_y - cy2);
    float strand = smoothstep(_56.u_line_width, 0.0, fast::min(d1, d2));
    float rung_phase = fract((uv.x * 0.300000011920928955078125) + (t * 0.20000000298023223876953125));
    float rung = step(0.4799999892711639404296875, rung_phase) * step(rung_phase, 0.519999980926513671875);
    float rung_line = rung * smoothstep(_56.u_line_width * 2.0, 0.0, abs(cell_y - mix(cy1, cy2, 0.5)));
    float overlay = fast::max(strand, rung_line * 0.60000002384185791015625);
    float hv = fract((_56.u_hue + (uv.x * 0.02999999932944774627685546875)) + (row * 0.070000000298023223876953125));
    float param = hv;
    float3 line_col = hue2rgb(param);
    float3 bg = col.xyz * (1.0 - (_56.u_bg_darken * 0.5));
    float3 result = mix(bg, line_col, float3(overlay));
    out.frag = float4(fast::clamp(result, float3(0.0), float3(1.0)), col.w);
    return out;
}

