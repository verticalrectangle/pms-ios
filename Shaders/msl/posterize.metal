#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_levels;
};

struct fx_posterize_out
{
    float4 frag [[color(0)]];
};

struct fx_posterize_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_posterize_out fx_posterize(fx_posterize_in in [[stage_in]], constant Params& _25 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_posterize_out out = {};
    float4 col = u_tex.sample(u_texSmplr, in.v_uv);
    float n = fast::max(2.0, _25.u_levels);
    float3 p = floor((col.xyz * n) + float3(0.5)) / float3(n);
    out.frag = float4(p, col.w);
    return out;
}

