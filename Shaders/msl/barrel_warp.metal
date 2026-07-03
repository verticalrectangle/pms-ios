#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_k1;
    float u_k2;
    float u_scale;
};

struct fx_barrel_warp_out
{
    float4 frag [[color(0)]];
};

struct fx_barrel_warp_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_barrel_warp_out fx_barrel_warp(fx_barrel_warp_in in [[stage_in]], constant Params& _18 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_barrel_warp_out out = {};
    float2 d = (in.v_uv - float2(0.5)) / float2(_18.u_scale);
    float r2 = dot(d, d);
    float distort = (1.0 + (_18.u_k1 * r2)) + ((_18.u_k2 * r2) * r2);
    float2 uv = (d * distort) + float2(0.5);
    out.frag = u_tex.sample(u_texSmplr, fast::clamp(uv, float2(0.0), float2(1.0)));
    return out;
}

