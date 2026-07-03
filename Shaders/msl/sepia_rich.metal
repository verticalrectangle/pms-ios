#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_strength;
    float u_vignette;
    float u_contrast;
};

struct fx_sepia_rich_out
{
    float4 frag [[color(0)]];
};

struct fx_sepia_rich_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_sepia_rich_out fx_sepia_rich(fx_sepia_rich_in in [[stage_in]], constant Params& _35 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_sepia_rich_out out = {};
    float4 col = u_tex.sample(u_texSmplr, in.v_uv);
    float lum = dot(col.xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    lum = fast::clamp(((lum - 0.5) * _35.u_contrast) + 0.5, 0.0, 1.0);
    float3 sepia = float3((lum * 1.08000004291534423828125) + 0.0500000007450580596923828125, (lum * 0.87999999523162841796875) + 0.0199999995529651641845703125, lum * 0.62000000476837158203125);
    float3 result = mix(col.xyz, sepia, float3(_35.u_strength));
    float2 d = (in.v_uv - float2(0.5)) * float2(1.0, 1.2999999523162841796875);
    float vig = 1.0 - (smoothstep(0.20000000298023223876953125, 0.699999988079071044921875, length(d)) * _35.u_vignette);
    result *= vig;
    out.frag = float4(fast::clamp(result, float3(0.0), float3(1.0)), col.w);
    return out;
}

