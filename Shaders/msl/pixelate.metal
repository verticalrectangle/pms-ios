#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_tex_w;
    float u_tex_h;
    float u_size;
};

struct fx_pixelate_out
{
    float4 frag [[color(0)]];
};

struct fx_pixelate_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_pixelate_out fx_pixelate(fx_pixelate_in in [[stage_in]], constant Params& _12 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_pixelate_out out = {};
    float px = fast::max(1.0, _12.u_size);
    float2 cell = float2(px / _12.u_tex_w, px / _12.u_tex_h);
    float2 snapped = (floor(in.v_uv / cell) * cell) + (cell * 0.5);
    out.frag = u_tex.sample(u_texSmplr, snapped);
    return out;
}

