#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_shadow_r;
    float u_shadow_g;
    float u_shadow_b;
    float u_highlight_r;
    float u_highlight_g;
    float u_highlight_b;
};

struct fx_duotone_out
{
    float4 frag [[color(0)]];
};

struct fx_duotone_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_duotone_out fx_duotone(fx_duotone_in in [[stage_in]], constant Params& _34 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_duotone_out out = {};
    float4 col = u_tex.sample(u_texSmplr, in.v_uv);
    float luma = dot(col.xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float3 shadow = float3(_34.u_shadow_r, _34.u_shadow_g, _34.u_shadow_b);
    float3 highlight = float3(_34.u_highlight_r, _34.u_highlight_g, _34.u_highlight_b);
    out.frag = float4(mix(shadow, highlight, float3(luma)), col.w);
    return out;
}

