#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_vignette;
    float u_saturation;
    float u_fade;
};

struct fx_lomo_out
{
    float4 frag [[color(0)]];
};

struct fx_lomo_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_lomo_out fx_lomo(fx_lomo_in in [[stage_in]], constant Params& _38 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_lomo_out out = {};
    float4 col = u_tex.sample(u_texSmplr, in.v_uv);
    float luma = dot(col.xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float3 sat = mix(float3(luma), col.xyz, float3(_38.u_saturation));
    sat = mix(sat, sat + float3(_38.u_fade * 0.1500000059604644775390625, _38.u_fade * 0.0500000007450580596923828125, (-_38.u_fade) * 0.0500000007450580596923828125), float3(1.0));
    float2 d = (in.v_uv - float2(0.5)) * float2(1.0, 1.39999997615814208984375);
    float vig = 1.0 - (smoothstep(0.300000011920928955078125, 0.75, length(d)) * _38.u_vignette);
    out.frag = float4(sat * vig, col.w);
    return out;
}

