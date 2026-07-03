#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_threshold;
    float u_strength;
};

struct fx_solarize_out
{
    float4 frag [[color(0)]];
};

struct fx_solarize_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_solarize_out fx_solarize(fx_solarize_in in [[stage_in]], constant Params& _36 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_solarize_out out = {};
    float4 col = u_tex.sample(u_texSmplr, in.v_uv);
    float3 inv = float3(1.0) - col.xyz;
    float3 solar = mix(col.xyz, mix(col.xyz, inv, step(float3(_36.u_threshold), col.xyz)), float3(_36.u_strength));
    float lum = dot(solar, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    solar = mix(float3(lum), solar, float3(1.60000002384185791015625));
    out.frag = float4(fast::clamp(solar, float3(0.0), float3(1.0)), col.w);
    return out;
}

