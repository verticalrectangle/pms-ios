#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_strength;
    float u_saturation;
};

struct fx_miami_vice_out
{
    float4 frag [[color(0)]];
};

struct fx_miami_vice_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_miami_vice_out fx_miami_vice(fx_miami_vice_in in [[stage_in]], constant Params& _38 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_miami_vice_out out = {};
    float4 col = u_tex.sample(u_texSmplr, in.v_uv);
    float lum = dot(col.xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float3 sat = mix(float3(lum), col.xyz, float3(_38.u_saturation));
    float shadow = smoothstep(0.5, 0.0, lum);
    float hi = smoothstep(0.5, 1.0, lum);
    float3 pink_tint = float3(1.0, 0.20000000298023223876953125, 0.60000002384185791015625);
    float3 teal_tint = float3(0.100000001490116119384765625, 0.89999997615814208984375, 0.800000011920928955078125);
    float3 result = (sat + (((pink_tint * shadow) * _38.u_strength) * 0.4000000059604644775390625)) + (((teal_tint * hi) * _38.u_strength) * 0.300000011920928955078125);
    result = fast::clamp(((result - float3(0.5)) * 1.14999997615814208984375) + float3(0.5), float3(0.0), float3(1.0));
    out.frag = float4(result, col.w);
    return out;
}

