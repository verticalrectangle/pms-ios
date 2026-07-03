#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_tex_w;
    float u_tex_h;
    float u_char_size;
    float u_fg_r;
    float u_fg_g;
    float u_fg_b;
    float u_bg_dark;
};

struct fx_ascii_art_out
{
    float4 frag [[color(0)]];
};

struct fx_ascii_art_in
{
    float2 v_uv [[user(locn0)]];
};

static inline __attribute__((always_inline))
float char_pattern(thread const float2& cell_uv, thread const float& density)
{
    float d = density;
    float pat1 = step(0.449999988079071044921875, cell_uv.y) * step(cell_uv.y, 0.550000011920928955078125);
    float pat2 = fast::max(step(0.449999988079071044921875, cell_uv.y) * step(cell_uv.y, 0.550000011920928955078125), step(0.449999988079071044921875, cell_uv.x) * step(cell_uv.x, 0.550000011920928955078125));
    float gx = (step(0.300000011920928955078125, cell_uv.x) * step(cell_uv.x, 0.4000000059604644775390625)) + (step(0.60000002384185791015625, cell_uv.x) * step(cell_uv.x, 0.699999988079071044921875));
    float gy = (step(0.300000011920928955078125, cell_uv.y) * step(cell_uv.y, 0.4000000059604644775390625)) + (step(0.60000002384185791015625, cell_uv.y) * step(cell_uv.y, 0.699999988079071044921875));
    float pat3 = fast::max(gx, gy);
    float pat4 = 1.0;
    if (d < 0.25)
    {
        return mix(0.0, pat1, d * 4.0);
    }
    if (d < 0.5)
    {
        return mix(pat1, pat2, (d - 0.25) * 4.0);
    }
    if (d < 0.75)
    {
        return mix(pat2, pat3, (d - 0.5) * 4.0);
    }
    return mix(pat3, pat4, (d - 0.75) * 4.0);
}

fragment fx_ascii_art_out fx_ascii_art(fx_ascii_art_in in [[stage_in]], constant Params& _136 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_ascii_art_out out = {};
    float2 px = float2(1.0 / _136.u_tex_w, 1.0 / _136.u_tex_h);
    float2 char_uv = (floor(in.v_uv / (px * _136.u_char_size)) * px) * _136.u_char_size;
    float lum = dot(u_tex.sample(u_texSmplr, (char_uv + ((px * _136.u_char_size) * 0.5))).xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float2 cell_uv = fract(in.v_uv / (px * _136.u_char_size));
    float2 param = cell_uv;
    float param_1 = lum;
    float on = char_pattern(param, param_1);
    float4 orig = u_tex.sample(u_texSmplr, in.v_uv);
    float3 fg = float3(_136.u_fg_r, _136.u_fg_g, _136.u_fg_b);
    float3 bg = orig.xyz * (1.0 - _136.u_bg_dark);
    float3 result = mix(bg, fg * (0.300000011920928955078125 + (lum * 0.699999988079071044921875)), float3(on));
    out.frag = float4(fast::clamp(result, float3(0.0), float3(1.0)), orig.w);
    return out;
}

